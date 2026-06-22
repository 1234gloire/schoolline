import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../models/user_model.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/app_logger.dart';
import 'notification_settings_provider.dart';

// ─── Firebase Auth state stream ───
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  return GoogleSignIn();
});

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).userChanges();
});

// ─── UserModel du profil Firestore ───
final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authNotifierProvider).value;
});

// ─── Auth Notifier ───
class AuthNotifier extends StateNotifier<AsyncValue<UserModel?>> {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final GoogleSignIn _googleSignIn;
  late final StreamSubscription<User?> _authSubscription;

  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _profileSubscription;

  AuthNotifier(this._auth, this._firestore, this._storage, this._googleSignIn)
    : super(const AsyncValue.loading()) {
    _authSubscription = _auth.userChanges().listen(
      _handleAuthStateChanged,
    );

    // Mettre à jour le token FCM dans Firestore chaque fois qu'il est régénéré
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
        .listen((token) {
          final uid = _auth.currentUser?.uid;
          if (uid == null) return;
          // Respecter l'opt-out local : ne pas réenregistrer un token désactivé.
          if (!notificationsLocallyEnabled()) return;
          _firestore
              .collection(AppConstants.usersCollection)
              .doc(uid)
              .update({'fcmToken': token})
              .catchError((e) {
                AppLogger.warn(
                  'AuthNotifier',
                  'Échec mise à jour token FCM: $e',
                );
              });
        });
  }

  Future<void> _handleAuthStateChanged(User? user) async {
    await _profileSubscription?.cancel();
    _profileSubscription = null;

    if (user == null) {
      state = const AsyncValue.data(null);
      return;
    }

    state = const AsyncValue.loading();
    final profile = await _loadOrCreateUserProfile(user);
    state = AsyncValue.data(profile);
    _listenToUserProfile(user);

    // Enregistrer le token FCM en arrière-plan (non bloquant)
    _saveFcmToken(user.uid).ignore();
  }

  void _listenToUserProfile(User user) {
    final docRef = _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid);

    _profileSubscription = docRef.snapshots().listen(
      (doc) async {
        if (_auth.currentUser?.uid != user.uid) {
          return;
        }

        if (!doc.exists) {
          final recreatedProfile = await _loadOrCreateUserProfile(user);
          if (_auth.currentUser?.uid == user.uid) {
            state = AsyncValue.data(recreatedProfile);
          }
          return;
        }

        final storedProfile = UserModel.fromFirestore(doc);

        // Compte bloqué par un admin → déconnexion immédiate
        if (storedProfile.blocked) {
          await _auth.signOut();
          state = AsyncValue.error(
            FirebaseAuthException(
              code: 'user-disabled',
              message: 'Ton compte a été suspendu. Contacte un administrateur.',
            ),
            StackTrace.current,
          );
          return;
        }

        final resolvedProfile = _mergeProfiles(
          storedProfile,
          _profileFromAuthUser(user),
        );

        if (_needsProfileSync(storedProfile, resolvedProfile)) {
          await doc.reference.set(
            resolvedProfile.toFirestore(),
            SetOptions(merge: true),
          );
        }

        if (_auth.currentUser?.uid == user.uid) {
          state = AsyncValue.data(resolvedProfile);
        }
      },
      onError: (err, stack) {
        // Le profil courant reste affiché ; une coupure réseau ne doit pas
        // vider brutalement la session visible côté mobile.
        AppLogger.warn('AuthNotifier', 'Erreur stream profil Firestore: $err');
      },
    );
  }

  Future<void> _saveFcmToken(String uid) async {
    try {
      // L'utilisateur a désactivé les notifications dans son profil → ne rien
      // (re)demander ni enregistrer (gère aussi l'opt-out après login).
      if (!notificationsLocallyEnabled()) return;

      final messaging = FirebaseMessaging.instance;

      // Ne pas déclencher la demande de permission ici : l'UI s'en charge
      // (prompt au premier lancement / réglage du profil). On enregistre le
      // token uniquement si la permission est déjà accordée.
      final settings = await messaging.getNotificationSettings();
      final status = settings.authorizationStatus;
      if (status != AuthorizationStatus.authorized &&
          status != AuthorizationStatus.provisional) {
        return;
      }

      // Sur iOS/macOS, le token APNS peut ne pas être enregistré immédiatement.
      // On patiente jusqu'à 5 secondes avant d'abandonner.
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        String? apnsToken;
        for (var i = 0; i < 5 && apnsToken == null; i++) {
          apnsToken = await messaging.getAPNSToken();
          if (apnsToken == null) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }
        if (apnsToken == null) {
          AppLogger.warn(
            'AuthNotifier',
            'Token APNS non disponible après 5s — token FCM non sauvegardé.',
          );
          return;
        }
      }

      final token = await messaging.getToken();
      if (token == null) return;

      await _firestore.collection(AppConstants.usersCollection).doc(uid).update(
        {'fcmToken': token},
      );
    } catch (e) {
      AppLogger.warn(
        'AuthNotifier',
        'Impossible de sauvegarder le token FCM: $e',
      );
    }
  }

  UserModel _profileFromAuthUser(User user) {
    return UserModel(
      uid: user.uid,
      displayName:
          (user.displayName ?? '').trim().isNotEmpty
              ? user.displayName!.trim()
              : (user.email ?? 'Utilisateur').trim(),
      email: (user.email ?? '').trim(),
      phone: (user.phoneNumber ?? '').trim(),
      role: UserRole.student,
      studentClass: StudentClass.terminale,
      series: '',
      school: '',
      avatarUrl: (user.photoURL ?? '').trim(),
      createdAt: DateTime.now(),
      subscriptions: const [],
      abandonedSubjectIds: const [],
    );
  }

  bool _isPlaceholderDisplayName(String displayName, String email) {
    final normalizedName = displayName.trim().toLowerCase();
    final normalizedEmail = email.trim().toLowerCase();

    if (normalizedName.isEmpty) return true;
    if (normalizedEmail.isNotEmpty && normalizedName == normalizedEmail) {
      return true;
    }
    return normalizedName.contains('@');
  }

  bool _isLikelyBrokenTroisiemeProfile(UserModel profile) {
    return profile.role == UserRole.student &&
        profile.studentClass == StudentClass.terminale &&
        profile.series.trim().isEmpty &&
        profile.school.trim().isNotEmpty;
  }

  UserModel _mergeProfiles(
    UserModel primary,
    UserModel fallback, {
    bool preferFallback = false,
  }) {
    final fallbackDisplayName = fallback.displayName.trim();
    final primaryDisplayName = primary.displayName.trim();
    final shouldUseFallbackDisplayName =
        fallbackDisplayName.isNotEmpty &&
        !(_isPlaceholderDisplayName(fallbackDisplayName, fallback.email) &&
            fallbackDisplayName.toLowerCase() ==
                primaryDisplayName.toLowerCase()) &&
        (preferFallback ||
            _isPlaceholderDisplayName(primaryDisplayName, primary.email));

    final resolvedStudentClass =
        preferFallback && fallback.studentClass != null
            ? fallback.studentClass
            : _isLikelyBrokenTroisiemeProfile(primary)
            ? StudentClass.troisieme
            : primary.studentClass ?? fallback.studentClass;

    return UserModel(
      uid: primary.uid,
      displayName:
          shouldUseFallbackDisplayName
              ? fallbackDisplayName
              : primaryDisplayName.isNotEmpty
              ? primaryDisplayName
              : fallbackDisplayName,
      email:
          primary.email.trim().isNotEmpty
              ? primary.email.trim()
              : fallback.email,
      phone:
          preferFallback && fallback.phone.trim().isNotEmpty
              ? fallback.phone.trim()
              : primary.phone.trim().isNotEmpty
              ? primary.phone.trim()
              : fallback.phone,
      role: primary.role,
      studentClass: resolvedStudentClass,
      series:
          preferFallback && fallback.series.trim().isNotEmpty
              ? fallback.series.trim()
              : primary.series.trim().isNotEmpty
              ? primary.series.trim()
              : fallback.series,
      school:
          preferFallback && fallback.school.trim().isNotEmpty
              ? fallback.school.trim()
              : primary.school.trim().isNotEmpty
              ? primary.school.trim()
              : fallback.school,
      avatarUrl:
          preferFallback && fallback.avatarUrl.trim().isNotEmpty
              ? fallback.avatarUrl.trim()
              : primary.avatarUrl.trim().isNotEmpty
              ? primary.avatarUrl.trim()
              : fallback.avatarUrl.trim(),
      createdAt: primary.createdAt,
      subscriptions:
          primary.subscriptions.isNotEmpty
              ? primary.subscriptions
              : fallback.subscriptions,
      abandonedSubjectIds:
          primary.abandonedSubjectIds.isNotEmpty
              ? primary.abandonedSubjectIds
              : fallback.abandonedSubjectIds,
    );
  }

  bool _needsProfileSync(UserModel current, UserModel resolved) {
    return current.displayName != resolved.displayName ||
        current.email != resolved.email ||
        current.phone != resolved.phone ||
        current.studentClass != resolved.studentClass ||
        current.series != resolved.series ||
        current.school != resolved.school ||
        current.avatarUrl != resolved.avatarUrl ||
        current.subscriptions.join('|') != resolved.subscriptions.join('|') ||
        current.abandonedSubjectIds.join('|') !=
            resolved.abandonedSubjectIds.join('|');
  }

  Future<UserModel> _loadOrCreateUserProfile(
    User user, {
    UserModel? preferredProfile,
  }) async {
    final fallbackProfile = preferredProfile ?? _profileFromAuthUser(user);
    final docRef = _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid);

    try {
      final doc = await docRef.get();
      if (doc.exists) {
        final storedProfile = UserModel.fromFirestore(doc);
        final resolvedProfile = _mergeProfiles(
          storedProfile,
          fallbackProfile,
          preferFallback: preferredProfile != null,
        );
        if (_needsProfileSync(storedProfile, resolvedProfile)) {
          await docRef.set(
            resolvedProfile.toFirestore(),
            SetOptions(merge: true),
          );
        }
        return resolvedProfile;
      }

      await docRef.set(fallbackProfile.toFirestore(), SetOptions(merge: true));
      return fallbackProfile;
    } on FirebaseException catch (e) {
      AppLogger.error(
        'AuthNotifier',
        'Échec chargement profil uid=${user.uid}',
        e,
      );
      return fallbackProfile;
    }
  }

  Future<User> _requireAuthenticatedUser() async {
    final user = _auth.currentUser;
    if (user != null) return user;
    throw FirebaseAuthException(
      code: 'user-not-found',
      message: 'Aucun utilisateur connecté.',
    );
  }

  Future<void> signIn(String email, String password) async {
    try {
      state = const AsyncValue.loading();
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Aucun utilisateur authentifié après la connexion.',
        );
      }
      await user.reload();
      final profile = await _loadOrCreateUserProfile(user);
      if (profile.blocked) {
        await _auth.signOut();
        final blocked = FirebaseAuthException(
          code: 'user-disabled',
          message: 'Ton compte a été suspendu. Contacte un administrateur.',
        );
        state = AsyncValue.error(blocked, StackTrace.current);
        throw blocked;
      }
      state = AsyncValue.data(profile);
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    } on FirebaseException catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> signInWithGoogle() async {
    try {
      state = const AsyncValue.loading();
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        throw FirebaseAuthException(
          code: 'aborted-by-user',
          message: 'Connexion Google annulée.',
        );
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Aucun utilisateur authentifié après la connexion Google.',
        );
      }
      final profile = await _loadOrCreateUserProfile(user);
      if (profile.blocked) {
        await signOut();
        final blocked = FirebaseAuthException(
          code: 'user-disabled',
          message: 'Ton compte a été suspendu. Contacte un administrateur.',
        );
        state = AsyncValue.error(blocked, StackTrace.current);
        throw blocked;
      }
      state = AsyncValue.data(profile);
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    } on FirebaseException catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> signInWithApple() async {
    try {
      state = const AsyncValue.loading();

      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      // Apple ne fournit le nom complet qu'à la toute première connexion.
      final firstName = appleCredential.givenName ?? '';
      final lastName = appleCredential.familyName ?? '';
      final fullName = [firstName, lastName]
          .where((s) => s.isNotEmpty)
          .join(' ')
          .trim();

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      final userCredential = await _auth.signInWithCredential(oauthCredential);
      final user = userCredential.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'Aucun utilisateur authentifié après la connexion Apple.',
        );
      }

      UserModel? preferredProfile;
      if (fullName.isNotEmpty &&
          (userCredential.additionalUserInfo?.isNewUser ?? false)) {
        await user.updateDisplayName(fullName);
        preferredProfile = _profileFromAuthUser(user).copyWith(
          displayName: fullName,
        );
      }

      final profile = await _loadOrCreateUserProfile(
        user,
        preferredProfile: preferredProfile,
      );

      if (profile.blocked) {
        await signOut();
        final blocked = FirebaseAuthException(
          code: 'user-disabled',
          message: 'Ton compte a été suspendu. Contacte un administrateur.',
        );
        state = AsyncValue.error(blocked, StackTrace.current);
        throw blocked;
      }

      state = AsyncValue.data(profile);
    } on SignInWithAppleAuthorizationException catch (e) {
      final isCancel = e.code == AuthorizationErrorCode.canceled;
      final mapped = FirebaseAuthException(
        code: isCancel ? 'aborted-by-user' : 'apple-auth-error',
        message: isCancel ? 'Connexion Apple annulée.' : e.message,
      );
      state = AsyncValue.error(mapped, StackTrace.current);
      throw mapped;
    } on SignInWithAppleNotSupportedException catch (_) {
      final mapped = FirebaseAuthException(
        code: 'apple-not-supported',
        message: 'Sign In with Apple non disponible sur cet appareil.',
      );
      state = AsyncValue.error(mapped, StackTrace.current);
      throw mapped;
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    } on FirebaseException catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    required String phone,
    required String series,
    required String school,
    required StudentClass studentClass,
  }) async {
    try {
      state = const AsyncValue.loading();
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = UserModel(
        uid: credential.user!.uid,
        displayName: displayName.trim(),
        email: email.trim(),
        phone: phone.trim(),
        role: UserRole.student,
        studentClass: studentClass,
        series: series.trim().toUpperCase(),
        school: school.trim(),
        avatarUrl: '',
        createdAt: DateTime.now(),
        subscriptions: [],
        abandonedSubjectIds: [],
      );
      await credential.user!.updateDisplayName(displayName.trim());
      await credential.user!.sendEmailVerification();
      final savedProfile = await _loadOrCreateUserProfile(
        credential.user!,
        preferredProfile: user,
      );
      state = AsyncValue.data(savedProfile);
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    } on FirebaseException catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    state = const AsyncValue.data(null);
  }

  Future<void> deleteMyAccount() async {
    await _requireAuthenticatedUser();

    try {
      state = const AsyncValue.loading();
      final callable = FirebaseFunctions.instanceFor(
        region: AppConstants.functionsRegion,
      ).httpsCallable('deleteMyAccount');

      await callable.call();
      await _googleSignIn.signOut();
      await _auth.signOut();
      state = const AsyncValue.data(null);
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    } on FirebaseFunctionsException catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    } on FirebaseException catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> markSubjectAbandoned(String subjectId) async {
    final firebaseUser = await _requireAuthenticatedUser();
    final currentProfile =
        state.value ?? await _loadOrCreateUserProfile(firebaseUser);
    if (currentProfile.abandonedSubjectIds.contains(subjectId)) {
      return;
    }

    final updatedProfile = currentProfile.copyWith(
      abandonedSubjectIds: [...currentProfile.abandonedSubjectIds, subjectId],
    );

    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(firebaseUser.uid)
          .update({'abandonedSubjectIds': updatedProfile.abandonedSubjectIds});

      state = AsyncValue.data(updatedProfile);
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    } on FirebaseException catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> updateProfile({
    required String displayName,
    required String phone,
    required String school,
    required StudentClass studentClass,
    required String series,
  }) async {
    final firebaseUser = await _requireAuthenticatedUser();
    final currentProfile =
        state.value ?? await _loadOrCreateUserProfile(firebaseUser);
    final updatedProfile = currentProfile.copyWith(
      displayName: displayName.trim(),
      phone: phone.trim(),
      school: school.trim(),
      studentClass: studentClass,
      series: series.trim(),
    );

    try {
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(firebaseUser.uid)
          .update({
            'displayName': updatedProfile.displayName,
            'phone': updatedProfile.phone,
            'school': updatedProfile.school,
            'class': updatedProfile.studentClass?.name,
            'series': updatedProfile.series,
          });

      if ((firebaseUser.displayName ?? '').trim() !=
          updatedProfile.displayName) {
        await firebaseUser.updateDisplayName(updatedProfile.displayName);
      }

      state = AsyncValue.data(updatedProfile);
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    } on FirebaseException catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final firebaseUser = await _requireAuthenticatedUser();
    final email = (firebaseUser.email ?? '').trim();

    if (email.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-email',
        message: 'Aucun email associé à ce compte.',
      );
    }

    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );

    await firebaseUser.reauthenticateWithCredential(credential);
    await firebaseUser.updatePassword(newPassword.trim());
  }

  Future<void> sendPasswordResetToCurrentEmail() async {
    final firebaseUser = await _requireAuthenticatedUser();
    final email = (firebaseUser.email ?? '').trim();

    if (email.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-email',
        message: 'Aucun email associé à ce compte.',
      );
    }

    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> sendEmailVerification() async {
    final firebaseUser = await _requireAuthenticatedUser();
    if (firebaseUser.emailVerified) return;
    await firebaseUser.sendEmailVerification();
  }

  Future<bool> reloadEmailVerificationStatus() async {
    final firebaseUser = await _requireAuthenticatedUser();
    await firebaseUser.reload();
    final refreshedUser = _auth.currentUser;
    if (refreshedUser == null) return false;

    final profile = state.value ?? await _loadOrCreateUserProfile(refreshedUser);
    state = AsyncValue.data(profile);
    return refreshedUser.emailVerified;
  }

  Future<void> updateProfilePhoto(File file) async {
    final firebaseUser = await _requireAuthenticatedUser();
    final currentProfile =
        state.value ?? await _loadOrCreateUserProfile(firebaseUser);
    final storageRef = _storage.ref(
      '${AppConstants.avatarsStoragePath}/${firebaseUser.uid}/profile_image',
    );

    await storageRef.putFile(
      file,
      SettableMetadata(
        contentType: _imageContentType(file.path),
        cacheControl: 'public,max-age=3600',
      ),
    );

    final downloadUrl = await storageRef.getDownloadURL();
    final separator = downloadUrl.contains('?') ? '&' : '?';
    final cacheBustedUrl =
        '$downloadUrl${separator}v=${DateTime.now().millisecondsSinceEpoch}';
    final updatedProfile = currentProfile.copyWith(avatarUrl: cacheBustedUrl);

    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(firebaseUser.uid)
        .update({'avatarUrl': cacheBustedUrl});

    await firebaseUser.updatePhotoURL(cacheBustedUrl);
    state = AsyncValue.data(updatedProfile);
  }

  Future<void> removeProfilePhoto() async {
    final firebaseUser = await _requireAuthenticatedUser();
    final currentProfile =
        state.value ?? await _loadOrCreateUserProfile(firebaseUser);
    final storageRef = _storage.ref(
      '${AppConstants.avatarsStoragePath}/${firebaseUser.uid}/profile_image',
    );

    try {
      await storageRef.delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') {
        rethrow;
      }
    }

    final updatedProfile = currentProfile.copyWith(avatarUrl: '');
    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(firebaseUser.uid)
        .update({'avatarUrl': ''});

    await firebaseUser.updatePhotoURL(null);
    state = AsyncValue.data(updatedProfile);
  }

  UserModel? get currentUser => state.value;
  bool get isAuthenticated => state.value != null;

  String _imageContentType(String path) {
    final normalized = path.toLowerCase();
    if (normalized.endsWith('.png')) return 'image/png';
    if (normalized.endsWith('.webp')) return 'image/webp';
    if (normalized.endsWith('.heic') || normalized.endsWith('.heif')) {
      return 'image/heic';
    }
    return 'image/jpeg';
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _tokenRefreshSubscription?.cancel();
    _profileSubscription?.cancel();
    super.dispose();
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<UserModel?>>((ref) {
      return AuthNotifier(
        FirebaseAuth.instance,
        FirebaseFirestore.instance,
        FirebaseStorage.instance,
        ref.watch(googleSignInProvider),
      );
    });

// ─── Helpers Apple Sign In ───────────────────────────────────────

String _generateNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}

String _sha256ofString(String input) {
  final bytes = utf8.encode(input);
  return sha256.convert(bytes).toString();
}

// Helper: message d'erreur Firebase Auth lisible
String firebaseAuthErrorMessage(FirebaseAuthException e) {
  switch (e.code) {
    case 'user-not-found':
      return 'Aucun compte trouvé pour cet email.';
    case 'wrong-password':
      return 'Mot de passe incorrect.';
    case 'invalid-credential':
      return 'Email ou mot de passe incorrect.';
    case 'email-already-in-use':
      return 'Cet email est déjà utilisé.';
    case 'weak-password':
      return 'Le mot de passe est trop faible (min. 6 caractères).';
    case 'invalid-email':
      return 'Adresse email invalide.';
    case 'missing-email':
      return 'Aucun email associé à ce compte.';
    case 'requires-recent-login':
      return 'Reconnecte-toi puis réessaie.';
    case 'network-request-failed':
      return 'Pas de connexion internet.';
    case 'too-many-requests':
      return 'Trop de tentatives. Réessayez plus tard.';
    case 'aborted-by-user':
      return 'Connexion annulée.';
    case 'apple-auth-error':
      return 'Erreur de connexion Apple. Réessaie.';
    case 'apple-not-supported':
      return 'Connexion Apple non disponible. Utilise un iPhone réel.';
    default:
      return 'Erreur : ${e.message}';
  }
}

String authErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    return firebaseAuthErrorMessage(error);
  }
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'unauthenticated':
        return 'Reconnecte-toi puis réessaie.';
      case 'failed-precondition':
        return error.message ?? 'Cette action n’est pas autorisée.';
      case 'internal':
        return error.message ?? 'Suppression impossible pour le moment.';
      default:
        return error.message ?? 'Une erreur est survenue côté serveur.';
    }
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Le profil n’est pas accessible pour le moment.';
      case 'failed-precondition':
        return error.message ?? 'Cette action n’est pas autorisée.';
      case 'internal':
        return error.message ?? 'Suppression impossible pour le moment.';
      case 'unauthorized':
        return 'Accès refusé au stockage. Vérifie les règles Firebase.';
      case 'unavailable':
        return 'Service temporairement indisponible. Réessaie dans un instant.';
      default:
        return 'Une erreur est survenue pendant le chargement du profil.';
    }
  }
  return 'Une erreur inattendue est survenue. Réessaie.';
}

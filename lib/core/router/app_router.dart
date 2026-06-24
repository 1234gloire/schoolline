import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/biometric_lock_provider.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/biometric_unlock_screen.dart';
import '../../features/auth/screens/verify_email_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/profile/screens/change_password_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/legal_information_screen.dart';
import '../../features/sessions/screens/planning_screen.dart';
import '../../features/exam/screens/exam_screen.dart';
import '../../features/submission/screens/submission_screen.dart';
import '../../features/results/screens/results_screen.dart';
import '../../features/results/screens/result_detail_screen.dart';
import '../../features/payment/screens/payment_screen.dart';
import '../../features/sessions/screens/request_on_demand_session_screen.dart';
import '../../features/sessions/screens/session_ranking_screen.dart';
import '../../features/notifications/screens/announcements_screen.dart';

// Routes nommées
class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const register = '/register';
  static const verifyEmail = '/verify-email';
  static const unlock = '/unlock';
  static const dashboard = '/dashboard';
  static const editProfile = '/profile/edit';
  static const changePassword = '/profile/password';
  static const legalInformation = '/profile/legal';
  static const planning = '/planning';
  static const planningSession = '/planning/:sessionId';
  static const exam = '/sessions/:sessionId/exam/:subjectId';
  static const submission = '/sessions/:sessionId/submission/:subjectId';
  static const results = '/results';
  static const resultDetail = '/results/:submissionId';
  static const payment = '/payment/:sessionId';
  static const requestOnDemandSession = '/sessions/request';
  static const sessionRanking = '/sessions/:sessionId/ranking';
  static const announcements = '/announcements';

  static String planningSessionPath(String sessionId) => '/planning/$sessionId';

  static String sessionRankingPath(String sessionId) =>
      '/sessions/$sessionId/ranking';

  static String examPath({
    required String sessionId,
    required String subjectId,
  }) => '/sessions/$sessionId/exam/$subjectId';

  static String submissionPath({
    required String sessionId,
    required String subjectId,
  }) => '/sessions/$sessionId/submission/$subjectId';

  static String resultDetailPath(String submissionId) =>
      '/results/$submissionId';

  static String paymentPath(String sessionId) => '/payment/$sessionId';
}

/// Durée minimale d'affichage du splash (animations = 1500 ms + marge).
/// GoRouter ne redirige pas tant que ce provider est false.
final splashReadyProvider = StateProvider<bool>((ref) => false);

// Notifier qui écoute l'auth ET la fin du splash pour déclencher les redirections
class _AuthNotifier extends ChangeNotifier {
  _AuthNotifier(this._ref) {
    _ref.listen<AsyncValue<User?>>(
      authStateProvider,
      (_, __) => notifyListeners(),
    );
    _ref.listen<AsyncValue<UserModel?>>(
      authNotifierProvider,
      (_, __) => notifyListeners(),
    );
    _ref.listen<bool>(
      splashReadyProvider,
      (_, __) => notifyListeners(),
    );
    _ref.listen<BiometricLockState>(
      biometricLockProvider,
      (_, __) => notifyListeners(),
    );
  }
  final Ref _ref;
}

final routerProvider = Provider<GoRouter>((ref) {
  final notifier = _AuthNotifier(ref);

  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    refreshListenable: notifier,
    redirect: (context, state) {
      final sessionState = ref.read(authStateProvider);
      final isLoading = sessionState.isLoading;
      final splashReady = ref.read(splashReadyProvider);
      final isAuthenticated =
          sessionState.asData?.value != null ||
          ref.read(firebaseAuthProvider).currentUser != null;
      final location = state.matchedLocation;
      final onSplash = location == AppRoutes.splash;
      final onPublicAuthScreen =
          location == AppRoutes.login || location == AppRoutes.register;
      final onVerifyEmail = location == AppRoutes.verifyEmail;
      final onUnlock = location == AppRoutes.unlock;
      final biometricLock = ref.read(biometricLockProvider);
      final currentFirebaseUser =
          sessionState.asData?.value ?? ref.read(firebaseAuthProvider).currentUser;
      final needsEmailVerification =
          _requiresEmailVerification(currentFirebaseUser);

      // Rester sur splash tant que l'auth charge OU que l'animation n'est pas finie
      if (isLoading || (onSplash && !splashReady)) {
        return onSplash ? null : AppRoutes.splash;
      }

      // Session rétablie → sortir des écrans publics
      if (isAuthenticated && (onSplash || onPublicAuthScreen)) {
        if (needsEmailVerification) return AppRoutes.verifyEmail;
        if (biometricLock.enabled && biometricLock.locked) {
          return AppRoutes.unlock;
        }
        return AppRoutes.dashboard;
      }

      // Pas de session → splash envoie vers login
      if (!isAuthenticated && onSplash) return AppRoutes.login;

      // Non authentifié + écran protégé → login
      if (!isAuthenticated && !onPublicAuthScreen) return AppRoutes.login;

      if (isAuthenticated && needsEmailVerification && !onVerifyEmail) {
        return AppRoutes.verifyEmail;
      }

      if (isAuthenticated && onVerifyEmail && !needsEmailVerification) {
        return AppRoutes.dashboard;
      }

      if (isAuthenticated &&
          biometricLock.enabled &&
          biometricLock.locked &&
          !onUnlock) {
        return AppRoutes.unlock;
      }

      if (isAuthenticated && onUnlock && !biometricLock.locked) {
        return AppRoutes.dashboard;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder:
            (context, state) => _fadeTransition(state, const SplashScreen()),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder:
            (context, state) => _fadeTransition(state, const LoginScreen()),
      ),
      GoRoute(
        path: AppRoutes.register,
        pageBuilder:
            (context, state) => _slideTransition(state, const RegisterScreen()),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        pageBuilder:
            (context, state) =>
                _fadeTransition(state, const VerifyEmailScreen()),
      ),
      GoRoute(
        path: AppRoutes.unlock,
        pageBuilder:
            (context, state) =>
                _fadeTransition(state, const BiometricUnlockScreen()),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        pageBuilder:
            (context, state) => _fadeTransition(state, const DashboardScreen()),
      ),
      GoRoute(
        path: AppRoutes.editProfile,
        pageBuilder:
            (context, state) =>
                _slideTransition(state, const EditProfileScreen()),
      ),
      GoRoute(
        path: AppRoutes.changePassword,
        pageBuilder:
            (context, state) =>
                _slideTransition(state, const ChangePasswordScreen()),
      ),
      GoRoute(
        path: AppRoutes.legalInformation,
        pageBuilder:
            (context, state) =>
                _slideTransition(state, const LegalInformationScreen()),
      ),
      GoRoute(
        path: AppRoutes.planning,
        pageBuilder:
            (context, state) =>
                _slideTransition(state, const PlanningScreen(isRoute: true)),
      ),
      GoRoute(
        path: AppRoutes.planningSession,
        pageBuilder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          return _slideTransition(
            state,
            PlanningScreen(sessionId: sessionId, isRoute: true),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.exam,
        pageBuilder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          final subjectId = state.pathParameters['subjectId']!;
          final extra = _readExtraMap(state.extra);
          return _slideTransition(
            state,
            ExamScreen(
              sessionId: sessionId,
              subjectId: subjectId,
              extra: extra,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.submission,
        pageBuilder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          final subjectId = state.pathParameters['subjectId']!;
          final extra = _readExtraMap(state.extra);
          return _slideTransition(
            state,
            SubmissionScreen(
              sessionId: sessionId,
              subjectId: subjectId,
              extra: extra,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.results,
        pageBuilder:
            (context, state) => _slideTransition(state, const ResultsScreen()),
      ),
      GoRoute(
        path: AppRoutes.resultDetail,
        pageBuilder: (context, state) {
          final submissionId = state.pathParameters['submissionId']!;
          final extra = _readExtraMap(state.extra);
          return _slideTransition(
            state,
            ResultDetailScreen(submissionId: submissionId, extra: extra),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.payment,
        pageBuilder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          final extra = _readExtraMap(state.extra);
          final session = extra?['session'];
          return _slideTransition(
            state,
            PaymentScreen(sessionId: sessionId, session: session),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.requestOnDemandSession,
        pageBuilder: (context, state) => _slideTransition(
          state,
          const RequestOnDemandSessionScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.sessionRanking,
        pageBuilder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          return _slideTransition(
            state,
            SessionRankingScreen(sessionId: sessionId),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.announcements,
        pageBuilder: (context, state) =>
            _slideTransition(state, const AnnouncementsScreen()),
      ),
    ],
    errorBuilder:
        (context, state) => Scaffold(
          body: Center(child: Text('Page introuvable: ${state.uri}')),
        ),
  );
});

bool _requiresEmailVerification(User? user) {
  if (user == null || user.emailVerified) return false;
  return user.providerData.any((info) => info.providerId == 'password');
}

Map<String, dynamic>? _readExtraMap(Object? extra) {
  if (extra is Map<String, dynamic>) {
    return extra;
  }

  return null;
}

/// Transition douce pour les routes top-level (dashboard, auth…)
/// Fondu + léger lift vertical — propre, non-distrayant.
CustomTransitionPage<void> _fadeTransition(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      final lift = Tween<Offset>(
        begin: const Offset(0.0, 0.035),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return FadeTransition(
        opacity: fade,
        child: SlideTransition(position: lift, child: child),
      );
    },
  );
}

/// Transition push pour les écrans enfant (profil, exam, résultats…).
/// Utilise CupertinoPage pour obtenir le swipe-back natif (bord gauche → droite)
/// sur iOS ET Android, tout en gardant le slide horizontal standard.
Page<void> _slideTransition(GoRouterState state, Widget child) {
  return CupertinoPage<void>(
    key: state.pageKey,
    child: child,
  );
}

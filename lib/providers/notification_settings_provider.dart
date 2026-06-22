import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/app_logger.dart';

const _kSettingsBox = 'settings';
const kNotificationsEnabledKey = 'notifications_enabled';
const kNotificationsPromptShownKey = 'notifications_prompt_shown';

/// Préférence locale (Hive) : l'utilisateur a-t-il activé les notifications ?
/// Par défaut `true` pour conserver l'opt-in automatique au premier login.
bool notificationsLocallyEnabled() {
  final box = Hive.box<dynamic>(_kSettingsBox);
  return box.get(kNotificationsEnabledKey, defaultValue: true) as bool;
}

bool _isAuthorized(AuthorizationStatus s) =>
    s == AuthorizationStatus.authorized ||
    s == AuthorizationStatus.provisional;

class NotificationSettingsState {
  /// État effectif du commutateur : préférence locale ET permission OS accordée.
  final bool enabled;

  /// Statut système (autorisé, refusé, non déterminé…).
  final AuthorizationStatus osStatus;

  const NotificationSettingsState({
    required this.enabled,
    required this.osStatus,
  });

  /// Permission refusée au niveau du système (nécessite les réglages OS).
  bool get osBlocked => osStatus == AuthorizationStatus.denied;
}

final notificationSettingsProvider = AsyncNotifierProvider<
  NotificationSettingsNotifier,
  NotificationSettingsState
>(NotificationSettingsNotifier.new);

class NotificationSettingsNotifier
    extends AsyncNotifier<NotificationSettingsState> {
  @override
  Future<NotificationSettingsState> build() => _read();

  Future<NotificationSettingsState> _read() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    final os = settings.authorizationStatus;
    final enabled = notificationsLocallyEnabled() && _isAuthorized(os);
    return NotificationSettingsState(enabled: enabled, osStatus: os);
  }

  Future<void> refresh() async {
    state = AsyncData(await _read());
  }

  /// Active les notifications : demande la permission puis enregistre le token.
  /// Retourne `false` si le système bloque (l'UI proposera d'ouvrir les réglages).
  Future<bool> enable() async {
    _setFlag(true);
    final messaging = FirebaseMessaging.instance;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final os = settings.authorizationStatus;

    if (!_isAuthorized(os)) {
      state = AsyncData(NotificationSettingsState(enabled: false, osStatus: os));
      return false;
    }

    await _saveToken();
    state = AsyncData(NotificationSettingsState(enabled: true, osStatus: os));
    return true;
  }

  /// Désactive les notifications : supprime le token Firestore pour que le
  /// serveur cesse d'envoyer à cet appareil.
  Future<void> disable() async {
    _setFlag(false);
    await _deleteToken();
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    state = AsyncData(
      NotificationSettingsState(enabled: false, osStatus: settings.authorizationStatus),
    );
  }

  // ── Prompt premier lancement ──
  bool get promptAlreadyShown =>
      Hive.box<dynamic>(_kSettingsBox)
          .get(kNotificationsPromptShownKey, defaultValue: false) as bool;

  void markPromptShown() {
    Hive.box<dynamic>(_kSettingsBox).put(kNotificationsPromptShownKey, true);
  }

  // ── Helpers ──
  void _setFlag(bool value) {
    Hive.box<dynamic>(_kSettingsBox).put(kNotificationsEnabledKey, value);
  }

  Future<void> _saveToken() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final messaging = FirebaseMessaging.instance;

      // iOS/macOS : attendre le token APNS (jusqu'à 5 s).
      if (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        String? apns;
        for (var i = 0; i < 5 && apns == null; i++) {
          apns = await messaging.getAPNSToken();
          if (apns == null) await Future.delayed(const Duration(seconds: 1));
        }
        if (apns == null) return;
      }

      final token = await messaging.getToken();
      if (token == null) return;

      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({'fcmToken': token});
    } catch (e) {
      AppLogger.warn('NotificationSettings', 'Échec enregistrement token: $e');
    }
  }

  Future<void> _deleteToken() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .update({'fcmToken': FieldValue.delete()});
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      AppLogger.warn('NotificationSettings', 'Échec suppression token: $e');
    }
  }
}

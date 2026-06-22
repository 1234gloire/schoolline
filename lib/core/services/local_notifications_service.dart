import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationsService {
  LocalNotificationsService._();

  static final LocalNotificationsService instance =
      LocalNotificationsService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<Map<String, dynamic>> _tapController =
      StreamController<Map<String, dynamic>>.broadcast();

  bool _initialized = false;
  Map<String, dynamic>? _pendingPayload;

  Stream<Map<String, dynamic>> get tapStream => _tapController.stream;

  Future<void> initialize() async {
    if (_initialized) return;

    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    await _createAndroidChannels();

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchPayload = launchDetails?.notificationResponse?.payload;
    if (launchPayload != null && launchPayload.isNotEmpty) {
      _emitPayload(_decodePayload(launchPayload));
    }

    _initialized = true;
  }

  Future<void> showRemoteMessage(RemoteMessage message) async {
    await initialize();

    final title = message.notification?.title?.trim() ?? '';
    final body = message.notification?.body?.trim() ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final data = Map<String, dynamic>.from(message.data);
    final type = data['type'] as String? ?? '';
    final channelId = type == 'exam_reminder'
        ? _examRemindersChannel.id
        : _generalUpdatesChannel.id;
    final channelName = type == 'exam_reminder'
        ? _examRemindersChannel.name
        : _generalUpdatesChannel.name;
    final channelDescription = type == 'exam_reminder'
        ? _examRemindersChannel.description
        : _generalUpdatesChannel.description;

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title.isEmpty ? 'Nouvelle notification' : title,
      body.isEmpty ? null : body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(data),
    );
  }

  Map<String, dynamic>? consumePendingPayload() {
    final payload = _pendingPayload;
    _pendingPayload = null;
    return payload;
  }

  Future<void> dispose() async {
    await _tapController.close();
  }

  Future<void> _createAndroidChannels() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    await androidPlugin.createNotificationChannel(_examRemindersChannel);
    await androidPlugin.createNotificationChannel(_generalUpdatesChannel);
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    _emitPayload(_decodePayload(payload));
  }

  void _emitPayload(Map<String, dynamic> payload) {
    if (_tapController.hasListener) {
      _tapController.add(payload);
      return;
    }
    _pendingPayload = payload;
  }

  Map<String, dynamic> _decodePayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return const <String, dynamic>{};
    }
    return const <String, dynamic>{};
  }
}

const AndroidNotificationChannel _examRemindersChannel =
    AndroidNotificationChannel(
      'exam_reminders',
      'Rappels d\'épreuves',
      description:
          'Notifications 30, 15 et 5 minutes avant le début d\'une épreuve.',
      importance: Importance.high,
      playSound: true,
    );

const AndroidNotificationChannel _generalUpdatesChannel =
    AndroidNotificationChannel(
      'general_updates',
      'Mises à jour DiakExam',
      description:
          'Validation de paiements, résultats publiés et notifications utiles.',
      importance: Importance.high,
      playSound: true,
    );

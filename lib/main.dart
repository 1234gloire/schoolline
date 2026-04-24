import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';
import 'core/services/local_notifications_service.dart';
import 'firebase_options.dart';

/// Handler de messages FCM quand l'app est fermée ou en arrière-plan.
/// Doit être une fonction top-level (pas de classe, pas de closure).
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Pas de navigation possible depuis ici — iOS/Android affichent la notification
  // système automatiquement. La navigation se fait via onMessageOpenedApp dans app.dart.
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Orientation portrait uniquement
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Barre de statut / nav : ajustée selon le thème dans app.dart (MaterialApp.builder)

  // Initialise la locale française pour intl
  await initializeLocale();

  // Initialise Hive pour la queue offline
  await Hive.initFlutter();
  await Hive.openBox<String>('submission_queue');
  await Hive.openBox<dynamic>('settings');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Handler background / app fermée
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Afficher les notifications FCM quand l'app est au premier plan (iOS)
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  await LocalNotificationsService.instance.initialize();

  runApp(
    const ProviderScope(
      child: ExamSimApp(),
    ),
  );
}

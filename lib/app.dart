import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/router/app_router.dart';
import 'core/services/local_notifications_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/exam_sim_palette.dart';
import 'providers/offline_queue_provider.dart';
import 'providers/theme_mode_provider.dart';

class ExamSimApp extends ConsumerStatefulWidget {
  const ExamSimApp({super.key});

  @override
  ConsumerState<ExamSimApp> createState() => _ExamSimAppState();
}

class _ExamSimAppState extends ConsumerState<ExamSimApp> {
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<Map<String, dynamic>>? _localNotificationTapSub;

  @override
  void initState() {
    super.initState();
    _setupFcm();
    _localNotificationTapSub = LocalNotificationsService.instance.tapStream
        .listen(_handleNotificationNavigation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingPayload =
          LocalNotificationsService.instance.consumePendingPayload();
      if (pendingPayload != null && mounted) {
        _handleNotificationNavigation(pendingPayload);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(offlineQueueProvider.notifier).processQueue();
    });
  }

  Future<void> _setupFcm() async {
    // 1. App lancée depuis une notification (app était fermée)
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null && mounted) {
      // addPostFrameCallback garantit que le router est monté avant de naviguer
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleNotificationNavigation(initial.data);
      });
    }

    // 2. App en arrière-plan, utilisateur tape la notification
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      if (mounted) _handleNotificationNavigation(message.data);
    });

    // 3. App au premier plan : affiche une notification locale native
    _foregroundSub = FirebaseMessaging.onMessage.listen((message) async {
      if (!mounted) return;
      await LocalNotificationsService.instance.showRemoteMessage(message);
    });
  }

  void _handleNotificationNavigation(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    final router = ref.read(routerProvider);

    switch (type) {
      case 'result_published':
      case 'results_published':
        router.go('/results');
        break;
      case 'payment_approved':
      case 'payment_rejected':
        router.go('/results');
        break;
      case 'exam_reminder':
        final sessionId = data['sessionId'] as String?;
        if (sessionId != null && sessionId.isNotEmpty) {
          router.go('/planning/$sessionId');
        } else {
          router.go('/dashboard');
        }
        break;
      default:
        router.go('/dashboard');
    }
  }

  @override
  void dispose() {
    _foregroundSub?.cancel();
    _localNotificationTapSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final mode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'ExamSim Congo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: mode,
      builder: (context, child) {
        final b = Theme.of(context).brightness;
        final p = context.palette;
        final overlay = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              b == Brightness.dark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: p.surface,
          systemNavigationBarIconBrightness:
              b == Brightness.dark ? Brightness.light : Brightness.dark,
        );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          child: child ?? const SizedBox.shrink(),
        );
      },
      routerConfig: router,
    );
  }
}

Future<void> initializeLocale() async {
  await initializeDateFormatting('fr', null);
}

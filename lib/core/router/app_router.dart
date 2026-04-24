import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
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

// Routes nommées
class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const register = '/register';
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

  static String planningSessionPath(String sessionId) => '/planning/$sessionId';

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

      // Rester sur splash tant que l'auth charge OU que l'animation n'est pas finie
      if (isLoading || (onSplash && !splashReady)) {
        return onSplash ? null : AppRoutes.splash;
      }

      // Session rétablie → sortir des écrans publics
      if (isAuthenticated && (onSplash || onPublicAuthScreen)) {
        return AppRoutes.dashboard;
      }

      // Pas de session → splash envoie vers login
      if (!isAuthenticated && onSplash) return AppRoutes.login;

      // Non authentifié + écran protégé → login
      if (!isAuthenticated && !onPublicAuthScreen) return AppRoutes.login;

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
    ],
    errorBuilder:
        (context, state) => Scaffold(
          body: Center(child: Text('Page introuvable: ${state.uri}')),
        ),
  );
});

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

/// Transition push pour les écrans enfant (profil, exam, résultats…)
/// Slide depuis la droite + fondu en entrée, recul léger à la sortie.
CustomTransitionPage<void> _slideTransition(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Entrée : slide depuis droite
      final enterSlide = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

      // Entrée : fondu rapide sur la première moitié
      final enterFade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: animation,
          curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
        ),
      );

      // Sortie : l'écran précédent recule légèrement sur la gauche
      final exitSlide = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.28, 0.0),
      ).animate(
        CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInCubic),
      );

      return SlideTransition(
        position: exitSlide,
        child: SlideTransition(
          position: enterSlide,
          child: FadeTransition(opacity: enterFade, child: child),
        ),
      );
    },
  );
}

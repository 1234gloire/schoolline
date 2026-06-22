import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  // Contrôleur principal (joue une fois) — séquence d'entrée
  late AnimationController _entry;
  // Contrôleur secondaire (boucle) — pulsation du halo
  late AnimationController _pulse;

  // Entrées séquencées
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _taglineFade;
  late Animation<double> _loaderFade;

  // Pulsation
  late Animation<double> _halo;
  late Animation<double> _haloOuter;

  @override
  void initState() {
    super.initState();

    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    // Logo : spring élastique centré sur les 0–45 %
    _logoScale = Tween<double>(begin: 0.25, end: 1.0).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.0, 0.45, curve: Curves.elasticOut),
      ),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.0, 0.22, curve: Curves.easeOut),
      ),
    );

    // Le logo contient deja le nom de l'app, donc on anime seulement
    // le bloc logo puis la signature.
    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.40, 0.68, curve: Curves.easeOut),
      ),
    );

    // Loader : fondu 65–88 %
    _loaderFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.65, 0.88, curve: Curves.easeOut),
      ),
    );

    // Halo interne (ring doré proche)
    _halo = Tween<double>(begin: 0.3, end: 0.95).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    // Halo externe (ring plus grand, décalé visuellement)
    _haloOuter = Tween<double>(begin: 0.1, end: 0.5).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );

    _entry.forward();

    // Durée minimale 2400 ms — laisse toutes les animations terminer
    // avant que GoRouter soit autorisé à rediriger.
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted) {
        ref.read(splashReadyProvider.notifier).state = true;
      }
    });
  }

  @override
  void dispose() {
    _entry.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final logoWidth = (constraints.maxWidth * 0.68).clamp(230.0, 310.0);
            final logoHeight = logoWidth / 1.5;

            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: Listenable.merge([_entry, _pulse]),
                    builder: (context, _) {
                      final glowWidth = logoWidth + 16 + (_haloOuter.value * 30);
                      final glowHeight = logoHeight + 24 + (_halo.value * 22);

                      return FadeTransition(
                        opacity: _logoFade,
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: SizedBox(
                            width: logoWidth + 44,
                            height: logoHeight + 56,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: glowWidth,
                                  height: glowHeight,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primaryLight.withAlpha(
                                          (_haloOuter.value * 110).toInt(),
                                        ),
                                        blurRadius: 42,
                                        spreadRadius: 6,
                                      ),
                                      BoxShadow(
                                        color: AppColors.accent.withAlpha(
                                          (_halo.value * 70).toInt(),
                                        ),
                                        blurRadius: 34,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                                Image.asset(
                                  'assets/images/logo_diakexam.png',
                                  width: logoWidth,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  FadeTransition(
                    opacity: _taglineFade,
                    child: Text(
                      'Simulation d\'examens nationaux',
                      style: TextStyle(
                        color: Colors.white.withAlpha(185),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 44),
                  FadeTransition(
                    opacity: _loaderFade,
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.accent.withAlpha(210),
                        ),
                        strokeWidth: 2.5,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

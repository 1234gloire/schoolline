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
  late Animation<Offset> _titleSlide;
  late Animation<double> _titleFade;
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

    // Titre : monte depuis le bas 30–60 %
    _titleSlide = Tween<Offset>(
      begin: const Offset(0.0, 0.7),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.32, 0.62, curve: Curves.easeOutCubic),
      ),
    );
    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.30, 0.58, curve: Curves.easeOut),
      ),
    );

    // Tagline : fondu 50–75 %
    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.50, 0.75, curve: Curves.easeOut),
      ),
    );

    // Loader : fondu 70–90 %
    _loaderFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.70, 0.90, curve: Curves.easeOut),
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
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Logo avec halo pulsant ──
              AnimatedBuilder(
                animation: Listenable.merge([_entry, _pulse]),
                builder: (context, _) {
                  return FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: SizedBox(
                        width: 160,
                        height: 160,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Ring externe — très doux
                            Container(
                              width: 152,
                              height: 152,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.accent.withAlpha(
                                    (_haloOuter.value * 140).toInt(),
                                  ),
                                  width: 1.0,
                                ),
                              ),
                            ),
                            // Ring interne — doré vif
                            Container(
                              width: 124,
                              height: 124,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.accent.withAlpha(
                                    (_halo.value * 200).toInt(),
                                  ),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            // Badge logo
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(20),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.accent,
                                  width: 2.5,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.accent.withAlpha(
                                      (_halo.value * 110).toInt(),
                                    ),
                                    blurRadius: 28,
                                    spreadRadius: 4,
                                  ),
                                  BoxShadow(
                                    color: AppColors.primaryLight.withAlpha(80),
                                    blurRadius: 16,
                                    spreadRadius: -4,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.school_rounded,
                                color: AppColors.accent,
                                size: 50,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 32),

              // ── Titre ──
              FadeTransition(
                opacity: _titleFade,
                child: SlideTransition(
                  position: _titleSlide,
                  child: const Text(
                    'ExamSim Congo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ── Tagline ──
              FadeTransition(
                opacity: _taglineFade,
                child: Text(
                  'Simulation d\'examens nationaux',
                  style: TextStyle(
                    color: Colors.white.withAlpha(175),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.2,
                  ),
                ),
              ),

              const SizedBox(height: 56),

              // ── Indicateur de chargement ──
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
        ),
      ),
    );
  }
}

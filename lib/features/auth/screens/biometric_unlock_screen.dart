import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/biometric_lock_provider.dart';

class BiometricUnlockScreen extends ConsumerStatefulWidget {
  const BiometricUnlockScreen({super.key});

  @override
  ConsumerState<BiometricUnlockScreen> createState() =>
      _BiometricUnlockScreenState();
}

class _BiometricUnlockScreenState extends ConsumerState<BiometricUnlockScreen> {
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_requested || !mounted) return;
    _requested = true;
    final ok = await ref.read(biometricLockProvider.notifier).authenticate();
    if (!mounted) return;
    if (ok) context.go(AppRoutes.dashboard);
    _requested = false;
  }

  Future<void> _signOut() async {
    await ref.read(authNotifierProvider.notifier).signOut();
    if (mounted) context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(biometricLockProvider);
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 92,
                height: 92,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.fingerprint_rounded,
                  size: 54,
                  color: AppColors.primary,
                ),
              ),
              Text(
                'Déverrouillage requis',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Utilise Face ID, Touch ID ou ton empreinte pour continuer.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary, height: 1.4),
              ),
              if (lock.errorMessage != null) ...[
                const SizedBox(height: 18),
                Text(
                  lock.errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.error),
                ),
              ],
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: lock.authenticating ? null : _unlock,
                icon:
                    lock.authenticating
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.lock_open_rounded),
                label: Text(
                  lock.authenticating
                      ? 'Vérification...'
                      : 'Déverrouiller',
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: lock.authenticating ? null : _signOut,
                child: const Text('Changer de compte'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../providers/auth_provider.dart';

class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  bool _checking = false;
  bool _resending = false;

  Future<void> _checkVerification() async {
    setState(() => _checking = true);
    try {
      final verified =
          await ref
              .read(authNotifierProvider.notifier)
              .reloadEmailVerificationStatus();
      if (!mounted) return;
      if (verified) {
        context.go(AppRoutes.dashboard);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email pas encore vérifié. Vérifie ta boîte mail.'),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _resendEmail() async {
    setState(() => _resending = true);
    try {
      await ref.read(authNotifierProvider.notifier).sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email de vérification renvoyé.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(authNotifierProvider.notifier).signOut();
    if (mounted) context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'ton adresse email';
    final p = context.palette;

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: _signOut,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded),
                ),
              ),
              const Spacer(),
              Container(
                width: 92,
                height: 92,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(14),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_unread_outlined,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
              Text(
                'Vérifie ton email',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'On a envoyé un lien de vérification à $email. Ouvre le lien, puis reviens ici.',
                textAlign: TextAlign.center,
                style: TextStyle(color: p.textSecondary, height: 1.45),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: _checking ? null : _checkVerification,
                icon:
                    _checking
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.verified_outlined),
                label: Text(_checking ? 'Vérification...' : 'J’ai vérifié'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _resending ? null : _resendEmail,
                icon:
                    _resending
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.refresh_rounded),
                label: Text(_resending ? 'Envoi...' : 'Renvoyer le mail'),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: _signOut,
                child: const Text('Utiliser un autre compte'),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

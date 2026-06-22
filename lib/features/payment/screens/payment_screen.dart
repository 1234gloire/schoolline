import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../core/router/app_router.dart';
import '../../../models/payment_model.dart';
import '../../../models/session_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/payments_provider.dart';
import '../../../providers/sessions_provider.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final SessionModel? session;

  const PaymentScreen({super.key, required this.sessionId, this.session});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  void _payWithMobileMoney(SessionModel session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MobileMoneyCheckoutScreen(session: session),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.value;

    if (authState.isLoading && user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (user == null) {
      return Scaffold(
        body: _StateView(
          icon: Icons.lock_outline,
          title: 'Connexion requise',
          message: 'Reconnecte-toi pour payer cette session.',
        ),
      );
    }

    final sessionAsync = widget.session != null
        ? AsyncValue<SessionModel?>.data(widget.session)
        : ref.watch(sessionByIdProvider(widget.sessionId));

    return sessionAsync.when(
      data: (session) {
        if (session == null) {
          return Scaffold(
            body: _StateView(
              icon: Icons.event_busy_outlined,
              title: 'Session introuvable',
              message: "Cette session n'existe plus.",
            ),
          );
        }

        if (!sessionMatchesStudent(session, user)) {
          return Scaffold(
            appBar: AppBar(title: const Text('Paiement')),
            body: _StateView(
              icon: Icons.lock_outline,
              title: 'Accès refusé',
              message: 'Cette session ne correspond pas à ton profil scolaire.',
              actionLabel: 'Retour',
              onAction: () => context.go(AppRoutes.planningSessionPath(session.id)),
            ),
          );
        }

        if (session.status == SessionStatus.closed ||
            session.status == SessionStatus.resultsPublished) {
          return Scaffold(
            appBar: AppBar(title: const Text('Paiement')),
            body: _StateView(
              icon: Icons.event_busy_outlined,
              title: 'Session terminée',
              message: 'Les inscriptions sont closes.',
              actionLabel: 'Retour',
              onAction: () => context.go(AppRoutes.planningSessionPath(session.id)),
            ),
          );
        }

        if (session.price <= 0) {
          return Scaffold(
            appBar: AppBar(title: const Text('Paiement')),
            body: _StateView(
              icon: Icons.check_circle_outline,
              title: 'Session gratuite',
              message: "Aucun paiement requis.",
              actionLabel: 'Voir le planning',
              onAction: () => context.go(AppRoutes.planningSessionPath(session.id)),
            ),
          );
        }

        final paymentAsync = ref.watch(
          paymentForSessionProvider((
            userId: user.uid,
            sessionId: session.id,
          )),
        );

        return Scaffold(
          backgroundColor: context.palette.background,
          appBar: AppBar(
            title: const Text('Paiement de la session'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios),
              onPressed: () =>
                  context.go(AppRoutes.planningSessionPath(session.id)),
            ),
          ),
          body: paymentAsync.when(
            data: (existingPayment) {
              if (existingPayment != null &&
                  existingPayment.isPending &&
                  !existingPayment.isGhostPending) {
                return _PendingView(
                  payment: existingPayment,
                  session: session,
                  onResumePayment: existingPayment.isMobileMoney
                      ? () => _payWithMobileMoney(session)
                      : null,
                );
              }
              if (existingPayment != null && existingPayment.isApproved) {
                return _ApprovedView(session: session);
              }
              return _PaymentForm(
                session: session,
                rejectedPayment:
                    existingPayment?.isRejected == true ? existingPayment : null,
                onPay: () => _payWithMobileMoney(session),
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => _StateView(
              icon: Icons.sync_problem_outlined,
              title: 'Paiement indisponible',
              message: 'Impossible de charger le statut de paiement.',
              actionLabel: 'Réessayer',
              onAction: () => ref.invalidate(
                paymentForSessionProvider((
                  userId: user.uid,
                  sessionId: session.id,
                )),
              ),
            ),
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: _StateView(
          icon: Icons.sync_problem_outlined,
          title: 'Session indisponible',
          message: 'Impossible de charger cette session.',
          actionLabel: 'Réessayer',
          onAction: () =>
              ref.invalidate(sessionByIdProvider(widget.sessionId)),
        ),
      ),
    );
  }
}

// ─── Checkout Mobile Money ────────────────────────────────────────

enum _MobileMoneyStage { phone, submitting, pending, approved, rejected }

class _MobileMoneyCheckoutScreen extends StatefulWidget {
  final SessionModel session;

  const _MobileMoneyCheckoutScreen({required this.session});

  @override
  State<_MobileMoneyCheckoutScreen> createState() =>
      _MobileMoneyCheckoutScreenState();
}

class _MobileMoneyCheckoutScreenState
    extends State<_MobileMoneyCheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  _MobileMoneyStage _stage = _MobileMoneyStage.phone;
  String? _paymentId;
  String? _errorMessage;
  bool _polling = false;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final localNumber = digits.startsWith('0') ? digits.substring(1) : digits;
    final phoneNumber = '242$localNumber';

    setState(() {
      _stage = _MobileMoneyStage.submitting;
      _errorMessage = null;
    });

    try {
      final result = await FirebaseFunctions.instanceFor(
        region: AppConstants.functionsRegion,
      ).httpsCallable('createPawapayPayment').call({
        'sessionId': widget.session.id,
        'phoneNumber': phoneNumber,
      });

      _paymentId = result.data['paymentId'] as String;
      if (!mounted) return;
      setState(() => _stage = _MobileMoneyStage.pending);
      _startPolling();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _MobileMoneyStage.phone;
        _errorMessage = e.code == 'already-exists'
            ? 'Tu as déjà accès à cette session.'
            : (e.message ?? 'Numéro invalide ou paiement refusé. Réessaie.');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _MobileMoneyStage.phone;
        _errorMessage = 'Erreur réseau. Vérifie ta connexion et réessaie.';
      });
    }
  }

  Future<void> _startPolling() async {
    if (_polling) return;
    _polling = true;
    const maxTries = 25;
    const interval = Duration(seconds: 4);

    final callable = FirebaseFunctions.instanceFor(
      region: AppConstants.functionsRegion,
    ).httpsCallable('checkPawapayPaymentStatus');

    var tries = 0;
    while (tries < maxTries && mounted) {
      await Future.delayed(interval);
      if (!mounted) break;
      try {
        final result = await callable.call({'paymentId': _paymentId});
        final status = result.data['status'] as String;
        if (status == 'approved') {
          if (mounted) setState(() => _stage = _MobileMoneyStage.approved);
          _polling = false;
          return;
        } else if (status == 'rejected') {
          if (mounted) {
            setState(() {
              _stage = _MobileMoneyStage.rejected;
              _errorMessage =
                  result.data['reason'] as String? ?? 'Le paiement a échoué.';
            });
          }
          _polling = false;
          return;
        }
      } catch (_) {
        // Erreur transitoire : on continue le sondage.
      }
      tries++;
    }

    _polling = false;
    if (mounted && _stage == _MobileMoneyStage.pending) {
      // Délai écoulé : l'écran principal continuera d'afficher l'état "en attente".
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paiement Mobile Money'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context)
              .pop(_stage == _MobileMoneyStage.approved),
        ),
      ),
      body: switch (_stage) {
        _MobileMoneyStage.phone => _buildPhoneForm(),
        _MobileMoneyStage.submitting =>
          const Center(child: CircularProgressIndicator()),
        _MobileMoneyStage.pending => _buildPendingView(),
        _MobileMoneyStage.approved => _buildResultView(success: true),
        _MobileMoneyStage.rejected => _buildResultView(success: false),
      },
    );
  }

  Widget _buildPhoneForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Paiement Mobile Money',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Tu vas recevoir une demande de paiement de '
              '${widget.session.price.toStringAsFixed(0)} FCFA sur ton '
              'téléphone Mobile Money.',
              style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withAlpha(15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Numéro Mobile Money',
                prefixText: '+242 ',
                hintText: '06 xxx xx xx',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.length < 9) return 'Numéro invalide';
                return null;
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'Payer ${widget.session.price.toStringAsFixed(0)} FCFA',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            const Text(
              'Confirme sur ton téléphone',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Une demande de paiement Mobile Money a été envoyée au '
              '+242 ${_phoneController.text}. Compose le code USSD ou '
              'valide la notification reçue pour confirmer.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultView({required bool success}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              success ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: success ? AppColors.success : AppColors.error,
              size: 64,
            ),
            const SizedBox(height: 20),
            Text(
              success ? 'Paiement confirmé !' : 'Paiement échoué',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            if (!success && _errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(success),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Fermer'),
            ),
            if (!success) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() {
                  _stage = _MobileMoneyStage.phone;
                  _errorMessage = null;
                }),
                child: const Text('Réessayer'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Vue formulaire ───────────────────────────────────────────────

class _PaymentForm extends StatelessWidget {
  final SessionModel session;
  final PaymentModel? rejectedPayment;
  final VoidCallback onPay;

  const _PaymentForm({
    required this.session,
    required this.rejectedPayment,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rejectedPayment != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withAlpha(80)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.cancel_outlined, color: AppColors.error, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Paiement précédent rejeté',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.error,
                        fontSize: 13,
                      ),
                    ),
                  ]),
                  if (rejectedPayment!.rejectionReason?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text(
                      rejectedPayment!.rejectionReason!,
                      style: TextStyle(fontSize: 13, color: AppColors.error),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Carte récap session
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.school_outlined,
                      color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        session.audienceLabel,
                        style: TextStyle(
                            color: Colors.white.withAlpha(180), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${session.price.toStringAsFixed(0)} FCFA',
                      style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const Text(
                      'À payer',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Mobile Money ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF1A56DB).withAlpha(50)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A56DB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.payment_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Payer avec Mobile Money',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onPay,
                    icon: const Icon(Icons.bolt_rounded, size: 20),
                    label: Text(
                      'Payer ${session.price.toStringAsFixed(0)} FCFA',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A56DB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─── Vues état ────────────────────────────────────────────────────

class _StateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StateView({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.5)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.arrow_back),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PendingView extends StatelessWidget {
  final PaymentModel payment;
  final SessionModel session;
  final VoidCallback? onResumePayment;
  const _PendingView({
    required this.payment,
    required this.session,
    this.onResumePayment,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                  color: AppColors.warning.withAlpha(20),
                  shape: BoxShape.circle),
              child: payment.isMobileMoney
                  ? Padding(
                      padding: const EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                          color: AppColors.warning, strokeWidth: 3),
                    )
                  : const Icon(Icons.hourglass_bottom_rounded,
                      color: AppColors.warning, size: 52),
            ),
            const SizedBox(height: 24),
            Text(
              payment.isMobileMoney
                  ? 'Confirmation en cours…'
                  : 'Preuve envoyée',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              payment.isMobileMoney
                  ? 'Ton paiement est en cours de vérification. Tu recevras une notification dès confirmation.'
                  : 'Ton paiement pour "${session.title}" est en attente de validation par un admin.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: Colors.grey[600], height: 1.5),
            ),
            const SizedBox(height: 28),
            if (onResumePayment != null) ...[
              ElevatedButton.icon(
                onPressed: onResumePayment,
                icon: const Icon(Icons.payment_outlined),
                label: const Text('Reprendre le paiement'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: () =>
                  context.go(AppRoutes.planningSessionPath(session.id)),
              icon: const Icon(Icons.arrow_back),
              label: const Text('Retour au planning'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApprovedView extends StatelessWidget {
  final SessionModel session;
  const _ApprovedView({required this.session});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                  color: AppColors.success.withAlpha(20),
                  shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.success, size: 56),
            ),
            const SizedBox(height: 24),
            const Text('Accès débloqué !',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              'Ton paiement pour "${session.title}" a été validé.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: Colors.grey[600], height: 1.5),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () =>
                  context.go(AppRoutes.planningSessionPath(session.id)),
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Voir le planning'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

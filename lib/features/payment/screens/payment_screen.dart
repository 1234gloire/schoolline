import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
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
  bool _isCreatingInvoice = false;

  Future<void> _payWithPaydunya(SessionModel session) async {
    setState(() => _isCreatingInvoice = true);
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: AppConstants.functionsRegion,
      ).httpsCallable('createPaydunyaInvoice');

      final result = await callable.call({'sessionId': session.id});
      final invoiceUrl = result.data['invoiceUrl'] as String;
      final paymentId = result.data['paymentId'] as String;

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _PaydunyaWebView(
            invoiceUrl: invoiceUrl,
            paymentId: paymentId,
            session: session,
          ),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'already-exists'
          ? 'Tu as déjà accès à cette session.'
          : (e.message ?? 'Impossible de créer la facture. Réessaie.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.error),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur réseau. Vérifie ta connexion et réessaie.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCreatingInvoice = false);
    }
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
              if (existingPayment != null && existingPayment.isPending) {
                return _PendingView(
                  payment: existingPayment,
                  session: session,
                  onResumePayment: existingPayment.provider == 'paydunya'
                      ? () => _payWithPaydunya(session)
                      : null,
                );
              }
              if (existingPayment != null && existingPayment.isApproved) {
                return _ApprovedView(session: session);
              }
              return _PaymentForm(
                session: session,
                isCreatingInvoice: _isCreatingInvoice,
                rejectedPayment:
                    existingPayment?.isRejected == true ? existingPayment : null,
                onPaydunya: () => _payWithPaydunya(session),
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

// ─── WebView PayDunya ─────────────────────────────────────────────

class _PaydunyaWebView extends StatefulWidget {
  final String invoiceUrl;
  final String paymentId;
  final SessionModel session;

  const _PaydunyaWebView({
    required this.invoiceUrl,
    required this.paymentId,
    required this.session,
  });

  @override
  State<_PaydunyaWebView> createState() => _PaydunyaWebViewState();
}

class _PaydunyaWebViewState extends State<_PaydunyaWebView> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _isClosing = false;

  void _closeWebView(bool paid) {
    if (_isClosing) return;
    _isClosing = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(paid);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
          onNavigationRequest: (request) {
            final url = request.url;
            // Intercepte les URLs de retour pour fermer la WebView
            if (url.startsWith(AppConstants.paydunyaReturnUrl) ||
                url.startsWith(AppConstants.paydunyaCancelUrl)) {
              final cancelled = url.startsWith(AppConstants.paydunyaCancelUrl);
              _closeWebView(!cancelled);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.invoiceUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paiement PayDunya'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _closeWebView(false),
        ),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection(AppConstants.paymentsCollection)
                .doc(widget.paymentId)
                .snapshots(),
            builder: (ctx, snap) {
              final data = snap.data?.data() as Map<String, dynamic>?;
              final approved = data?['status'] == 'approved';
              if (approved) {
                _closeWebView(true);
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

// ─── Vue formulaire ───────────────────────────────────────────────

class _PaymentForm extends StatelessWidget {
  final SessionModel session;
  final bool isCreatingInvoice;
  final PaymentModel? rejectedPayment;
  final VoidCallback onPaydunya;

  const _PaymentForm({
    required this.session,
    required this.isCreatingInvoice,
    required this.rejectedPayment,
    required this.onPaydunya,
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

          // ── PayDunya ──────────────────────────────────────────────
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Payer avec PayDunya',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          'Mobile Money · Carte bancaire · Wave',
                          style: TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(30),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Recommandé',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.green,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isCreatingInvoice ? null : onPaydunya,
                    icon: isCreatingInvoice
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.bolt_rounded, size: 20),
                    label: Text(
                      isCreatingInvoice
                          ? 'Préparation...'
                          : 'Payer ${session.price.toStringAsFixed(0)} FCFA',
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
              child: payment.isFeexpay || payment.provider == 'paydunya'
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
              payment.provider == 'paydunya'
                  ? 'Confirmation en cours…'
                  : 'Preuve envoyée',
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              payment.provider == 'paydunya'
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

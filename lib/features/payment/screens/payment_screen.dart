import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

  const PaymentScreen({
    super.key,
    required this.sessionId,
    this.session,
  });

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  XFile? _proofImage;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _successMessage;

  Future<void> _pickProof() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (image != null) setState(() => _proofImage = image);
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (image != null) setState(() => _proofImage = image);
  }

  Future<void> _submit(SessionModel session) async {
    final proof = _proofImage;
    if (proof == null) return;

    final userId = ref.read(authNotifierProvider).value?.uid;
    if (userId == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      // 1. Upload de la preuve vers Firebase Storage
      final ext = proof.path.split('.').last.toLowerCase();
      final storagePath =
          '${AppConstants.paymentsStoragePath}/$userId/${session.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';

      final storageRef = FirebaseStorage.instance.ref(storagePath);
      final task = storageRef.putFile(
        File(proof.path),
        SettableMetadata(contentType: ext == 'png' ? 'image/png' : 'image/jpeg'),
      );

      await for (final snapshot in task.snapshotEvents) {
        if (!mounted) break;
        setState(() {
          _uploadProgress = snapshot.totalBytes > 0
              ? snapshot.bytesTransferred / snapshot.totalBytes
              : 0.0;
        });
      }
      await task;

      // 2. Forcer le refresh du token avant l'appel (fix timing iOS)
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('Session expirée, reconnecte-toi.');
      await currentUser.getIdToken(true);

      // 3. Appel Cloud Function
      final callable = FirebaseFunctions.instanceFor(region: 'europe-west1')
          .httpsCallable('submitPaymentProof');
      await callable.call({
        'sessionId': session.id,
        'proofFileRef': storagePath,
      });

      if (mounted) {
        setState(() {
          _successMessage =
              'Ta preuve a bien été envoyée. Un admin va valider ton paiement sous peu.';
          _isUploading = false;
        });
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(paymentErrorMessage(e)),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(paymentErrorMessage(e)),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.value;
    final userId = user?.uid;

    if (authState.isLoading && user == null) {
      return Scaffold(
        backgroundColor: context.palette.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (user == null) {
      return Scaffold(
        backgroundColor: context.palette.background,
        body: _PaymentStateView(
          icon: Icons.lock_outline,
          title: 'Connexion requise',
          message: 'Reconnecte-toi pour payer cette session.',
        ),
      );
    }

    final sessionAsync =
        widget.session != null
            ? AsyncValue<SessionModel?>.data(widget.session)
            : ref.watch(sessionByIdProvider(widget.sessionId));

    return sessionAsync.when(
      data: (session) {
        if (session == null) {
          return Scaffold(
            backgroundColor: context.palette.background,
            body: _PaymentStateView(
              icon: Icons.event_busy_outlined,
              title: 'Session introuvable',
              message: "Cette session n'existe plus ou n'est plus accessible.",
            ),
          );
        }

        if (!sessionMatchesStudent(session, user)) {
          return Scaffold(
            backgroundColor: context.palette.background,
            appBar: AppBar(title: Text('Paiement de la session')),
            body: _PaymentStateView(
              icon: Icons.lock_outline,
              title: 'Accès refusé',
              message:
                  'Cette session ne correspond pas à ton profil scolaire.',
              actionLabel: 'Retour au planning',
              onAction:
                  () => context.go(AppRoutes.planningSessionPath(session.id)),
            ),
          );
        }

        if (session.status == SessionStatus.closed ||
            session.status == SessionStatus.resultsPublished) {
          return Scaffold(
            backgroundColor: context.palette.background,
            appBar: AppBar(title: Text('Paiement de la session')),
            body: _PaymentStateView(
              icon: Icons.event_busy_outlined,
              title: 'Session terminée',
              message:
                  'Les inscriptions pour cette session sont closes. Les paiements ne sont plus acceptés.',
              actionLabel: 'Retour au planning',
              onAction:
                  () => context.go(AppRoutes.planningSessionPath(session.id)),
            ),
          );
        }

        if (session.price <= 0) {
          return Scaffold(
            backgroundColor: context.palette.background,
            appBar: AppBar(title: Text('Paiement de la session')),
            body: _PaymentStateView(
              icon: Icons.check_circle_outline,
              title: 'Session gratuite',
              message:
                  "Aucun paiement n'est requis pour accéder à cette session.",
              actionLabel: 'Voir le planning',
              onAction:
                  () => context.go(AppRoutes.planningSessionPath(session.id)),
            ),
          );
        }

        final paymentAsync = ref.watch(
          paymentForSessionProvider((
            userId: userId!,
            sessionId: session.id,
          )),
        );

        return Scaffold(
          backgroundColor: context.palette.background,
          appBar: AppBar(
            title: Text('Paiement de la session'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios),
              onPressed:
                  () => context.go(AppRoutes.planningSessionPath(session.id)),
            ),
          ),
          body: paymentAsync.when(
            data: (existingPayment) {
              if (existingPayment != null && existingPayment.isPending) {
                return _PendingView(payment: existingPayment, session: session);
              }
              if (existingPayment != null && existingPayment.isApproved) {
                return _ApprovedView(session: session);
              }
              if (_successMessage != null) {
                return _SentView(message: _successMessage!, session: session);
              }
              if (_isUploading) {
                return _UploadingView(progress: _uploadProgress);
              }
              return _PaymentForm(
                session: session,
                proofImage: _proofImage,
                rejectedPayment:
                    existingPayment?.isRejected == true ? existingPayment : null,
                onPickGallery: _pickProof,
                onPickCamera: _takePhoto,
                onRemove: () => setState(() => _proofImage = null),
                onSubmit:
                    _proofImage != null ? () => _submit(session) : null,
              );
            },
            loading: () => Center(child: CircularProgressIndicator()),
            error:
                (error, _) => _PaymentStateView(
                  icon: Icons.sync_problem_outlined,
                  title: 'Paiement indisponible',
                  message: firestoreDataErrorMessage(
                    error,
                    fallback:
                        'Impossible de charger le statut de paiement pour le moment.',
                  ),
                  actionLabel: 'Réessayer',
                  onAction:
                      () => ref.invalidate(
                        paymentForSessionProvider((
                          userId: userId,
                          sessionId: session.id,
                        )),
                      ),
                ),
          ),
        );
      },
      loading: () => Scaffold(
            backgroundColor: context.palette.background,
            body: const Center(child: CircularProgressIndicator()),
          ),
      error:
          (error, _) => Scaffold(
            backgroundColor: context.palette.background,
            body: _PaymentStateView(
              icon: Icons.sync_problem_outlined,
              title: 'Session indisponible',
              message: firestoreDataErrorMessage(
                error,
                fallback:
                    'Impossible de charger cette session pour le moment.',
              ),
              actionLabel: 'Réessayer',
              onAction: () => ref.invalidate(sessionByIdProvider(widget.sessionId)),
            ),
          ),
    );
  }
}

// ─── Vue formulaire ───────────────────────────────────────────────

class _PaymentForm extends StatelessWidget {
  final SessionModel session;
  final XFile? proofImage;
  final PaymentModel? rejectedPayment;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onRemove;
  final VoidCallback? onSubmit;

  const _PaymentForm({
    required this.session,
    required this.proofImage,
    required this.rejectedPayment,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onRemove,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Alerte paiement rejeté
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
                  Row(
                    children: [
                      Icon(Icons.cancel_outlined, color: AppColors.error, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Paiement précédent rejeté',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
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
                  child: const Icon(Icons.school_outlined, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        session.audienceLabel,
                        style: TextStyle(
                          color: Colors.white.withAlpha(180),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${session.price.toStringAsFixed(0)} FCFA',
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    Text(
                      'À payer',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Instructions de paiement
          Text(
            'Comment payer ?',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          _InstructionCard(
            step: '1',
            title: 'Envoie le montant par Mobile Money',
            body: 'MTN Money : +242 06 756 64 10\nAirtel Money : +242 05 547 30 89\nRéférence : ${session.title}',
            icon: Icons.phone_android_outlined,
          ),
          const SizedBox(height: 10),
          const _InstructionCard(
            step: '2',
            title: 'Prends une capture du reçu',
            body: "Fais une capture d'écran du SMS de confirmation ou prends en photo le reçu.",
            icon: Icons.camera_alt_outlined,
          ),
          const SizedBox(height: 10),
          const _InstructionCard(
            step: '3',
            title: 'Envoie la preuve ici',
            body: 'Un admin validera ton paiement et ton accès sera débloqué.',
            icon: Icons.send_outlined,
          ),

          const SizedBox(height: 28),

          // Zone preuve
          Text(
            'Ta preuve de paiement',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),

          if (proofImage == null) ...[
            Row(
              children: [
                Expanded(
                  child: _PickButton(
                    icon: Icons.camera_alt_outlined,
                    label: 'Prendre une photo',
                    onTap: onPickCamera,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PickButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Depuis la galerie',
                    onTap: onPickGallery,
                  ),
                ),
              ],
            ),
          ] else ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(
                    File(proofImage!.path),
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: onRemove,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(160),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 32),

          // Bouton soumettre
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onSubmit,
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(
                proofImage == null
                    ? 'Ajoute une preuve pour continuer'
                    : 'Envoyer ma preuve',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    proofImage == null ? context.palette.textHint : AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PaymentStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _PaymentStateView({
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
            Icon(icon, size: 56, color: context.palette.textHint),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.palette.textSecondary,
                height: 1.5,
              ),
            ),
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

// ─── Vues état ────────────────────────────────────────────────────

class _PendingView extends StatelessWidget {
  final PaymentModel payment;
  final SessionModel session;
  const _PendingView({required this.payment, required this.session});

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
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.hourglass_bottom_rounded,
                color: AppColors.warning,
                size: 52,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Preuve envoyée',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Ton paiement pour "${session.title}" est en cours de vérification. Tu recevras une notification dès validation.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: context.palette.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Soumis le ${_formatDate(payment.submittedAt)}',
              style: TextStyle(fontSize: 12, color: context.palette.textHint),
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: () => context.go(AppRoutes.planningSessionPath(session.id)),
              icon: const Icon(Icons.arrow_back),
              label: Text('Retour au planning'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} à ${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
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
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56),
            ),
            const SizedBox(height: 24),
            Text(
              'Accès débloqué !',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
            const SizedBox(height: 10),
            Text(
              'Ton paiement pour "${session.title}" a été validé. Tu peux maintenant accéder à toutes les épreuves.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: context.palette.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => context.go(AppRoutes.planningSessionPath(session.id)),
              icon: const Icon(Icons.arrow_back),
              label: Text('Voir le planning'),
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

class _SentView extends StatelessWidget {
  final String message;
  final SessionModel session;
  const _SentView({required this.message, required this.session});

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
                color: AppColors.info.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mark_email_read_outlined, color: AppColors.info, size: 52),
            ),
            const SizedBox(height: 24),
            Text(
              'Preuve envoyée !',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: context.palette.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 28),
            OutlinedButton.icon(
              onPressed: () => context.go(AppRoutes.planningSessionPath(session.id)),
              icon: const Icon(Icons.arrow_back),
              label: Text('Retour au planning'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UploadingView extends StatelessWidget {
  final double progress;
  const _UploadingView({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(15),
                shape: BoxShape.circle,
              ),
              child: progress < 1.0
                  ? Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 4,
                      ),
                    )
                  : const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56),
            ),
            const SizedBox(height: 24),
            Text(
              progress < 1.0 ? 'Envoi en cours…' : 'Envoi terminé',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: context.palette.surfaceVariant,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(progress * 100).toInt()}%',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Widgets utilitaires ──────────────────────────────────────────

class _InstructionCard extends StatelessWidget {
  final String step;
  final String title;
  final String body;
  final IconData icon;

  const _InstructionCard({
    required this.step,
    required this.title,
    required this.body,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                step,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.palette.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PickButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withAlpha(60)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primary, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

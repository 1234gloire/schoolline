import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../core/router/app_router.dart';
import '../../../models/submission_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/sessions_provider.dart';

class ResultDetailScreen extends ConsumerWidget {
  final String submissionId;
  final Map<String, dynamic>? extra;

  const ResultDetailScreen({super.key, required this.submissionId, this.extra});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallbackSubmission = extra?['submission'] as SubmissionModel?;
    final authState = ref.watch(authNotifierProvider);
    final userId = authState.value?.uid;

    if (authState.isLoading && fallbackSubmission == null) {
      return const _ResultDetailShell(
        title: 'Résultat',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (userId == null) {
      return const _ResultDetailShell(
        title: 'Résultat',
        body: _ResultStateView(
          title: 'Connexion requise',
          message: 'Connecte-toi pour consulter le détail de cette copie.',
        ),
      );
    }

    final providerArgs = (userId: userId, submissionId: submissionId);
    final submissionAsync = ref.watch(submissionByIdProvider(providerArgs));

    return submissionAsync.when(
      data: (submission) {
        final resolvedSubmission = submission ?? fallbackSubmission;
        if (resolvedSubmission == null) {
          return _ResultDetailShell(
            title: 'Résultat introuvable',
            body: _ResultStateView(
              title: 'Résultat introuvable',
              message: 'Cette copie n’existe pas ou n’est plus accessible.',
              actionLabel: 'Retour aux résultats',
              onAction: () => context.go(AppRoutes.results),
            ),
          );
        }

        if (!resolvedSubmission.canAccessResultDetail) {
          return _ResultDetailShell(
            title: resolvedSubmission.subjectName,
            body: _PendingResultView(submission: resolvedSubmission),
          );
        }

        return _ResultDetailScaffold(submission: resolvedSubmission);
      },
      loading: () {
        if (fallbackSubmission != null) {
          if (!fallbackSubmission.canAccessResultDetail) {
            return _ResultDetailShell(
              title: fallbackSubmission.subjectName,
              body: _PendingResultView(submission: fallbackSubmission),
            );
          }
          return _ResultDetailScaffold(submission: fallbackSubmission);
        }
        return const _ResultDetailShell(
          title: 'Résultat',
          body: Center(child: CircularProgressIndicator()),
        );
      },
      error: (error, _) {
        if (fallbackSubmission != null) {
          if (!fallbackSubmission.canAccessResultDetail) {
            return _ResultDetailShell(
              title: fallbackSubmission.subjectName,
              body: _PendingResultView(submission: fallbackSubmission),
            );
          }
          return _ResultDetailScaffold(submission: fallbackSubmission);
        }
        return _ResultDetailShell(
          title: 'Résultat',
          body: _ResultStateView(
            title: 'Chargement impossible',
            message: submissionDataErrorMessage(error),
            actionLabel: 'Réessayer',
            onAction:
                () => ref.invalidate(submissionByIdProvider(providerArgs)),
          ),
        );
      },
    );
  }
}

class _ResultDetailScaffold extends StatelessWidget {
  final SubmissionModel submission;

  const _ResultDetailScaffold({required this.submission});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: Text(submission.subjectName),
      ),
      body: _ResultDetailContent(submission: submission),
    );
  }
}

class _ResultDetailShell extends StatelessWidget {
  final String title;
  final Widget body;

  const _ResultDetailShell({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(title: Text(title)),
      body: body,
    );
  }
}

class _ResultDetailContent extends StatelessWidget {
  final SubmissionModel submission;

  const _ResultDetailContent({required this.submission});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _ScoreHero(submission: submission),

          const SizedBox(height: 20),

          _ResultMetaCard(submission: submission),

          // Examen blanc = relevé seul (note ici, moyenne/mention/rang dans le
          // bulletin), comme au vrai BAC/BEPC : on ne « rend » pas la copie ni
          // le détail de correction. Le feedback pédagogique (barème, synthèse
          // IA, points forts, à améliorer, commentaire correcteur) sera réservé
          // au futur mode entraînement.

          const SizedBox(height: 32),

          OutlinedButton.icon(
            onPressed: () => context.go(AppRoutes.results),
            icon: const Icon(Icons.arrow_back),
            label: Text('Voir tous mes résultats'),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _PendingResultView extends StatelessWidget {
  final SubmissionModel submission;

  const _PendingResultView({required this.submission});

  @override
  Widget build(BuildContext context) {
    final isErrorState =
        submission.status == SubmissionStatus.error ||
        submission.status == SubmissionStatus.rejected;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isErrorState ? Icons.error_outline : Icons.hourglass_top_rounded,
              size: 56,
              color:
                  isErrorState
                      ? AppColors.error
                      : AppColors.statusCorrecting,
            ),
            const SizedBox(height: 16),
            Text(
              submission.studentResultLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              submission.workflowDescription,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Copie reçue le ${DateFormat('dd/MM/yyyy à HH:mm').format(submission.submittedAt)}',
              style: TextStyle(fontSize: 13, color: context.palette.textHint),
              textAlign: TextAlign.center,
            ),
            if (submission.shouldShowStudentErrorReason) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.palette.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.palette.divider),
                ),
                child: Text(
                  submission.errorReasonLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.palette.textPrimary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => context.go(AppRoutes.results),
              icon: const Icon(Icons.arrow_back),
              label: Text('Retour aux résultats'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultStateView extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ResultStateView({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, size: 56, color: context.palette.textHint),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.palette.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: context.palette.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultMetaCard extends StatelessWidget {
  final SubmissionModel submission;

  const _ResultMetaCard({required this.submission});

  @override
  Widget build(BuildContext context) {
    final visibleDate = submission.publishedAt ?? submission.workflowUpdatedAt;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.divider),
      ),
      child: Column(
        children: [
          _MetaRow(label: 'Statut', value: submission.studentResultLabel),
          const Divider(height: 20),
          _MetaRow(
            label: 'Soumis le',
            value: DateFormat(
              'dd/MM/yyyy à HH:mm',
            ).format(submission.submittedAt),
          ),
          if (visibleDate != null) ...[
            const Divider(height: 20),
            _MetaRow(
              label: 'Publié le',
              value: DateFormat('dd/MM/yyyy à HH:mm').format(visibleDate),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label :',
          style: TextStyle(fontSize: 13, color: context.palette.textSecondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _ScoreHero extends StatelessWidget {
  final SubmissionModel submission;
  const _ScoreHero({required this.submission});

  @override
  Widget build(BuildContext context) {
    final score = submission.studentVisibleScore;
    final percent = (score ?? 0) / 20;
    final scoreColor = _scoreColor(score ?? 0);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A1172), Color(0xFF1E2FA0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            submission.subjectName,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Résultat officiel',
            style: TextStyle(color: Colors.white.withAlpha(160), fontSize: 12),
          ),
          const SizedBox(height: 24),
          CircularPercentIndicator(
            radius: 70.0,
            lineWidth: 10.0,
            percent: percent.clamp(0.0, 1.0),
            center: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  score == null ? '—' : score.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: scoreColor,
                  ),
                ),
                Text(
                  '/ 20',
                  style: TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ),
            backgroundColor: Colors.white.withAlpha(30),
            progressColor: scoreColor,
            circularStrokeCap: CircularStrokeCap.round,
          ),
          const SizedBox(height: 20),
          if (submission.mention.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                color: scoreColor.withAlpha(40),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scoreColor, width: 1.5),
              ),
              child: Text(
                submission.mention,
                style: TextStyle(
                  color: scoreColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 1,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                submission.isPublished
                    ? Icons.check_circle_outline
                    : Icons.smart_toy_outlined,
                color: Colors.white54,
                size: 14,
              ),
              const SizedBox(width: 6),
              Text(
                submission.isPublished
                    ? 'Note validée par le correcteur'
                    : 'Évaluation IA — ${submission.aiConfidence?.toInt() ?? 0}% confiance',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 16) return const Color(0xFF22C55E);
    if (score >= 14) return const Color(0xFF3B82F6);
    if (score >= 12) return AppColors.accent;
    if (score >= 10) return AppColors.warning;
    return AppColors.error;
  }
}


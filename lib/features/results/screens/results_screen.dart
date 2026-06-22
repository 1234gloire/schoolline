import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../core/router/app_router.dart';
import '../../../models/student_result_model.dart';
import '../../../models/submission_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/sessions_provider.dart';

class ResultsScreen extends ConsumerWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final userId = authState.value?.uid;

    if (authState.isLoading && userId == null) {
      return Scaffold(
        backgroundColor: context.palette.background,
        appBar: AppBar(title: Text('Mes résultats')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (userId == null) {
      return Scaffold(
        backgroundColor: context.palette.background,
        appBar: AppBar(title: Text('Mes résultats')),
        body: const _ResultsUnavailableView(
          title: 'Connexion requise',
          message: 'Connecte-toi pour consulter tes résultats.',
        ),
      );
    }

    final submissionsAsync = ref.watch(mySubmissionsProvider(userId));

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(title: Text('Mes résultats')),
      body: submissionsAsync.when(
        data: (submissions) {
          if (submissions.isEmpty) {
            return _EmptyResultsView();
          }

          final correcting = submissions.where((s) => s.isCorrecting).toList();
          final published = submissions.where((s) => s.isPublished).toList();
          if (correcting.isNotEmpty && published.isEmpty) {
            return _CorrectingView(submission: correcting.first);
          }

          return _ResultsListView(submissions: submissions, userId: userId);
        },
        loading: () => Center(child: CircularProgressIndicator()),
        error:
            (error, _) => _ResultsUnavailableView(
              title: 'Chargement impossible',
              message: submissionDataErrorMessage(error),
              actionLabel: 'Réessayer',
              onAction: () => ref.invalidate(mySubmissionsProvider(userId)),
            ),
      ),
    );
  }
}

// ─── Vue "Correction en cours" ───
class _CorrectingView extends StatelessWidget {
  final SubmissionModel submission;
  const _CorrectingView({required this.submission});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 32),

          // Animation hourglass
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 800),
            builder: (context, value, child) {
              return Transform.scale(scale: value, child: child);
            },
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withAlpha(30),
                    AppColors.primary.withAlpha(60),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withAlpha(40),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                Icons.hourglass_bottom_rounded,
                color: AppColors.primary,
                size: 60,
              ),
            ),
          ),

          const SizedBox(height: 28),

          Text(
            'Correction en cours',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),

          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.statusCorrecting.withAlpha(20),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              submission.subjectName,
              style: TextStyle(
                color: AppColors.statusCorrecting,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),

          const SizedBox(height: 20),

          Text(
            'Merci d\'avoir rendu ta copie !',
            style: TextStyle(
              fontSize: 16,
              color: context.palette.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'Le détail de la note restera masqué tant que la publication n’est pas terminée.',
            style: TextStyle(fontSize: 14, color: context.palette.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          Text(
            submission.workflowDescription,
            style: TextStyle(fontSize: 13, color: context.palette.textHint),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Étapes de correction
          _CorrectionSteps(submission: submission),

          const SizedBox(height: 32),

          // Infos soumission
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.palette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.palette.divider),
            ),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.access_time,
                  label: 'Soumis le',
                  value: DateFormat(
                    'dd/MM/yyyy à HH:mm',
                  ).format(submission.submittedAt),
                ),
                const Divider(height: 20),
                _InfoRow(
                  icon: Icons.pending_actions_outlined,
                  label: 'Statut',
                  value: submission.studentResultLabel,
                  valueColor: AppColors.statusCorrecting,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          OutlinedButton.icon(
            onPressed: () => context.go(AppRoutes.dashboard),
            icon: const Icon(Icons.home_outlined),
            label: Text('Retour à l\'accueil'),
          ),
        ],
      ),
    );
  }
}

class _CorrectionSteps extends StatelessWidget {
  final SubmissionModel submission;
  const _CorrectionSteps({required this.submission});

  @override
  Widget build(BuildContext context) {
    final correctionDone = {
      SubmissionStatus.humanReviewed,
      SubmissionStatus.published,
    }.contains(submission.status);

    final steps = [
      ('Copie reçue', Icons.cloud_done_outlined, true),
      ('Correction en cours', Icons.rate_review_outlined, correctionDone),
      ('Note publiée', Icons.check_circle_outline, submission.isPublished),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Étapes de correction',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        ...steps.asMap().entries.map((entry) {
          final i = entry.key;
          final (label, icon, done) = entry.value;
          final isLast = i == steps.length - 1;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color:
                          done
                              ? (isLast ? AppColors.success : AppColors.primary)
                              : context.palette.surfaceVariant,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      done ? Icons.check : icon,
                      size: 16,
                      color: done ? Colors.white : context.palette.textHint,
                    ),
                  ),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 28,
                      color: done ? AppColors.primary : context.palette.divider,
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: done ? FontWeight.w600 : FontWeight.normal,
                    color: done ? context.palette.textPrimary : context.palette.textHint,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        Text(
          '$label : ',
          style: TextStyle(color: context.palette.textSecondary, fontSize: 13),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: valueColor ?? context.palette.textPrimary,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

// ─── Vue liste résultats ───
class _ResultsListView extends ConsumerWidget {
  final List<SubmissionModel> submissions;
  final String userId;
  const _ResultsListView({required this.submissions, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Grouper par session
    final bySession = <String, List<SubmissionModel>>{};
    for (final s in submissions) {
      bySession.putIfAbsent(s.sessionId, () => []).add(s);
    }

    // Sessions avec bulletin (toutes copies publiées)
    final bulletinSessionIds = bySession.entries
        .where((e) => e.value.every((s) => s.isPublished))
        .map((e) => e.key)
        .toList();

    // Copies encore en correction
    final correcting = submissions.where((s) => s.isCorrecting).toList()
      ..sort((a, b) =>
          (b.workflowUpdatedAt ?? b.submittedAt)
              .compareTo(a.workflowUpdatedAt ?? a.submittedAt));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (correcting.isNotEmpty) ...[
          const _SectionHeader('En cours de correction'),
          ...correcting.map((s) => _ResultTile(submission: s, isPending: true)),
          const SizedBox(height: 16),
        ],
        if (bulletinSessionIds.isNotEmpty) ...[
          const _SectionHeader('Bulletins de résultats'),
          ...bulletinSessionIds.map((sessionId) => _SessionBulletinCard(
                sessionId: sessionId,
                userId: userId,
                submissions: bySession[sessionId]!,
              )),
        ],
      ],
    );
  }
}

// ─── Bulletin d'une session ───
class _SessionBulletinCard extends ConsumerWidget {
  final String sessionId;
  final String userId;
  final List<SubmissionModel> submissions;

  const _SessionBulletinCard({
    required this.sessionId,
    required this.userId,
    required this.submissions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(
      studentResultProvider((sessionId: sessionId, userId: userId)),
    );

    return resultAsync.when(
      data: (result) {
        if (result == null) {
          // Bulletin pas encore calculé : afficher les notes individuelles
          return _FallbackSubjectList(submissions: submissions);
        }
        return _BulletinCard(result: result, onSubjectTap: (submissionId) {
          final sub = submissions.firstWhere(
            (s) => s.id == submissionId,
            orElse: () => submissions.first,
          );
          context.push(
            AppRoutes.resultDetailPath(submissionId),
            extra: {'submission': sub},
          );
        });
      },
      loading: () => Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _FallbackSubjectList(submissions: submissions),
    );
  }
}

class _BulletinCard extends StatelessWidget {
  final StudentResultModel result;
  final void Function(String submissionId) onSubjectTap;

  const _BulletinCard({required this.result, required this.onSubjectTap});

  @override
  Widget build(BuildContext context) {
    final moyenne = result.moyenneGenerale;
    final percent = (moyenne / 20).clamp(0.0, 1.0);
    final color = _moyenneColor(moyenne);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF0A1172), Color(0xFF1E2FA0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A1172).withAlpha(60),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── En-tête : moyenne + admis/ajourné ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Row(
              children: [
                CircularPercentIndicator(
                  radius: 52,
                  lineWidth: 8,
                  percent: percent,
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        moyenne.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      Text(
                        '/ 20',
                        style: TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                    ],
                  ),
                  backgroundColor: Colors.white.withAlpha(25),
                  progressColor: color,
                  circularStrokeCap: CircularStrokeCap.round,
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Moyenne générale',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: result.isAdmis
                              ? const Color(0xFF22C55E).withAlpha(40)
                              : AppColors.error.withAlpha(40),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: result.isAdmis
                                ? const Color(0xFF22C55E)
                                : AppColors.error,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          result.isAdmis ? 'ADMIS(E)' : 'AJOURNÉ(E)',
                          style: TextStyle(
                            color: result.isAdmis
                                ? const Color(0xFF22C55E)
                                : AppColors.error,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        result.mention,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Tableau des matières ──
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                // En-tête tableau
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          'Matière',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          'Note',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          'Coef',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          'Points',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white24, height: 1),
                ...result.subjects.asMap().entries.map((entry) {
                  final i = entry.key;
                  final sub = entry.value;
                  final isLast = i == result.subjects.length - 1;
                  return GestureDetector(
                    onTap: () => onSubjectTap(sub.submissionId),
                    behavior: HitTestBehavior.opaque,
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Text(
                                  sub.subjectName,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  sub.finalScore.toStringAsFixed(1),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _noteColor(sub.finalScore),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 32,
                                child: Text(
                                  sub.coefficient.toInt().toString(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 44,
                                child: Text(
                                  sub.points.toStringAsFixed(1),
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isLast)
                          const Divider(color: Colors.white12, height: 1),
                      ],
                    ),
                  );
                }),
                // Ligne totaux
                const Divider(color: Colors.white38, height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      const Expanded(
                        flex: 4,
                        child: Text(
                          'Total',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '/ ${result.totalCoefficients.toInt() * 20}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 32),
                      SizedBox(
                        width: 44,
                        child: Text(
                          result.totalPoints.toStringAsFixed(1),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Publié le ${DateFormat('dd/MM/yyyy').format(result.publishedAt)}',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Color _moyenneColor(double m) {
    if (m >= 16) return const Color(0xFF22C55E);
    if (m >= 14) return const Color(0xFF3B82F6);
    if (m >= 12) return AppColors.accent;
    if (m >= 10) return AppColors.warning;
    return AppColors.error;
  }

  Color _noteColor(double note) {
    if (note >= 10) return const Color(0xFF86EFAC);
    return const Color(0xFFFCA5A5);
  }
}

// Fallback si le bulletin n'est pas encore calculé
class _FallbackSubjectList extends StatelessWidget {
  final List<SubmissionModel> submissions;
  const _FallbackSubjectList({required this.submissions});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: submissions
          .map((s) => _ResultTile(submission: s, isPending: false))
          .toList(),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final SubmissionModel submission;
  final bool isPending;

  const _ResultTile({required this.submission, required this.isPending});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap:
          isPending
              ? null
              : () => context.push(
                AppRoutes.resultDetailPath(submission.id),
                extra: {'submission': submission},
              ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.palette.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color:
                    isPending
                        ? AppColors.statusCorrecting.withAlpha(25)
                        : AppColors.statusPublished.withAlpha(25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isPending
                    ? Icons.hourglass_empty_rounded
                    : Icons.check_circle_outline,
                color:
                    isPending
                        ? AppColors.statusCorrecting
                        : AppColors.statusPublished,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    submission.subjectName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    submission.studentResultLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          isPending
                              ? AppColors.statusCorrecting
                              : AppColors.statusPublished,
                    ),
                  ),
                  if (submission.shouldShowStudentErrorReason) ...[
                    const SizedBox(height: 2),
                    Text(
                      submission.errorReasonLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.palette.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    isPending
                        ? 'Soumise le ${DateFormat('dd/MM/yyyy').format(submission.submittedAt)}'
                        : 'Publiée le ${DateFormat('dd/MM/yyyy').format(submission.publishedAt ?? submission.workflowUpdatedAt ?? submission.submittedAt)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.textHint,
                    ),
                  ),
                ],
              ),
            ),
            if (!isPending && submission.studentVisibleScore != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${submission.studentVisibleScore!.toStringAsFixed(1)}/20',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    submission.mention,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.textSecondary,
                    ),
                  ),
                ],
              )
            else if (!isPending)
              Icon(Icons.chevron_right, color: context.palette.textHint),
          ],
        ),
      ),
    );
  }
}

class _ResultsUnavailableView extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ResultsUnavailableView({
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

class _EmptyResultsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_outlined, size: 72, color: context.palette.textHint),
          SizedBox(height: 20),
          Text(
            'Aucun résultat disponible',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.palette.textSecondary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Tes notes apparaîtront ici après correction',
            style: TextStyle(fontSize: 14, color: context.palette.textHint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

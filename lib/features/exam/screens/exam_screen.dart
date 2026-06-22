import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_windowmanager/flutter_windowmanager.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../core/router/app_router.dart';
import '../../../models/payment_model.dart';
import '../../../models/session_model.dart';
import '../../../models/submission_model.dart';
import '../../../models/subject_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/payments_provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../shared/widgets/exam_countdown.dart';

class ExamScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String subjectId;
  final Map<String, dynamic>? extra;

  const ExamScreen({
    super.key,
    required this.sessionId,
    required this.subjectId,
    this.extra,
  });

  @override
  ConsumerState<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends ConsumerState<ExamScreen>
    with WidgetsBindingObserver {
  SubjectModel? _subject;
  bool _examExpired = false;
  bool _examModeEnabled = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subject = widget.extra?['subject'] as SubjectModel?;
  }

  void _startExam() {
    if (_examModeEnabled) return;
    _examModeEnabled = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Bloquer les captures d'écran sur Android
    if (Platform.isAndroid) {
      FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
    }
  }

  void _restoreSystemUi() {
    if (!_examModeEnabled) return;
    _examModeEnabled = false;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Réautoriser les captures d'écran
    if (Platform.isAndroid) {
      FlutterWindowManager.clearFlags(FlutterWindowManager.FLAG_SECURE);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restoreSystemUi();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!_examModeEnabled || _examExpired) return;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _backgroundedAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final backgroundedAt = _backgroundedAt;
        if (backgroundedAt == null) break;
        _backgroundedAt = null;
        if (!mounted) break;
        final seconds = DateTime.now().difference(backgroundedAt).inSeconds;
        // Absence courte : avertissement non bloquant.
        if (seconds < 300) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Absence de ${seconds}s détectée. Reviens à l\'épreuve.',
              ),
              backgroundColor: AppColors.warning,
              duration: const Duration(seconds: 4),
            ),
          );
        } else {
          // Absence ≥ 5 minutes : traite comme un abandon volontaire.
          final subject = _subject;
          if (subject != null) _handleExitExam(subject);
        }
      default:
        break;
    }
  }

  void _onExamExpired(SubjectModel subject) {
    setState(() => _examExpired = true);
    _showExpiredDialog(subject);
  }

  void _showExpiredDialog(SubjectModel subject) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.timer_off, color: AppColors.error),
                SizedBox(width: 8),
                Text('Temps écoulé !'),
              ],
            ),
            content: Text(
              'Le temps de l\'épreuve est écoulé. Votre copie doit être soumise maintenant.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _goToSubmission(subject);
                },
                child: Text('Soumettre ma copie'),
              ),
            ],
          ),
    );
  }

  void _goToSubmission(SubjectModel subject) {
    context.pushReplacement(
      AppRoutes.submissionPath(
        sessionId: subject.sessionId,
        subjectId: subject.id,
      ),
      extra: {'subject': subject, 'sessionId': subject.sessionId},
    );
  }

  void _openExistingSubmission(SubmissionModel submission) {
    if (submission.canAccessResultDetail) {
      context.go(
        AppRoutes.resultDetailPath(submission.id),
        extra: {'submission': submission},
      );
      return;
    }

    context.go(AppRoutes.results);
  }

  Future<void> _handleExitExam(SubjectModel subject) async {
    if (_examExpired) return;
    final result = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text('Quitter l\'épreuve ?'),
            content: Text(
              'Si tu quittes maintenant, cette épreuve sera marquée comme abandonnée '
              'et restera bloquée pour ton compte.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Rester'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                child: Text('Quitter'),
              ),
            ],
          ),
    );
    if (result != true || !mounted) {
      return;
    }

    try {
      await ref.read(authNotifierProvider.notifier).markSubjectAbandoned(
        subject.id,
      );
      if (!mounted) return;
      context.go(AppRoutes.planningSessionPath(subject.sessionId));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(authErrorMessage(error)),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.value;
    final userId = user?.uid;

    if (authState.isLoading && userId == null) {
      _restoreSystemUi();
      return const _ExamShell(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (userId == null) {
      _restoreSystemUi();
      return const _ExamShell(
        child: _ExamStateView(
          icon: Icons.lock_outline,
          title: 'Connexion requise',
          message: 'Reconnecte-toi pour accéder à cette épreuve.',
        ),
      );
    }

    final subject = _subject;
    if (subject == null) {
      final subjectAsync = ref.watch(
        subjectByIdProvider((
          sessionId: widget.sessionId,
          subjectId: widget.subjectId,
        )),
      );
      subjectAsync.whenData((loadedSubject) {
        if (loadedSubject == null || _subject != null || !mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _subject != null) return;
          setState(() {
            _subject = loadedSubject;
          });
        });
      });

      return subjectAsync.when(
        data: (loadedSubject) {
          if (loadedSubject == null) {
            return const _ExamShell(
              child: _ExamStateView(
                icon: Icons.find_in_page_outlined,
                title: 'Sujet introuvable',
                message:
                    "Cette épreuve est introuvable ou n'a pas encore été publiée.",
              ),
            );
          }

          return const _ExamShell(
            child: Center(child: CircularProgressIndicator()),
          );
        },
        loading:
            () => const _ExamShell(
              child: Center(child: CircularProgressIndicator()),
            ),
        error:
            (error, _) => _ExamShell(
              child: _ExamStateView(
                icon: Icons.sync_problem_outlined,
                title: 'Sujet indisponible',
                message: firestoreDataErrorMessage(
                  error,
                  fallback:
                      'Impossible de charger cette épreuve pour le moment.',
                ),
              ),
            ),
      );
    }

    final sessionAsync = ref.watch(sessionByIdProvider(widget.sessionId));
    return sessionAsync.when(
      data: (session) {
        if (session == null) {
          _restoreSystemUi();
          return const _ExamShell(
            child: _ExamStateView(
              icon: Icons.event_busy_outlined,
              title: 'Session introuvable',
              message: "Cette session n'existe plus ou n'est plus accessible.",
            ),
          );
        }

        if (user == null ||
            !sessionMatchesStudent(session, user) ||
            !subjectMatchesStudent(subject, user)) {
          _restoreSystemUi();
          return _ExamShell(
            child: _ExamStateView(
              icon: Icons.lock_outline,
              title: 'Accès refusé',
              message:
                  "Cette épreuve ne correspond pas à ton profil ou n'est pas disponible pour ton compte.",
              actionLabel: 'Retour au planning',
              onAction: () => context.go(AppRoutes.planningSessionPath(session.id)),
            ),
          );
        }

        // Seul le statut 'closed' bloque complètement l'accès.
        // 'resultsPublished' : les résultats sont publiés pour ceux qui ont soumis,
        // mais un élève dans son créneau horaire doit encore pouvoir passer.
        if (session.status == SessionStatus.closed) {
          _restoreSystemUi();
          return _ExamShell(
            child: _ExamStateView(
              icon: Icons.event_busy_outlined,
              title: 'Session fermée',
              message:
                  'Cette session est terminée. Les épreuves ne sont plus accessibles.',
              actionLabel: 'Retour au planning',
              onAction: () => context.go(AppRoutes.planningSessionPath(session.id)),
            ),
          );
        }

        final paymentAsync =
            session.price <= 0
                ? const AsyncValue<PaymentModel?>.data(null)
                : ref.watch(
                  paymentForSessionProvider((
                    userId: user.uid,
                    sessionId: session.id,
                  )),
                );

        return paymentAsync.when(
          data: (payment) {
            final hasSessionAccess = studentHasSessionAccess(
              session: session,
              user: user,
              payment: payment,
            );
            if (!hasSessionAccess) {
              _restoreSystemUi();
              final paymentPending = payment?.isPending ?? false;
              return _ExamShell(
                child: _ExamStateView(
                  icon:
                      paymentPending
                          ? Icons.hourglass_top_rounded
                          : Icons.lock_outline,
                  title:
                      paymentPending
                          ? 'Paiement en cours'
                          : 'Session verrouillée',
                  message:
                      paymentPending
                          ? "Ton paiement est en cours de validation. L'accès sera ouvert automatiquement dès approbation."
                          : "Cette session est payante. Déverrouille-la avant d'ouvrir l'épreuve.",
                  actionLabel:
                      paymentPending
                          ? 'Retour au planning'
                          : 'Déverrouiller la session',
                  onAction:
                      paymentPending
                          ? () => context.go(AppRoutes.planningSessionPath(session.id))
                          : () => context.push(
                            AppRoutes.paymentPath(session.id),
                            extra: {'session': session},
                          ),
                ),
              );
            }

            if (user.hasAbandonedSubject(subject.id)) {
              _restoreSystemUi();
              return _ExamShell(
                child: _ExamStateView(
                  icon: Icons.block_outlined,
                  title: 'Épreuve abandonnée',
                  message:
                      'Tu as quitté cette épreuve sans soumettre de copie. Elle reste bloquée pour ton compte.',
                  actionLabel: 'Retour au planning',
                  onAction: () => context.go(AppRoutes.planningSessionPath(session.id)),
                ),
              );
            }

            final providerArgs = (userId: user.uid, subjectId: subject.id);
            final existingSubmissionAsync = ref.watch(
              submissionForSubjectProvider(providerArgs),
            );

            return existingSubmissionAsync.when(
              data: (existingSubmission) {
                if (existingSubmission != null) {
                  _restoreSystemUi();
                  return _ExamShell(
                    child: _ExamStateView(
                      icon:
                          existingSubmission.canAccessResultDetail
                              ? Icons.verified_outlined
                              : Icons.hourglass_top_rounded,
                      title:
                          existingSubmission.canAccessResultDetail
                              ? 'Résultat déjà disponible'
                              : 'Copie déjà soumise',
                      message:
                          '${existingSubmission.subjectName}\n\n${existingSubmission.workflowDescription}',
                      actionLabel:
                          existingSubmission.canAccessResultDetail
                              ? 'Voir le résultat'
                              : 'Suivre la correction',
                      onAction: () => _openExistingSubmission(existingSubmission),
                    ),
                  );
                }

                if (!subject.isAccessibleNow) {
                  _restoreSystemUi();
                  final (title, message) = switch (subject.timeStatus) {
                    ExamTimeStatus.upcoming => (
                      'Épreuve non ouverte',
                      "Cette épreuve n'a pas encore commencé. Reviens pendant la plage autorisée.",
                    ),
                    ExamTimeStatus.lateBlocked => (
                      'Accès expiré',
                      "Le délai d'entrée dans cette épreuve est dépassé.",
                    ),
                    ExamTimeStatus.past => (
                      'Épreuve terminée',
                      "Cette épreuve est terminée. Tu ne peux plus l'ouvrir depuis cet écran.",
                    ),
                    ExamTimeStatus.accessible => (
                      'Épreuve disponible',
                      'Cette épreuve est prête.',
                    ),
                  };

                  return _ExamShell(
                    child: _ExamStateView(
                      icon: Icons.schedule_outlined,
                      title: title,
                      message: message,
                      actionLabel: 'Retour au planning',
                      onAction:
                          () => context.go(
                            AppRoutes.planningSessionPath(session.id),
                          ),
                    ),
                  );
                }

                _startExam();
                return PopScope(
                  canPop: false,
                  onPopInvokedWithResult: (didPop, _) async {
                    if (didPop) return;
                    await _handleExitExam(subject);
                  },
                  child: Scaffold(
                    backgroundColor: context.palette.background,
                    body: Column(
                      children: [
                        _ExamTopBar(
                          subject: subject,
                          sessionTitle: session.title,
                          audienceLabel: session.audienceLabel,
                          onSubmit: () => _goToSubmission(subject),
                          onExpired: () => _onExamExpired(subject),
                          examExpired: _examExpired,
                        ),
                        Expanded(child: _SubjectViewer(subject: subject)),
                        _ExamBottomBar(
                          subject: subject,
                          onSubmit: () => _goToSubmission(subject),
                          examExpired: _examExpired,
                        ),
                      ],
                    ),
                  ),
                );
              },
              loading: () {
                _restoreSystemUi();
                return const _ExamShell(
                  child: Center(child: CircularProgressIndicator()),
                );
              },
              error: (error, _) {
                _restoreSystemUi();
                return _ExamShell(
                  child: _ExamStateView(
                    icon: Icons.sync_problem_outlined,
                    title: 'Vérification impossible',
                    message: submissionDataErrorMessage(error),
                    actionLabel: 'Réessayer',
                    onAction:
                        () => ref.invalidate(
                          submissionForSubjectProvider(providerArgs),
                        ),
                  ),
                );
              },
            );
          },
          loading: () {
            _restoreSystemUi();
            return const _ExamShell(
              child: Center(child: CircularProgressIndicator()),
            );
          },
          error: (error, _) {
            _restoreSystemUi();
            return _ExamShell(
              child: _ExamStateView(
                icon: Icons.lock_outline,
                title: 'Accès indisponible',
                message: firestoreDataErrorMessage(
                  error,
                  fallback:
                      "Impossible de vérifier l'accès à cette session pour le moment.",
                ),
                actionLabel: 'Retour au planning',
                onAction: () => context.go(AppRoutes.planningSessionPath(session.id)),
              ),
            );
          },
        );
      },
      loading: () {
        _restoreSystemUi();
        return const _ExamShell(
          child: Center(child: CircularProgressIndicator()),
        );
      },
      error: (error, _) {
        _restoreSystemUi();
        return _ExamShell(
          child: _ExamStateView(
            icon: Icons.sync_problem_outlined,
            title: 'Session indisponible',
            message: firestoreDataErrorMessage(
              error,
              fallback:
                  'Impossible de charger la session de cette épreuve pour le moment.',
            ),
            actionLabel: 'Réessayer',
            onAction: () => ref.invalidate(sessionByIdProvider(widget.sessionId)),
          ),
        );
      },
    );
  }
}

class _ExamTopBar extends StatelessWidget {
  final SubjectModel subject;
  final String sessionTitle;
  final String audienceLabel;
  final VoidCallback onSubmit;
  final VoidCallback onExpired;
  final bool examExpired;

  const _ExamTopBar({
    required this.subject,
    required this.sessionTitle,
    required this.audienceLabel,
    required this.onSubmit,
    required this.onExpired,
    required this.examExpired,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              // Ligne 1 : nom matière + bouton soumettre
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.article_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '$sessionTitle${audienceLabel.trim().isEmpty ? '' : ' • $audienceLabel'}',
                          style: TextStyle(
                            color: Colors.white.withAlpha(180),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: onSubmit,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Soumettre',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Ligne 2 : chrono centré
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Heure de début
                  Text(
                    'Début : ${DateFormat('HH:mm').format(subject.startTime)}',
                    style: TextStyle(
                      color: Colors.white.withAlpha(160),
                      fontSize: 12,
                    ),
                  ),

                  // Countdown
                  if (!examExpired)
                    ExamCountdown(
                      remaining: subject.remainingTime,
                      onExpired: onExpired,
                      large: false,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'TEMPS ÉCOULÉ',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 1,
                        ),
                      ),
                    ),

                  // Heure de fin
                  Text(
                    'Fin : ${DateFormat('HH:mm').format(subject.endTime)}',
                    style: TextStyle(
                      color: Colors.white.withAlpha(160),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExamShell extends StatelessWidget {
  final Widget child;

  const _ExamShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: context.palette.background, body: child);
  }
}

class _SubjectViewer extends StatefulWidget {
  final SubjectModel subject;

  const _SubjectViewer({required this.subject});

  @override
  State<_SubjectViewer> createState() => _SubjectViewerState();
}

class _SubjectViewerState extends State<_SubjectViewer> {
  late Future<String?> _pdfPathFuture;

  @override
  void initState() {
    super.initState();
    _pdfPathFuture = _resolvePdfPath();
  }

  @override
  void didUpdateWidget(covariant _SubjectViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.subject.subjectFileRef != widget.subject.subjectFileRef) {
      _pdfPathFuture = _resolvePdfPath();
    }
  }

  Future<String?> _resolvePdfPath() async {
    final fileRef = widget.subject.subjectFileRef.trim();
    if (fileRef.isEmpty) return null;

    final tempDir = await getTemporaryDirectory();
    final safeId = widget.subject.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final localFile = File('${tempDir.path}/$safeId.pdf');

    if (await localFile.exists() && await localFile.length() > 0) {
      return localFile.path;
    }

    await FirebaseStorage.instance.ref(fileRef).writeToFile(localFile);
    return localFile.path;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.palette.surfaceVariant,
      child: Column(
        children: [
          // Barre d'outils PDF
          Container(
            height: 44,
            color: context.palette.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  'Sujet d\'examen',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    fontSize: 13,
                  ),
                ),
                Spacer(),
                Icon(
                  Icons.picture_as_pdf_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
                SizedBox(width: 6),
                Text(
                  'PDF sécurisé',
                  style: TextStyle(fontSize: 11, color: AppColors.primary),
                ),
                VerticalDivider(width: 20),
                Icon(Icons.no_photography, size: 16, color: context.palette.textHint),
                SizedBox(width: 4),
                Text(
                  'Capture désactivée',
                  style: TextStyle(fontSize: 10, color: context.palette.textHint),
                ),
              ],
            ),
          ),

          // Contenu du sujet
          Expanded(
            child: FutureBuilder<String?>(
              future: _pdfPathFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return const _ExamStateView(
                    icon: Icons.cloud_off_outlined,
                    title: 'Sujet indisponible',
                    message:
                        "Le fichier PDF n'a pas pu être téléchargé depuis le stockage.",
                  );
                }

                final filePath = snapshot.data;
                if (filePath == null || filePath.isEmpty) {
                  return const _ExamStateView(
                    icon: Icons.picture_as_pdf_outlined,
                    title: 'Sujet non disponible',
                    message: "Aucun fichier PDF n'est associé à cette épreuve.",
                  );
                }

                return PDFView(
                  filePath: filePath,
                  enableSwipe: true,
                  autoSpacing: true,
                  pageFling: true,
                  swipeHorizontal: false,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ExamStateView({
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: context.palette.textHint),
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

class _ExamBottomBar extends StatelessWidget {
  final SubjectModel subject;
  final VoidCallback onSubmit;
  final bool examExpired;

  const _ExamBottomBar({
    required this.subject,
    required this.onSubmit,
    required this.examExpired,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Quand tu as terminé',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.palette.textSecondary,
                  ),
                ),
                Text(
                  'Prends une photo de ta copie',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: onSubmit,
            icon: const Icon(Icons.upload_file_outlined, size: 18),
            label: Text('Soumettre'),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  examExpired ? AppColors.error : AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 46),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
          ),
        ],
      ),
    );
  }
}

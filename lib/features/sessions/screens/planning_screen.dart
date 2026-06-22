import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../core/router/app_router.dart';
import '../../../models/payment_model.dart';
import '../../../models/session_model.dart';
import '../../../models/submission_model.dart';
import '../../../models/subject_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/payments_provider.dart';
import '../../../providers/sessions_provider.dart';

class PlanningScreen extends ConsumerStatefulWidget {
  final String? sessionId;
  /// true quand ouvert comme route indépendante (pas comme onglet du dashboard).
  final bool isRoute;
  const PlanningScreen({super.key, this.sessionId, this.isRoute = false});

  @override
  ConsumerState<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends ConsumerState<PlanningScreen> {
  String? _selectedSessionId;
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedSessionId = widget.sessionId;
  }

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(sessionsProvider);
    final currentUser = ref.watch(currentUserProvider);
    final canSeeRequestEntry = currentUser?.isStudent ?? false;

    return Scaffold(
      backgroundColor: context.palette.background,
      body: sessionsAsync.when(
        data: (sessions) {
          if (sessions.isEmpty) {
            return _PlanningStateView(
              icon: Icons.event_busy_outlined,
              title: 'Aucune session disponible',
              message: 'Les sessions apparaîtront ici dès leur ouverture.',
              showBack: widget.isRoute || widget.sessionId != null,
              onRequestSession: canSeeRequestEntry
                  ? () => handleRequestOnDemandTap(context, currentUser)
                  : null,
            );
          }

          _selectedSessionId ??= sessions.first.id;
          final session = sessions.firstWhere(
            (s) => s.id == _selectedSessionId,
            orElse: () => sessions.first,
          );

          return Column(
            children: [
              _PlanningHeader(
                session: session,
                sessions: sessions,
                selectedDay: _selectedDay,
                onBack: (widget.isRoute || widget.sessionId != null)
                    ? () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(AppRoutes.dashboard);
                        }
                      }
                    : null,
                onDaySelected: (d) => setState(() => _selectedDay = d),
                onSessionChanged: (id) => setState(() {
                  _selectedSessionId = id;
                  _selectedDay = DateTime.now();
                }),
              ),
              Expanded(
                child: _SubjectsList(
                  session: session,
                  selectedDay: _selectedDay,
                  onDaySelected: (d) => setState(() => _selectedDay = d),
                ),
              ),
            ],
          );
        },
        loading: () => const _LoadingView(),
        error: (error, _) => _PlanningStateView(
          icon: Icons.sync_problem_outlined,
          title: 'Planning indisponible',
          message: firestoreDataErrorMessage(
            error,
            fallback: 'Impossible de charger les sessions pour le moment.',
          ),
          showBack: widget.isRoute || widget.sessionId != null,
        ),
      ),
    );
  }
}

// ─── Header sombre avec sélecteur de jours ────────────────────────────────────
class _PlanningHeader extends ConsumerWidget {
  final SessionModel session;
  final List<SessionModel> sessions;
  final DateTime selectedDay;
  /// Callback de retour fourni par le parent. Null = pas de bouton retour.
  final VoidCallback? onBack;
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<String> onSessionChanged;

  const _PlanningHeader({
    required this.session,
    required this.sessions,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onSessionChanged,
    this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjectsAsync = ref.watch(subjectsProvider(session.id));
    final subjects = subjectsAsync.asData?.value ?? [];
    final topPad = MediaQuery.of(context).padding.top;
    final currentUser = ref.watch(currentUserProvider);
    final canSeeRequestEntry = currentUser?.isStudent ?? false;

    // Extraire les jours uniques
    final days = <DateTime>{};
    for (final s in subjects) {
      days.add(DateTime(s.startTime.year, s.startTime.month, s.startTime.day));
    }
    final sortedDays = days.toList()..sort();

    // Label semaine
    final weekLabel = sortedDays.isNotEmpty
        ? 'Semaine du ${DateFormat('d MMM', 'fr').format(sortedDays.first)}'
        : DateFormat("'Semaine du' d MMM", 'fr').format(selectedDay);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(0, topPad, 0, 0),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF080E4A), Color(0xFF1A2590)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titre + back
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 16, 0),
            child: Row(
              children: [
                if (onBack != null)
                  IconButton(
                    icon: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(22),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                    onPressed: onBack,
                    padding: EdgeInsets.zero,
                  )
                else
                  const SizedBox(width: 16),
                Text(
                  "Planning d'Examen",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Semaine + session picker
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
            child: Row(
              children: [
                Text(
                  weekLabel,
                  style: TextStyle(
                    color: Colors.white.withAlpha(180),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (canSeeRequestEntry)
                  GestureDetector(
                    onTap: () => handleRequestOnDemandTap(context, currentUser),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withAlpha(40),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: AppColors.accent.withAlpha(90)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_circle_outline_rounded,
                            color: Colors.white.withAlpha(230),
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Demander une session',
                            style: TextStyle(
                              color: Colors.white.withAlpha(230),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (sessions.length > 1)
                  GestureDetector(
                    onTap: () => _showSessionPicker(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(22),
                        borderRadius: BorderRadius.circular(20),
                        border:
                            Border.all(color: Colors.white.withAlpha(40)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Choisir session',
                            style: TextStyle(
                              color: Colors.white.withAlpha(210),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white.withAlpha(200),
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Sélecteur de jours
          const SizedBox(height: 16),
          if (sortedDays.isEmpty)
            const SizedBox(height: 80)
          else
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: sortedDays.length,
                itemBuilder: (_, i) {
                  final day = sortedDays[i];
                  final isSelected = day.year == selectedDay.year &&
                      day.month == selectedDay.month &&
                      day.day == selectedDay.day;
                  final isToday = day.year == DateTime.now().year &&
                      day.month == DateTime.now().month &&
                      day.day == DateTime.now().day;

                  return GestureDetector(
                    onTap: () => onDaySelected(day),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      width: 56,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white
                            : Colors.white.withAlpha(18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isToday && !isSelected
                              ? AppColors.accent
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat('EEE', 'fr')
                                .format(day)
                                .toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.white.withAlpha(160),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            day.day.toString(),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _showSessionPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Text(
              'Choisir une session',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const Divider(height: 1),
          ...sessions.map((s) {
            final isSelected = s.id == session.id;
            return ListTile(
              leading: Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: isSelected ? AppColors.primary : context.palette.textHint,
              ),
              title: Text(
                s.title,
                style: TextStyle(
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? AppColors.primary
                      : context.palette.textPrimary,
                ),
              ),
              subtitle: Text(s.audienceLabel),
              onTap: () {
                onSessionChanged(s.id);
                Navigator.pop(context);
              },
            );
          }),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ─── Liste des épreuves (avec gestion paywall) ────────────────────────────────
class _SubjectsList extends ConsumerWidget {
  final SessionModel session;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  const _SubjectsList({
    required this.session,
    required this.selectedDay,
    required this.onDaySelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjectsAsync = ref.watch(subjectsProvider(session.id));
    final user = ref.watch(currentUserProvider);
    final userId = user?.uid;
    final hasSubscription =
        user?.subscriptions.contains(session.id) ?? false;

    if (session.price <= 0 || hasSubscription) {
      return _buildContent(subjectsAsync, context, userId);
    }

    final paymentAsync = userId == null
        ? const AsyncValue<PaymentModel?>.data(null)
        : ref.watch(paymentForSessionProvider((
            userId: userId,
            sessionId: session.id,
          )));

    return paymentAsync.when(
      data: (payment) {
        if (payment?.isApproved ?? false) {
          return _buildContent(subjectsAsync, context, userId);
        }
        return _PaymentGate(
          session: session,
          paymentAsync: AsyncValue.data(payment),
        );
      },
      loading: () => const _LoadingView(),
      error: (_, __) => _PaymentGate(
        session: session,
        paymentAsync: const AsyncValue.data(null),
      ),
    );
  }

  Widget _buildContent(
    AsyncValue<List<SubjectModel>> subjectsAsync,
    BuildContext context,
    String? userId,
  ) {
    return subjectsAsync.when(
      data: (subjects) {
        if (subjects.isEmpty) {
          return const _PlanningStateView(
            icon: Icons.inbox_outlined,
            title: 'Aucune épreuve',
            message: 'Les épreuves seront disponibles bientôt.',
          );
        }

        // Grouper par jour
        final byDay = <DateTime, List<SubjectModel>>{};
        for (final s in subjects) {
          final day = DateTime(
            s.startTime.year, s.startTime.month, s.startTime.day);
          byDay.putIfAbsent(day, () => []).add(s);
        }
        final sortedDays = byDay.keys.toList()..sort();

        final dayKey = DateTime(
            selectedDay.year, selectedDay.month, selectedDay.day);

        List<SubjectModel> todaySubjects;
        DateTime activeDay;
        if (byDay.containsKey(dayKey)) {
          todaySubjects = byDay[dayKey]!;
          activeDay = dayKey;
        } else {
          // Sélectionner le premier jour avec des épreuves
          activeDay = sortedDays.first;
          todaySubjects = byDay[activeDay]!;
        }

        todaySubjects = [...todaySubjects]
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Label du jour
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 22,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEA580C),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    DateFormat('EEEE d MMMM', 'fr')
                        .format(activeDay)
                        .toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: context.palette.textPrimary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),

            // Liste timeline
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                itemCount: todaySubjects.length,
                itemBuilder: (_, i) => _TimelineSubjectCard(
                  subject: todaySubjects[i],
                  userId: userId,
                  isLast: i == todaySubjects.length - 1,
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const _LoadingView(),
      error: (error, _) => _PlanningStateView(
        icon: Icons.article_outlined,
        title: 'Épreuves indisponibles',
        message: firestoreDataErrorMessage(
          error,
          fallback: 'Impossible de charger les épreuves.',
        ),
      ),
    );
  }
}

// ─── Carte épreuve — style timeline ──────────────────────────────────────────
class _TimelineSubjectCard extends ConsumerWidget {
  final SubjectModel subject;
  final String? userId;
  final bool isLast;

  const _TimelineSubjectCard({
    required this.subject,
    required this.userId,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final isAbandoned =
        currentUser?.abandonedSubjectIds.contains(subject.id) ?? false;
    final submissionAsync = userId == null
        ? const AsyncValue<SubmissionModel?>.data(null)
        : ref.watch(submissionForSubjectProvider((
            userId: userId!,
            subjectId: subject.id,
          )));

    final timeStatus = subject.timeStatus;

    return submissionAsync.when(
      data: (submission) => _buildCard(
        context,
        timeStatus,
        submission,
        isAbandoned,
      ),
      loading: () => _buildCard(context, timeStatus, null, isAbandoned),
      error: (_, __) => _buildCard(context, timeStatus, null, isAbandoned),
    );
  }

  Widget _buildCard(
    BuildContext context,
    ExamTimeStatus timeStatus,
    SubmissionModel? submission,
    bool isAbandoned,
  ) {
    final isDone = submission != null ||
        timeStatus == ExamTimeStatus.past ||
        timeStatus == ExamTimeStatus.lateBlocked;
    final isActive = timeStatus == ExamTimeStatus.accessible &&
        submission == null &&
        !isAbandoned;
    final isSubmitted = submission != null;

    // Couleur du cercle timeline
    Color circleColor;
    if (isAbandoned) {
      circleColor = AppColors.error;
    } else if (isSubmitted || timeStatus == ExamTimeStatus.past) {
      circleColor = AppColors.statusOpen; // vert
    } else if (isActive) {
      circleColor = const Color(0xFFEA580C); // orange
    } else {
      circleColor = context.palette.divider; // gris
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cercle + ligne verticale
        Column(
          children: [
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(top: 18),
              decoration: BoxDecoration(
                color: isActive || isSubmitted || isDone
                    ? circleColor
                    : context.palette.surface,
                shape: BoxShape.circle,
                border: Border.all(color: circleColor, width: 2),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 110,
                color: context.palette.divider,
              ),
          ],
        ),
        const SizedBox(width: 14),

        // Carte
        Expanded(
          child: GestureDetector(
            onTap: () => _onTap(context, timeStatus, submission, isAbandoned),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              decoration: BoxDecoration(
                color: context.palette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isActive
                      ? const Color(0xFFEA580C)
                      : context.palette.divider,
                  width: isActive ? 1.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isActive ? 10 : 5),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Infos matière
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          subject.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: context.palette.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Text(
                              '${DateFormat('HH:mm').format(subject.startTime)} - ${DateFormat('HH:mm').format(subject.endTime)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.palette.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusBadge(
                              timeStatus: timeStatus,
                              submission: submission,
                              isAbandoned: isAbandoned,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Coeff. ${subject.coefficient.toInt()}  ·  ${subject.durationLabel}',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.palette.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Action droite
                  _ActionWidget(
                    timeStatus: timeStatus,
                    submission: submission,
                    subject: subject,
                    isAbandoned: isAbandoned,
                    onTap: () => _onTap(
                      context,
                      timeStatus,
                      submission,
                      isAbandoned,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onTap(
    BuildContext context,
    ExamTimeStatus timeStatus,
    SubmissionModel? submission,
    bool isAbandoned,
  ) {
    if (submission != null) {
      if (submission.canAccessResultDetail) {
        context.push(
          AppRoutes.resultDetailPath(submission.id),
          extra: {'submission': submission},
        );
      } else {
        context.push(AppRoutes.results);
      }
      return;
    }
    if (!isAbandoned && timeStatus == ExamTimeStatus.accessible) {
      context.push(
        AppRoutes.examPath(
          sessionId: subject.sessionId,
          subjectId: subject.id,
        ),
        extra: {'subject': subject, 'sessionId': subject.sessionId},
      );
    }
  }
}

// ─── Badge statut ─────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final ExamTimeStatus timeStatus;
  final SubmissionModel? submission;
  final bool isAbandoned;

  const _StatusBadge({
    required this.timeStatus,
    this.submission,
    this.isAbandoned = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isAbandoned) {
      return _badge('ABANDONNÉE', AppColors.error, AppColors.error.withAlpha(18));
    }

    if (submission != null) {
      // Copie soumise
      switch (submission!.status) {
        case SubmissionStatus.published:
          return _badge('TERMINÉ', const Color(0xFF16A34A),
              const Color(0xFF16A34A).withAlpha(22));
        case SubmissionStatus.humanReviewed:
          return _badge('CORRIGÉ', AppColors.statusPublished,
              AppColors.statusPublished.withAlpha(20));
        default:
          return _badge('EN CORRECTION', AppColors.statusCorrecting,
              AppColors.statusCorrecting.withAlpha(20));
      }
    }

    switch (timeStatus) {
      case ExamTimeStatus.accessible:
        return _badge(
            'EN COURS', const Color(0xFFEA580C), const Color(0xFFEA580C).withAlpha(22));
      case ExamTimeStatus.upcoming:
        return _badge('À VENIR', context.palette.textSecondary,
            context.palette.surfaceVariant);
      case ExamTimeStatus.lateBlocked:
        return _badge('FERMÉE', AppColors.error, AppColors.error.withAlpha(18));
      case ExamTimeStatus.past:
        return _badge('TERMINÉE', context.palette.textHint,
            context.palette.surfaceVariant);
    }
  }

  Widget _badge(String label, Color text, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ─── Widget d'action (droite de la carte) ─────────────────────────────────────
class _ActionWidget extends StatelessWidget {
  final ExamTimeStatus timeStatus;
  final SubmissionModel? submission;
  final SubjectModel subject;
  final bool isAbandoned;
  final VoidCallback onTap;

  const _ActionWidget({
    required this.timeStatus,
    required this.submission,
    required this.subject,
    required this.isAbandoned,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isAbandoned) {
      return const Icon(
        Icons.block_outlined,
        color: AppColors.error,
        size: 22,
      );
    }

    // Copie publiée → afficher la note
    if (submission != null && submission!.isPublished &&
        submission!.studentVisibleScore != null) {
      return Text(
        '${submission!.studentVisibleScore!.toStringAsFixed(1)}/20',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          color: Color(0xFF16A34A),
        ),
      );
    }

    // Copie en correction → icône hourglass
    if (submission != null) {
      return const Icon(
        Icons.hourglass_bottom_rounded,
        color: AppColors.statusCorrecting,
        size: 22,
      );
    }

    // EN COURS → bouton play bleu
    if (timeStatus == ExamTimeStatus.accessible) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      );
    }

    // À VENIR → cadenas
    if (timeStatus == ExamTimeStatus.upcoming) {
      return Icon(
        Icons.lock_outline_rounded,
        color: context.palette.textHint,
        size: 22,
      );
    }

    return const SizedBox.shrink();
  }
}

// ─── Paywall ──────────────────────────────────────────────────────────────────
class _PaymentGate extends StatelessWidget {
  final SessionModel session;
  final AsyncValue<PaymentModel?> paymentAsync;

  const _PaymentGate({required this.session, required this.paymentAsync});

  @override
  Widget build(BuildContext context) {
    return paymentAsync.when(
      data: (payment) {
        final isPending = payment?.isPending ?? false;
        final isAutomaticPayment = payment?.isMobileMoney == true;
        final canRetry = isAutomaticPayment || (payment?.isGhostPending ?? false);
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPending
                        ? Icons.hourglass_bottom_rounded
                        : Icons.lock_outline_rounded,
                    color: isPending ? AppColors.warning : AppColors.primary,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  isPending ? 'Validation en cours…' : 'Session payante',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isPending
                      ? canRetry
                          ? 'Ton paiement est en cours de confirmation. Tu seras notifié dès validation.'
                          : 'Ta preuve de paiement est en cours de vérification. Tu seras notifié dès validation.'
                      : 'Accède à toutes les épreuves de ${session.title} pour ${session.price.toStringAsFixed(0)} FCFA.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: context.palette.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                if (!isPending || canRetry)
                  ElevatedButton.icon(
                    onPressed: () => context.push(
                      AppRoutes.paymentPath(session.id),
                      extra: {'session': session},
                    ),
                    icon: Icon(
                      isPending
                          ? Icons.refresh_rounded
                          : Icons.payment_outlined,
                      size: 18,
                    ),
                    label: Text(
                      isPending
                          ? 'Réessayer le paiement'
                          : 'Payer ${session.price.toStringAsFixed(0)} FCFA',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      loading: () => const _LoadingView(),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: AppColors.accent.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline_rounded,
                    color: AppColors.primary, size: 40),
              ),
              const SizedBox(height: 20),
              Text('Session payante',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
              const SizedBox(height: 10),
              Text(
                'Accède à toutes les épreuves de ${session.title} pour ${session.price.toStringAsFixed(0)} FCFA.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14, color: context.palette.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => context.push(
                  AppRoutes.paymentPath(session.id),
                  extra: {'session': session},
                ),
                icon: const Icon(Icons.payment_outlined, size: 18),
                label: Text('Payer ${session.price.toStringAsFixed(0)} FCFA'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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

// ─── Demande de session à la demande ──────────────────────────────────────────
/// Point d'entrée partagé (header + état vide) pour demander une session.
/// Si le profil n'est pas complet, redirige vers l'édition du profil plutôt
/// que de laisser la Cloud Function rejeter silencieusement la demande.
void handleRequestOnDemandTap(BuildContext context, UserModel? user) {
  if (user == null) return;

  if (!user.isProfileComplete) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Profil incomplet'),
        content: const Text(
          'Complète ton profil (téléphone, établissement, classe et série) '
          'avant de demander une session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.push(AppRoutes.editProfile);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Compléter mon profil'),
          ),
        ],
      ),
    );
    return;
  }

  context.push(AppRoutes.requestOnDemandSession);
}

// ─── États génériques ─────────────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Center(child: CircularProgressIndicator());
  }
}

class _PlanningStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final bool showBack;
  final VoidCallback? onRequestSession;

  const _PlanningStateView({
    required this.icon,
    required this.title,
    required this.message,
    this.showBack = false,
    this.onRequestSession,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: showBack
          ? AppBar(
              title: Text("Planning d'Examen"),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppRoutes.dashboard);
                  }
                },
              ),
            )
          : null,
      body: Center(
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
              if (onRequestSession != null) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: onRequestSession,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  label: const Text('Demander une session'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../core/router/app_router.dart';
import '../../../models/session_model.dart';
import '../../../models/submission_model.dart';
import '../../../models/subject_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/announcements_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/biometric_lock_provider.dart';
import '../../../providers/notification_settings_provider.dart';
import '../../../providers/offline_queue_provider.dart';
import '../../../providers/sessions_provider.dart';
import '../../../providers/theme_mode_provider.dart';
import '../../results/screens/results_screen.dart';
import '../../sessions/screens/planning_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _currentNavIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromptNotifications();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Au premier lancement (permission encore non déterminée), propose
  /// d'activer les notifications avec une explication, puis déclenche la
  /// vraie demande système.
  Future<void> _maybePromptNotifications() async {
    final notifier = ref.read(notificationSettingsProvider.notifier);
    if (notifier.promptAlreadyShown) return;

    final settings = await ref.read(notificationSettingsProvider.future);
    if (!mounted) return;

    // Décision déjà prise par l'utilisateur (accordé/refusé) → ne pas reproposer.
    if (settings.osStatus != AuthorizationStatus.notDetermined) {
      notifier.markPromptShown();
      return;
    }

    notifier.markPromptShown();

    final accept = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Activer les notifications ?'),
        content: const Text(
          "Reçois les rappels d'épreuves, la validation de tes paiements, "
          "la publication de tes résultats et les annonces de l'administration.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Plus tard'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Activer'),
          ),
        ],
      ),
    );

    if (accept == true) {
      await notifier.enable();
    }
  }

  void _onTabTapped(int index) {
    if (index == _currentNavIndex) return;
    setState(() => _currentNavIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 340),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.value;

    if (authState.isLoading && user == null) {
      return Scaffold(
        backgroundColor: context.palette.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: context.palette.background,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _KeepAlivePage(child: _HomeTab(user: user)),
          const _KeepAlivePage(child: _PlanningTab()),
          const _KeepAlivePage(child: _ResultsTab()),
          _KeepAlivePage(child: _ProfileTab(user: user)),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    const gold = Color(0xFFF5B731);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(18),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: BottomNavigationBar(
          currentIndex: _currentNavIndex,
          onTap: _onTabTapped,
          elevation: 0,
          backgroundColor: context.palette.surface,
          selectedItemColor: isDark ? gold : AppColors.primary,
          unselectedItemColor: context.palette.textSecondary,
          type: BottomNavigationBarType.fixed,
          selectedLabelStyle: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: TextStyle(fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Accueil',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_month_outlined),
              activeIcon: Icon(Icons.calendar_month_rounded),
              label: 'Planning',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.check_circle_outline),
              activeIcon: Icon(Icons.check_circle_rounded),
              label: 'Résultats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person_rounded),
              label: 'Profil',
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Garde les pages PageView en vie lors des changements d'onglet ───────────
class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ─── Onglet Accueil ──────────────────────────────────────────────────────────
class _HomeTab extends ConsumerWidget {
  final UserModel? user;
  const _HomeTab({this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: context.palette.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          // Ré-abonne tous les flux de l'accueil (sessions, épreuves,
          // soumissions, résultats et classement).
          ref.invalidate(activeSessionsProvider);
          ref.invalidate(sessionsProvider);
          ref.invalidate(subjectsProvider);
          ref.invalidate(mySubmissionsProvider);
          ref.invalidate(studentResultProvider);
          ref.invalidate(studentRankingProvider);
          // Laisse le temps aux flux de se ré-abonner pour un retour visible.
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header sombre ──
              _EntranceMotion(
                beginOffset: const Offset(0, -22),
                child: _DashboardHeader(user: user),
              ),

              // ── Bloc stats + classement (padded) ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (user case final currentUser?) ...[
                      if (!currentUser.isProfileComplete) ...[
                        _EntranceMotion(
                          delay: const Duration(milliseconds: 60),
                          child: _ProfileIncompleteBanner(user: currentUser),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                    _EntranceMotion(
                      delay: const Duration(milliseconds: 110),
                      child: _StatsRow(userId: user?.uid),
                    ),
                    const SizedBox(height: 12),
                    const _EntranceMotion(
                      delay: Duration(milliseconds: 150),
                      child: _PendingUploadsBanner(),
                    ),
                    _EntranceMotion(
                      delay: const Duration(milliseconds: 190),
                      child: _RankingCard(user: user),
                    ),
                    const SizedBox(height: 24),
                    // Label sessions
                    _EntranceMotion(
                      delay: const Duration(milliseconds: 220),
                      child: Text(
                        'Sessions disponibles',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: context.palette.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Sessions carousel horizontal (pleine largeur) ──
              const SizedBox(height: 12),
              const _EntranceMotion(
                delay: Duration(milliseconds: 250),
                child: _SessionsSection(),
              ),
              const SizedBox(height: 24),

              // ── Épreuves (padded) ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _EntranceMotion(
                  delay: const Duration(milliseconds: 300),
                  child: _SubjectsSection(user: user),
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Header sombre ────────────────────────────────────────────────────────────
class _DashboardHeader extends ConsumerWidget {
  final UserModel? user;
  const _DashboardHeader({this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topPad = MediaQuery.of(context).padding.top;
    final sessionsAsync = ref.watch(activeSessionsProvider);
    final sessions = sessionsAsync.asData?.value ?? [];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, topPad + 18, 20, 22),
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
          // Ligne profil
          Row(
            children: [
              // Avatar
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withAlpha(60),
                    width: 2,
                  ),
                ),
                child: _UserAvatar(
                  user: user,
                  backgroundColor: AppColors.accent,
                  textColor: AppColors.primary,
                  fontSize: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bon retour,',
                      style: TextStyle(
                        color: Colors.white.withAlpha(170),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _userDisplayName(user),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const _ThemeToggleButton(),
              const SizedBox(width: 6),
              const _NotificationsButton(),
            ],
          ),

          // Focus global sur toutes les sessions ouvertes / en cours
          if (sessionsAsync.isLoading)
            Padding(padding: EdgeInsets.only(top: 16), child: _HeaderSkeleton())
          else if (sessions.isNotEmpty) ...[
            const SizedBox(height: 16),
            _HeaderSessionsCarousel(sessions: sessions),
          ],
        ],
      ),
    );
  }
}

class _NotificationsButton extends ConsumerWidget {
  const _NotificationsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFF5B731);
    final unread = ref.watch(unreadAnnouncementsCountProvider);

    return GestureDetector(
      onTap: () => context.push(AppRoutes.announcements),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isDark ? gold.withAlpha(32) : Colors.white.withAlpha(22),
              shape: BoxShape.circle,
              border: isDark
                  ? Border.all(color: gold.withAlpha(80), width: 1)
                  : null,
            ),
            child: Icon(
              Icons.notifications_outlined,
              color: isDark ? gold : Colors.white,
              size: 20,
            ),
          ),
          if (unread > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFF080E4A), width: 1.5),
                ),
                child: Text(
                  unread > 9 ? '9+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ThemeToggleButton extends ConsumerWidget {
  const _ThemeToggleButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final effectiveBrightness = Theme.of(context).brightness;
    final isDark = effectiveBrightness == Brightness.dark;

    IconData icon;
    String label;
    if (mode == ThemeMode.system) {
      icon = Icons.brightness_auto;
      label = 'Thème (système)';
    } else if (isDark) {
      icon = Icons.light_mode_outlined;
      label = 'Passer en mode clair';
    } else {
      icon = Icons.dark_mode_outlined;
      label = 'Passer en mode sombre';
    }

    ThemeMode next;
    if (mode == ThemeMode.system) {
      next = ThemeMode.dark;
    } else if (mode == ThemeMode.dark) {
      next = ThemeMode.light;
    } else {
      next = ThemeMode.system;
    }

    const gold = Color(0xFFF5B731);

    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: () => ref.read(themeModeProvider.notifier).setTheme(next),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isDark ? gold.withAlpha(32) : Colors.white.withAlpha(22),
            shape: BoxShape.circle,
            border:
                isDark ? Border.all(color: gold.withAlpha(80), width: 1) : null,
          ),
          child: Icon(icon, color: isDark ? gold : Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _HeaderSkeleton extends StatelessWidget {
  const _HeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

class _EntranceMotion extends StatelessWidget {
  final Widget child;
  final Duration delay;
  final Offset beginOffset;

  const _EntranceMotion({
    required this.child,
    this.delay = Duration.zero,
    this.beginOffset = const Offset(0, 18),
  });

  @override
  Widget build(BuildContext context) {
    final totalDuration = Duration(milliseconds: 420 + delay.inMilliseconds);
    final delayFraction =
        totalDuration.inMilliseconds == 0
            ? 0.0
            : delay.inMilliseconds / totalDuration.inMilliseconds;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: totalDuration,
      curve: Interval(
        delayFraction.clamp(0.0, 0.92),
        1,
        curve: Curves.easeOutCubic,
      ),
      child: child,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(
              beginOffset.dx * (1 - value),
              beginOffset.dy * (1 - value),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _SessionSubjectEntry {
  final SessionModel session;
  final SubjectModel subject;

  const _SessionSubjectEntry({required this.session, required this.subject});

  ExamTimeStatus get timeStatus => subject.timeStatus;

  DateTime get priorityDate {
    switch (timeStatus) {
      case ExamTimeStatus.accessible:
        return subject.endTime;
      case ExamTimeStatus.upcoming:
        return subject.startTime;
      case ExamTimeStatus.lateBlocked:
        return subject.endTime;
      case ExamTimeStatus.past:
        return subject.endTime;
    }
  }
}

Map<String, AsyncValue<List<SubjectModel>>> _watchSubjectsBySession(
  WidgetRef ref,
  List<SessionModel> sessions,
) {
  final states = <String, AsyncValue<List<SubjectModel>>>{};

  for (final session in sessions) {
    states[session.id] = ref.watch(subjectsProvider(session.id));
  }

  return states;
}

List<_SessionSubjectEntry> _collectDashboardSubjectEntries(
  List<SessionModel> sessions,
  Map<String, AsyncValue<List<SubjectModel>>> subjectStates,
) {
  final entries = <_SessionSubjectEntry>[];

  for (final session in sessions) {
    final subjects = subjectStates[session.id]?.asData?.value ?? const [];
    for (final subject in subjects) {
      if (subject.timeStatus == ExamTimeStatus.past) continue;
      entries.add(_SessionSubjectEntry(session: session, subject: subject));
    }
  }

  entries.sort(_compareDashboardSubjectEntries);
  return entries;
}

bool _hasAnySubjectLoading(
  List<SessionModel> sessions,
  Map<String, AsyncValue<List<SubjectModel>>> subjectStates,
) {
  return sessions.any(
    (session) => subjectStates[session.id]?.isLoading ?? false,
  );
}

int _dashboardStatusPriority(ExamTimeStatus status) {
  switch (status) {
    case ExamTimeStatus.accessible:
      return 0;
    case ExamTimeStatus.upcoming:
      return 1;
    case ExamTimeStatus.lateBlocked:
      return 2;
    case ExamTimeStatus.past:
      return 3;
  }
}

int _compareDashboardSubjectEntries(
  _SessionSubjectEntry a,
  _SessionSubjectEntry b,
) {
  final statusCompare = _dashboardStatusPriority(
    a.timeStatus,
  ).compareTo(_dashboardStatusPriority(b.timeStatus));
  if (statusCompare != 0) return statusCompare;

  final dateCompare = a.priorityDate.compareTo(b.priorityDate);
  if (dateCompare != 0) return dateCompare;

  final sessionCompare = a.session.startDate.compareTo(b.session.startDate);
  if (sessionCompare != 0) return sessionCompare;

  return a.subject.name.compareTo(b.subject.name);
}

SubjectModel? _pickSessionFocusSubject(List<SubjectModel> subjects) {
  SubjectModel? upcoming;

  for (final subject in subjects) {
    if (subject.timeStatus == ExamTimeStatus.accessible) {
      return subject;
    }
    if (upcoming == null && subject.timeStatus == ExamTimeStatus.upcoming) {
      upcoming = subject;
    }
  }

  return upcoming;
}

class _HeaderSessionsCarousel extends StatefulWidget {
  final List<SessionModel> sessions;

  const _HeaderSessionsCarousel({required this.sessions});

  @override
  State<_HeaderSessionsCarousel> createState() =>
      _HeaderSessionsCarouselState();
}

class _HeaderSessionsCarouselState extends State<_HeaderSessionsCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.94);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = widget.sessions;

    if (sessions.length == 1) {
      return _HeaderSessionCard(session: sessions.first);
    }

    return Column(
      children: [
        SizedBox(
          height: 98,
          child: PageView.builder(
            controller: _pageController,
            itemCount: sessions.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(
                  right: index == sessions.length - 1 ? 0 : 10,
                ),
                child: _HeaderSessionCard(session: sessions[index]),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(sessions.length, (index) {
            final isActive = index == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(isActive ? 220 : 90),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ─── Carte session individuelle dans le header ───────────────────────────────
class _HeaderSessionCard extends ConsumerWidget {
  final SessionModel session;

  const _HeaderSessionCard({required this.session});

  String _subtitle(SubjectModel? focusSubject) {
    if (focusSubject == null) {
      return session.audienceLabel;
    }

    switch (focusSubject.timeStatus) {
      case ExamTimeStatus.accessible:
        return 'En cours : ${focusSubject.name}';
      case ExamTimeStatus.upcoming:
        return 'Prochaine : ${focusSubject.name} à ${DateFormat('HH:mm').format(focusSubject.startTime)}';
      case ExamTimeStatus.lateBlocked:
        return 'Fenêtre fermée : ${focusSubject.name}';
      case ExamTimeStatus.past:
        return session.audienceLabel;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subjects =
        ref.watch(subjectsProvider(session.id)).asData?.value ?? [];
    final focusSubject = _pickSessionFocusSubject(subjects);
    final subtitle = _subtitle(focusSubject);

    return GestureDetector(
      onTap: () => context.push(AppRoutes.planningSessionPath(session.id)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withAlpha(30)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(25),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.calendar_month_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.12),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      subtitle,
                      key: ValueKey(subtitle),
                      style: TextStyle(
                        color: Colors.white.withAlpha(170),
                        fontSize: 12,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Builder(
              builder: (context) {
                const gold = Color(0xFFF5B731);
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color:
                        isDark ? gold.withAlpha(28) : context.palette.surface,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        isDark
                            ? Border.all(color: gold.withAlpha(80), width: 1)
                            : null,
                  ),
                  child: Text(
                    'Planning',
                    style: TextStyle(
                      color: isDark ? gold : AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Ligne de stats ───────────────────────────────────────────────────────────
class _StatsRow extends ConsumerWidget {
  final String? userId;
  const _StatsRow({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (userId == null) return const SizedBox.shrink();
    final submissionsAsync = ref.watch(mySubmissionsProvider(userId!));

    return submissionsAsync.when(
      data: (submissions) {
        final latestBySubject = <String, SubmissionModel>{};
        for (final submission in submissions) {
          final existing = latestBySubject[submission.subjectId];
          if (existing == null ||
              (submission.workflowUpdatedAt ?? submission.submittedAt).isAfter(
                existing.workflowUpdatedAt ?? existing.submittedAt,
              )) {
            latestBySubject[submission.subjectId] = submission;
          }
        }

        final latestSubmissions = latestBySubject.values.toList();
        final examsFaits = latestSubmissions.length;
        final enAttente =
            latestSubmissions
                .where((submission) => submission.isCorrecting)
                .length;

        const gold = Color(0xFFF5B731);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.assignment_turned_in_outlined,
                iconColor: isDark ? gold : AppColors.primary,
                value: '$examsFaits',
                label: 'EXAMENS FAITS',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.hourglass_top_rounded,
                iconColor:
                    enAttente > 0
                        ? AppColors.statusCorrecting
                        : context.palette.textHint,
                value: '$enAttente',
                label: 'EN ATTENTE',
              ),
            ),
          ],
        );
      },
      loading:
          () => Row(
            children: [
              Expanded(child: _StatSkeleton()),
              const SizedBox(width: 12),
              Expanded(child: _StatSkeleton()),
            ],
          ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(6),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(20),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.18),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  value,
                  key: ValueKey(value),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                  ),
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textSecondary,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: context.palette.shimmerBase,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

// ─── Sessions carousel horizontal ────────────────────────────────────────────
class _SessionsSection extends ConsumerWidget {
  const _SessionsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(activeSessionsProvider).asData?.value ?? [];
    if (sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.palette.divider),
          ),
          child: Text(
            'Aucune session disponible pour le moment.',
            style: TextStyle(
              color: context.palette.textSecondary,
              fontSize: 13,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SizedBox(
      height: 210,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 16, right: 8),
        itemCount: sessions.length,
        itemBuilder: (context, i) {
          final cappedIndex = i > 5 ? 5 : i;
          return _EntranceMotion(
            delay: Duration(milliseconds: 45 * cappedIndex),
            beginOffset: const Offset(28, 0),
            child: _SessionCard(session: sessions[i]),
          );
        },
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final SessionModel session;
  const _SessionCard({required this.session});

  @override
  Widget build(BuildContext context) {
    final isActive = session.status == SessionStatus.active;

    return GestureDetector(
      onTap: () => context.push(AppRoutes.planningSessionPath(session.id)),
      child: Container(
        width: 210,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                isActive
                    ? AppColors.primary.withAlpha(60)
                    : context.palette.divider,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(6),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge + prix
            Row(
              children: [
                _SessionStatusBadge(status: session.status),
                const Spacer(),
                Text(
                  session.price > 0
                      ? '${session.price.toStringAsFixed(0)} F'
                      : 'Gratuit',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color:
                        session.price > 0
                            ? context.palette.textPrimary
                            : AppColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Titre
            Text(
              session.title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: context.palette.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),

            // Dates
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 11,
                  color: context.palette.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '${DateFormat('dd MMM', 'fr').format(session.startDate)}'
                    ' – '
                    '${DateFormat('dd MMM', 'fr').format(session.endDate)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),

            // Public cible
            Row(
              children: [
                Icon(
                  Icons.school_outlined,
                  size: 11,
                  color: context.palette.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    session.audienceLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.palette.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

            const Spacer(),

            // Bouton
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Voir le planning',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionStatusBadge extends StatelessWidget {
  final SessionStatus status;
  const _SessionStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case SessionStatus.active:
        return _badge(
          'EN COURS',
          const Color(0xFF16A34A),
          const Color(0xFF16A34A).withAlpha(22),
        );
      case SessionStatus.open:
        return _badge(
          'OUVERTE',
          const Color(0xFF2563EB),
          const Color(0xFF2563EB).withAlpha(22),
        );
      case SessionStatus.closed:
        return _badge(
          'TERMINÉE',
          context.palette.textSecondary,
          context.palette.surfaceVariant,
        );
      case SessionStatus.resultsPublished:
        return _badge(
          'RÉSULTATS',
          const Color(0xFF7C3AED),
          const Color(0xFF7C3AED).withAlpha(22),
        );
      default:
        return const SizedBox.shrink();
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

// ─── Card classement ──────────────────────────────────────────────────────────
class _RankingCard extends ConsumerWidget {
  final UserModel? user;
  const _RankingCard({this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (user == null) return const SizedBox.shrink();

    final sessionsAsync = ref.watch(sessionsProvider);
    final sessions = sessionsAsync.asData?.value ?? [];

    // Chercher la session avec résultats publiés la plus récente
    final publishedSession = sessions.cast<SessionModel?>().firstWhere(
      (s) => s?.status == SessionStatus.resultsPublished,
      orElse: () => null,
    );

    if (publishedSession == null) return const SizedBox.shrink();

    final resultAsync = ref.watch(
      studentResultProvider((
        sessionId: publishedSession.id,
        userId: user!.uid,
      )),
    );
    final rankAsync = ref.watch(
      studentRankingProvider((
        sessionId: publishedSession.id,
        userId: user!.uid,
      )),
    );

    final result = resultAsync.asData?.value;
    final ranking = rankAsync.asData?.value;

    if (result == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => context.push(AppRoutes.results),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF080E4A), Color(0xFF1A2590)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Trophée
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(20),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                color: Color(0xFFF5B731),
                size: 28,
              ),
            ),
            const SizedBox(width: 14),

            // Infos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    publishedSession.title,
                    style: TextStyle(
                      color: Colors.white.withAlpha(180),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${result.moyenneGenerale.toStringAsFixed(2)}/20',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color:
                                result.isAdmis
                                    ? const Color(0xFF16A34A)
                                    : AppColors.error,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            result.isAdmis ? 'ADMIS' : 'AJOURNÉ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (result.mention.isNotEmpty)
                    Text(
                      result.mention,
                      style: TextStyle(
                        color: Color(0xFFF5B731),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),

            // Rang
            if (ranking != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${ranking.rank}',
                    style: TextStyle(
                      color: Color(0xFFF5B731),
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'sur ${ranking.total}',
                    style: TextStyle(
                      color: Colors.white.withAlpha(180),
                      fontSize: 11,
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white54,
                    size: 18,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Section épreuves ─────────────────────────────────────────────────────────
class _SubjectsSection extends ConsumerWidget {
  final UserModel? user;
  const _SubjectsSection({this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(activeSessionsProvider);
    final sessions = sessionsAsync.asData?.value ?? [];
    final subjectStates = _watchSubjectsBySession(ref, sessions);
    final subjectEntries = _collectDashboardSubjectEntries(
      sessions,
      subjectStates,
    );
    final isSectionLoading =
        sessionsAsync.isLoading ||
        (sessions.isNotEmpty &&
            _hasAnySubjectLoading(sessions, subjectStates) &&
            subjectEntries.isEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Sessions en cours',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: context.palette.textPrimary,
              ),
            ),
            TextButton(
              onPressed: () => context.push(AppRoutes.planning),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Voir tout',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (isSectionLoading)
          _SubjectsSkeleton()
        else if (sessions.isEmpty)
          _NoSessionCard()
        else if (subjectEntries.isEmpty)
          _AllDoneCard()
        else
          _SubjectsList(entries: subjectEntries, user: user),
      ],
    );
  }
}

class _SubjectsList extends StatelessWidget {
  final List<_SessionSubjectEntry> entries;
  final UserModel? user;
  const _SubjectsList({required this.entries, this.user});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(entries.length, (index) {
        final entry = entries[index];
        final session = entry.session;
        final sessionLocked =
            session.price > 0 &&
            !(user?.subscriptions.contains(session.id) ?? false);
        final cappedIndex = index > 5 ? 5 : index;

        return _EntranceMotion(
          delay: Duration(milliseconds: 40 * cappedIndex),
          child: _SubjectBadgeCard(
            subject: entry.subject,
            session: session,
            sessionLocked: sessionLocked,
            isAbandoned: user?.hasAbandonedSubject(entry.subject.id) ?? false,
          ),
        );
      }),
    );
  }
}

// ─── Carte épreuve avec badge ─────────────────────────────────────────────────
class _SubjectBadgeCard extends StatelessWidget {
  final SubjectModel subject;
  final SessionModel session;
  final bool sessionLocked;
  final bool isAbandoned;

  const _SubjectBadgeCard({
    required this.subject,
    required this.session,
    required this.sessionLocked,
    required this.isAbandoned,
  });

  @override
  Widget build(BuildContext context) {
    final status = subject.timeStatus;
    final isUrgent = status == ExamTimeStatus.accessible && !isAbandoned;
    final isSoon = status == ExamTimeStatus.upcoming;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              isUrgent
                  ? const Color(0xFFFB923C).withAlpha(80)
                  : context.palette.divider,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isUrgent ? 10 : 5),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge + time
          Row(
            children: [
              _StatusBadge(status: status, isAbandoned: isAbandoned),
              const Spacer(),
              if (isAbandoned)
                Text(
                  'Épreuve bloquée',
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (isUrgent)
                StreamBuilder<int>(
                  stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
                  builder: (_, __) {
                    final rem = subject.endTime.difference(DateTime.now());
                    if (rem.isNegative) return const SizedBox.shrink();
                    final h = rem.inHours;
                    final m = rem.inMinutes % 60;
                    return Text(
                      h > 0 ? 'Fin dans ${h}h${m}min' : 'Fin dans ${m}min',
                      style: TextStyle(
                        color: Color(0xFFEA580C),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                )
              else if (isSoon)
                Text(
                  _nextTimeLabel(subject.startTime),
                  style: TextStyle(
                    color: context.palette.textSecondary,
                    fontSize: 12,
                  ),
                )
              else
                Text(
                  'Délai dépassé',
                  style: TextStyle(color: AppColors.error, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Nom de la matière
          Text(
            subject.name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: context.palette.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            session.title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Durée: ${subject.durationLabel}  ·  Coefficient: ${subject.coefficient.toInt()}',
            style: TextStyle(
              fontSize: 12,
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: 14),

          // Bouton d'action
          if (isUrgent && !sessionLocked)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    () => context.push(
                      AppRoutes.examPath(
                        sessionId: session.id,
                        subjectId: subject.id,
                      ),
                      extra: {'subject': subject, 'sessionId': session.id},
                    ),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text("Lancer l'épreuve"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  elevation: 0,
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed:
                    sessionLocked && status == ExamTimeStatus.accessible
                        ? () => context.push(
                          AppRoutes.planningSessionPath(session.id),
                        )
                        : null,
                icon: Icon(
                  isAbandoned
                      ? Icons.block_outlined
                      : sessionLocked
                      ? Icons.lock_outline
                      : Icons.access_time,
                  size: 16,
                  color:
                      isAbandoned ? AppColors.error : context.palette.textHint,
                ),
                label: Text(
                  isAbandoned
                      ? 'Épreuve abandonnée'
                      : sessionLocked
                      ? 'Déverrouiller la session'
                      : 'Disponible bientôt',
                  style: TextStyle(
                    color: context.palette.textSecondary,
                    fontSize: 13,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(color: context.palette.divider),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _nextTimeLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final examDay = DateTime(dt.year, dt.month, dt.day);
    final dayDiff = examDay.difference(today).inDays;
    if (dayDiff == 0) {
      return "Aujourd'hui, ${DateFormat('HH:mm').format(dt)}";
    } else if (dayDiff == 1) {
      return "Demain, ${DateFormat('HH:mm').format(dt)}";
    }
    return DateFormat('EEE dd MMM', 'fr').format(dt);
  }
}

// ─── Badge statut ─────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final ExamTimeStatus status;
  final bool isAbandoned;

  const _StatusBadge({required this.status, this.isAbandoned = false});

  @override
  Widget build(BuildContext context) {
    if (isAbandoned) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.error.withAlpha(18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'ABANDONNÉE',
          style: TextStyle(
            color: AppColors.error,
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.4,
          ),
        ),
      );
    }

    switch (status) {
      case ExamTimeStatus.accessible:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFEA580C).withAlpha(30),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'URGENT',
            style: TextStyle(
              color: Color(0xFFEA580C),
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        );
      case ExamTimeStatus.upcoming:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: context.palette.surfaceVariant,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'BIENTÔT',
            style: TextStyle(
              color: context.palette.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        );
      case ExamTimeStatus.lateBlocked:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.error.withAlpha(18),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'FERMÉE',
            style: TextStyle(
              color: AppColors.error,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ─── État vide / squelettes ───────────────────────────────────────────────────
class _NoSessionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.divider),
      ),
      child: Column(
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 40,
            color: context.palette.textHint,
          ),
          SizedBox(height: 10),
          Text(
            'Aucune session active',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.palette.textSecondary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Les prochaines sessions apparaîtront ici',
            style: TextStyle(fontSize: 13, color: context.palette.textHint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _AllDoneCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.statusOpen.withAlpha(12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.statusOpen.withAlpha(50)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 40,
            color: AppColors.statusOpen,
          ),
          SizedBox(height: 10),
          Text(
            'Toutes les épreuves sont terminées !',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Text(
            'Tes résultats seront publiés prochainement',
            style: TextStyle(
              fontSize: 13,
              color: context.palette.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SubjectsSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        2,
        (i) => Container(
          height: 140,
          margin: EdgeInsets.only(bottom: i == 1 ? 0 : 12),
          decoration: BoxDecoration(
            color: context.palette.shimmerBase,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

String _formatProfileFieldList(List<String> fields) {
  if (fields.isEmpty) return '';
  if (fields.length == 1) return fields.first;
  if (fields.length == 2) return '${fields.first} et ${fields.last}';
  return '${fields.sublist(0, fields.length - 1).join(', ')} et ${fields.last}';
}

// ─── Bannière profil incomplet ─────────────────────────────────────────────────
class _ProfileIncompleteBanner extends StatelessWidget {
  final UserModel user;

  const _ProfileIncompleteBanner({required this.user});

  String _message() {
    if (user.missingRequiredFields.isEmpty) {
      return 'Ton dossier élève est déjà complet.';
    }

    return 'Complète ces informations : ${_formatProfileFieldList(user.missingRequiredFields)}.';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const amber = Color(0xFFF59E0B);
    final textColor = isDark ? amber : const Color(0xFF92400E);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: amber.withAlpha(isDark ? 25 : 18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: amber.withAlpha(isDark ? 80 : 120),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: amber, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profil à compléter',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: textColor,
                  ),
                ),
                Text(
                  _message(),
                  style: TextStyle(fontSize: 12, color: textColor),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.push(AppRoutes.editProfile),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              foregroundColor: amber,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Compléter',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Onglet Planning ──────────────────────────────────────────────────────────
class _PlanningTab extends ConsumerWidget {
  const _PlanningTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const PlanningScreen();
  }
}

// ─── Onglet Résultats ─────────────────────────────────────────────────────────
class _ResultsTab extends ConsumerWidget {
  const _ResultsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ResultsScreen();
  }
}

// ─── Onglet Profil ────────────────────────────────────────────────────────────
class _ProfileTab extends ConsumerStatefulWidget {
  final UserModel? user;
  const _ProfileTab({this.user});

  @override
  ConsumerState<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<_ProfileTab>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  bool _isDeletingAccount = false;
  bool _notifBusy = false;

  // Chaque section entre avec un délai décalé
  late List<Animation<double>> _fades;
  late List<Animation<Offset>> _slides;

  static const _count = 6; // avatar, nom, card, actions, infos, historique

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fades = List.generate(_count, (i) {
      final start = i * 0.10;
      final end = (start + 0.40).clamp(0.0, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(start, end, curve: Curves.easeOut),
        ),
      );
    });

    _slides = List.generate(_count, (i) {
      final start = i * 0.10;
      final end = (start + 0.45).clamp(0.0, 1.0);
      return Tween<Offset>(
        begin: const Offset(0, 0.28),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );
    });

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _animated(int index, Widget child) {
    return FadeTransition(
      opacity: _fades[index],
      child: SlideTransition(position: _slides[index], child: child),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final shouldSignOut =
        await showDialog<bool>(
          context: context,
          builder:
              (_) => AlertDialog(
                title: Text('Se déconnecter'),
                content: Text(
                  'Veux-tu vraiment te déconnecter de ton compte ?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text('Annuler'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text('Déconnexion'),
                  ),
                ],
              ),
        ) ??
        false;

    if (!shouldSignOut || !context.mounted) return;

    try {
      await ref.read(authNotifierProvider.notifier).signOut();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
    }
  }

  Future<void> _confirmDeleteAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    var canDelete = false;

    final shouldDelete =
        await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder:
              (dialogContext) => StatefulBuilder(
                builder:
                    (dialogContext, setDialogState) => AlertDialog(
                      title: const Text('Supprimer le compte'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Cette action va supprimer ton accès au compte et anonymiser ton profil. Tes anciens paiements/résultats peuvent rester conservés pour le suivi administratif.',
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Tape SUPPRIMER pour confirmer.',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            autofocus: true,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              hintText: 'SUPPRIMER',
                            ),
                            onChanged: (value) {
                              setDialogState(
                                () => canDelete = value.trim() == 'SUPPRIMER',
                              );
                            },
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Annuler'),
                        ),
                        ElevatedButton(
                          onPressed:
                              canDelete
                                  ? () => Navigator.pop(dialogContext, true)
                                  : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.error,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Supprimer'),
                        ),
                      ],
                    ),
              ),
        ) ??
        false;

    if (!shouldDelete || !context.mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      await ref.read(authNotifierProvider.notifier).deleteMyAccount();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Compte supprimé.')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
    } finally {
      if (mounted) {
        setState(() => _isDeletingAccount = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.user;

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: Text('Mon profil'),
        actions: [
          IconButton(
            onPressed:
                profile == null
                    ? null
                    : () => context.push(AppRoutes.editProfile),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Modifier mon profil',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 0 — Avatar
          _animated(
            0,
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: _UserAvatar(
                  user: widget.user,
                  backgroundColor: AppColors.primary,
                  textColor: Colors.white,
                  fontSize: 36,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 1 — Nom + label
          _animated(
            1,
            Column(
              children: [
                Text(
                  _userDisplayName(widget.user),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  _userAcademicLabel(widget.user),
                  style: TextStyle(color: context.palette.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (profile != null) ...[
            // 2 — Carte de complétion
            _animated(2, _profileSummaryCard(context, profile)),
            const SizedBox(height: 20),

            // 3 — Section Compte & sécurité
            _animated(
              3,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Compte et sécurité'),
                  if (profile.isStudent)
                    _profileActionTile(
                      icon: Icons.add_circle_outline_rounded,
                      title: 'Demander une session à la demande',
                      subtitle:
                          'Choisis tes dates, 1500 FCFA, composée par l\'administration.',
                      onTap: () => handleRequestOnDemandTap(context, profile),
                    ),
                  _profileActionTile(
                    icon: Icons.edit_outlined,
                    title: 'Modifier mes informations',
                    subtitle: 'Nom, téléphone, établissement, classe et série.',
                    onTap: () => context.push(AppRoutes.editProfile),
                  ),
                  _profileActionTile(
                    icon: Icons.lock_reset_outlined,
                    title: 'Modifier mon mot de passe',
                    subtitle: 'Mets à jour l\'accès à ton compte.',
                    onTap: () => context.push(AppRoutes.changePassword),
                  ),
                  _biometricLockTile(),
                  _notificationsTile(),
                  _profileActionTile(
                    icon: Icons.gavel_outlined,
                    title: 'Mentions légales',
                    subtitle:
                        'Consulte les règles d\'usage et de confidentialité.',
                    onTap: () => context.push(AppRoutes.legalInformation),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 4 — Informations élève
            _animated(
              4,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Informations élève'),
                  _infoTile(
                    Icons.verified_user_outlined,
                    'Statut du profil',
                    profile.isProfileComplete ? 'Complet' : 'À compléter',
                    helper:
                        profile.isProfileComplete
                            ? 'Ton dossier élève est prêt.'
                            : 'Champs manquants : ${_formatProfileFieldList(profile.missingRequiredFields)}.',
                  ),
                  _infoTile(
                    Icons.school_outlined,
                    'Établissement',
                    profile.school,
                  ),
                  _infoTile(Icons.email_outlined, 'Email', profile.email),
                  _infoTile(Icons.phone_outlined, 'Téléphone', profile.phone),
                  _infoTile(Icons.class_outlined, 'Classe', profile.classLabel),
                  if (profile.studentClass == StudentClass.terminale)
                    _infoTile(
                      Icons.category_outlined,
                      'Série',
                      profile.series.trim().isEmpty
                          ? 'Non renseignée'
                          : profile.series.trim(),
                    ),
                  _infoTile(
                    Icons.calendar_today_outlined,
                    'Compte créé le',
                    DateFormat('dd/MM/yyyy').format(profile.createdAt),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 5 — Historique
            _animated(
              5,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('Historique'),
                  _HistoriqueSection(userId: profile.uid),
                ],
              ),
            ),
          ] else ...[
            _animated(
              2,
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.palette.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.palette.divider),
                ),
                child: Text(
                  'Impossible de charger ton profil pour le moment.',
                  style: TextStyle(color: context.palette.textSecondary),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),

          _animated(
            5,
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _confirmSignOut(context, ref),
                    icon: const Icon(Icons.logout),
                    label: const Text('Se déconnecter'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed:
                        _isDeletingAccount
                            ? null
                            : () => _confirmDeleteAccount(context, ref),
                    icon:
                        _isDeletingAccount
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.delete_forever_outlined),
                    label: Text(
                      _isDeletingAccount
                          ? 'Suppression en cours...'
                          : 'Supprimer mon compte',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              '${AppConstants.appName} ${AppConstants.appVersion}',
              style: TextStyle(
                fontSize: 12,
                color: context.palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: context.palette.textPrimary,
        ),
      ),
    );
  }

  Widget _profileSummaryCard(BuildContext context, UserModel user) {
    final ratio = user.profileCompletionRatio.clamp(0.0, 1.0);
    final percentage = (ratio * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.palette.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(8),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color:
                      user.isProfileComplete
                          ? AppColors.success.withAlpha(14)
                          : AppColors.warning.withAlpha(14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  user.isProfileComplete
                      ? Icons.verified_outlined
                      : Icons.assignment_late_outlined,
                  color:
                      user.isProfileComplete
                          ? AppColors.success
                          : AppColors.warning,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.isProfileComplete
                          ? 'Profil complet'
                          : 'Profil à finaliser',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.palette.textPrimary,
                      ),
                    ),
                    Text(
                      user.isProfileComplete
                          ? 'Ton dossier élève est prêt.'
                          : 'Informations manquantes : ${_formatProfileFieldList(user.missingRequiredFields)}.',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.palette.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 9,
              backgroundColor: context.palette.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                user.isProfileComplete ? AppColors.success : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '$percentage% complété',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => context.push(AppRoutes.editProfile),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(
                  user.isProfileComplete ? 'Mettre à jour' : 'Compléter',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    const gold = Color(0xFFF5B731);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? gold : AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.divider),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color:
                isDark ? gold.withAlpha(28) : AppColors.primary.withAlpha(12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: context.palette.textSecondary,
              height: 1.35,
            ),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: context.palette.textSecondary,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _biometricLockTile() {
    final lock = ref.watch(biometricLockProvider);
    const gold = Color(0xFFF5B731);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? gold : AppColors.primary;
    final subtitle =
        lock.supported
            ? 'Demande Face ID ou empreinte quand tu reviens dans l\'app.'
            : 'Configure Face ID ou empreinte sur ton téléphone pour l\'activer.';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.divider),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        value: lock.enabled,
        onChanged:
            lock.checking || lock.authenticating
                ? null
                : (value) async {
                  await ref
                      .read(biometricLockProvider.notifier)
                      .setEnabled(value);
                  final error = ref.read(biometricLockProvider).errorMessage;
                  if (!mounted || error == null) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(error)));
                },
        secondary: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color:
                isDark ? gold.withAlpha(28) : AppColors.primary.withAlpha(12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.fingerprint_rounded, color: iconColor, size: 20),
        ),
        title: const Text(
          'Déverrouillage biométrique',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: context.palette.textSecondary,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }

  Widget _notificationsTile() {
    final asyncSettings = ref.watch(notificationSettingsProvider);
    final settings = asyncSettings.value;
    const gold = Color(0xFFF5B731);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? gold : AppColors.primary;

    final enabled = settings?.enabled ?? false;
    final osBlocked = settings?.osBlocked ?? false;
    final subtitle =
        osBlocked && !enabled
            ? 'Bloquées dans les réglages du téléphone. Touche pour les réactiver.'
            : enabled
            ? 'Rappels d\'épreuves, paiements, résultats et annonces.'
            : 'Active pour recevoir rappels, résultats et annonces.';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.divider),
      ),
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        value: enabled,
        onChanged:
            (_notifBusy || asyncSettings.isLoading)
                ? null
                : (value) => _toggleNotifications(value),
        secondary: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color:
                isDark ? gold.withAlpha(28) : AppColors.primary.withAlpha(12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Icons.notifications_active_outlined,
            color: iconColor,
            size: 20,
          ),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: context.palette.textSecondary,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() => _notifBusy = true);
    final notifier = ref.read(notificationSettingsProvider.notifier);
    try {
      if (value) {
        final ok = await notifier.enable();
        if (!ok && mounted) {
          await _showOpenNotifSettingsDialog();
        }
      } else {
        await notifier.disable();
      }
    } finally {
      if (mounted) setState(() => _notifBusy = false);
    }
  }

  Future<void> _showOpenNotifSettingsDialog() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Notifications bloquées'),
        content: const Text(
          'Les notifications sont désactivées dans les réglages de ton '
          'téléphone. Ouvre les réglages pour les autoriser.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Plus tard'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ouvrir les réglages'),
          ),
        ],
      ),
    );
    if (go == true) {
      await openAppSettings();
    }
  }

  Widget _infoTile(
    IconData icon,
    String label,
    String value, {
    String? helper,
  }) {
    const gold = Color(0xFFF5B731);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.divider),
      ),
      child: Row(
        children: [
          Icon(icon, color: isDark ? gold : AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.palette.textSecondary,
                  ),
                ),
                Text(
                  value.trim().isEmpty ? 'Non renseigné' : value,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
                if (helper != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    helper,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Historique des sessions (profil) ─────────────────────────────────────────
class _HistoriqueSection extends ConsumerWidget {
  final String userId;
  const _HistoriqueSection({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historicAsync = ref.watch(historicSessionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Icon(Icons.history, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Historique des sessions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.palette.textPrimary,
                ),
              ),
            ],
          ),
        ),
        historicAsync.when(
          loading:
              () => Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          error:
              (_, __) => Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.palette.divider),
                ),
                child: Text(
                  'Impossible de charger l\'historique.',
                  style: TextStyle(
                    color: context.palette.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
          data: (sessions) {
            if (sessions.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.palette.divider),
                ),
                child: Text(
                  'Aucune session passée pour le moment.',
                  style: TextStyle(
                    color: context.palette.textSecondary,
                    fontSize: 13,
                  ),
                ),
              );
            }
            return Column(
              children:
                  sessions
                      .map(
                        (session) =>
                            _HistoriqueCard(session: session, userId: userId),
                      )
                      .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _HistoriqueCard extends ConsumerWidget {
  final SessionModel session;
  final String userId;
  const _HistoriqueCard({required this.session, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(
      studentResultProvider((sessionId: session.id, userId: userId)),
    );

    final result = resultAsync.asData?.value;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.school_outlined,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: context.palette.textPrimary,
                  ),
                ),
                Text(
                  session.audienceLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (result != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${result.moyenneGenerale.toStringAsFixed(2)}/20',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: result.isAdmis ? AppColors.success : AppColors.error,
                  ),
                ),
                Text(
                  result.mention,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.palette.textSecondary,
                  ),
                ),
              ],
            )
          else
            Text(
              'Pas de résultat',
              style: TextStyle(fontSize: 11, color: context.palette.textHint),
            ),
        ],
      ),
    );
  }
}

// ─── Bannière soumissions en attente ──────────────────────────────────────────
class _PendingUploadsBanner extends ConsumerWidget {
  const _PendingUploadsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(pendingSubmissionsCountProvider);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1,
            child: child,
          ),
        );
      },
      child:
          count == 0
              ? const SizedBox.shrink(key: ValueKey('pending-empty'))
              : Container(
                key: ValueKey('pending-$count'),
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEA580C).withAlpha(25),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFEA580C).withAlpha(80),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cloud_upload_outlined,
                      color: Color(0xFFEA580C),
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$count soumission${count > 1 ? 's' : ''} en attente d\'envoi',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.palette.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed:
                          () =>
                              ref
                                  .read(offlineQueueProvider.notifier)
                                  .processQueue(),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        foregroundColor: const Color(0xFFEA580C),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Réessayer',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
String _userDisplayName(UserModel? user) {
  final value = user?.displayName.trim() ?? '';
  return value.isNotEmpty ? value : 'Élève';
}

String _userInitial(UserModel? user) {
  final label = _userDisplayName(user);
  return label.substring(0, 1).toUpperCase();
}

class _UserAvatar extends StatelessWidget {
  final UserModel? user;
  final Color backgroundColor;
  final Color textColor;
  final double fontSize;

  const _UserAvatar({
    required this.user,
    required this.backgroundColor,
    required this.textColor,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final avatarUrl = user?.avatarUrl.trim() ?? '';

    return ClipOval(
      child: ColoredBox(
        color: backgroundColor,
        child: SizedBox.expand(
          child:
              avatarUrl.isNotEmpty
                  ? Image.network(
                    avatarUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallback(),
                  )
                  : _fallback(),
        ),
      ),
    );
  }

  Widget _fallback() {
    return Center(
      child: Text(
        _userInitial(user),
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: fontSize,
        ),
      ),
    );
  }
}

String _userAcademicLabel(UserModel? user) {
  if (user == null) return 'Profil en cours de chargement';
  if (user.studentClass == StudentClass.troisieme ||
      user.series.trim().isEmpty) {
    return user.classLabel;
  }
  return '${user.classLabel} — Série ${user.series}';
}

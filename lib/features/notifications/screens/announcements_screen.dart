import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../models/announcement_model.dart';
import '../../../providers/announcements_provider.dart';

class AnnouncementsScreen extends ConsumerStatefulWidget {
  const AnnouncementsScreen({super.key});

  @override
  ConsumerState<AnnouncementsScreen> createState() =>
      _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends ConsumerState<AnnouncementsScreen> {
  late final DateTime _openedReadMark;

  @override
  void initState() {
    super.initState();
    // Mémorise l'horodatage « lu » courant pour différencier les non-lus à
    // l'affichage, puis marque tout comme lu.
    _openedReadMark = ref.read(announcementsReadProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(announcementsReadProvider.notifier).markAllRead();
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncAnnouncements = ref.watch(studentAnnouncementsProvider);

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(title: const Text('Annonces')),
      body: asyncAnnouncements.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _ErrorState(
          onRetry: () => ref.invalidate(studentAnnouncementsProvider),
        ),
        data: (announcements) {
          if (announcements.isEmpty) return const _EmptyState();
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async {
              ref.invalidate(studentAnnouncementsProvider);
              await Future.delayed(const Duration(milliseconds: 400));
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: announcements.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final a = announcements[i];
                final isUnread =
                    a.createdAt != null && a.createdAt!.isAfter(_openedReadMark);
                return _AnnouncementCard(announcement: a, isUnread: isUnread);
              },
            ),
          );
        },
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final AnnouncementModel announcement;
  final bool isUnread;

  const _AnnouncementCard({required this.announcement, required this.isUnread});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFF5B731);
    final accent = isDark ? gold : AppColors.primary;
    final created = announcement.createdAt;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUnread ? accent.withAlpha(90) : context.palette.divider,
          width: isUnread ? 1.4 : 1,
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
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withAlpha(isDark ? 28 : 14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.campaign_outlined, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  announcement.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.palette.textPrimary,
                  ),
                ),
              ),
              if (isUnread)
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            announcement.body,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 12,
                color: context.palette.textHint,
              ),
              const SizedBox(width: 4),
              Text(
                created != null
                    ? DateFormat('EEEE d MMMM, HH:mm', 'fr').format(created)
                    : '',
                style: TextStyle(fontSize: 11, color: context.palette.textHint),
              ),
              if (announcement.sentByName.isNotEmpty) ...[
                const Spacer(),
                Text(
                  announcement.sentByName,
                  style:
                      TextStyle(fontSize: 11, color: context.palette.textHint),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.campaign_outlined,
              size: 56,
              color: context.palette.textHint,
            ),
            const SizedBox(height: 14),
            Text(
              'Aucune annonce pour le moment',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Les annonces de l\'administration apparaîtront ici.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 48, color: context.palette.textHint),
            const SizedBox(height: 14),
            Text(
              'Impossible de charger les annonces',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.palette.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/sessions_provider.dart';

class SessionRankingScreen extends ConsumerWidget {
  final String sessionId;

  const SessionRankingScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUser = ref.watch(currentUserProvider);
    final rankingAsync = ref.watch(fullRankingProvider(sessionId));

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: const Text('Classement'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: rankingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(firestoreDataErrorMessage(error)),
        ),
        data: (entries) {
          if (entries.length < 2) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.emoji_events_outlined,
                      size: 48,
                      color: context.palette.textHint,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Le classement sera disponible dès qu\'un second '
                      'participant rejoindra cette session.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final isCurrentUser = entry.userId == currentUser?.uid;
              return _RankingTile(
                rank: entry.rank,
                displayName: entry.displayName,
                moyenneGenerale: entry.moyenneGenerale,
                highlighted: isCurrentUser,
              );
            },
          );
        },
      ),
    );
  }
}

class _RankingTile extends StatelessWidget {
  final int rank;
  final String displayName;
  final double moyenneGenerale;
  final bool highlighted;

  const _RankingTile({
    required this.rank,
    required this.displayName,
    required this.moyenneGenerale,
    required this.highlighted,
  });

  Color? get _medalColor {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700);
      case 2:
        return const Color(0xFFC0C0C0);
      case 3:
        return const Color(0xFFCD7F32);
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final medalColor = _medalColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.primary.withAlpha(15)
            : context.palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted
              ? AppColors.primary.withAlpha(60)
              : context.palette.divider,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: medalColor != null
                ? CircleAvatar(
                    backgroundColor: medalColor,
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  )
                : CircleAvatar(
                    backgroundColor: context.palette.surfaceVariant,
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              displayName,
              style: TextStyle(
                fontSize: 14,
                fontWeight: highlighted ? FontWeight.bold : FontWeight.w500,
                color: context.palette.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${moyenneGenerale.toStringAsFixed(2)}/20',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: highlighted ? AppColors.primary : context.palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants/app_constants.dart';
import '../models/announcement_model.dart';
import 'auth_provider.dart';

const _kSettingsBox = 'settings';
const _kAnnouncementsLastReadKey = 'announcements_last_read_at';

/// Flux des annonces destinées à l'élève courant (filtrées par classe/série).
final studentAnnouncementsProvider =
    StreamProvider<List<AnnouncementModel>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return Stream.value(const <AnnouncementModel>[]);
  }

  return FirebaseFirestore.instance
      .collection(AppConstants.announcementsCollection)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map(AnnouncementModel.fromFirestore)
            .where((a) => a.matchesStudent(user))
            .toList(),
      );
});

/// Contrôleur de l'état « lu » des annonces (horodatage local, Hive).
final announcementsReadProvider =
    NotifierProvider<AnnouncementsReadController, DateTime>(
  AnnouncementsReadController.new,
);

class AnnouncementsReadController extends Notifier<DateTime> {
  @override
  DateTime build() {
    final box = Hive.box<dynamic>(_kSettingsBox);
    final millis = box.get(_kAnnouncementsLastReadKey) as int?;
    return millis != null
        ? DateTime.fromMillisecondsSinceEpoch(millis)
        : DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// Marque toutes les annonces comme lues (au moment d'ouvrir la boîte).
  void markAllRead() {
    final now = DateTime.now();
    Hive.box<dynamic>(_kSettingsBox)
        .put(_kAnnouncementsLastReadKey, now.millisecondsSinceEpoch);
    state = now;
  }
}

/// Nombre d'annonces non lues (pour le badge sur la cloche).
final unreadAnnouncementsCountProvider = Provider<int>((ref) {
  final lastRead = ref.watch(announcementsReadProvider);
  final announcements = ref.watch(studentAnnouncementsProvider).asData?.value;
  if (announcements == null) return 0;
  return announcements
      .where((a) => a.createdAt != null && a.createdAt!.isAfter(lastRead))
      .length;
});

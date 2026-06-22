import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/offline/queued_submission.dart';
import '../core/utils/app_logger.dart';

const _kBoxName = 'submission_queue';
const _kMaxRetries = 3;

class OfflineQueueNotifier extends StateNotifier<List<QueuedSubmission>> {
  late final Box<String> _box;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _processing = false;

  OfflineQueueNotifier() : super(const []) {
    _init();
  }

  Future<void> _init() async {
    _box = Hive.box<String>(_kBoxName);
    _loadState();

    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline && state.isNotEmpty) {
        processQueue();
      }
    });
  }

  void _loadState() {
    final items = _box.values
        .map((v) {
          try {
            return QueuedSubmission.fromJsonString(v);
          } catch (e) {
            AppLogger.warn('OfflineQueue', 'Entrée corrompue ignorée: $e');
            return null;
          }
        })
        .whereType<QueuedSubmission>()
        .toList()
      ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));

    state = items;
  }

  /// Ajoute une soumission en attente d'upload dans la queue Hive.
  /// Les fichiers sont copiés vers le répertoire documents (persistant entre
  /// relances et réinstallations de l'app, contrairement au cache temporaire).
  Future<String> enqueue({
    required String sessionId,
    required String subjectId,
    required String subjectName,
    required List<String> pagePaths,
  }) async {
    final id = const Uuid().v4();
    final persistentPaths = await _copyToPersistentStorage(id, pagePaths);
    final item = QueuedSubmission(
      id: id,
      sessionId: sessionId,
      subjectId: subjectId,
      subjectName: subjectName,
      pagePaths: persistentPaths,
      queuedAt: DateTime.now(),
    );
    await _box.put(id, item.toJsonString());
    state = [...state, item];
    AppLogger.info('OfflineQueue', 'Soumission mise en queue: $subjectName ($id)');
    return id;
  }

  /// Copie les pages vers `documents/offline_queue/{id}/` pour garantir leur
  /// persistance même si le cache système est vidé.
  Future<List<String>> _copyToPersistentStorage(
    String queueId,
    List<String> pagePaths,
  ) async {
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final destDir = Directory('${docDir.path}/offline_queue/$queueId');
      await destDir.create(recursive: true);

      final persistent = <String>[];
      for (var i = 0; i < pagePaths.length; i++) {
        final src = File(pagePaths[i]);
        final ext = pagePaths[i].split('.').last.toLowerCase();
        final dest = File(
          '${destDir.path}/page_${(i + 1).toString().padLeft(3, '0')}.$ext',
        );
        if (await src.exists()) {
          await src.copy(dest.path);
          persistent.add(dest.path);
        } else {
          persistent.add(pagePaths[i]);
        }
      }
      return persistent;
    } catch (e) {
      AppLogger.warn('OfflineQueue', 'Copie persistante échouée, chemins originaux conservés: $e');
      return pagePaths;
    }
  }

  /// Tente d'uploader toutes les soumissions en attente.
  /// Appelé automatiquement à la reconnexion et depuis l'UI.
  Future<void> processQueue() async {
    if (_processing || state.isEmpty) return;
    _processing = true;

    AppLogger.info('OfflineQueue', 'Traitement de ${state.length} soumission(s) en attente...');

    // Copie pour itérer sans modifier state en cours de route
    final items = List<QueuedSubmission>.from(state);

    for (final item in items) {
      await _processItem(item);
    }

    _processing = false;
  }

  Future<void> _processItem(QueuedSubmission item) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    // Vérifier que les fichiers existent encore
    final missingFiles = item.pagePaths
        .where((path) => !File(path).existsSync())
        .toList();

    if (missingFiles.isNotEmpty) {
      AppLogger.warn(
        'OfflineQueue',
        '${missingFiles.length} fichier(s) manquant(s) pour ${item.subjectName} — suppression de la queue.',
      );
      await _removeFromQueue(item.id);
      return;
    }

    try {
      // 1. Upload les pages vers Firebase Storage
      final folderRef = await _uploadPages(
        pagePaths: item.pagePaths,
        userId: userId,
        subjectId: item.subjectId,
      );

      // 2. Créer le document Firestore
      await FirebaseFirestore.instance
          .collection(AppConstants.submissionsCollection)
          .add({
        'userId': userId,
        'sessionId': item.sessionId,
        'subjectId': item.subjectId,
        'subjectName': item.subjectName,
        'submittedAt': FieldValue.serverTimestamp(),
        'fileRef': folderRef,
        'ocrText': '',
        'status': 'submitted',
        'aiDetails': {},
        'aiStrengths': [],
        'aiImprovements': [],
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });

      AppLogger.info('OfflineQueue', 'Soumission envoyée depuis la queue: ${item.subjectName}');
      await _removeFromQueue(item.id);
    } catch (e) {
      final newRetryCount = item.retryCount + 1;
      AppLogger.warn(
        'OfflineQueue',
        'Échec upload ${item.subjectName} (tentative $newRetryCount/$_kMaxRetries): $e',
      );

      if (newRetryCount >= _kMaxRetries) {
        AppLogger.error('OfflineQueue', 'Abandonnée après $_kMaxRetries tentatives: ${item.subjectName}');
        await _removeFromQueue(item.id);
      } else {
        final updated = item.copyWith(retryCount: newRetryCount);
        await _box.put(item.id, updated.toJsonString());
        state = state.map((s) => s.id == item.id ? updated : s).toList();
      }
    }
  }

  Future<String> _uploadPages({
    required List<String> pagePaths,
    required String userId,
    required String subjectId,
  }) async {
    final folderRef =
        '${AppConstants.submissionsStoragePath}/$userId/$subjectId/${DateTime.now().millisecondsSinceEpoch}';

    for (var index = 0; index < pagePaths.length; index++) {
      final path = pagePaths[index];
      final ext = _fileExtension(path);
      final storageRef = FirebaseStorage.instance.ref(
        '$folderRef/page_${(index + 1).toString().padLeft(3, '0')}.$ext',
      );
      await storageRef.putFile(
        File(path),
        SettableMetadata(contentType: _contentType(ext)),
      );
    }

    return folderRef;
  }

  Future<void> _removeFromQueue(String id) async {
    await _box.delete(id);
    state = state.where((s) => s.id != id).toList();
    // Nettoie les fichiers copiés dans le stockage persistant.
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${docDir.path}/offline_queue/$id');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  String _fileExtension(String path) {
    final parts = path.split('.');
    return parts.length >= 2 ? parts.last.toLowerCase() : 'jpg';
  }

  String _contentType(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'heic':
        return 'image/heic';
      case 'webp':
        return 'image/webp';
      default:
        return 'image/jpeg';
    }
  }

  int get pendingCount => state.length;

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }
}

final offlineQueueProvider =
    StateNotifierProvider<OfflineQueueNotifier, List<QueuedSubmission>>(
  (_) => OfflineQueueNotifier(),
);

/// Nombre de soumissions en attente d'upload.
final pendingSubmissionsCountProvider = Provider<int>((ref) {
  return ref.watch(offlineQueueProvider).length;
});

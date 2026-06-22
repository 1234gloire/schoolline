import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../core/router/app_router.dart';
import '../../../models/payment_model.dart';
import '../../../models/submission_model.dart';
import '../../../models/subject_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/offline_queue_provider.dart';
import '../../../providers/payments_provider.dart';
import '../../../providers/sessions_provider.dart';

class SubmissionScreen extends ConsumerStatefulWidget {
  final String sessionId;
  final String subjectId;
  final Map<String, dynamic>? extra;

  const SubmissionScreen({
    super.key,
    required this.sessionId,
    required this.subjectId,
    this.extra,
  });

  @override
  ConsumerState<SubmissionScreen> createState() => _SubmissionScreenState();
}

class _SubmissionScreenState extends ConsumerState<SubmissionScreen> {
  SubjectModel? _subject;
  final List<XFile> _pages = [];
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadStep = '';

  // Brouillon local : photos copiées dans le répertoire documents pour survivre aux crashs.
  Directory? _draftDir;

  @override
  void initState() {
    super.initState();
    _subject = widget.extra?['subject'] as SubjectModel?;
    _initDraft();
  }

  Future<void> _initDraft() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${docDir.path}/submission_drafts/${widget.sessionId}_${widget.subjectId}',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    _draftDir = dir;

    // Restaure les photos sauvegardées lors d'un crash précédent.
    final saved = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final ext = f.path.split('.').last.toLowerCase();
          return ['jpg', 'jpeg', 'png', 'heic', 'webp'].contains(ext);
        })
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    if (saved.isNotEmpty && mounted) {
      setState(() => _pages.addAll(saved.map((f) => XFile(f.path))));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${saved.length} page(s) de brouillon restaurée(s). Vérifie l\'ordre avant de soumettre.',
            ),
            backgroundColor: AppColors.warning,
            duration: const Duration(seconds: 5),
          ),
        );
      });
    }
  }

  // Copie un fichier dans le répertoire de brouillon (best-effort, sans bloquer l'UI).
  Future<void> _persistPageToDraft(XFile file) async {
    final dir = _draftDir;
    if (dir == null) return;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = _fileExtension(file.path);
    try {
      await File(file.path).copy('${dir.path}/${timestamp}_$ext.$ext');
    } catch (_) {}
  }

  Future<void> _clearDraft() async {
    final dir = _draftDir;
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> _pickFromCamera() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 2048,
    );
    if (image != null) {
      setState(() => _pages.add(image));
      _persistPageToDraft(image);
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 2048,
    );
    if (images.isNotEmpty) {
      setState(() => _pages.addAll(images));
      for (final img in images) {
        _persistPageToDraft(img);
      }
    }
  }

  void _removePage(int index) {
    setState(() => _pages.removeAt(index));
  }

  void _reorderPage(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final page = _pages.removeAt(oldIndex);
      _pages.insert(newIndex, page);
    });
  }

  Future<void> _submit() async {
    final subject = _subject;
    if (subject == null) return;

    if (!subject.isSubmissionOpen) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La fenêtre de soumission pour cette épreuve est fermée.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_pages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ajoute au moins une page de ta copie'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final totalSize = await _computeTotalSize();
    if (totalSize > AppConstants.maxSubmissionSizeBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'La copie dépasse 5 MB (${(totalSize / 1024 / 1024).toStringAsFixed(1)} MB). Réduis le nombre ou la taille des images.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    final confirmed = await _showConfirmDialog();
    if (!confirmed) return;

    final authState = ref.read(authNotifierProvider);
    final userId = authState.value?.uid;
    if (userId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session utilisateur invalide. Reconnecte-toi.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final existingSubmission = await ref.read(
      submissionForSubjectProvider((
        userId: userId,
        subjectId: subject.id,
      )).future,
    );
    if (existingSubmission != null) {
      if (!mounted) return;
      _openExistingSubmission(existingSubmission);
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _uploadStep = 'Préparation de la copie...';
    });

    String? uploadedFolderRef;
    try {
      uploadedFolderRef = await _uploadPages(userId: userId, subject: subject);

      await ref
          .read(submissionNotifierProvider.notifier)
          .submitCopy(
            userId: userId,
            sessionId: subject.sessionId,
            subjectId: subject.id,
            subjectName: subject.name,
            fileRef: uploadedFolderRef,
          );

      ref.invalidate(
        submissionForSubjectProvider((userId: userId, subjectId: subject.id)),
      );
      ref.invalidate(mySubmissionsProvider(userId));

      await _clearDraft();
      if (mounted) {
        context.pushReplacement(AppRoutes.results);
      }
    } catch (e) {
      if (e is DuplicateSubmissionException) {
        if (mounted) {
          setState(() => _isUploading = false);
          _openExistingSubmission(e.existingSubmission);
        }
        return;
      }

      // Upload échoué → nettoyer le dossier partiel et mettre en queue offline
      if (uploadedFolderRef != null) {
        await _cleanupUploadedFolder(uploadedFolderRef);
      }

      final subject = _subject;
      if (subject != null) {
        await ref.read(offlineQueueProvider.notifier).enqueue(
          sessionId: subject.sessionId,
          subjectId: subject.id,
          subjectName: subject.name,
          pagePaths: _pages.map((p) => p.path).toList(),
        );

        if (mounted) {
          setState(() => _isUploading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pas de connexion — ta copie est sauvegardée et sera envoyée automatiquement dès que tu seras connecté.',
              ),
              backgroundColor: AppColors.warning,
              duration: Duration(seconds: 6),
            ),
          );
          context.go(AppRoutes.dashboard);
        }
        return;
      }

      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(submissionDataErrorMessage(e)),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<int> _computeTotalSize() async {
    var total = 0;
    for (final page in _pages) {
      total += await File(page.path).length();
    }
    return total;
  }

  Future<String> _uploadPages({
    required String userId,
    required SubjectModel subject,
  }) async {
    final folderRef =
        'submissions/$userId/${subject.id}/${DateTime.now().millisecondsSinceEpoch}';

    for (var index = 0; index < _pages.length; index++) {
      final page = _pages[index];
      final extension = _fileExtension(page.path);
      final storageRef = FirebaseStorage.instance.ref(
        '$folderRef/page_${(index + 1).toString().padLeft(3, '0')}.$extension',
      );

      if (mounted) {
        setState(() {
          _uploadStep = 'Upload page ${index + 1}/${_pages.length}...';
        });
      }

      final task = storageRef.putFile(
        File(page.path),
        SettableMetadata(contentType: _contentType(extension)),
      );

      await for (final snapshot in task.snapshotEvents) {
        if (!mounted) continue;
        final pageProgress =
            snapshot.totalBytes > 0
                ? snapshot.bytesTransferred / snapshot.totalBytes
                : 0.0;
        setState(() {
          _uploadProgress = ((index + pageProgress) / _pages.length).clamp(
            0.0,
            1.0,
          );
        });
      }

      await task;
    }

    if (mounted) {
      setState(() {
        _uploadProgress = 1.0;
        _uploadStep = 'Copie envoyée avec succès !';
      });
    }

    return folderRef;
  }

  Future<void> _cleanupUploadedFolder(String folderRef) async {
    try {
      final rootRef = FirebaseStorage.instance.ref(folderRef);
      final listResult = await rootRef.listAll();
      for (final item in listResult.items) {
        await item.delete();
      }
      for (final prefix in listResult.prefixes) {
        await _cleanupUploadedFolder(prefix.fullPath);
      }
    } catch (_) {
      // Le nettoyage est un best-effort pour éviter les fichiers orphelins.
    }
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

  String _fileExtension(String path) {
    final parts = path.split('.');
    if (parts.length < 2) return 'jpg';
    return parts.last.toLowerCase();
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

  Future<bool> _showConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text('Confirmer la soumission'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Matière : ${_subject?.name}'),
                Text('Pages : ${_pages.length}'),
                const SizedBox(height: 12),
                Text(
                  '⚠️ Une fois soumise, ta copie ne peut plus être modifiée.',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Annuler'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Confirmer'),
              ),
            ],
          ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.value;
    final userId = user?.uid;

    if (authState.isLoading && userId == null) {
      return const _SubmissionShell(
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (userId == null) {
      return const _SubmissionShell(
        child: _SubmissionStateView(
          icon: Icons.lock_outline,
          title: 'Connexion requise',
          message: 'Reconnecte-toi pour soumettre ta copie.',
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
          setState(() => _subject = loadedSubject);
        });
      });

      return subjectAsync.when(
        data: (loadedSubject) {
          if (loadedSubject == null) {
            return const _SubmissionShell(
              child: _SubmissionStateView(
                icon: Icons.find_in_page_outlined,
                title: 'Épreuve introuvable',
                message:
                    'Impossible de préparer la soumission sans matière valide.',
              ),
            );
          }
          return const _SubmissionShell(
            child: Center(child: CircularProgressIndicator()),
          );
        },
        loading:
            () => const _SubmissionShell(
              child: Center(child: CircularProgressIndicator()),
            ),
        error:
            (error, _) => _SubmissionShell(
              child: _SubmissionStateView(
                icon: Icons.sync_problem_outlined,
                title: 'Soumission indisponible',
                message: firestoreDataErrorMessage(
                  error,
                  fallback:
                      'Impossible de charger les informations de cette épreuve.',
                ),
              ),
            ),
      );
    }

    if (_isUploading) {
      return Scaffold(
        backgroundColor: context.palette.background,
        appBar: AppBar(title: Text('Soumettre ma copie')),
        body: _buildUploadingView(),
      );
    }

    final sessionAsync = ref.watch(sessionByIdProvider(widget.sessionId));
    return sessionAsync.when(
      data: (session) {
        if (session == null) {
          return const _SubmissionShell(
            child: _SubmissionStateView(
              icon: Icons.event_busy_outlined,
              title: 'Session introuvable',
              message:
                  'Impossible de préparer cette soumission sans session valide.',
            ),
          );
        }

        if (user == null ||
            !sessionMatchesStudent(session, user) ||
            !subjectMatchesStudent(subject, user)) {
          return Scaffold(
            backgroundColor: context.palette.background,
            appBar: AppBar(title: Text('Soumettre ma copie')),
            body: _SubmissionStateView(
              icon: Icons.lock_outline,
              title: 'Accès refusé',
              message:
                  'Cette épreuve n’est pas accessible pour ton profil actuel.',
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
              final paymentPending = payment?.isPending ?? false;
              return Scaffold(
                backgroundColor: context.palette.background,
                appBar: AppBar(title: Text('Soumettre ma copie')),
                body: _SubmissionStateView(
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
                          ? 'Ton paiement est en cours de validation. La soumission sera disponible dès approbation.'
                          : 'Tu dois d’abord débloquer cette session avant de soumettre une copie.',
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
              return Scaffold(
                backgroundColor: context.palette.background,
                appBar: AppBar(title: Text('Soumettre ma copie')),
                body: _SubmissionStateView(
                  icon: Icons.block_outlined,
                  title: 'Épreuve abandonnée',
                  message:
                      'Cette épreuve a été quittée sans soumission. La copie ne peut plus être déposée depuis ton compte.',
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
                  return _buildExistingSubmissionScaffold(existingSubmission);
                }

                if (!subject.isSubmissionOpen) {
                  return Scaffold(
                    backgroundColor: context.palette.background,
                    appBar: AppBar(title: Text('Soumettre ma copie')),
                    body: _SubmissionStateView(
                      icon: Icons.schedule_outlined,
                      title: 'Soumission indisponible',
                      message:
                          'La fenêtre de soumission pour cette épreuve est fermée.',
                      actionLabel: 'Retour au planning',
                      onAction:
                          () => context.go(
                            AppRoutes.planningSessionPath(session.id),
                          ),
                    ),
                  );
                }

                return Scaffold(
                  backgroundColor: context.palette.background,
                  appBar: AppBar(
                    title: Text('Soumettre ma copie'),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios),
                      onPressed:
                          () => context.go(
                            AppRoutes.planningSessionPath(session.id),
                          ),
                    ),
                  ),
                  body: _buildMainView(),
                );
              },
              loading:
                  () => Scaffold(
                    backgroundColor: context.palette.background,
                    appBar: AppBar(title: Text('Soumettre ma copie')),
                    body: Center(child: CircularProgressIndicator()),
                  ),
              error:
                  (error, _) => Scaffold(
                    backgroundColor: context.palette.background,
                    appBar: AppBar(title: Text('Soumettre ma copie')),
                    body: _SubmissionStateView(
                      icon: Icons.sync_problem_outlined,
                      title: 'Vérification impossible',
                      message: submissionDataErrorMessage(error),
                      actionLabel: 'Réessayer',
                      onAction:
                          () => ref.invalidate(
                            submissionForSubjectProvider(providerArgs),
                          ),
                    ),
                  ),
            );
          },
          loading:
              () => Scaffold(
                backgroundColor: context.palette.background,
                appBar: AppBar(title: Text('Soumettre ma copie')),
                body: Center(child: CircularProgressIndicator()),
              ),
          error:
              (error, _) => Scaffold(
                backgroundColor: context.palette.background,
                appBar: AppBar(title: Text('Soumettre ma copie')),
                body: _SubmissionStateView(
                  icon: Icons.lock_outline,
                  title: 'Accès indisponible',
                  message: firestoreDataErrorMessage(
                    error,
                    fallback:
                        'Impossible de vérifier l’accès à cette session pour le moment.',
                  ),
                  actionLabel: 'Retour au planning',
                  onAction:
                      () => context.go(AppRoutes.planningSessionPath(session.id)),
                ),
              ),
        );
      },
      loading:
          () => Scaffold(
            backgroundColor: context.palette.background,
            appBar: AppBar(title: Text('Soumettre ma copie')),
            body: Center(child: CircularProgressIndicator()),
          ),
      error:
          (error, _) => Scaffold(
            backgroundColor: context.palette.background,
            appBar: AppBar(title: Text('Soumettre ma copie')),
            body: _SubmissionStateView(
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
          ),
    );
  }

  Widget _buildExistingSubmissionScaffold(SubmissionModel submission) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(title: Text('Copie déjà enregistrée')),
      body: _SubmissionStateView(
        icon:
            submission.canAccessResultDetail
                ? Icons.verified_outlined
                : Icons.hourglass_top_rounded,
        title:
            submission.canAccessResultDetail
                ? 'Résultat déjà disponible'
                : 'Copie déjà soumise',
        message:
            '${submission.subjectName}\n\n${submission.workflowDescription}',
        actionLabel:
            submission.canAccessResultDetail
                ? 'Voir le résultat'
                : 'Suivre la correction',
        onAction: () => _openExistingSubmission(submission),
      ),
    );
  }

  Widget _buildUploadingView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animation de chargement
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(15),
                shape: BoxShape.circle,
              ),
              child:
                  _uploadProgress < 1.0
                      ? Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 4,
                        ),
                      )
                      : const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.success,
                        size: 56,
                      ),
            ),
            const SizedBox(height: 24),
            Text(
              _uploadProgress < 1.0 ? 'Envoi en cours...' : 'Copie envoyée !',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _uploadStep,
              style: TextStyle(
                color: context.palette.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _uploadProgress,
                minHeight: 8,
                backgroundColor: context.palette.surfaceVariant,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_uploadProgress * 100).toInt()}%',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainView() {
    return Column(
      children: [
        // En-tête matière
        Container(
          padding: const EdgeInsets.all(16),
          color: context.palette.surface,
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color:
                      _subject?.subjectColor.withAlpha(25) ??
                      AppColors.primary.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.description_outlined,
                  color: _subject?.subjectColor ?? AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _subject?.name ?? 'Épreuve',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${_pages.length} page(s) · Max 5 MB par copie',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Guide
                _GuideBanner(),

                const SizedBox(height: 16),

                // Boutons ajout
                Row(
                  children: [
                    Expanded(
                      child: _AddPageButton(
                        icon: Icons.camera_alt_outlined,
                        label: 'Appareil photo',
                        subtitle: 'Prendre une photo',
                        onTap: _pickFromCamera,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _AddPageButton(
                        icon: Icons.photo_library_outlined,
                        label: 'Galerie',
                        subtitle: 'Choisir depuis la galerie',
                        onTap: _pickFromGallery,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                if (_pages.isNotEmpty) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Pages de ta copie (${_pages.length})',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => _pages.clear()),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                        label: Text('Tout effacer'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Grille des pages
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _pages.length,
                    onReorder: _reorderPage,
                    itemBuilder: (context, i) {
                      return _PageItem(
                        key: ValueKey(_pages[i].path),
                        page: _pages[i],
                        index: i,
                        onRemove: () => _removePage(i),
                      );
                    },
                  ),
                ] else
                  _EmptyPagesPlaceholder(),

                const SizedBox(height: 80),
              ],
            ),
          ),
        ),

        // Bouton soumettre
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          decoration: BoxDecoration(
            color: context.palette.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(15),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: _pages.isEmpty ? null : _submit,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(
              _pages.isEmpty
                  ? 'Ajoute des pages pour continuer'
                  : 'Soumettre ma copie (${_pages.length} page${_pages.length > 1 ? 's' : ''})',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _pages.isEmpty ? context.palette.textHint : AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _SubmissionShell extends StatelessWidget {
  final Widget child;

  const _SubmissionShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: context.palette.background, body: child);
  }
}

class _SubmissionStateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SubmissionStateView({
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

class _GuideBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.info.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tips_and_updates_outlined,
                color: AppColors.info,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Conseils pour une bonne photo',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.info,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          _GuideLine('Bonne luminosité — évite les ombres sur la copie'),
          _GuideLine('Copie bien à plat, sans plis ni froissements'),
          _GuideLine('Texte lisible — vérifie que tout est net'),
          _GuideLine('Une photo par page, dans l\'ordre'),
        ],
      ),
    );
  }
}

class _GuideLine extends StatelessWidget {
  final String text;
  const _GuideLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(color: AppColors.info)),
          Expanded(
            child: Text(
              text,
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
}

class _AddPageButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _AddPageButton({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.primary.withAlpha(60),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primary, size: 26),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: context.palette.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PageItem extends StatelessWidget {
  final XFile page;
  final int index;
  final VoidCallback onRemove;

  const _PageItem({
    super.key,
    required this.page,
    required this.index,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.palette.divider),
      ),
      child: Row(
        children: [
          // Numéro de page
          Container(
            width: 44,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(15),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(11),
              ),
            ),
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  fontSize: 20,
                ),
              ),
            ),
          ),

          // Aperçu image
          ClipRRect(
            borderRadius: BorderRadius.zero,
            child: Image.file(
              File(page.path),
              width: 64,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),

          const SizedBox(width: 12),

          // Infos
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Page ${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  page.name.split('/').last,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.palette.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Supprimer
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.error),
            onPressed: onRemove,
          ),

          // Drag handle
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.drag_handle, color: context.palette.textHint),
          ),
        ],
      ),
    );
  }
}

class _EmptyPagesPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.palette.divider, style: BorderStyle.solid),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 48,
              color: context.palette.textHint,
            ),
            SizedBox(height: 12),
            Text(
              'Aucune page ajoutée',
              style: TextStyle(
                color: context.palette.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Utilise les boutons ci-dessus pour ajouter ta copie',
              style: TextStyle(fontSize: 12, color: context.palette.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/theme_mode_provider.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _schoolCtrl = TextEditingController();

  StudentClass _selectedClass = StudentClass.terminale;
  String _selectedSeries = 'D';
  bool _isSaving = false;
  bool _isUpdatingAvatar = false;
  bool _didSeedForm = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _schoolCtrl.dispose();
    super.dispose();
  }

  void _seedForm(UserModel user) {
    if (_didSeedForm) return;
    _nameCtrl.text = user.displayName;
    _phoneCtrl.text = user.phone;
    _schoolCtrl.text = user.school;
    _selectedClass = user.studentClass ?? StudentClass.terminale;
    _selectedSeries = user.series.trim().isNotEmpty ? user.series.trim() : 'D';
    _didSeedForm = true;
  }

  Future<void> _save(UserModel user) async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);

    try {
      await ref
          .read(authNotifierProvider.notifier)
          .updateProfile(
            displayName: _nameCtrl.text,
            phone: _phoneCtrl.text,
            school: _schoolCtrl.text,
            studentClass: _selectedClass,
            series:
                _selectedClass == StudentClass.terminale ? _selectedSeries : '',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profil mis à jour.')));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(authErrorMessage(e))));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final picker = ImagePicker();

    try {
      final image = await picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (image == null) return;

      setState(() => _isUpdatingAvatar = true);
      await ref
          .read(authNotifierProvider.notifier)
          .updateProfilePhoto(File(image.path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil mise à jour.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(authErrorMessage(e))));
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAvatar = false);
      }
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _isUpdatingAvatar = true);

    try {
      await ref.read(authNotifierProvider.notifier).removeProfilePhoto();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de profil supprimée.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(authErrorMessage(e))));
    } finally {
      if (mounted) {
        setState(() => _isUpdatingAvatar = false);
      }
    }
  }

  Widget _avatarPreview(BuildContext context, UserModel user) {
    final avatarUrl = user.avatarUrl.trim();

    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: context.palette.divider, width: 2),
      ),
      child: ClipOval(
        child:
            avatarUrl.isEmpty
                ? Center(
                  child: Text(
                    user.displayName.trim().isEmpty
                        ? 'E'
                        : user.displayName.trim().substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
                : Image.network(
                  avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return Center(
                      child: Text(
                        user.displayName.trim().isEmpty
                            ? 'E'
                            : user.displayName
                                .trim()
                                .substring(0, 1)
                                .toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  },
                ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final user = authState.value;

    if (authState.isLoading && user == null) {
      return Scaffold(
        backgroundColor: context.palette.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (user == null) {
      return Scaffold(
        backgroundColor: context.palette.background,
        appBar: AppBar(title: const Text('Modifier mon profil')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Impossible de charger ton profil pour le moment.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    _seedForm(user);

    const gold = Color(0xFFF5B731);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sectionTitleColor = isDark ? gold : AppColors.primary;
    final photoActionColor = isDark ? gold : AppColors.primary;
    final photoActionBackground =
        isDark ? gold.withAlpha(16) : AppColors.primary.withAlpha(6);
    final photoActionBorder =
        isDark ? gold.withAlpha(90) : AppColors.primary.withAlpha(50);
    final deleteActionBackground =
        isDark ? AppColors.error.withAlpha(16) : AppColors.error.withAlpha(6);

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(title: const Text('Modifier mon profil')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.palette.divider),
                  ),
                  child: Column(
                    children: [
                      _avatarPreview(context, user),
                      const SizedBox(height: 14),
                      Text(
                        'Photo de profil',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: sectionTitleColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ajoute une photo claire pour personnaliser ton compte.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed:
                                _isUpdatingAvatar
                                    ? null
                                    : () => _pickAvatar(ImageSource.camera),
                            icon:
                                _isUpdatingAvatar
                                    ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: photoActionColor,
                                      ),
                                    )
                                    : const Icon(Icons.photo_camera_outlined),
                            label: const Text('Appareil photo'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: photoActionColor,
                              backgroundColor: photoActionBackground,
                              side: BorderSide(color: photoActionBorder),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                _isUpdatingAvatar
                                    ? null
                                    : () => _pickAvatar(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('Galerie'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: photoActionColor,
                              backgroundColor: photoActionBackground,
                              side: BorderSide(color: photoActionBorder),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                          ),
                          if (user.avatarUrl.trim().isNotEmpty)
                            TextButton.icon(
                              onPressed:
                                  _isUpdatingAvatar ? null : _removeAvatar,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Supprimer'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.error,
                                backgroundColor: deleteActionBackground,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.palette.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Informations personnelles',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: sectionTitleColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nom complet',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Nom requis';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        initialValue: user.email,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'L’email n’est pas modifiable ici.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Téléphone',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Téléphone requis';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.palette.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Informations scolaires',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: sectionTitleColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _schoolCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Établissement scolaire',
                          prefixIcon: Icon(Icons.school_outlined),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'École requise';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<StudentClass>(
                        initialValue: _selectedClass,
                        decoration: const InputDecoration(
                          labelText: 'Classe',
                          prefixIcon: Icon(Icons.class_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: StudentClass.terminale,
                            child: Text('Terminale (BAC)'),
                          ),
                          DropdownMenuItem(
                            value: StudentClass.troisieme,
                            child: Text('3ème (BEPC)'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _selectedClass = value;
                            if (_selectedClass == StudentClass.terminale) {
                              if (_selectedSeries.isEmpty) {
                                _selectedSeries = 'D';
                              }
                            } else {
                              _selectedSeries = '';
                            }
                          });
                        },
                      ),
                      if (_selectedClass == StudentClass.terminale) ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedSeries,
                          decoration: const InputDecoration(
                            labelText: 'Série',
                            prefixIcon: Icon(Icons.category_outlined),
                          ),
                          items:
                              AppConstants.bacSeries
                                  .map(
                                    (series) => DropdownMenuItem<String>(
                                      value: series,
                                      child: Text('Série $series'),
                                    ),
                                  )
                                  .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _selectedSeries = value);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.palette.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Apparence',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: sectionTitleColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choisis un thème clair, sombre, ou celle du téléphone.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.system,
                            label: Text('Système'),
                            icon: Icon(Icons.brightness_auto, size: 16),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.light,
                            label: Text('Clair'),
                            icon: Icon(Icons.light_mode, size: 16),
                          ),
                          ButtonSegment<ThemeMode>(
                            value: ThemeMode.dark,
                            label: Text('Sombre'),
                            icon: Icon(Icons.dark_mode, size: 16),
                          ),
                        ],
                        selected: {ref.watch(themeModeProvider)},
                        onSelectionChanged: (s) {
                          if (s.isNotEmpty) {
                            ref
                                .read(themeModeProvider.notifier)
                                .setTheme(s.first);
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : () => _save(user),
                    icon:
                        _isSaving
                            ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: AppColors.primary,
                              ),
                            )
                            : const Icon(Icons.save_outlined),
                    label: Text(
                      _isSaving ? 'Enregistrement...' : 'Enregistrer',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

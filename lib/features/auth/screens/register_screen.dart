import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _schoolCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  StudentClass _selectedClass = StudentClass.terminale;
  String _selectedSeries = 'D';
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _schoolCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).register(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
            displayName: _nameCtrl.text,
            phone: _phoneCtrl.text,
            series: _selectedClass == StudentClass.terminale ? _selectedSeries : '',
            school: _schoolCtrl.text,
            studentClass: _selectedClass,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(authErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                      onPressed: () => context.pop(),
                    ),
                    const Expanded(
                      child: Text(
                        'Créer mon compte',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Formulaire
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: context.palette.background,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Informations personnelles',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Nom complet',
                              hintText: 'Prénom NOM',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Nom requis' : null,
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _emailCtrl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              hintText: 'ton@email.com',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Email requis';
                              if (!v.contains('@')) return 'Email invalide';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Numéro de téléphone',
                              hintText: '+242 06 000 0000',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'Téléphone requis' : null,
                          ),
                          const SizedBox(height: 24),

                          Text(
                            'Informations scolaires',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _schoolCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Établissement scolaire',
                              hintText: 'Nom de votre lycée',
                              prefixIcon: Icon(Icons.school_outlined),
                            ),
                            validator: (v) =>
                                v == null || v.isEmpty ? 'École requise' : null,
                          ),
                          const SizedBox(height: 14),

                          // Classe
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
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                _selectedClass = v;
                                if (_selectedClass == StudentClass.troisieme) {
                                  _selectedSeries = '';
                                } else if (_selectedSeries.isEmpty) {
                                  _selectedSeries = 'D';
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 14),

                          // Série
                          if (_selectedClass == StudentClass.terminale)
                            DropdownButtonFormField<String>(
                              initialValue: _selectedSeries,
                              decoration: const InputDecoration(
                                labelText: 'Série',
                                prefixIcon: Icon(Icons.category_outlined),
                              ),
                              items: AppConstants.bacSeries
                                  .map((s) => DropdownMenuItem(
                                        value: s,
                                        child: Text('Série $s'),
                                      ))
                                  .toList(),
                              onChanged: (v) => setState(() => _selectedSeries = v!),
                            ),
                          const SizedBox(height: 24),

                          Text(
                            'Sécurité',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: context.palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _passwordCtrl,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Mot de passe',
                              hintText: 'Minimum 6 caractères',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Mot de passe requis';
                              if (v.length < 6) return 'Minimum 6 caractères';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _confirmCtrl,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Confirmer le mot de passe',
                              hintText: 'Répète ton mot de passe',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            validator: (v) {
                              if (v != _passwordCtrl.text) {
                                return 'Les mots de passe ne correspondent pas';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 32),

                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _register,
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        color: AppColors.primary,
                                      ),
                                    )
                                  : const Text('Créer mon compte'),
                            ),
                          ),

                          const SizedBox(height: 16),

                          Center(
                            child: TextButton(
                              onPressed: () => context.pop(),
                              child: const Text('J\'ai déjà un compte'),
                            ),
                          ),
                        ],
                      ),
                    ),
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

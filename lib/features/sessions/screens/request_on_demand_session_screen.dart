import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/on_demand_session_provider.dart';

class RequestOnDemandSessionScreen extends ConsumerStatefulWidget {
  const RequestOnDemandSessionScreen({super.key});

  @override
  ConsumerState<RequestOnDemandSessionScreen> createState() =>
      _RequestOnDemandSessionScreenState();
}

class _RequestOnDemandSessionScreenState
    extends ConsumerState<RequestOnDemandSessionScreen> {
  static const _minLeadTime = Duration(hours: 48);

  DateTime? _startDate;
  DateTime? _endDate;
  bool _isPublic = false;

  DateTime get _earliestStart => DateTime.now().add(_minLeadTime);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final notifierState = ref.watch(onDemandSessionNotifierProvider);
    final isLoading = notifierState.isLoading;

    ref.listen(onDemandSessionNotifierProvider, (previous, next) {
      next.whenOrNull(
        error: (error, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(onDemandSessionErrorMessage(error))),
          );
        },
      );
    });

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(
        title: const Text('Demander une session'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withAlpha(10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.primary.withAlpha(30)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Comment ça marche ?',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Prix fixe : 1500 FCFA par participant.\n'
                    '• Choisis juste tes dates — l\'administration compose les épreuves.\n'
                    '• Délai minimum de 48h pour laisser le temps à la composition.\n'
                    '• Dès la date de début, plus aucune inscription n\'est possible.',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              'Classe',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            _ReadOnlyField(
              value: user?.studentClass?.name == 'terminale'
                  ? 'Terminale${(user?.series.isNotEmpty ?? false) ? ' • Série ${user!.series}' : ''}'
                  : '3ème',
            ),
            const SizedBox(height: 20),

            Text(
              'Date de début',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            _DatePickerField(
              value: _startDate,
              placeholder: 'Choisir une date (min. 48h)',
              onTap: () => _pickStartDate(context),
            ),
            const SizedBox(height: 20),

            Text(
              'Date de fin',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.palette.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            _DatePickerField(
              value: _endDate,
              placeholder: 'Choisir une date',
              onTap: _startDate == null ? null : () => _pickEndDate(context),
            ),
            const SizedBox(height: 20),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isPublic,
              onChanged: (v) => setState(() => _isPublic = v),
              activeColor: AppColors.primary,
              title: const Text(
                'Rendre publique',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(
                'Les autres élèves de ta classe et série pourront la voir et '
                'payer 1500 FCFA pour la rejoindre avant la date de début.',
                style: TextStyle(fontSize: 12, color: context.palette.textSecondary),
              ),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.accent.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined, color: AppColors.accentDark, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Prix : 1500 FCFA',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : () => _submit(context, user?.uid),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Envoyer la demande'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _earliestStart,
      firstDate: _earliestStart,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked;
      if (_endDate != null && !_endDate!.isAfter(_startDate!)) {
        _endDate = null;
      }
    });
  }

  Future<void> _pickEndDate(BuildContext context) async {
    final start = _startDate!;
    final picked = await showDatePicker(
      context: context,
      initialDate: start.add(const Duration(days: 1)),
      firstDate: start.add(const Duration(days: 1)),
      lastDate: start.add(const Duration(days: 30)),
    );
    if (picked == null) return;
    setState(() => _endDate = picked);
  }

  Future<void> _submit(BuildContext context, String? uid) async {
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choisis une date de début et de fin.')),
      );
      return;
    }

    try {
      final sessionId = await ref
          .read(onDemandSessionNotifierProvider.notifier)
          .requestSession(
            startDate: _startDate!,
            endDate: _endDate!,
            isPublic: _isPublic,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demande envoyée ! Tu peux payer ta place.')),
      );
      context.go(AppRoutes.paymentPath(sessionId));
    } catch (_) {
      // Erreur déjà affichée via ref.listen plus haut.
    }
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String value;
  const _ReadOnlyField({required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: context.palette.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        value,
        style: TextStyle(fontSize: 14, color: context.palette.textPrimary),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  final DateTime? value;
  final String placeholder;
  final VoidCallback? onTap;

  const _DatePickerField({
    required this.value,
    required this.placeholder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: disabled ? context.palette.surfaceVariant : context.palette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.palette.divider),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: disabled ? context.palette.textHint : AppColors.primary,
            ),
            const SizedBox(width: 10),
            Text(
              value != null
                  ? DateFormat('d MMMM yyyy', 'fr').format(value!)
                  : placeholder,
              style: TextStyle(
                fontSize: 14,
                color: value != null
                    ? context.palette.textPrimary
                    : context.palette.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

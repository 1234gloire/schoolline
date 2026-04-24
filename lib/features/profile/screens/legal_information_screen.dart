import 'package:flutter/material.dart';
import '../../../core/theme/exam_sim_palette.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/legal_information.dart';

class LegalInformationScreen extends StatelessWidget {
  const LegalInformationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: AppBar(title: const Text('Mentions légales')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _LegalIntroCard(),
            if (LegalInformation.hasAnyIdentityInformation) ...[
              const SizedBox(height: 16),
              const _LegalIdentityCard(),
              const SizedBox(height: 14),
            ],
            const _LegalSectionCard(
              icon: Icons.shield_outlined,
              title: 'Données du profil élève',
              body:
                  'Le profil élève contient les informations nécessaires au fonctionnement du service : nom, email, téléphone, établissement, classe, série et historique de participation aux sessions.',
            ),
            const SizedBox(height: 14),
            const _LegalSectionCard(
              icon: Icons.lock_outline,
              title: 'Sécurité et accès',
              body:
                  'Chaque élève est responsable de la confidentialité de ses identifiants. Le mot de passe peut être modifié depuis le profil. En cas d’anomalie, un administrateur peut suspendre un compte.',
            ),
            const SizedBox(height: 14),
            const _LegalSectionCard(
              icon: Icons.school_outlined,
              title: 'Usage pédagogique',
              body:
                  'Les sessions, sujets, copies et résultats sont fournis dans un cadre d’évaluation ou d’entraînement scolaire. Les informations affichées dans l’application doivent être vérifiées par l’organisation qui exploite la plateforme.',
            ),
            const SizedBox(height: 14),
            const _LegalSectionCard(
              icon: Icons.payments_outlined,
              title: 'Paiements et validation',
              body:
                  'Certaines sessions peuvent nécessiter une validation de paiement avant ouverture. Les preuves soumises sont utilisées uniquement pour traiter l’accès à la session concernée.',
            ),
            const SizedBox(height: 14),
            _LegalSectionCard(
              icon: Icons.notifications_outlined,
              title: 'Notifications',
              body:
                  'Les notifications servent à informer l’élève des ouvertures de sessions, rappels utiles et publications de résultats. Elles peuvent apparaître sous forme de push natif ou de notification locale selon l’état de l’application et les autorisations accordées sur l’appareil.',
            ),
            const SizedBox(height: 14),
            _LegalSectionCard(
              icon: Icons.info_outline,
              title: 'Conservation et confidentialité',
              body: LegalInformation.legalDataRetention,
            ),
            const SizedBox(height: 16),
            const _LegalFooterCard(),
          ],
        ),
      ),
    );
  }
}

class _LegalIntroCard extends StatelessWidget {
  const _LegalIntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0A1172), Color(0xFF1E2FA0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppConstants.appName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cette page résume les règles d’utilisation du profil élève, la gestion des données essentielles et les points de vigilance sur la sécurité du compte.',
            style: TextStyle(color: Colors.white, fontSize: 13, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _LegalIdentityCard extends StatelessWidget {
  const _LegalIdentityCard();

  @override
  Widget build(BuildContext context) {
    final rows =
        [
          (label: 'Entité', value: LegalInformation.legalEntityName.trim()),
          (label: 'Adresse', value: LegalInformation.legalEntityAddress.trim()),
          (
            label: 'Support email',
            value: LegalInformation.legalSupportEmail.trim(),
          ),
          (
            label: 'Support téléphone',
            value: LegalInformation.legalSupportPhone.trim(),
          ),
          (
            label: 'Contact données personnelles',
            value: LegalInformation.legalPrivacyContact.trim(),
          ),
        ].where((row) => row.value.isNotEmpty).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      clipBehavior: Clip.antiAlias,
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
            'Responsable du service',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.palette.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...rows.map(
            (row) => _LegalInfoRow(label: row.label, value: row.value),
          ),
        ],
      ),
    );
  }
}

class _LegalInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _LegalInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: context.palette.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalSectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _LegalSectionCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const gold = Color(0xFFF5B731);
    final iconColor = isDark ? gold : AppColors.primary;
    final iconBg =
        isDark ? gold.withAlpha(28) : AppColors.primary.withAlpha(12);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.palette.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: context.palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalFooterCard extends StatelessWidget {
  const _LegalFooterCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Version de l’application',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF92400E),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${AppConstants.appName} ${AppConstants.appVersion}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF92400E)),
          ),
        ],
      ),
    );
  }
}

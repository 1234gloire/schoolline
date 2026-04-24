class LegalInformation {
  LegalInformation._();

  static const String legalEntityName = String.fromEnvironment(
    'LEGAL_ENTITY_NAME',
    defaultValue: '',
  );
  static const String legalEntityAddress = String.fromEnvironment(
    'LEGAL_ENTITY_ADDRESS',
    defaultValue: '',
  );
  static const String legalSupportEmail = String.fromEnvironment(
    'LEGAL_SUPPORT_EMAIL',
    defaultValue: '',
  );
  static const String legalSupportPhone = String.fromEnvironment(
    'LEGAL_SUPPORT_PHONE',
    defaultValue: '',
  );
  static const String legalDataRetention = String.fromEnvironment(
    'LEGAL_DATA_RETENTION',
    defaultValue:
        'Les données sont conservées pendant la durée nécessaire au suivi pédagogique, '
        'à la gestion des paiements et au traitement des résultats.',
  );
  static const String legalPrivacyContact = String.fromEnvironment(
    'LEGAL_PRIVACY_CONTACT',
    defaultValue: '',
  );

  static bool get isProductionReady =>
      legalEntityName.trim().isNotEmpty &&
      legalEntityAddress.trim().isNotEmpty &&
      legalSupportEmail.trim().isNotEmpty &&
      legalSupportPhone.trim().isNotEmpty &&
      legalPrivacyContact.trim().isNotEmpty;

  static bool get hasAnyIdentityInformation =>
      legalEntityName.trim().isNotEmpty ||
      legalEntityAddress.trim().isNotEmpty ||
      legalSupportEmail.trim().isNotEmpty ||
      legalSupportPhone.trim().isNotEmpty ||
      legalPrivacyContact.trim().isNotEmpty;

  static String orPlaceholder(
    String value, {
    String placeholder = 'À renseigner avant la mise en production',
  }) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? placeholder : trimmed;
  }
}

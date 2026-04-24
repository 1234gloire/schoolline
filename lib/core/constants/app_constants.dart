class AppConstants {
  AppConstants._();

  // App info
  static const String appName = 'ExamSim Congo';
  static const String appVersion = '1.0.0';

  // Firestore collections
  static const String usersCollection = 'users';
  static const String sessionsCollection = 'sessions';
  static const String subjectsSubcollection = 'subjects';
  static const String submissionsCollection = 'submissions';
  static const String paymentsCollection = 'payments';
  static const String studentResultsSubcollection = 'studentResults';
  static const String paymentsStoragePath = 'payments';
  static const String avatarsStoragePath = 'avatars';
  static const String trainingDataCollection = 'training_data';

  // Storage paths
  static const String subjectsStoragePath = 'subjects';
  static const String submissionsStoragePath = 'submissions';

  // Région Cloud Functions
  static const String functionsRegion = 'europe-west1';

  // Seuil de confiance IA (%)
  static const int aiConfidenceThreshold = 80;

  // Tolérance d'accès à l'épreuve (minutes)
  static const int examAccessToleranceMinutes = 5;

  // Taille max upload copie (bytes = 5 MB)
  static const int maxSubmissionSizeBytes = 5 * 1024 * 1024;

  // Alertes chrono (secondes restantes)
  static const int alertAt30Min = 30 * 60;
  static const int alertAt15Min = 15 * 60;
  static const int alertAt5Min = 5 * 60;

  // Séries BAC Congo
  static const List<String> bacSeries = ['A', 'B', 'C', 'D', 'TI', 'G'];

  // Matières
  static const List<String> mathSubjects = [
    'Mathématiques',
    'Physique-Chimie',
    'SVT',
    'Informatique',
  ];
  static const List<String> literarySubjects = [
    'Français',
    'Philosophie',
    'Histoire-Géographie',
    'Anglais',
    'Espagnol',
  ];

  // Mentions BAC (Congo)
  static const double passableMin = 10.0;
  static const double assezBienMin = 12.0;
  static const double bienMin = 14.0;
  static const double tresBienMin = 16.0;
}

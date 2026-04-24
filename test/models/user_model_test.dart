import 'package:flutter_test/flutter_test.dart';
import 'package:examsim_congo/models/user_model.dart';

UserModel _buildUser({
  UserRole role = UserRole.student,
  StudentClass? studentClass = StudentClass.terminale,
  String series = 'D',
  String school = 'Lycée Savorgnan',
  bool blocked = false,
  List<String> subscriptions = const [],
  List<String> abandonedSubjectIds = const [],
}) {
  return UserModel(
    uid: 'uid-test',
    displayName: 'Élève Test',
    email: 'test@examsim.cg',
    phone: '+242060000000',
    role: role,
    studentClass: studentClass,
    series: series,
    school: school,
    createdAt: DateTime(2025, 1, 1),
    subscriptions: subscriptions,
    abandonedSubjectIds: abandonedSubjectIds,
    blocked: blocked,
  );
}

void main() {
  group('UserModel — getters de rôle', () {
    test('isStudent vrai pour UserRole.student', () {
      expect(_buildUser(role: UserRole.student).isStudent, isTrue);
      expect(_buildUser(role: UserRole.student).isCorrector, isFalse);
      expect(_buildUser(role: UserRole.student).isAdmin, isFalse);
    });

    test('isCorrector vrai pour UserRole.corrector', () {
      final u = _buildUser(role: UserRole.corrector);
      expect(u.isCorrector, isTrue);
      expect(u.isStudent, isFalse);
    });

    test('isAdmin vrai pour UserRole.admin', () {
      final u = _buildUser(role: UserRole.admin);
      expect(u.isAdmin, isTrue);
    });
  });

  group('UserModel — classLabel', () {
    test('terminale → "Terminale"', () {
      expect(
        _buildUser(studentClass: StudentClass.terminale).classLabel,
        'Terminale',
      );
    });

    test('troisieme → "3ème"', () {
      expect(
        _buildUser(studentClass: StudentClass.troisieme).classLabel,
        '3ème',
      );
    });

    test('null → message par défaut', () {
      expect(
        _buildUser(studentClass: null).classLabel,
        'Classe non renseignée',
      );
    });
  });

  group('UserModel — copyWith', () {
    test('copie partielle préserve les champs non modifiés', () {
      final original = _buildUser(series: 'D', school: 'Lycée Test');
      final copy = original.copyWith(series: 'C');
      expect(copy.series, 'C');
      expect(copy.school, 'Lycée Test');
      expect(copy.uid, original.uid);
    });

    test('copyWith(blocked: true) modifie correctement le champ', () {
      final original = _buildUser(blocked: false);
      final blocked = original.copyWith(blocked: true);
      expect(blocked.blocked, isTrue);
      expect(original.blocked, isFalse);
    });

    test('copyWith sans argument retourne un objet identique', () {
      final original = _buildUser();
      final copy = original.copyWith();
      expect(copy.displayName, original.displayName);
      expect(copy.email, original.email);
      expect(copy.role, original.role);
      expect(copy.blocked, original.blocked);
    });

    test('copyWith(subscriptions) remplace la liste', () {
      final original = _buildUser(subscriptions: ['sess-1']);
      final updated = original.copyWith(subscriptions: ['sess-1', 'sess-2']);
      expect(updated.subscriptions, ['sess-1', 'sess-2']);
      expect(original.subscriptions, ['sess-1']);
    });

    test('copyWith(avatarUrl) met à jour la photo de profil', () {
      final original = _buildUser();
      final updated = original.copyWith(
        avatarUrl: 'https://cdn.test/avatar.jpg',
      );
      expect(updated.avatarUrl, 'https://cdn.test/avatar.jpg');
      expect(original.avatarUrl, isEmpty);
    });
  });

  group('UserModel — complétude du profil', () {
    test('terminale sans série est incomplet', () {
      final user = _buildUser(series: '');

      expect(user.isProfileComplete, isFalse);
      expect(user.missingRequiredFields, contains('série'));
    });

    test(
      'troisieme sans série reste complet si les autres champs sont présents',
      () {
        final user = _buildUser(
          studentClass: StudentClass.troisieme,
          series: '',
        );

        expect(user.isProfileComplete, isTrue);
        expect(user.missingRequiredFields, isEmpty);
      },
    );

    test('champs manquants multiples sont détectés correctement', () {
      final user = UserModel(
        uid: 'uid-test',
        displayName: '',
        email: 'test@examsim.cg',
        phone: '',
        role: UserRole.student,
        studentClass: null,
        series: '',
        school: '',
        createdAt: DateTime(2025, 1, 1),
        subscriptions: const [],
        abandonedSubjectIds: const [],
      );

      expect(user.missingRequiredFields, [
        'nom complet',
        'téléphone',
        'établissement',
        'classe',
      ]);
      expect(user.profileCompletionRatio, 0);
    });

    test('ratio de complétude terminale complet vaut 1', () {
      final user = _buildUser();

      expect(user.profileCompletionRatio, 1);
      expect(user.isProfileComplete, isTrue);
    });
  });

  group('UserModel — hasAbandonedSubject', () {
    test('retourne vrai si l\'épreuve est dans la liste', () {
      final u = _buildUser(abandonedSubjectIds: ['subj-abc']);
      expect(u.hasAbandonedSubject('subj-abc'), isTrue);
    });

    test('retourne faux si l\'épreuve est absente', () {
      final u = _buildUser(abandonedSubjectIds: ['subj-abc']);
      expect(u.hasAbandonedSubject('subj-xyz'), isFalse);
    });

    test('retourne faux si la liste est vide', () {
      expect(_buildUser().hasAbandonedSubject('subj-abc'), isFalse);
    });
  });
}

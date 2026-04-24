import 'package:flutter_test/flutter_test.dart';
import 'package:examsim_congo/models/subject_model.dart';

SubjectModel _buildSubject({
  String name = 'Mathématiques',
  int durationMinutes = 180,
  DateTime? startTime,
  DateTime? endTime,
  List<String> series = const ['D', 'C'],
}) {
  final now = DateTime.now();
  return SubjectModel(
    id: 'subj-test',
    sessionId: 'sess-test',
    name: name,
    durationMinutes: durationMinutes,
    startTime: startTime ?? now.subtract(const Duration(minutes: 10)),
    endTime: endTime ?? now.add(const Duration(hours: 2)),
    subjectFileRef: 'subjects/test.pdf',
    coefficient: 5,
    maxScore: 20,
    bareme: const {},
    series: series,
    type: SubjectType.structured,
  );
}

void main() {
  group('SubjectModel — durationLabel', () {
    test('180 min → "3h"', () {
      expect(_buildSubject(durationMinutes: 180).durationLabel, '3h');
    });

    test('90 min → "1h30"', () {
      expect(_buildSubject(durationMinutes: 90).durationLabel, '1h30');
    });

    test('45 min → "45min"', () {
      expect(_buildSubject(durationMinutes: 45).durationLabel, '45min');
    });

    test('60 min → "1h"', () {
      expect(_buildSubject(durationMinutes: 60).durationLabel, '1h');
    });
  });

  group('SubjectModel — timeStatus', () {
    test('upcoming si maintenant avant startTime', () {
      final now = DateTime.now();
      final s = _buildSubject(
        startTime: now.add(const Duration(hours: 1)),
        endTime: now.add(const Duration(hours: 4)),
      );
      expect(s.timeStatus, ExamTimeStatus.upcoming);
      expect(s.isAccessibleNow, isFalse);
    });

    test('accessible dans la fenêtre de tolérance', () {
      final now = DateTime.now();
      final s = _buildSubject(
        startTime: now.subtract(const Duration(minutes: 2)),
        endTime: now.add(const Duration(hours: 3)),
      );
      expect(s.timeStatus, ExamTimeStatus.accessible);
      expect(s.isAccessibleNow, isTrue);
    });

    test('lateBlocked après la tolérance mais avant endTime', () {
      final now = DateTime.now();
      final s = _buildSubject(
        startTime: now.subtract(const Duration(minutes: 30)),
        endTime: now.add(const Duration(hours: 2)),
      );
      expect(s.timeStatus, ExamTimeStatus.lateBlocked);
      expect(s.isAccessibleNow, isFalse);
    });

    test('past après endTime', () {
      final now = DateTime.now();
      final s = _buildSubject(
        startTime: now.subtract(const Duration(hours: 4)),
        endTime: now.subtract(const Duration(hours: 1)),
      );
      expect(s.timeStatus, ExamTimeStatus.past);
    });
  });

  group('SubjectModel — isSubmissionOpen', () {
    test('ouvert pendant l\'épreuve', () {
      final now = DateTime.now();
      final s = _buildSubject(
        startTime: now.subtract(const Duration(minutes: 2)),
        endTime: now.add(const Duration(hours: 3)),
      );
      expect(s.isSubmissionOpen, isTrue);
    });

    test('fermé avant le début', () {
      final now = DateTime.now();
      final s = _buildSubject(
        startTime: now.add(const Duration(hours: 1)),
        endTime: now.add(const Duration(hours: 4)),
      );
      expect(s.isSubmissionOpen, isFalse);
    });

    test('fermé après submissionCutoff', () {
      final now = DateTime.now();
      final s = _buildSubject(
        startTime: now.subtract(const Duration(hours: 4)),
        endTime: now.subtract(const Duration(minutes: 10)),
      );
      expect(s.isSubmissionOpen, isFalse);
    });
  });

  group('SubjectModel — remainingTime', () {
    test('retourne Duration.zero si épreuve terminée', () {
      final now = DateTime.now();
      final s = _buildSubject(
        startTime: now.subtract(const Duration(hours: 4)),
        endTime: now.subtract(const Duration(hours: 1)),
      );
      expect(s.remainingTime, Duration.zero);
    });

    test('retourne une durée positive si épreuve en cours', () {
      final now = DateTime.now();
      final s = _buildSubject(
        startTime: now.subtract(const Duration(minutes: 5)),
        endTime: now.add(const Duration(hours: 2)),
      );
      expect(s.remainingTime.inMinutes, greaterThan(100));
    });
  });

  group('ExamTimeStatus — label', () {
    test('chaque statut a un label non vide', () {
      for (final status in ExamTimeStatus.values) {
        expect(status.label, isNotEmpty);
      }
    });
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/app_colors.dart';

enum SubjectType { structured, literary, qcm }

class SubjectModel {
  final String id;
  final String sessionId;
  final String name;
  final int durationMinutes;
  final DateTime startTime;
  final DateTime endTime;
  final String subjectFileRef; // chemin Firebase Storage
  final double coefficient;
  final double maxScore;
  final Map<String, double> bareme; // ex: {comprehension: 5, analyse: 8}
  final List<String> series;
  final SubjectType type;
  final String corrigeText; // Corrigé officiel — utilisé par l'IA pour corriger les copies

  const SubjectModel({
    required this.id,
    required this.sessionId,
    required this.name,
    required this.durationMinutes,
    required this.startTime,
    required this.endTime,
    required this.subjectFileRef,
    required this.coefficient,
    required this.maxScore,
    required this.bareme,
    required this.series,
    required this.type,
    this.corrigeText = '',
  });

  factory SubjectModel.fromFirestore(DocumentSnapshot doc, String sessionId) {
    final data = doc.data() as Map<String, dynamic>;
    return SubjectModel(
      id: doc.id,
      sessionId: sessionId,
      name: data['name'] ?? '',
      durationMinutes: data['duration'] ?? 120,
      startTime: (data['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endTime: (data['endTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      subjectFileRef: data['subjectFileRef'] ?? '',
      coefficient: (data['coefficient'] ?? 1).toDouble(),
      maxScore: (data['maxScore'] ?? 20).toDouble(),
      bareme: Map<String, double>.from(
        (data['bareme'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, (v as num).toDouble()),
        ),
      ),
      series: List<String>.from(data['series'] ?? []),
      type: SubjectType.values.firstWhere(
        (t) => t.name == (data['type'] ?? 'structured'),
        orElse: () => SubjectType.structured,
      ),
      corrigeText: data['corrigeText'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'duration': durationMinutes,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'subjectFileRef': subjectFileRef,
      'coefficient': coefficient,
      'maxScore': maxScore,
      'bareme': bareme,
      'series': series,
      'type': type.name,
      'corrigeText': corrigeText,
    };
  }

  // Statut de l'épreuve par rapport à l'heure actuelle
  ExamTimeStatus get timeStatus {
    final now = DateTime.now();
    final toleranceAfter = startTime.add(
      const Duration(minutes: AppConstants.examAccessToleranceMinutes),
    );

    if (now.isBefore(startTime)) return ExamTimeStatus.upcoming;
    if (now.isAfter(endTime)) return ExamTimeStatus.past;
    if (now.isAfter(toleranceAfter)) return ExamTimeStatus.lateBlocked;
    return ExamTimeStatus.accessible;
  }

  bool get isAccessibleNow => timeStatus == ExamTimeStatus.accessible;

  DateTime get submissionCutoff => endTime.add(
    const Duration(minutes: AppConstants.examAccessToleranceMinutes),
  );

  bool get isSubmissionOpen {
    final now = DateTime.now();
    return !now.isBefore(startTime) && !now.isAfter(submissionCutoff);
  }

  Duration get remainingTime {
    final now = DateTime.now();
    if (now.isAfter(endTime)) return Duration.zero;
    return endTime.difference(now);
  }

  Color get subjectColor {
    final n = name.toLowerCase();
    if (n.contains('math')) return AppColors.mathColor;
    if (n.contains('physique')) return AppColors.physicsColor;
    if (n.contains('svt') || n.contains('biologie')) return AppColors.svtColor;
    if (n.contains('français') || n.contains('francais')) return AppColors.frenchColor;
    if (n.contains('philo')) return AppColors.philoColor;
    if (n.contains('histoire')) return AppColors.historyColor;
    if (n.contains('chimie')) return AppColors.chemistryColor;
    return AppColors.primary;
  }

  String get durationLabel {
    if (durationMinutes >= 60) {
      final h = durationMinutes ~/ 60;
      final m = durationMinutes % 60;
      return m > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '${h}h';
    }
    return '${durationMinutes}min';
  }
}

enum ExamTimeStatus { upcoming, accessible, lateBlocked, past }

extension ExamTimeStatusExtension on ExamTimeStatus {
  String get label {
    switch (this) {
      case ExamTimeStatus.upcoming: return 'À venir';
      case ExamTimeStatus.accessible: return 'Accessible';
      case ExamTimeStatus.lateBlocked: return 'Accès refusé';
      case ExamTimeStatus.past: return 'Terminée';
    }
  }
}

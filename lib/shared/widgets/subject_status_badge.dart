import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/exam_sim_palette.dart';
import '../../models/subject_model.dart';
import '../../models/submission_model.dart';

class SubjectStatusBadge extends StatelessWidget {
  final ExamTimeStatus? timeStatus;
  final SubmissionStatus? submissionStatus;

  const SubjectStatusBadge({super.key, this.timeStatus, this.submissionStatus});

  @override
  Widget build(BuildContext context) {
    final (label, color) = _resolve(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  (String, Color) _resolve(BuildContext context) {
    if (submissionStatus != null) {
      switch (submissionStatus!) {
        case SubmissionStatus.submitted:
        case SubmissionStatus.ocrDone:
        case SubmissionStatus.aiReviewed:
        case SubmissionStatus.pendingHuman:
        case SubmissionStatus.humanReviewed:
          return ('Correction en cours', AppColors.statusCorrecting);
        case SubmissionStatus.published:
          return ('Note publiée', AppColors.statusPublished);
        case SubmissionStatus.rejected:
          return ('Copie rejetée', AppColors.error);
        case SubmissionStatus.error:
          return ('Erreur traitement', AppColors.error);
      }
    }
    switch (timeStatus) {
      case ExamTimeStatus.upcoming:
        return ('À venir', AppColors.statusLocked);
      case ExamTimeStatus.accessible:
        return ('Accès ouvert', AppColors.statusOpen);
      case ExamTimeStatus.lateBlocked:
        return ('Accès refusé', AppColors.error);
      case ExamTimeStatus.past:
        return ('Terminée', AppColors.statusDone);
      default:
        return ('—', context.palette.textSecondary);
    }
  }
}

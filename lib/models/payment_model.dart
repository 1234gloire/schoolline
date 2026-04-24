import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentStatus { pending, approved, rejected }

class PaymentModel {
  final String id;
  final String userId;
  final String sessionId;
  final String sessionTitle;
  final double amount;
  final String proofFileRef;
  final PaymentStatus status;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final String? rejectionReason;

  const PaymentModel({
    required this.id,
    required this.userId,
    required this.sessionId,
    required this.sessionTitle,
    required this.amount,
    required this.proofFileRef,
    required this.status,
    required this.submittedAt,
    this.reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
  });

  factory PaymentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PaymentModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      sessionId: data['sessionId'] ?? '',
      sessionTitle: data['sessionTitle'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      proofFileRef: data['proofFileRef'] ?? '',
      status: PaymentStatus.values.firstWhere(
        (s) => s.name == (data['status'] ?? 'pending'),
        orElse: () => PaymentStatus.pending,
      ),
      submittedAt: (data['submittedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reviewedAt: (data['reviewedAt'] as Timestamp?)?.toDate(),
      reviewedBy: data['reviewedBy'],
      rejectionReason: data['rejectionReason'],
    );
  }

  bool get isPending => status == PaymentStatus.pending;
  bool get isApproved => status == PaymentStatus.approved;
  bool get isRejected => status == PaymentStatus.rejected;

  String get statusLabel {
    switch (status) {
      case PaymentStatus.pending:
        return 'En attente de validation';
      case PaymentStatus.approved:
        return 'Paiement validé';
      case PaymentStatus.rejected:
        return 'Paiement rejeté';
    }
  }
}

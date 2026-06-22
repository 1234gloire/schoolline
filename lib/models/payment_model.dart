import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentStatus { pending, approved, rejected }

/// provider : 'manual' (preuve uploadée) | 'pawapay' (mobile money automatique)
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
  final String provider;
  final String? transKey;
  final String? providerRef;

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
    this.provider = 'manual',
    this.transKey,
    this.providerRef,
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
      provider: data['provider'] ?? 'manual',
      transKey: data['transKey'],
      providerRef: data['providerRef'],
    );
  }

  bool get isPending => status == PaymentStatus.pending;
  bool get isApproved => status == PaymentStatus.approved;
  bool get isRejected => status == PaymentStatus.rejected;
  bool get isMobileMoney => provider == 'pawapay';

  /// En attente, sans preuve manuelle ni provider mobile money reconnu :
  /// aucun admin ni callback ne peut jamais la faire avancer (ex. ancien
  /// document orphelin d'une tentative interrompue). Doit pouvoir être
  /// relancée comme un nouveau paiement.
  bool get isGhostPending => isPending && !isMobileMoney && proofFileRef.isEmpty;

  String get statusLabel {
    switch (status) {
      case PaymentStatus.pending:
        return isMobileMoney ? 'Confirmation en cours' : 'En attente de validation';
      case PaymentStatus.approved:
        return 'Paiement validé';
      case PaymentStatus.rejected:
        return 'Paiement rejeté';
    }
  }
}

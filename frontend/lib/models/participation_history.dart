import 'post.dart';

class ParticipationHistory {
  const ParticipationHistory({
    required this.post,
    required this.participationId,
    required this.quantity,
    required this.settlementId,
    required this.settlementAmount,
    required this.paymentStatus,
    required this.pickupCompletedAt,
  });

  final Post post;
  final int participationId;
  final int quantity;
  final int? settlementId;
  final int? settlementAmount;
  final String? paymentStatus;
  final DateTime? pickupCompletedAt;

  factory ParticipationHistory.fromJson(Map<String, dynamic> json) {
    DateTime? nullableDate(String key) {
      final value = json[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    return ParticipationHistory(
      post: Post.fromJson(json),
      participationId: json['participation_id'] as int,
      quantity: json['quantity'] as int,
      settlementId: json['settlement_id'] as int?,
      settlementAmount: json['settlement_amount'] as int?,
      paymentStatus: json['payment_status'] as String?,
      pickupCompletedAt: nullableDate('pickup_completed_at'),
    );
  }
}

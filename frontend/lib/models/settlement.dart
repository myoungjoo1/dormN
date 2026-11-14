class Settlement {
  const Settlement({
    required this.id,
    required this.participationId,
    required this.amount,
    required this.paymentStatus,
    required this.sentAt,
    required this.confirmedAt,
    required this.createdAt,
  });

  final int id;
  final int participationId;
  final int amount;
  final String paymentStatus;
  final DateTime? sentAt;
  final DateTime? confirmedAt;
  final DateTime createdAt;

  factory Settlement.fromJson(Map<String, dynamic> json) {
    DateTime? nullableDate(String key) {
      final value = json[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    return Settlement(
      id: json['id'] as int,
      participationId: json['participation_id'] as int,
      amount: json['amount'] as int,
      paymentStatus: json['payment_status'] as String,
      sentAt: nullableDate('sent_at'),
      confirmedAt: nullableDate('confirmed_at'),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

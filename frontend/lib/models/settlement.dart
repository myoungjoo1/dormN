class Settlement {
  const Settlement({
    required this.id,
    required this.participationId,
    required this.quantity,
    required this.pickupCompletedAt,
    required this.amount,
    required this.paymentStatus,
    required this.sentAt,
    required this.confirmedAt,
    required this.createdAt,
  });

  final int id;
  final int participationId;
  final int? quantity;
  final DateTime? pickupCompletedAt;
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
      quantity: json['quantity'] as int?,
      pickupCompletedAt: nullableDate('pickup_completed_at'),
      amount: json['amount'] as int,
      paymentStatus: json['payment_status'] as String,
      sentAt: nullableDate('sent_at'),
      confirmedAt: nullableDate('confirmed_at'),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class SettlementAccount {
  const SettlementAccount({
    required this.bankName,
    required this.accountNumber,
    required this.accountHolderName,
    this.updatedAt,
    this.registeredAt,
  });

  final String bankName;
  final String accountNumber;
  final String accountHolderName;
  final DateTime? updatedAt;
  final DateTime? registeredAt;

  factory SettlementAccount.fromJson(Map<String, dynamic> json) {
    DateTime? nullableDate(String key) {
      final value = json[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    return SettlementAccount(
      bankName: json['bank_name'] as String,
      accountNumber: json['account_number'] as String,
      accountHolderName: json['account_holder_name'] as String,
      updatedAt: nullableDate('updated_at'),
      registeredAt: nullableDate('registered_at'),
    );
  }
}

class HostSettlementParticipant {
  const HostSettlementParticipant({
    required this.settlementId,
    required this.userId,
    required this.roomNumber,
    required this.quantity,
    required this.amount,
    required this.paymentStatus,
    required this.sentAt,
    required this.confirmedAt,
  });

  final int? settlementId;
  final String userId;
  final String? roomNumber;
  final int quantity;
  final int? amount;
  final String? paymentStatus;
  final DateTime? sentAt;
  final DateTime? confirmedAt;

  HostSettlementParticipant copyWith({
    String? paymentStatus,
    DateTime? confirmedAt,
  }) {
    return HostSettlementParticipant(
      settlementId: settlementId,
      userId: userId,
      roomNumber: roomNumber,
      quantity: quantity,
      amount: amount,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      sentAt: sentAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
    );
  }

  factory HostSettlementParticipant.fromJson(Map<String, dynamic> json) {
    DateTime? nullableDate(String key) {
      final value = json[key] as String?;
      return value == null ? null : DateTime.parse(value);
    }

    return HostSettlementParticipant(
      settlementId: json['settlement_id'] as int?,
      userId: json['user_id'] as String,
      roomNumber: json['room_number'] as String?,
      quantity: json['quantity'] as int,
      amount: json['amount'] as int?,
      paymentStatus: json['payment_status'] as String?,
      sentAt: nullableDate('sent_at'),
      confirmedAt: nullableDate('confirmed_at'),
    );
  }
}

class HostSettlementSummary {
  const HostSettlementSummary({
    required this.postId,
    required this.status,
    required this.totalPrice,
    required this.participantTotalAmount,
    required this.hostAmount,
    required this.participants,
  });

  final int postId;
  final String status;
  final int totalPrice;
  final int participantTotalAmount;
  final int hostAmount;
  final List<HostSettlementParticipant> participants;

  factory HostSettlementSummary.fromJson(Map<String, dynamic> json) {
    return HostSettlementSummary(
      postId: json['post_id'] as int,
      status: json['status'] as String,
      totalPrice: json['total_price'] as int,
      participantTotalAmount: json['participant_total_amount'] as int,
      hostAmount: json['host_amount'] as int,
      participants: (json['participants'] as List<dynamic>)
          .map(
            (participant) => HostSettlementParticipant.fromJson(
              Map<String, dynamic>.from(participant as Map),
            ),
          )
          .toList(),
    );
  }
}

class ParticipationQuote {
  const ParticipationQuote({
    required this.postId,
    required this.quantity,
    required this.estimatedAmount,
    required this.remainingQuantityAfterJoin,
  });

  final int postId;
  final int quantity;
  final int estimatedAmount;
  final int remainingQuantityAfterJoin;

  factory ParticipationQuote.fromJson(Map<String, dynamic> json) {
    return ParticipationQuote(
      postId: json['post_id'] as int,
      quantity: json['quantity'] as int,
      estimatedAmount: json['estimated_amount'] as int,
      remainingQuantityAfterJoin: json['remaining_quantity_after_join'] as int,
    );
  }
}

class MyParticipation {
  const MyParticipation({
    required this.isJoined,
    required this.participationId,
    required this.quantity,
  });

  final bool isJoined;
  final int? participationId;
  final int? quantity;

  factory MyParticipation.fromJson(Map<String, dynamic> json) {
    return MyParticipation(
      isJoined: json['is_joined'] as bool,
      participationId: json['participation_id'] as int?,
      quantity: json['quantity'] as int?,
    );
  }
}

class Participation {
  const Participation({
    required this.id,
    required this.postId,
    required this.userId,
    required this.quantity,
    required this.createdAt,
  });

  final int id;
  final int postId;
  final String userId;
  final int quantity;
  final DateTime createdAt;

  factory Participation.fromJson(Map<String, dynamic> json) {
    return Participation(
      id: json['id'] as int,
      postId: json['post_id'] as int,
      userId: json['user_id'] as String,
      quantity: json['quantity'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

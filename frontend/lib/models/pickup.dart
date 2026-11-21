class PickupCompletion {
  const PickupCompletion({
    required this.participationId,
    required this.postId,
    required this.pickupCompletedAt,
    required this.postStatus,
  });

  final int participationId;
  final int postId;
  final DateTime pickupCompletedAt;
  final String postStatus;

  factory PickupCompletion.fromJson(Map<String, dynamic> json) {
    return PickupCompletion(
      participationId: json['participation_id'] as int,
      postId: json['post_id'] as int,
      pickupCompletedAt:
          DateTime.parse(json['pickup_completed_at'] as String),
      postStatus: json['post_status'] as String,
    );
  }
}

class PickupParticipant {
  const PickupParticipant({
    required this.participationId,
    required this.roomNumber,
    required this.quantity,
    required this.pickupCompleted,
    required this.pickupCompletedAt,
  });

  final int participationId;
  final String? roomNumber;
  final int quantity;
  final bool pickupCompleted;
  final DateTime? pickupCompletedAt;

  factory PickupParticipant.fromJson(Map<String, dynamic> json) {
    final completedAt = json['pickup_completed_at'] as String?;
    return PickupParticipant(
      participationId: json['participation_id'] as int,
      roomNumber: json['room_number'] as String?,
      quantity: json['quantity'] as int,
      pickupCompleted: json['pickup_completed'] as bool,
      pickupCompletedAt:
          completedAt == null ? null : DateTime.parse(completedAt),
    );
  }
}

class PickupSummary {
  const PickupSummary({required this.participants});

  final List<PickupParticipant> participants;

  int get totalCount => participants.length;

  int get completedCount =>
      participants
          .where((participant) => participant.pickupCompletedAt != null)
          .length;

  factory PickupSummary.fromJson(List<dynamic> json) {
    return PickupSummary(
      participants: json
          .map(
            (participant) => PickupParticipant.fromJson(
              Map<String, dynamic>.from(participant as Map),
            ),
          )
          .toList(),
    );
  }
}

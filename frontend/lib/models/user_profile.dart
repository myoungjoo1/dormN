class UserProfile {
  const UserProfile({
    required this.id,
    required this.roomNumber,
    required this.dormVerified,
    required this.dormVerifiedAt,
    required this.createdAt,
  });

  final String id;
  final String? roomNumber;
  final bool dormVerified;
  final DateTime? dormVerifiedAt;
  final DateTime createdAt;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      roomNumber: json['room_number'] as String?,
      dormVerified: json['dorm_verified'] as bool,
      dormVerifiedAt: json['dorm_verified_at'] == null
          ? null
          : DateTime.parse(json['dorm_verified_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

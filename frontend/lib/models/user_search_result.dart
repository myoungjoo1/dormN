class UserSearchResult {
  const UserSearchResult({
    required this.userId,
    required this.roomNumber,
  });

  final String userId;
  final String roomNumber;

  factory UserSearchResult.fromJson(Map<String, dynamic> json) {
    return UserSearchResult(
      userId: json['user_id'] as String,
      roomNumber: json['room_number'] as String,
    );
  }
}

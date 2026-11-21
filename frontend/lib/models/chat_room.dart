class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.roomType,
    required this.postId,
    required this.productName,
    required this.otherUserId,
    required this.otherUserRoomNumber,
    required this.createdAt,
  });

  final int id;
  final String roomType;
  final int? postId;
  final String? productName;
  final String? otherUserId;
  final String? otherUserRoomNumber;
  final DateTime createdAt;

  bool get isGroup => roomType == 'GROUP';
  bool get isDirect => roomType == 'DM';

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: json['id'] as int,
      roomType: json['room_type'] as String,
      postId: json['post_id'] as int?,
      productName: json['product_name'] as String?,
      otherUserId: json['other_user_id'] as String?,
      otherUserRoomNumber: json['other_user_room_number'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderRoomNumber,
    required this.messageType,
    required this.body,
    required this.createdAt,
    required this.deletedAt,
  });

  final int id;
  final String? senderId;
  final String? senderRoomNumber;
  final String messageType;
  final String body;
  final DateTime createdAt;
  final DateTime? deletedAt;

  bool get isUserMessage => messageType == 'USER';
  bool get isSystemMessage => messageType == 'SYSTEM';
  bool get isDeleted => deletedAt != null;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      senderId: json['sender_id'] as String?,
      senderRoomNumber: json['sender_room_number'] as String?,
      messageType: json['message_type'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      deletedAt: json['deleted_at'] == null
          ? null
          : DateTime.parse(json['deleted_at'] as String),
    );
  }
}

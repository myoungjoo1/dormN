import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/chat_message.dart';

void main() {
  test('deleted message response is parsed as a tombstone', () {
    final message = ChatMessage.fromJson({
      'id': 1,
      'sender_id': '11111111-1111-1111-1111-111111111111',
      'sender_room_number': '717-1',
      'message_type': 'USER',
      'body': '삭제된 메시지입니다.',
      'created_at': '2026-11-28T09:00:00Z',
      'deleted_at': '2026-11-28T09:01:00Z',
    });

    expect(message.isDeleted, isTrue);
    expect(message.body, '삭제된 메시지입니다.');
  });
}

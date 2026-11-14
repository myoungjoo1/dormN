import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/models/post.dart';

void main() {
  test('parses a post list response item', () {
    final post = Post.fromJson({
      'id': 10,
      'author_id': '11111111-1111-1111-1111-111111111111',
      'product_name': '햇반 24개',
      'product_url': null,
      'image_url': null,
      'total_price': 22900,
      'total_quantity': 24,
      'host_quantity': 4,
      'deadline': '2026-11-20T12:00:00Z',
      'pickup_location': '기숙사 로비',
      'shortfall_policy': 'KEEP_BY_HOST',
      'status': 'RECRUITING',
      'created_at': '2026-11-15T12:00:00Z',
      'author_room_number': '717-1',
      'joined_quantity': 10,
      'remaining_quantity': 10,
      'participant_count': 2,
    });

    expect(post.productName, '햇반 24개');
    expect(post.filledQuantity, 14);
    expect(post.remainingQuantity, 10);
  });
}

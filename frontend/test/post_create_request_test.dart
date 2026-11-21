import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/models/post_create_request.dart';

void main() {
  final now = DateTime.utc(2026, 11, 17, 12);

  PostCreateRequest request({
    String productName = '햇반 24개',
    String? productUrl = 'https://shop.example/item/1',
    int totalPrice = 22900,
    int totalQuantity = 24,
    int hostQuantity = 4,
    DateTime? deadline,
    String pickupLocation = '기숙사 로비',
    String shortfallPolicy = PostCreateRequest.keepByHost,
  }) {
    return PostCreateRequest(
      productName: productName,
      productUrl: productUrl,
      imageUploadId: '11111111-1111-1111-1111-111111111111',
      totalPrice: totalPrice,
      totalQuantity: totalQuantity,
      hostQuantity: hostQuantity,
      deadline: deadline ?? DateTime.utc(2030, 1, 1),
      pickupLocation: pickupLocation,
      shortfallPolicy: shortfallPolicy,
    );
  }

  test('valid request serializes backend field names and UTC deadline', () {
    final value = request();

    value.validate(now: now);
    final json = value.toJson();

    expect(json['product_name'], '햇반 24개');
    expect(json['product_url'], 'https://shop.example/item/1');
    expect(json['image_upload_id'], '11111111-1111-1111-1111-111111111111');
    expect(json['deadline'], '2030-01-01T00:00:00.000Z');
    expect(json['shortfall_policy'], 'KEEP_BY_HOST');
  });

  test('calculates integer-safe recruitment estimates', () {
    final value = request();

    expect(value.estimatedUnitPrice, closeTo(22900 / 24, 0.000001));
    expect(value.estimatedHostAmount, 3816);
    expect(value.recruitmentQuantity, 20);
    expect(value.maximumHostShortfallAmount, 22900);
  });

  test('rejects invalid price, quantities, and past deadline', () {
    expect(
      () => request(totalPrice: 0).validate(now: now),
      throwsA(isA<PostCreateValidationException>()),
    );
    expect(
      () => request(totalQuantity: 0).validate(now: now),
      throwsA(isA<PostCreateValidationException>()),
    );
    expect(
      () => request(hostQuantity: 25).validate(now: now),
      throwsA(isA<PostCreateValidationException>()),
    );
    expect(
      () => request(deadline: now).validate(now: now),
      throwsA(isA<PostCreateValidationException>()),
    );
  });

  test('rejects blank text, invalid URL, and invalid policy', () {
    expect(
      () => request(productName: '   ').validate(now: now),
      throwsA(isA<PostCreateValidationException>()),
    );
    expect(
      () => request(productUrl: 'ftp://shop.example/item/1').validate(now: now),
      throwsA(isA<PostCreateValidationException>()),
    );
    expect(
      () => request(shortfallPolicy: 'UNKNOWN').validate(now: now),
      throwsA(isA<PostCreateValidationException>()),
    );
    expect(
      () => request(productName: 'a' * 201).validate(now: now),
      throwsA(isA<PostCreateValidationException>()),
    );
    expect(
      () => request(pickupLocation: ' ').validate(now: now),
      throwsA(isA<PostCreateValidationException>()),
    );
  });
}

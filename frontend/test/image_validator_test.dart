import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:frontend/core/image/image_validator.dart';

void main() {
  test('accepts a supported image within the size limit', () async {
    final file = XFile.fromData(
      Uint8List(1),
      path: 'product.webp',
    );

    await expectLater(validatePostImage(file), completes);
  });

  test('rejects unsupported formats and oversized files', () async {
    final unsupported = XFile.fromData(
      Uint8List(1),
      path: 'product.gif',
    );
    final oversized = XFile.fromData(
      Uint8List(maxPostImageBytes + 1),
      path: 'product.jpg',
    );

    await expectLater(
      validatePostImage(unsupported),
      throwsA(isA<ImageValidationException>()),
    );
    await expectLater(
      validatePostImage(oversized),
      throwsA(isA<ImageValidationException>()),
    );
  });
}

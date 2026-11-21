import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/api/api_exception.dart';
import 'package:frontend/features/posts/post_create_page.dart';
import 'package:frontend/models/product_preview.dart';

void main() {
  test('parses product name and image when both are returned', () {
    final preview = ProductPreview.fromJson({
      'product_url': 'https://shop.example/item/1',
      'product_name_suggestion': '상품명',
      'image_url': 'https://cdn.example/image.jpg',
    });

    expect(preview.productNameSuggestion, '상품명');
    expect(preview.imageUrl, 'https://cdn.example/image.jpg');
  });

  test('allows either preview field to be null', () {
    final nameOnly = ProductPreview.fromJson({
      'product_url': 'https://shop.example/item/1',
      'product_name_suggestion': '상품명',
      'image_url': null,
    });
    final imageOnly = ProductPreview.fromJson({
      'product_url': 'https://shop.example/item/1',
      'product_name_suggestion': null,
      'image_url': 'https://cdn.example/image.jpg',
    });

    expect(nameOnly.imageUrl, isNull);
    expect(imageOnly.productNameSuggestion, isNull);
  });

  testWidgets('loads a preview and keeps the name editable', (tester) async {
    final result = Completer<ProductPreview>();
    await tester.pumpWidget(
      MaterialApp(
        home: PostCreatePage(previewLoader: (_) => result.future),
      ),
    );

    await tester.enterText(
      find.byKey(const ValueKey('product-url')),
      'https://shop.example/item/1',
    );
    await tester.tap(find.byKey(const ValueKey('preview-button')));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    result.complete(
      const ProductPreview(
        productUrl: 'https://shop.example/item/1',
        productNameSuggestion: '자동 상품명',
        imageUrl: 'https://cdn.example/image.jpg',
      ),
    );
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('product-name'))).controller!.text,
      '자동 상품명',
    );
    expect(find.byType(Image), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('product-name')), '수정한 상품명');
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('product-name'))).controller!.text,
      '수정한 상품명',
    );

    await tester.enterText(
      find.byKey(const ValueKey('product-url')),
      'https://shop.example/item/2',
    );
    await tester.pump();
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('validates URL and preserves input after API failure', (tester) async {
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: PostCreatePage(
          previewLoader: (_) async {
            called = true;
            throw const ApiException(422, 'INVALID_PRODUCT_URL', 'invalid');
          },
        ),
      ),
    );

    await tester.enterText(find.byKey(const ValueKey('product-name')), '직접 입력 상품');
    await tester.enterText(find.byKey(const ValueKey('product-url')), 'ftp://invalid');
    tester.testTextInput.hide();
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('preview-button')));
    await tester.tap(find.byKey(const ValueKey('preview-button')));
    await tester.pump();
    expect(find.text('상품 링크는 HTTP 또는 HTTPS URL이어야 합니다.'), findsOneWidget);
    expect(called, isFalse);

    await tester.enterText(
      find.byKey(const ValueKey('product-url')),
      'https://shop.example/item/1',
    );
    tester.testTextInput.hide();
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('preview-button')));
    await tester.tap(find.byKey(const ValueKey('preview-button')));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('product-name'))).controller!.text,
      '직접 입력 상품',
    );
    expect(find.text('상품 정보를 불러오지 못했습니다. 링크를 확인해주세요.'), findsNWidgets(2));
  });
}

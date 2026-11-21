import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/posts/post_create_page.dart';

void main() {
  Widget buildPage() {
    return const MaterialApp(home: PostCreatePage());
  }

  testWidgets('validates step one before moving forward', (tester) async {
    await tester.pumpWidget(buildPage());

    await tester.tap(find.text('다음'));
    await tester.pump();

    expect(find.text('상품명을 입력해주세요.'), findsOneWidget);
    expect(find.text('상품 정보를 입력해주세요'), findsOneWidget);
  });

  testWidgets('moves through steps and keeps entered values', (tester) async {
    await tester.pumpWidget(buildPage());

    await tester.enterText(find.byKey(const ValueKey('product-name')), '테스트 상품');
    tester.testTextInput.hide();
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(find.text('구매 조건을 정해주세요'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('total-price')), '10000');
    await tester.enterText(find.byKey(const ValueKey('total-quantity')), '10');
    await tester.enterText(find.byKey(const ValueKey('host-quantity')), '2');
    await tester.pump();

    expect(find.text('1000원'), findsOneWidget);
    expect(find.text('2000원'), findsOneWidget);
    expect(find.text('8개'), findsOneWidget);

    tester.testTextInput.hide();
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(find.text('모집 조건을 정해주세요'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('total-price'))).controller!.text,
      '10000',
    );

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('product-name'))).controller!.text,
      '테스트 상품',
    );
  });

  testWidgets('shows recruitment deadline validation on step three', (tester) async {
    await tester.pumpWidget(buildPage());

    await tester.enterText(find.byKey(const ValueKey('product-name')), '테스트 상품');
    tester.testTextInput.hide();
    await tester.pump();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('total-price')), '10000');
    await tester.enterText(find.byKey(const ValueKey('total-quantity')), '10');
    await tester.enterText(find.byKey(const ValueKey('host-quantity')), '2');
    tester.testTextInput.hide();
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('최종 확인'));
    await tester.pumpAndSettle();
    expect(find.text('모집 마감 일시는 현재 시각 이후여야 합니다.'), findsOneWidget);
  });
}

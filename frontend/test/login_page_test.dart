import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/features/auth/login_page.dart';

void main() {
  testWidgets('shows the DormN login introduction', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));

    expect(find.text('기숙사 룸메들과 함께하는 실속 공동구매'), findsOneWidget);
    expect(find.text('카카오로 시작하기'), findsOneWidget);
    expect(find.text('로그인 없이 둘러보기  ›'), findsOneWidget);
  });
}

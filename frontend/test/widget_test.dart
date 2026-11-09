import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('shows configuration guidance without Supabase settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DormNApp());

    expect(find.textContaining('Supabase 설정이 없습니다.'), findsOneWidget);
  });
}

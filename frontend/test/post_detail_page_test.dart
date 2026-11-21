import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/api/api_exception.dart';
import 'package:frontend/features/posts/post_detail_page.dart';
import 'package:frontend/models/participation.dart';
import 'package:frontend/models/post.dart';

Post buildPost({String status = 'RECRUITING', int remainingQuantity = 6}) {
  return Post(
    id: 1,
    authorId: '00000000-0000-0000-0000-000000000001',
    productName: 'Test product',
    productUrl: 'https://example.com/item',
    imageUrl: null,
    totalPrice: 22900,
    totalQuantity: 24,
    hostQuantity: 4,
    deadline: DateTime.now().add(const Duration(hours: 2)),
    pickupLocation: 'Dorm lobby',
    shortfallPolicy: 'KEEP_BY_HOST',
    status: status,
    createdAt: DateTime.now(),
    authorRoomNumber: '717-1호',
    joinedQuantity: 14,
    remainingQuantity: remainingQuantity,
    participantCount: 3,
  );
}

Widget buildPage({
  required PostLoader loader,
  String? currentUserId,
  ParticipationLoader? participationLoader,
  QuoteLoader? quoteLoader,
  JoinLoader? joinLoader,
}) {
  return MaterialApp(
    home: PostDetailPage(
      postId: 1,
      postLoader: loader,
      currentUserIdProvider: () => currentUserId,
      accessTokenProvider: () => 'access-token',
      participationLoader:
          participationLoader ??
          (_, _) async => const MyParticipation(
            isJoined: false,
            participationId: null,
            quantity: null,
          ),
      quoteLoader:
          quoteLoader ??
          ((postId, quantity, token) async {
            return ParticipationQuote(
              postId: postId,
              quantity: quantity,
              estimatedAmount: 22900 * quantity ~/ 24,
              remainingQuantityAfterJoin: 6 - quantity,
            );
          }),
      joinLoader:
          joinLoader ??
          ((postId, quantity, token) async {
            return Participation(
              id: 99,
              postId: postId,
              userId: '00000000-0000-0000-0000-000000000002',
              quantity: quantity,
              createdAt: DateTime.now(),
            );
          }),
    ),
  );
}

void main() {
  testWidgets('loads and displays the server post', (tester) async {
    final post = buildPost();
    var calls = 0;
    await tester.pumpWidget(
      buildPage(
        loader: (_) async {
          calls += 1;
          return post;
        },
        currentUserId: '00000000-0000-0000-0000-000000000002',
      ),
    );
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Test product'), findsOneWidget);
    expect(find.text('남은 모집 수량 6개'), findsOneWidget);
    expect(find.text('공동구매 참여하기'), findsOneWidget);
  });

  testWidgets('retries after a detail request failure', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      buildPage(
        loader: (_) async {
          calls += 1;
          if (calls == 1) {
            throw const ApiException(503, 'TEMPORARY', 'temporary');
          }
          return buildPost();
        },
        currentUserId: '00000000-0000-0000-0000-000000000002',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('게시글을 불러오지 못했습니다.'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('Test product'), findsOneWidget);
  });

  testWidgets('shows a not-found message without retry for 404', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildPage(
        loader: (_) async =>
            throw const ApiException(404, 'POST_NOT_FOUND', 'not found'),
        currentUserId: '00000000-0000-0000-0000-000000000002',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('게시글을 찾을 수 없습니다.'), findsOneWidget);
    expect(find.text('다시 시도'), findsNothing);
  });

  testWidgets('hides participation area for the post author', (tester) async {
    await tester.pumpWidget(
      buildPage(
        loader: (_) async => buildPost(),
        currentUserId: '00000000-0000-0000-0000-000000000001',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('공동구매 참여하기'), findsNothing);
    expect(find.text('Test product'), findsOneWidget);
  });

  testWidgets('shows the current participation instead of join controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildPage(
        loader: (_) async => buildPost(),
        currentUserId: '00000000-0000-0000-0000-000000000002',
        participationLoader: (_, _) async => const MyParticipation(
          isJoined: true,
          participationId: 55,
          quantity: 4,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('참여 완료'), findsOneWidget);
    expect(find.text('신청 수량 4개'), findsOneWidget);
    expect(find.text('공동구매 참여하기'), findsNothing);
  });

  testWidgets('disables joining when quote lookup fails', (tester) async {
    await tester.pumpWidget(
      buildPage(
        loader: (_) async => buildPost(),
        currentUserId: '00000000-0000-0000-0000-000000000002',
        quoteLoader: (_, _, _) async {
          throw const ApiException(409, 'INSUFFICIENT_QUANTITY', 'not enough');
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('예상 금액을 조회하지 못했습니다. 수량을 다시 선택해주세요.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('updates quantity and clamps to refreshed remaining quantity', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildPage(
        loader: (_) async => buildPost(remainingQuantity: 2),
        currentUserId: '00000000-0000-0000-0000-000000000002',
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('2개'), findsOneWidget);
    expect(find.text('1908원'), findsOneWidget);
  });

  testWidgets('confirms and submits a participation', (tester) async {
    var postCalls = 0;
    var joined = false;
    var closed = false;
    var joinCalls = 0;
    await tester.pumpWidget(
      buildPage(
        loader: (_) async {
          postCalls += 1;
          return buildPost(
            status: closed ? 'CLOSED' : 'RECRUITING',
            remainingQuantity: closed ? 0 : 6,
          );
        },
        currentUserId: '00000000-0000-0000-0000-000000000002',
        participationLoader: (_, _) async => MyParticipation(
          isJoined: joined,
          participationId: joined ? 99 : null,
          quantity: joined ? 1 : null,
        ),
        joinLoader: (postId, quantity, token) async {
          joinCalls += 1;
          joined = true;
          closed = true;
          return Participation(
            id: 99,
            postId: postId,
            userId: '00000000-0000-0000-0000-000000000002',
            quantity: quantity,
            createdAt: DateTime.now(),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('공동구매 참여하기'));
    await tester.pumpAndSettle();
    expect(find.text('신청 수량'), findsOneWidget);
    expect(find.text('예상 부담 금액'), findsOneWidget);
    expect(find.text('픽업 장소'), findsOneWidget);
    expect(find.text('모집 마감 후 최종 정산 금액이 확정됩니다.'), findsOneWidget);

    await tester.tap(find.text('참여 확정'));
    await tester.pumpAndSettle();

    expect(joinCalls, 1);
    expect(postCalls, greaterThanOrEqualTo(2));
    expect(find.text('참여 완료'), findsOneWidget);
    expect(find.text('신청 수량 1개'), findsOneWidget);
    expect(find.text('모집 마감'), findsOneWidget);
  });

  testWidgets('does not submit when participation is cancelled', (
    tester,
  ) async {
    var joinCalls = 0;
    await tester.pumpWidget(
      buildPage(
        loader: (_) async => buildPost(),
        currentUserId: '00000000-0000-0000-0000-000000000002',
        joinLoader: (_, _, _) async {
          joinCalls += 1;
          throw StateError('should not be called');
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('공동구매 참여하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();

    expect(joinCalls, 0);
    expect(find.text('공동구매 참여하기'), findsOneWidget);
  });

  testWidgets('prevents duplicate participation requests while submitting', (
    tester,
  ) async {
    final pending = Completer<Participation>();
    var joinCalls = 0;
    await tester.pumpWidget(
      buildPage(
        loader: (_) async => buildPost(),
        currentUserId: '00000000-0000-0000-0000-000000000002',
        joinLoader: (_, _, _) {
          joinCalls += 1;
          return pending.future;
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('공동구매 참여하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('참여 확정'));
    await tester.pump();
    expect(joinCalls, 1);

    final joinButton = find.text('참여 처리 중');
    expect(joinButton, findsOneWidget);
    await tester.tap(joinButton);
    expect(joinCalls, 1);

    pending.complete(
      Participation(
        id: 99,
        postId: 1,
        userId: '00000000-0000-0000-0000-000000000002',
        quantity: 1,
        createdAt: DateTime.now(),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('refreshes after a join conflict without resubmitting', (
    tester,
  ) async {
    var postCalls = 0;
    var joinCalls = 0;
    await tester.pumpWidget(
      buildPage(
        loader: (_) async {
          postCalls += 1;
          return buildPost(remainingQuantity: postCalls == 1 ? 6 : 2);
        },
        currentUserId: '00000000-0000-0000-0000-000000000002',
        joinLoader: (_, _, _) async {
          joinCalls += 1;
          throw const ApiException(
            409,
            'INSUFFICIENT_QUANTITY',
            'not enough quantity',
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('공동구매 참여하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('참여 확정'));
    await tester.pumpAndSettle();

    expect(joinCalls, 1);
    expect(postCalls, greaterThanOrEqualTo(2));
    expect(find.text('남은 모집 수량이 부족합니다.'), findsOneWidget);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

import 'package:frontend/core/api/api_exception.dart';
import 'package:frontend/features/posts/post_create_page.dart';
import 'package:frontend/models/post_create_request.dart';

void main() {
  final deadline = DateTime.now().add(const Duration(hours: 2));

  Future<void> fillValidForm(
    WidgetTester tester, {
    String? productUrl,
  }) async {
    if (productUrl != null) {
      await tester.enterText(
        find.byKey(const ValueKey('product-url')),
        productUrl,
      );
    }
    await tester.enterText(
      find.byKey(const ValueKey('product-name')),
      'Test product',
    );
    await _tapBottom(tester);

    await tester.enterText(find.byKey(const ValueKey('total-price')), '10000');
    await tester.enterText(find.byKey(const ValueKey('total-quantity')), '10');
    await tester.enterText(find.byKey(const ValueKey('host-quantity')), '2');
    await _tapBottom(tester);

    await tester.enterText(
      find.byKey(const ValueKey('pickup-location')),
      'Dorm lobby',
    );
    await _tapBottom(tester);
  }

  testWidgets('registers URL-only and no-image posts', (tester) async {
    final requests = <PostCreateRequest>[];
    var uploadCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PostCreatePage(
          initialDeadline: deadline,
          accessTokenProvider: () => 'access-token',
          imageUploader: (path, token) async {
            uploadCalls += 1;
            return 'upload-id';
          },
          postCreator: (request, token) async {
            requests.add(request);
            return {'id': requests.length};
          },
        ),
      ),
    );

    await fillValidForm(tester, productUrl: 'https://shop.example/item');
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    expect(uploadCalls, 0);
    expect(requests.single.productUrl, 'https://shop.example/item');
    expect(requests.single.imageUploadId, isNull);
  });

  testWidgets('uploads a directly selected image only at registration', (tester) async {
    final imageFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}dormn-post.png',
    )
      ..writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ));
    addTearDown(() {
      if (imageFile.existsSync()) imageFile.deleteSync();
    });

    var uploadCalls = 0;
    String? uploadedPath;
    PostCreateRequest? createdRequest;
    await tester.pumpWidget(
      MaterialApp(
        home: PostCreatePage(
          initialDeadline: deadline,
          initialSelectedImage: XFile(imageFile.path),
          accessTokenProvider: () => 'access-token',
          imageUploader: (path, token) async {
            uploadCalls += 1;
            uploadedPath = path;
            return 'upload-id';
          },
          postCreator: (request, token) async {
            createdRequest = request;
            return {'id': 1};
          },
        ),
      ),
    );

    await fillValidForm(tester);
    expect(uploadCalls, 0);
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    expect(uploadCalls, 1);
    expect(uploadedPath, imageFile.path);
    expect(createdRequest?.imageUploadId, 'upload-id');
  });

  testWidgets('stops registration when image upload fails', (tester) async {
    final imageFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}dormn-post-fail.png',
    )
      ..writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ));
    addTearDown(() {
      if (imageFile.existsSync()) imageFile.deleteSync();
    });

    var postCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PostCreatePage(
          initialDeadline: deadline,
          initialSelectedImage: XFile(imageFile.path),
          accessTokenProvider: () => 'access-token',
          imageUploader: (path, token) async {
            throw const ApiException(503, 'IMAGE_UPLOAD_UNAVAILABLE', 'temporary');
          },
          postCreator: (request, token) async {
            postCalls += 1;
            return {'id': 1};
          },
        ),
      ),
    );

    await fillValidForm(tester);
    await tester.tap(find.byType(FilledButton).last);
    await tester.pumpAndSettle();

    expect(postCalls, 0);
  });

  testWidgets('keeps upload id for post retry and prevents duplicate submit', (tester) async {
    var uploadCalls = 0;
    var postCalls = 0;
    final firstPost = Completer<Map<String, dynamic>>();
    final imageFile = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}dormn-post-retry.png',
    )
      ..writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ));
    addTearDown(() {
      if (imageFile.existsSync()) imageFile.deleteSync();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: PostCreatePage(
          initialDeadline: deadline,
          initialSelectedImage: XFile(imageFile.path),
          accessTokenProvider: () => 'access-token',
          imageUploader: (path, token) async {
            uploadCalls += 1;
            return 'upload-id';
          },
          postCreator: (request, token) async {
            postCalls += 1;
            if (postCalls == 1) {
              return firstPost.future;
            }
            throw const ApiException(503, 'TEMPORARY', 'temporary');
          },
        ),
      ),
    );

    await fillValidForm(tester);
    await tester.tap(find.byType(FilledButton).last);
    await tester.pump();
    expect(uploadCalls, 1);
    expect(postCalls, 1);

    await tester.tap(find.byType(FilledButton).last);
    await tester.pump();
    expect(uploadCalls, 1);
    expect(postCalls, 1);

    firstPost.completeError(const ApiException(503, 'TEMPORARY', 'temporary'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton).last);
    await tester.pump();
    expect(uploadCalls, 1);
    expect(postCalls, 2);
  });
}

Future<void> _tapBottom(WidgetTester tester) async {
  tester.testTextInput.hide();
  await tester.pump();
  await tester.tap(find.byType(FilledButton).last);
  await tester.pumpAndSettle();
}

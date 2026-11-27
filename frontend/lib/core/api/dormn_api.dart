import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/chat_message.dart';
import '../../models/chat_room.dart';
import '../../models/post.dart';
import '../../models/post_create_request.dart';
import '../../models/participation.dart';
import '../../models/participation_history.dart';
import '../../models/pickup.dart';
import '../../models/product_preview.dart';
import '../../models/settlement.dart';
import '../../models/user_search_result.dart';
import '../../models/user_profile.dart';
import '../../models/location_verification.dart';
import 'api_exception.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

class DormNApi {
  const DormNApi();

  Future<UserProfile> getMyProfile(
    String accessToken, {
    Duration? timeout,
  }) async {
    final data = await get(
      '/users/me',
      headers: {'Authorization': 'Bearer $accessToken'},
      timeout: timeout,
    );
    return UserProfile.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<UserProfile> completeDormVerification(String accessToken) async {
    final data = await post(
      '/users/me/dorm-verification',
      headers: {'Authorization': 'Bearer $accessToken'},
      timeout: const Duration(seconds: 15),
    );
    if (data is! Map) {
      throw const ApiException(
        0,
        'INVALID_RESPONSE',
        '최종 기숙사 인증 응답이 올바르지 않습니다.',
      );
    }
    return UserProfile.fromJson(Map<String, dynamic>.from(data));
  }

  Future<LocationVerificationStatus> submitLocationCheck({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required String accessToken,
  }) async {
    final data = await post(
      '/users/me/location-check',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_meters': accuracyMeters,
      },
      timeout: const Duration(seconds: 15),
    );
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', 'GPS 인증 응답이 올바르지 않습니다.');
    }
    return LocationVerificationStatus.fromJson(Map<String, dynamic>.from(data));
  }

  Future<LocationVerificationStatus> getLocationVerificationStatus({
    required String accessToken,
  }) async {
    final data = await get(
      '/users/me/location-verification',
      headers: {'Authorization': 'Bearer $accessToken'},
      timeout: const Duration(seconds: 15),
    );
    if (data is! Map) {
      throw const ApiException(
        0,
        'INVALID_RESPONSE',
        'GPS 인증 상태 응답이 올바르지 않습니다.',
      );
    }
    return LocationVerificationStatus.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<UserSearchResult>> searchUsersByRoomNumber({
    required String roomNumber,
    required String accessToken,
  }) async {
    final normalizedRoomNumber = roomNumber.trim();
    if (!RegExp(r'^[0-9]{3,4}-[1-9][0-9]*$').hasMatch(normalizedRoomNumber)) {
      throw const ApiException(422, 'INVALID_ROOM_NUMBER', '호실 번호 형식을 확인해주세요.');
    }

    final data = await get(
      '/users/search?room_number=${Uri.encodeQueryComponent(normalizedRoomNumber)}',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! List) {
      throw const ApiException(0, 'INVALID_RESPONSE', '사용자 검색 응답이 올바르지 않습니다.');
    }
    return data
        .map(
          (user) =>
              UserSearchResult.fromJson(Map<String, dynamic>.from(user as Map)),
        )
        .toList();
  }

  Future<List<Post>> getPosts() async {
    final data = await get('/posts');
    if (data is! List) {
      throw const ApiException(0, 'INVALID_RESPONSE', '목록 응답이 올바르지 않습니다.');
    }
    return data
        .map((post) => Post.fromJson(Map<String, dynamic>.from(post as Map)))
        .toList();
  }

  Future<Post> getPost(int postId) async {
    final data = await get('/posts/$postId');
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '게시글 상세 응답이 올바르지 않습니다.');
    }
    return Post.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<Post>> getMyPosts({required String accessToken}) async {
    final data = await get(
      '/users/me/posts',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! List) {
      throw const ApiException(0, 'INVALID_RESPONSE', '모집 내역 응답이 올바르지 않습니다.');
    }
    return data
        .map((post) => Post.fromJson(Map<String, dynamic>.from(post as Map)))
        .toList();
  }

  Future<List<ParticipationHistory>> getMyParticipations({
    required String accessToken,
  }) async {
    final data = await get(
      '/users/me/participations',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! List) {
      throw const ApiException(0, 'INVALID_RESPONSE', '참여 내역 응답이 올바르지 않습니다.');
    }
    return data
        .map(
          (item) => ParticipationHistory.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Future<List<ChatRoom>> getChatRooms({required String accessToken}) async {
    final data = await get(
      '/chat/rooms',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! List) {
      throw const ApiException(0, 'INVALID_RESPONSE', '채팅방 목록 응답이 올바르지 않습니다.');
    }
    return data
        .map(
          (room) => ChatRoom.fromJson(Map<String, dynamic>.from(room as Map)),
        )
        .toList();
  }

  Future<ChatRoom> getPostChat({
    required int postId,
    required String accessToken,
  }) async {
    final data = await get(
      '/posts/$postId/chat',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! Map) {
      throw const ApiException(
        0,
        'INVALID_RESPONSE',
        '공동구매 채팅방 응답이 올바르지 않습니다.',
      );
    }
    return ChatRoom.fromJson(Map<String, dynamic>.from(data));
  }

  Future<ChatRoom> createDirectChat({
    required String userId,
    required String accessToken,
  }) async {
    final data = await post(
      '/chat/direct/$userId',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '1:1 채팅방 응답이 올바르지 않습니다.');
    }
    return ChatRoom.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<ChatMessage>> getRoomMessages({
    required int roomId,
    required String accessToken,
    int? beforeId,
    int limit = 50,
  }) async {
    if (limit < 1 || limit > 50) {
      throw ArgumentError.value(
        limit,
        'limit',
        'limit must be between 1 and 50',
      );
    }

    final query = <String>['limit=$limit'];
    if (beforeId != null) query.add('before_id=$beforeId');
    final data = await get(
      '/chat/rooms/$roomId/messages?${query.join('&')}',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! List) {
      throw const ApiException(0, 'INVALID_RESPONSE', '메시지 목록 응답이 올바르지 않습니다.');
    }
    return data
        .map(
          (message) =>
              ChatMessage.fromJson(Map<String, dynamic>.from(message as Map)),
        )
        .toList();
  }

  Future<ChatMessage> sendChatMessage({
    required int roomId,
    required String body,
    required String accessToken,
  }) async {
    final trimmedBody = body.trim();
    if (trimmedBody.isEmpty) {
      throw const ApiException(422, 'INVALID_MESSAGE', '메시지를 입력해주세요.');
    }
    if (trimmedBody.length > 2000) {
      throw const ApiException(
        422,
        'INVALID_MESSAGE',
        '메시지는 2,000자 이내로 입력해주세요.',
      );
    }

    final data = await post(
      '/chat/rooms/$roomId/messages',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: {'body': trimmedBody},
    );
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '메시지 전송 응답이 올바르지 않습니다.');
    }
    return ChatMessage.fromJson(Map<String, dynamic>.from(data));
  }

  Future<ChatMessage> deleteChatMessage({
    required int roomId,
    required int messageId,
    required String accessToken,
  }) async {
    final data = await delete(
      '/chat/rooms/$roomId/messages/$messageId',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '메시지 삭제 응답이 올바르지 않습니다.');
    }
    return ChatMessage.fromJson(Map<String, dynamic>.from(data));
  }

  Future<ParticipationQuote> quoteParticipation({
    required int postId,
    required int quantity,
    required String accessToken,
  }) async {
    final data = await post(
      '/posts/$postId/quote',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: {'quantity': quantity},
    );
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '예상 금액 응답이 올바르지 않습니다.');
    }
    return ParticipationQuote.fromJson(Map<String, dynamic>.from(data));
  }

  Future<MyParticipation> getMyParticipation({
    required int postId,
    required String accessToken,
  }) async {
    final data = await get(
      '/posts/$postId/participation/me',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '참여 여부 응답이 올바르지 않습니다.');
    }
    return MyParticipation.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Participation> joinPost({
    required int postId,
    required int quantity,
    required String accessToken,
  }) async {
    final data = await post(
      '/posts/$postId/join',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: {'quantity': quantity},
    );
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '참여 응답이 올바르지 않습니다.');
    }
    return Participation.fromJson(Map<String, dynamic>.from(data));
  }

  Future<PickupCompletion> completePickup({
    required int participationId,
    required String accessToken,
  }) async {
    final data = await post(
      '/participations/$participationId/pickup',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '픽업 완료 응답이 올바르지 않습니다.');
    }
    return PickupCompletion.fromJson(Map<String, dynamic>.from(data));
  }

  Future<PickupSummary> getPostPickups({
    required int postId,
    required String accessToken,
  }) async {
    final data = await get(
      '/posts/$postId/pickups',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! List) {
      throw const ApiException(0, 'INVALID_RESPONSE', '픽업 현황 응답이 올바르지 않습니다.');
    }
    return PickupSummary.fromJson(data);
  }

  Future<Settlement> getMySettlement({
    required int postId,
    required String accessToken,
  }) async {
    final data = await get(
      '/posts/$postId/settlement/me',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '개인 정산 응답이 올바르지 않습니다.');
    }
    return Settlement.fromJson(Map<String, dynamic>.from(data));
  }

  Future<SettlementAccount> getPostSettlementAccount({
    required int postId,
    required String accessToken,
  }) async {
    final data = await get(
      '/posts/$postId/settlement-account',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '거래 계좌 응답이 올바르지 않습니다.');
    }
    return SettlementAccount.fromJson(Map<String, dynamic>.from(data));
  }

  Future<SettlementAccount?> getMySettlementAccount({
    required String accessToken,
  }) async {
    final data = await get(
      '/users/me/settlement-account',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data == null) return null;
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '기본 계좌 응답이 올바르지 않습니다.');
    }
    return SettlementAccount.fromJson(Map<String, dynamic>.from(data));
  }

  Future<SettlementAccount> upsertMySettlementAccount({
    required String bankName,
    required String accountNumber,
    required String accountHolderName,
    required String accessToken,
  }) async {
    final data = await put(
      '/users/me/settlement-account',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: {
        'bank_name': bankName,
        'account_number': accountNumber,
        'account_holder_name': accountHolderName,
      },
    );
    if (data is! Map) {
      throw const ApiException(
        0,
        'INVALID_RESPONSE',
        '기본 계좌 저장 응답이 올바르지 않습니다.',
      );
    }
    return SettlementAccount.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Map<String, dynamic>> confirmPostSettlementAccount({
    required int postId,
    required String accessToken,
  }) async {
    final data = await post(
      '/posts/$postId/settlement-account',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! Map) {
      throw const ApiException(
        0,
        'INVALID_RESPONSE',
        '거래 계좌 확정 응답이 올바르지 않습니다.',
      );
    }
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> updatePostStatus({
    required int postId,
    required String status,
    required String accessToken,
  }) async {
    final data = await patch(
      '/posts/$postId/status',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: {'status': status},
    );
    if (data is! Map) {
      throw const ApiException(
        0,
        'INVALID_RESPONSE',
        '거래 상태 변경 응답이 올바르지 않습니다.',
      );
    }
    return Map<String, dynamic>.from(data);
  }

  Future<Settlement> markSettlementSent({
    required int settlementId,
    required String accessToken,
  }) async {
    final data = await post(
      '/settlements/$settlementId/sent',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '송금 상태 응답이 올바르지 않습니다.');
    }
    return Settlement.fromJson(Map<String, dynamic>.from(data));
  }

  Future<HostSettlementSummary> getHostSettlements({
    required int postId,
    required String accessToken,
  }) async {
    final data = await get(
      '/posts/$postId/settlements',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! Map) {
      throw const ApiException(
        0,
        'INVALID_RESPONSE',
        '모집자 정산 목록 응답이 올바르지 않습니다.',
      );
    }
    return HostSettlementSummary.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Settlement> confirmSettlement({
    required int settlementId,
    required String accessToken,
  }) async {
    final data = await post(
      '/settlements/$settlementId/confirm',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '입금 확인 응답이 올바르지 않습니다.');
    }
    return Settlement.fromJson(Map<String, dynamic>.from(data));
  }

  Future<ProductPreview> previewProduct(String productUrl) async {
    final data = await post(
      '/products/preview',
      body: {'product_url': productUrl},
    );
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '상품 정보 응답이 올바르지 않습니다.');
    }
    return ProductPreview.fromJson(Map<String, dynamic>.from(data));
  }

  Future<String> uploadPostImage({
    required String filePath,
    required String accessToken,
  }) async {
    final data = await uploadImage(
      '/post-images',
      filePath: filePath,
      accessToken: accessToken,
    );
    if (data is! Map || data['upload_id'] is! String) {
      throw const ApiException(0, 'INVALID_RESPONSE', '이미지 업로드 응답이 올바르지 않습니다.');
    }
    return data['upload_id'] as String;
  }

  Future<Map<String, dynamic>> createPost({
    required PostCreateRequest request,
    required String accessToken,
  }) async {
    final data = await post(
      '/posts',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: request.toJson(),
    );
    if (data is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '게시글 등록 응답이 올바르지 않습니다.');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Duration? timeout,
  }) => _request('GET', path, headers: headers, timeout: timeout);

  Future<dynamic> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) => _request('POST', path, headers: headers, body: body, timeout: timeout);

  Future<dynamic> patch(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) => _request('PATCH', path, headers: headers, body: body);

  Future<dynamic> put(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) => _request('PUT', path, headers: headers, body: body);

  Future<dynamic> delete(String path, {Map<String, String>? headers}) =>
      _request('DELETE', path, headers: headers);

  Future<dynamic> uploadImage(
    String path, {
    required String filePath,
    required String accessToken,
    String fieldName = 'file',
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$apiBaseUrl$path'))
      ..headers['Authorization'] = 'Bearer $accessToken'
      ..headers['Accept'] = 'application/json'
      ..files.add(await http.MultipartFile.fromPath(fieldName, filePath));

    final response = await http.Response.fromStream(await request.send());
    return _parseResponse(response);
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    final request = http.Request(method, Uri.parse('$apiBaseUrl$path'))
      ..headers.addAll({
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        ...?headers,
      });

    if (body != null) {
      request.body = jsonEncode(body);
    }

    final response = await http.Response.fromStream(
      await (timeout == null
          ? request.send()
          : request.send().timeout(timeout)),
    );
    return _parseResponse(response);
  }

  dynamic _parseResponse(http.Response response) {
    final body = _decodeBody(response);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body is Map ? body['error'] : null;
      if (error is Map) {
        throw ApiException(
          response.statusCode,
          error['code']?.toString() ?? 'HTTP_ERROR',
          error['message']?.toString() ?? '요청을 처리하지 못했습니다.',
        );
      }
      throw ApiException(
        response.statusCode,
        'HTTP_ERROR',
        '요청을 처리하지 못했습니다. (${response.statusCode})',
      );
    }

    if (body is! Map) {
      throw const ApiException(0, 'INVALID_RESPONSE', '서버 응답이 올바르지 않습니다.');
    }

    return body['data'];
  }

  dynamic _decodeBody(http.Response response) {
    if (response.bodyBytes.isEmpty) {
      return <String, dynamic>{};
    }

    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ApiException(0, 'INVALID_RESPONSE', '서버 응답이 올바르지 않습니다.');
    }
  }
}

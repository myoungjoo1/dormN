import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/post.dart';
import '../../models/post_create_request.dart';
import '../../models/participation.dart';
import '../../models/product_preview.dart';
import '../../models/user_profile.dart';
import 'api_exception.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

class DormNApi {
  const DormNApi();

  Future<UserProfile> getMyProfile(String accessToken) async {
    final data = await get(
      '/users/me',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return UserProfile.fromJson(Map<String, dynamic>.from(data as Map));
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

  Future<dynamic> get(String path, {Map<String, String>? headers}) =>
      _request('GET', path, headers: headers);

  Future<dynamic> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) => _request('POST', path, headers: headers, body: body);

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

    final response = await http.Response.fromStream(await request.send());
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

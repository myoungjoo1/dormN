import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/post.dart';
import '../../models/user_profile.dart';
import 'api_exception.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

class DormNApi {
  const DormNApi();

  Future<UserProfile> getMyProfile(String accessToken) async {
    final data = await _get(
      '/users/me',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return UserProfile.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<Post>> getPosts() async {
    final data = await _get('/posts');
    if (data is! List) {
      throw const ApiException(
        0,
        'INVALID_RESPONSE',
        '목록 응답이 올바르지 않습니다.',
      );
    }
    return data
        .map((post) => Post.fromJson(Map<String, dynamic>.from(post as Map)))
        .toList();
  }

  Future<dynamic> _get(
    String path, {
    Map<String, String>? headers,
  }) async {
    final response = await http.get(
      Uri.parse('$apiBaseUrl$path'),
      headers: headers,
    );
    final body = jsonDecode(response.body);

    if (body is! Map) {
      throw const ApiException(
        0,
        'INVALID_RESPONSE',
        '서버 응답이 올바르지 않습니다.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body['error'];
      if (error is Map) {
        throw ApiException(
          response.statusCode,
          error['code']?.toString() ?? 'HTTP_ERROR',
          error['message']?.toString() ?? '요청을 처리할 수 없습니다.',
        );
      }
      throw ApiException(
        response.statusCode,
        'HTTP_ERROR',
        '요청을 처리할 수 없습니다. (${response.statusCode})',
      );
    }

    return body['data'];
  }
}

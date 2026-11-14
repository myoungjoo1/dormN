import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _serverMessage = 'FastAPI 사용자 정보 확인 중...';
  List<Map<String, dynamic>> _posts = [];
  String? _postsError;
  bool _isPostsLoading = true;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadMyProfile();
    _loadPosts();
  }

  Future<void> _loadMyProfile() async {
    final session = _supabase.auth.currentSession;
    if (session == null) {
      setState(() => _serverMessage = 'Supabase 로그인 세션이 없습니다.');
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/users/me'),
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        if (response.statusCode == 200) {
          final profile = body['data'] as Map<String, dynamic>;
          _serverMessage = 'FastAPI 연결 성공\n사용자: ${profile['id']}';
        } else {
          final apiError = body['error'] as Map<String, dynamic>;
          _serverMessage =
              'FastAPI 응답 오류 (${response.statusCode})\n${apiError['message']}';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _serverMessage = 'FastAPI 연결 실패\n$error');
    }
  }

  Future<void> _loadPosts() async {
    setState(() {
      _isPostsLoading = true;
      _postsError = null;
    });

    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/posts'));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (!mounted) return;

      if (response.statusCode != 200) {
        final apiError = body['error'] as Map<String, dynamic>;
        setState(() {
          _isPostsLoading = false;
          _postsError = apiError['message']?.toString() ??
              '공동구매 목록을 불러오지 못했습니다. (${response.statusCode})';
        });
        return;
      }

      final decoded = body['data'] as List<dynamic>;
      setState(() {
        _isPostsLoading = false;
        _posts = decoded
            .map((post) => Map<String, dynamic>.from(post as Map))
            .toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isPostsLoading = false;
        _postsError = '공동구매 목록 연결 실패\n$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DormN 공동구매'),
        actions: [
          IconButton(
            onPressed: () => _supabase.auth.signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              '로그인 사용자: ${user?.id ?? 'UUID 없음'}\n$_serverMessage',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '공동구매 목록',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(child: _buildPostsView()),
        ],
      ),
    );
  }

  Widget _buildPostsView() {
    if (_isPostsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_postsError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_postsError!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadPosts,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadPosts,
        child: ListView(
          children: const [
            SizedBox(height: 180),
            Center(child: Text('등록된 공동구매가 없습니다.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPosts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _posts.length,
        itemBuilder: (context, index) {
          final post = _posts[index];
          return Card(
            child: ListTile(
              title: Text(post['product_name']?.toString() ?? '상품명 없음'),
              subtitle: Text(
                '${post['total_price']}원 · ${post['pickup_location']}\n'
                '마감: ${post['deadline']}',
              ),
              trailing: Text(post['status']?.toString() ?? ''),
            ),
          );
        },
      ),
    );
  }
}

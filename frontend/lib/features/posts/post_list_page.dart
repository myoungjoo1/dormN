import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dormn_api.dart';
import '../../models/post.dart';

class PostListPage extends StatefulWidget {
  const PostListPage({super.key});

  @override
  State<PostListPage> createState() => _PostListPageState();
}

class _PostListPageState extends State<PostListPage> {
  final _api = const DormNApi();
  String _serverMessage = 'FastAPI 사용자 정보 확인 중...';
  List<Post> _posts = [];
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
      final profile = await _api.getMyProfile(session.accessToken);
      if (!mounted) return;
      setState(() {
        _serverMessage = 'FastAPI 연결 성공\n사용자: ${profile.id}';
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _serverMessage =
            'FastAPI 응답 오류 (${error.statusCode})\n${error.message}';
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
      final posts = await _api.getPosts();
      if (!mounted) return;
      setState(() {
        _isPostsLoading = false;
        _posts = posts;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isPostsLoading = false;
        _postsError = error.message;
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
              title: Text(post.productName),
              subtitle: Text(
                '${post.authorRoomNumber ?? '호실 미등록'} · ${post.pickupLocation}\n'
                '${post.filledQuantity}/${post.totalQuantity}개 참여 · '
                '${post.remainingQuantity}개 남음',
              ),
              trailing: Text(post.status),
            ),
          );
        },
      ),
    );
  }
}

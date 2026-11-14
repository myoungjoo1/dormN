import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dormn_api.dart';
import '../../models/post.dart';
import 'post_create_page.dart';
import 'post_detail_page.dart';

const _blue = Color(0xFF3156D9);
const _pageBackground = Color(0xFFF7F8FC);

class PostListPage extends StatefulWidget {
  const PostListPage({super.key});

  @override
  State<PostListPage> createState() => _PostListPageState();
}

class _PostListPageState extends State<PostListPage> {
  final _api = const DormNApi();
  List<Post> _posts = [];
  String? _roomNumber;
  String? _postsError;
  bool _isPostsLoading = true;
  int _selectedFilter = 0;

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadMyProfile();
    _loadPosts();
  }

  Future<void> _loadMyProfile() async {
    final session = _supabase.auth.currentSession;
    if (session == null) return;

    try {
      final profile = await _api.getMyProfile(session.accessToken);
      if (mounted) setState(() => _roomNumber = profile.roomNumber);
    } catch (_) {
      // The feed remains usable even when the optional room label fails to load.
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

  List<Post> get _visiblePosts {
    final now = DateTime.now();
    if (_selectedFilter == 1) {
      return _posts.where((post) => post.status == 'RECRUITING').toList();
    }
    if (_selectedFilter == 2) {
      return _posts.where((post) {
        final remaining = post.deadline.difference(now);
        return post.status == 'RECRUITING' &&
            remaining.inHours >= 0 &&
            remaining.inHours <= 24;
      }).toList();
    }
    return _posts;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      floatingActionButton: FloatingActionButton(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PostCreatePage()),
          );
        },
        child: const Icon(Icons.add, size: 32),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        indicatorColor: const Color(0xFFE5EAFE),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag),
            label: '공구피드',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: '참여내역',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: '기숙사톡',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: '내정보',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _FeedTopBar(onSignOut: _supabase.auth.signOut),
            Expanded(child: _buildFeed()),
          ],
        ),
      ),
    );
  }

  Widget _buildFeed() {
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
            OutlinedButton(onPressed: _loadPosts, child: const Text('다시 시도')),
          ],
        ),
      );
    }

    final posts = _visiblePosts;
    return RefreshIndicator(
      onRefresh: _loadPosts,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 104),
        children: [
          _FeedTitle(roomNumber: _roomNumber),
          const SizedBox(height: 16),
          const _TogetherBanner(),
          const SizedBox(height: 16),
          _FilterRow(
            selectedFilter: _selectedFilter,
            onSelected: (filter) => setState(() => _selectedFilter = filter),
          ),
          const SizedBox(height: 14),
          if (posts.isEmpty)
            const _EmptyFeed()
          else
            ...posts.map(
              (post) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PostCard(
                  post: post,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PostDetailPage(postId: post.id),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FeedTopBar extends StatelessWidget {
  const _FeedTopBar({required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE9ECF5))),
      ),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 9, color: _blue),
          const SizedBox(width: 5),
          const Text(
            'Dorm Feed',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
          ),
          const SizedBox(width: 8),
          const _BuildingChip(),
          const Spacer(),
          const Icon(Icons.search, color: Color(0xFF4E5568)),
          const SizedBox(width: 20),
          const Icon(Icons.notifications_none, color: Color(0xFF4E5568)),
          const SizedBox(width: 12),
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onSignOut,
            child: const CircleAvatar(
              radius: 17,
              backgroundColor: _blue,
              child: Icon(Icons.person, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _BuildingChip extends StatelessWidget {
  const _BuildingChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F2F8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        '기숙사 A동',
        style: TextStyle(fontSize: 10, color: Color(0xFF687086)),
      ),
    );
  }
}

class _FeedTitle extends StatelessWidget {
  const _FeedTitle({required this.roomNumber});

  final String? roomNumber;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'DormN',
          style: TextStyle(
            color: _blue,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Icon(Icons.circle, size: 7, color: Color(0xFF3BE07E)),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8FF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '▣ ${roomNumber ?? '호실 미등록'}',
            style: const TextStyle(
              color: _blue,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _TogetherBanner extends StatelessWidget {
  const _TogetherBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EEFF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '♧ 실시간 룸메이트 나눔',
                  style: TextStyle(color: _blue, fontSize: 11),
                ),
                SizedBox(height: 6),
                Text(
                  '오늘 같이 살 사람?',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 3),
                Text(
                  '수경재 공동구매 배송비 아끼고\n달거로 득템해요',
                  style: TextStyle(color: _blue, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Color(0xFFDDE5FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.group_outlined, color: _blue, size: 30),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.selectedFilter, required this.onSelected});

  final int selectedFilter;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const filters = ['전체', '모집중', '마감임박'];
    return Row(
      children: [
        for (var index = 0; index < filters.length; index++) ...[
          ChoiceChip(
            label: Text(filters[index]),
            selected: selectedFilter == index,
            selectedColor: _blue,
            labelStyle: TextStyle(
              color: selectedFilter == index
                  ? Colors.white
                  : const Color(0xFF4E5568),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
            side: BorderSide.none,
            shape: const StadiumBorder(),
            onSelected: (_) => onSelected(index),
          ),
          if (index != filters.length - 1) const SizedBox(width: 8),
        ],
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: Color(0xFFF0F2F8),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.tune, size: 18, color: Color(0xFF4E5568)),
        ),
      ],
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isRecruiting = post.status == 'RECRUITING';
    final statusColor = isRecruiting
        ? const Color(0xFF48D979)
        : const Color(0xFFF5B85B);
    final progress = post.filledQuantity / post.totalQuantity;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE7EAF2)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F2FF),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Text(
                      '공동구매',
                      style: TextStyle(color: _blue, fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _formatDeadline(post.deadline),
                    style: const TextStyle(
                      color: Color(0xFF7B8398),
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isRecruiting ? '● 모집중' : '● ${post.status}',
                      style: const TextStyle(
                        color: Color(0xFF123824),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                post.productName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F5FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: _blue,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${post.authorRoomNumber ?? '호실 미등록'} · ${post.pickupLocation}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4E5568),
                        ),
                      ),
                    ),
                    Text(
                      '${post.totalPrice}원',
                      style: const TextStyle(
                        color: _blue,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '${post.filledQuantity} / ${post.totalQuantity}개 참여',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(progress * 100).round()}% 달성',
                    style: const TextStyle(color: _blue, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  color: _blue,
                  backgroundColor: const Color(0xFFE4E8F2),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _SmallInfo(
                    icon: Icons.inventory_2_outlined,
                    text: '${post.remainingQuantity}개 남음',
                  ),
                  const SizedBox(width: 10),
                  _SmallInfo(
                    icon: Icons.schedule,
                    text: _formatDeadline(post.deadline),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _blue,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '참여하기  ›',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallInfo extends StatelessWidget {
  const _SmallInfo({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFFFFA900)),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(fontSize: 10, color: Color(0xFF6C7488)),
        ),
      ],
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 96),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 42,
              color: Color(0xFF9BA4BA),
            ),
            SizedBox(height: 12),
            Text('아직 등록된 공동구매가 없어요.'),
            SizedBox(height: 4),
            Text(
              '+ 버튼을 눌러 첫 공동구매를 만들어보세요.',
              style: TextStyle(color: Color(0xFF7B8398), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDeadline(DateTime deadline) {
  final local = deadline.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.month}/${local.day} $hour:$minute';
}

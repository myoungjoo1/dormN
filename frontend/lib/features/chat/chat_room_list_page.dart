import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dormn_api.dart';
import '../../models/chat_room.dart';
import '../mypage/mypage_page.dart';
import 'chat_room_page.dart';
import 'user_search_page.dart';

const _blue = Color(0xFF3156D9);
const _pageBackground = Color(0xFFF7F8FC);

enum _ChatFilter { all, group, direct }

class ChatRoomListPage extends StatefulWidget {
  const ChatRoomListPage({super.key});

  @override
  State<ChatRoomListPage> createState() => _ChatRoomListPageState();
}

class _ChatRoomListPageState extends State<ChatRoomListPage> {
  final _api = const DormNApi();
  List<ChatRoom> _rooms = [];
  _ChatFilter _selectedFilter = _ChatFilter.all;
  bool _isLoading = true;
  bool _isDormVerificationRequired = false;
  String? _error;
  String? _activeUserId;
  int _roomsRequestVersion = 0;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _listenToAuthState();
    _loadRooms();
  }

  void _listenToAuthState() {
    try {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            if (!mounted) return;
            final session = state.session;
            if (session == null) {
              _roomsRequestVersion += 1;
              _activeUserId = null;
              setState(() {
                _rooms = [];
                _error = '로그인이 필요합니다. 다시 로그인해주세요.';
                _isDormVerificationRequired = false;
                _isLoading = false;
              });
              return;
            }
            if (_activeUserId != null && _activeUserId != session.user.id) {
              _roomsRequestVersion += 1;
              _activeUserId = session.user.id;
              setState(() {
                _rooms = [];
                _error = null;
                _isDormVerificationRequired = false;
              });
              unawaited(_loadRooms());
            }
          });
    } catch (_) {
      // AuthGate remains the source of truth when the auth stream is unavailable.
    }
  }

  List<ChatRoom> get _visibleRooms {
    switch (_selectedFilter) {
      case _ChatFilter.group:
        return _rooms.where((room) => room.isGroup).toList();
      case _ChatFilter.direct:
        return _rooms.where((room) => room.isDirect).toList();
      case _ChatFilter.all:
        return _rooms;
    }
  }

  Future<void> _loadRooms() async {
    final requestVersion = ++_roomsRequestVersion;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
        _isDormVerificationRequired = false;
      });
    }

    final session = _currentSession();
    final userId = session?.user.id;
    _activeUserId = userId;
    if (session == null) {
      if (!mounted || requestVersion != _roomsRequestVersion) return;
      setState(() {
        _isLoading = false;
        _error = '로그인이 필요합니다. 다시 로그인해주세요.';
      });
      return;
    }

    try {
      final rooms = await _api.getChatRooms(accessToken: session.accessToken);
      if (!mounted ||
          requestVersion != _roomsRequestVersion ||
          _currentSession()?.user.id != userId) {
        return;
      }
      setState(() {
        _rooms = rooms;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted || requestVersion != _roomsRequestVersion) return;
      setState(() {
        _isLoading = false;
        _isDormVerificationRequired =
            error.code == 'DORM_VERIFICATION_REQUIRED';
        _error = _roomErrorMessage(error);
      });
    } catch (_) {
      if (!mounted || requestVersion != _roomsRequestVersion) return;
      setState(() {
        _isLoading = false;
        _error = '채팅방 목록을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  Session? _currentSession() {
    try {
      return Supabase.instance.client.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  String _roomErrorMessage(ApiException error) {
    switch (error.code) {
      case 'DORM_VERIFICATION_REQUIRED':
        return '기숙사 인증을 완료한 사용자만 기숙사톡을 이용할 수 있어요.';
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다. 다시 로그인해주세요.';
      case 'CHAT_ACCESS_FORBIDDEN':
        return '이 채팅방에 접근할 권한이 없습니다.';
      default:
        return error.message;
    }
  }

  void _showNotImplemented(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openRoom(ChatRoom room) {
    Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => ChatRoomPage(room: room)));
  }

  Future<void> _startDirectChat() async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const UserSearchPage()));
    if (!mounted || changed != true) return;
    await _loadRooms();
  }

  Future<void> _openMypage() async {
    await Navigator.of(context)
        .push<void>(MaterialPageRoute(builder: (_) => const MypagePage()));
  }

  void _selectNavigation(int index) {
    if (index == 0) {
      Navigator.of(context).pop();
      return;
    }
    if (index == 3) {
      _openMypage();
      return;
    }
    if (index != 2) {
      _showNotImplemented('해당 메뉴는 다음 단계에서 연결됩니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _pageBackground,
        elevation: 0,
        title: const Text(
          '기숙사톡',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _startDirectChat,
            tooltip: '새 1:1 채팅',
            icon: const Icon(Icons.edit_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 2,
        onDestinationSelected: _selectNavigation,
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
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _ErrorRooms(
        message: _error!,
        showRetry: !_isDormVerificationRequired,
        onRetry: _loadRooms,
      );
    }

    final rooms = _visibleRooms;
    return RefreshIndicator(
      onRefresh: _loadRooms,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _FilterRow(
            selectedFilter: _selectedFilter,
            onSelected: (filter) => setState(() => _selectedFilter = filter),
          ),
          const SizedBox(height: 16),
          if (rooms.isEmpty)
            _EmptyRooms(filtered: _selectedFilter != _ChatFilter.all)
          else
            ...rooms.map(
              (room) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ChatRoomCard(room: room, onTap: () => _openRoom(room)),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.selectedFilter, required this.onSelected});

  final _ChatFilter selectedFilter;
  final ValueChanged<_ChatFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FilterChip(
          label: '전체',
          selected: selectedFilter == _ChatFilter.all,
          onTap: () => onSelected(_ChatFilter.all),
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: '공동구매',
          selected: selectedFilter == _ChatFilter.group,
          onTap: () => onSelected(_ChatFilter.group),
        ),
        const SizedBox(width: 8),
        _FilterChip(
          label: '1:1 채팅',
          selected: selectedFilter == _ChatFilter.direct,
          onTap: () => onSelected(_ChatFilter.direct),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _blue : Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF697386),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatRoomCard extends StatelessWidget {
  const _ChatRoomCard({required this.room, required this.onTap});

  final ChatRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isGroup = room.isGroup;
    final title = isGroup
        ? room.productName ?? '공동구매 채팅방'
        : room.otherUserRoomNumber ?? '1:1 채팅';
    final subtitle = isGroup ? '공동구매 참여자 단체 채팅방' : '1:1 채팅방';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isGroup
                      ? const Color(0xFFE8EDFF)
                      : const Color(0xFFEAF8F0),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isGroup ? Icons.groups_rounded : Icons.person_rounded,
                  color: isGroup ? _blue : const Color(0xFF29945B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF172033),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF697386),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '생성 ${room.createdAt.month}/${room.createdAt.day}',
                      style: const TextStyle(
                        color: Color(0xFF9AA3B2),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF9AA3B2)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 120),
      child: Column(
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 52,
            color: Color(0x593156D9),
          ),
          const SizedBox(height: 14),
          Text(
            filtered ? '선택한 유형의 채팅방이 없어요' : '아직 채팅방이 없어요',
            style: TextStyle(
              color: Color(0xFF172033),
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            filtered ? '다른 필터를 선택해보세요.' : '공동구매에 참여하거나 1:1 채팅을 시작해보세요.',
            style: TextStyle(color: Color(0xFF697386), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ErrorRooms extends StatelessWidget {
  const _ErrorRooms({
    required this.message,
    required this.showRetry,
    required this.onRetry,
  });

  final String message;
  final bool showRetry;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 44,
              color: Color(0xFF8A92A5),
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (showRetry) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
            ],
          ],
        ),
      ),
    );
  }
}

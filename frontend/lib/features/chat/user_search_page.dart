import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dormn_api.dart';
import '../../models/user_search_result.dart';
import 'chat_room_page.dart';

const _blue = Color(0xFF3156D9);
const _pageBackground = Color(0xFFF7F8FC);

class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final _api = const DormNApi();
  final _roomController = TextEditingController();
  List<UserSearchResult> _results = [];
  bool _isSearching = false;
  bool _isCreatingChat = false;
  bool _isDormVerificationRequired = false;
  bool _hasSearched = false;
  String? _error;

  Session? _currentSession() {
    try {
      return Supabase.instance.client.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  Future<void> _search() async {
    if (_isSearching || _isCreatingChat) return;

    final roomNumber = _roomController.text.trim();
    final session = _currentSession();
    if (session == null) {
      _setError('로그인이 필요합니다. 다시 로그인해주세요.');
      return;
    }

    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _error = null;
      _isDormVerificationRequired = false;
      _results = [];
    });

    try {
      final results = await _api.searchUsersByRoomNumber(
        roomNumber: roomNumber,
        accessToken: session.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _isDormVerificationRequired =
            error.code == 'DORM_VERIFICATION_REQUIRED';
        _error = _searchErrorMessage(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _error = '사용자를 검색하지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
    }
  }

  Future<void> _createChat(UserSearchResult user) async {
    if (_isCreatingChat) return;

    final session = _currentSession();
    if (session == null) {
      _setError('로그인이 필요합니다. 다시 로그인해주세요.');
      return;
    }

    setState(() => _isCreatingChat = true);
    try {
      final room = await _api.createDirectChat(
        userId: user.userId,
        accessToken: session.accessToken,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ChatRoomPage(room: room)),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) _setError(_chatErrorMessage(error));
    } catch (_) {
      if (mounted) _setError('1:1 채팅방을 만들지 못했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isCreatingChat = false);
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _results = [];
    });
  }

  String _searchErrorMessage(ApiException error) {
    switch (error.code) {
      case 'DORM_VERIFICATION_REQUIRED':
        return '기숙사 인증을 완료한 사용자만 검색할 수 있어요.';
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다. 다시 로그인해주세요.';
      case 'INVALID_ROOM_NUMBER':
        return '호실 번호 형식을 확인해주세요. 예: 717-2';
      default:
        return error.message;
    }
  }

  String _chatErrorMessage(ApiException error) {
    switch (error.code) {
      case 'DORM_VERIFICATION_REQUIRED':
        return '기숙사 인증을 완료한 사용자만 1:1 채팅을 만들 수 있어요.';
      case 'CHAT_SELF_DM_NOT_ALLOWED':
        return '자기 자신과는 1:1 채팅을 만들 수 없습니다.';
      case 'TARGET_DORM_VERIFICATION_REQUIRED':
        return '상대방이 기숙사 인증을 완료한 뒤 채팅할 수 있습니다.';
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다. 다시 로그인해주세요.';
      default:
        return error.message;
    }
  }

  @override
  void dispose() {
    _roomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _pageBackground,
        elevation: 0,
        title: const Text(
          '새로운 1:1 채팅',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _SearchField(
              controller: _roomController,
              isLoading: _isSearching,
              onSearch: _search,
            ),
            const SizedBox(height: 20),
            if (_error != null)
              _SearchError(
                message: _error!,
                dormVerificationRequired: _isDormVerificationRequired,
              )
            else if (!_isSearching && _results.isEmpty)
              _SearchEmpty(hasSearched: _hasSearched)
            else
              ..._results.map(
                (user) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SearchResultCard(
                    user: user,
                    isLoading: _isCreatingChat,
                    onStartChat: () => _createChat(user),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.isLoading,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool isLoading;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: !isLoading,
      keyboardType: TextInputType.text,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => onSearch(),
      decoration: InputDecoration(
        labelText: '호실 번호',
        hintText: '예: 717-2',
        filled: true,
        fillColor: Colors.white,
        suffixIcon: IconButton(
          onPressed: isLoading ? null : onSearch,
          icon: isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.user,
    required this.isLoading,
    required this.onStartChat,
  });

  final UserSearchResult user;
  final bool isLoading;
  final VoidCallback onStartChat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFE8EDFF),
            child: Icon(Icons.person_rounded, color: _blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              user.roomNumber,
              style: const TextStyle(
                color: Color(0xFF172033),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          FilledButton(
            onPressed: isLoading ? null : onStartChat,
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            child: const Text('채팅하기'),
          ),
        ],
      ),
    );
  }
}

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty({required this.hasSearched});

  final bool hasSearched;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: 90),
      child: Center(
        child: Text(
          hasSearched
              ? '해당 호실의 사용자를 찾을 수 없습니다.'
              : '호실 번호를 입력하고 검색해주세요.',
          style: TextStyle(color: Color(0xFF697386)),
        ),
      ),
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({
    required this.message,
    required this.dormVerificationRequired,
  });

  final String message;
  final bool dormVerificationRequired;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 90),
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: dormVerificationRequired
                ? const Color(0xFF8A6418)
                : const Color(0xFF697386),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dormn_api.dart';
import '../../models/user_profile.dart';
import '../chat/chat_room_list_page.dart';
import 'dorm_verification_page.dart';
import 'purchase_history_page.dart';
import 'settlement_account_page.dart';

const _blue = Color(0xFF3156D9);
const _pageBackground = Color(0xFFF7F8FC);

class MypagePage extends StatefulWidget {
  const MypagePage({super.key});

  @override
  State<MypagePage> createState() => _MypagePageState();
}

class _MypagePageState extends State<MypagePage> {
  final _api = const DormNApi();
  UserProfile? _profile;
  String? _provider;
  String? _error;
  bool _isLoading = true;
  bool _isSigningOut = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _listenToAuthState();
    _loadProfile();
  }

  void _listenToAuthState() {
    try {
      _authSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (!mounted) return;
        final session = state.session;
        if (session == null) {
          setState(() {
            _profile = null;
            _provider = null;
            _error = '로그인이 필요합니다. 다시 로그인해주세요.';
          });
          Navigator.of(context).popUntil((route) => route.isFirst);
          return;
        }
        if (_profile?.id != session.user.id && !_isLoading) {
          unawaited(_loadProfile());
        }
      });
    } catch (_) {
      // AuthGate remains the source of truth when the auth stream is unavailable.
    }
  }

  Future<void> _loadProfile() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
        _profile = null;
        _provider = null;
      });
    }

    final auth = _currentAuth();
    final session = auth?.currentSession;
    final userId = session?.user.id;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '로그인이 필요합니다. 다시 로그인해주세요.';
      });
      return;
    }

    try {
      final profile = await _api.getMyProfile(session.accessToken);
      if (!mounted || _currentAuth()?.auth.currentUser?.id != userId) return;
      setState(() {
        _profile = profile;
        _provider = _providerLabel(auth?.currentUser);
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = _profileErrorMessage(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '사용자 정보를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
    }
  }

  SupabaseClient? _currentAuth() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  String _providerLabel(User? user) {
    final provider = user?.appMetadata['provider'];
    if (provider is String && provider.isNotEmpty) {
      return _providerName(provider);
    }

    final providers = user?.appMetadata['providers'];
    if (providers is List && providers.isNotEmpty) {
      final firstProvider = providers.first;
      if (firstProvider is String && firstProvider.isNotEmpty) {
        return _providerName(firstProvider);
      }
    }
    return '로그인 계정';
  }

  String _providerName(String provider) {
    switch (provider.toLowerCase()) {
      case 'kakao':
        return '카카오 로그인';
      case 'google':
        return 'Google 로그인';
      case 'apple':
        return 'Apple 로그인';
      default:
        return '$provider 로그인';
    }
  }

  String _profileErrorMessage(ApiException error) {
    switch (error.code) {
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다. 다시 로그인해주세요.';
      case 'USER_PROFILE_NOT_FOUND':
        return '사용자 정보를 찾을 수 없습니다.';
      default:
        return '사용자 정보를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.';
    }
  }

  void _showNotImplemented(String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label 기능은 다음 단계에서 연결됩니다.')));
  }

  Future<void> _openChat() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ChatRoomListPage()),
    );
  }

  Future<void> _openHistory(PurchaseHistoryTab tab) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PurchaseHistoryPage(initialTab: tab),
      ),
    );
  }

  Future<void> _openDormVerification() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const DormVerificationPage()),
    );
    if (mounted) unawaited(_loadProfile());
  }

  Future<void> _confirmSignOut() async {
    if (_isSigningOut) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('현재 계정에서 로그아웃할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD14343),
            ),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _isSigningOut) return;

    setState(() => _isSigningOut = true);
    try {
      final auth = _currentAuth();
      if (auth == null) {
        _showMessage('로그아웃에 실패했습니다. 다시 시도해주세요.');
        return;
      }
      await auth.auth.signOut();
      if (!mounted) return;
      if (auth.auth.currentSession != null) {
        _showMessage('로그아웃 상태를 확인하지 못했습니다. 다시 시도해주세요.');
        return;
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException {
      if (mounted) _showMessage('로그아웃에 실패했습니다. 다시 시도해주세요.');
    } catch (_) {
      if (mounted) _showMessage('로그아웃에 실패했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _selectNavigation(int index) {
    if (index == 0) {
      Navigator.of(context).pop();
      return;
    }
    if (index == 2) {
      _openChat();
      return;
    }
    if (index == 1) {
      _showNotImplemented('참여내역');
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
          '마이페이지',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 3,
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
      return RefreshIndicator(
        onRefresh: _loadProfile,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.65,
              child: _ErrorState(message: _error!, onRetry: _loadProfile),
            ),
          ],
        ),
      );
    }

    final profile = _profile;
    if (profile == null) {
      return _ErrorState(message: '사용자 정보를 찾을 수 없습니다.', onRetry: _loadProfile);
    }

    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _ProfileCard(profile: profile, provider: _provider ?? '로그인 계정'),
          const SizedBox(height: 16),
          const _SectionTitle(title: '나의 공동구매'),
          const SizedBox(height: 8),
          _MenuCard(
            icon: Icons.campaign_outlined,
            title: '내가 모집한 공동구매',
            subtitle: '모집글과 거래 진행 상태를 확인해요',
            onTap: () => _openHistory(PurchaseHistoryTab.hosted),
          ),
          const SizedBox(height: 10),
          _MenuCard(
            icon: Icons.shopping_bag_outlined,
            title: '내가 참여한 공동구매',
            subtitle: '참여 수량과 정산 상태를 확인해요',
            onTap: () => _openHistory(PurchaseHistoryTab.participated),
          ),
          const SizedBox(height: 18),
          const _SectionTitle(title: '계정 관리'),
          const SizedBox(height: 8),
          _MenuCard(
            icon: Icons.account_balance_outlined,
            title: '정산 계좌 관리',
            subtitle: '기본 계좌 등록 및 수정',
            onTap: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => const SettlementAccountPage(),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          _MenuCard(
            icon: Icons.verified_user_outlined,
            title: '기숙사 인증 관리',
            subtitle: profile.dormVerified ? '기숙사 인증 완료' : '기숙사 인증이 필요해요',
            onTap: _openDormVerification,
          ),
          const SizedBox(height: 10),
          _MenuCard(
            icon: Icons.logout_rounded,
            title: '로그아웃',
            subtitle: _isSigningOut ? '로그아웃 중...' : '현재 계정에서 로그아웃',
            color: const Color(0xFFD14343),
            onTap: _isSigningOut ? () {} : _confirmSignOut,
          ),
          const SizedBox(height: 28),
          const Center(
            child: Text(
              'DormN',
              style: TextStyle(
                color: Color(0xFF9AA3B2),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.provider});

  final UserProfile profile;
  final String provider;

  @override
  Widget build(BuildContext context) {
    final verified = profile.dormVerified;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Color(0xFFE5EAFF),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded, color: _blue, size: 34),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.roomNumber ?? '호실 미등록',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  provider,
                  style: const TextStyle(color: Color(0xFF697386), fontSize: 12),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      verified ? Icons.verified_rounded : Icons.info_outline_rounded,
                      size: 16,
                      color: verified ? const Color(0xFF1D9B55) : const Color(0xFFB57900),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      verified ? '기숙사 인증 완료' : '기숙사 인증 필요',
                      style: TextStyle(
                        color: verified ? const Color(0xFF1D9B55) : const Color(0xFFB57900),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color = _blue,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Color(0xFF697386), fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dormn_api.dart';
import '../../models/user_profile.dart';
import '../verification/location_verification_page.dart';

const _blue = Color(0xFF3156D9);
const _pageBackground = Color(0xFFF7F8FC);

class DormVerificationPage extends StatefulWidget {
  const DormVerificationPage({super.key});

  @override
  State<DormVerificationPage> createState() => _DormVerificationPageState();
}

class _DormVerificationPageState extends State<DormVerificationPage> {
  final _api = const DormNApi();
  UserProfile? _profile;
  String? _error;
  bool _isLoading = true;
  String? _activeUserId;
  int _profileRequestVersion = 0;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _listenToAuthState();
    _loadProfile();
  }

  void _listenToAuthState() {
    try {
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) {
            if (!mounted) return;
            final session = state.session;
            if (session == null) {
              _profileRequestVersion += 1;
              _activeUserId = null;
              setState(() {
                _profile = null;
                _isLoading = false;
                _error = '로그인이 필요합니다. 다시 로그인해주세요.';
              });
              return;
            }
            if (_activeUserId != null && _activeUserId != session.user.id) {
              _activeUserId = session.user.id;
              unawaited(_loadProfile());
            }
          });
    } catch (_) {
      // AuthGate remains the source of truth when the auth stream is unavailable.
    }
  }

  Session? _currentSession() {
    try {
      return Supabase.instance.client.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadProfile() async {
    final requestVersion = ++_profileRequestVersion;
    final session = _currentSession();
    final userId = session?.user.id;
    _activeUserId = userId;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
        _profile = null;
      });
    }

    if (session == null || session.accessToken.isEmpty) {
      if (!mounted || requestVersion != _profileRequestVersion) return;
      setState(() {
        _isLoading = false;
        _error = '로그인이 필요합니다. 다시 로그인해주세요.';
      });
      return;
    }

    try {
      final profile = await _api.getMyProfile(session.accessToken);
      if (!mounted ||
          requestVersion != _profileRequestVersion ||
          _currentSession()?.user.id != userId) {
        return;
      }
      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted ||
          requestVersion != _profileRequestVersion ||
          _currentSession()?.user.id != userId) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = _errorMessage(error);
      });
    } catch (_) {
      if (!mounted ||
          requestVersion != _profileRequestVersion ||
          _currentSession()?.user.id != userId) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = '인증 상태를 확인하지 못했습니다. 다시 시도해주세요.';
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  String _errorMessage(ApiException error) {
    switch (error.code) {
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다. 다시 로그인해주세요.';
      default:
        return error.message;
    }
  }

  Future<void> _openLocationVerification() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const LocationVerificationPage()),
    );
    if (mounted) await _loadProfile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _pageBackground,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        title: const Text(
          '기숙사 인증 관리',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
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

    final verified = profile.dormVerified;
    return RefreshIndicator(
      onRefresh: _loadProfile,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          _Card(
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE5EAFF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.apartment_rounded,
                    color: _blue,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '현재 등록된 호실',
                        style: TextStyle(
                          color: Color(0xFF697386),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        profile.roomNumber ?? '호실 미등록',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      verified
                          ? Icons.verified_rounded
                          : Icons.info_outline_rounded,
                      color: verified
                          ? const Color(0xFF1D9B55)
                          : const Color(0xFFB57900),
                      size: 24,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      verified ? '기숙사 인증 완료' : '기숙사 미인증',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  verified
                      ? '현재 서버에 저장된 기숙사 인증 상태가 완료입니다.'
                      : '기숙사 인증을 완료해야 기숙사톡 등 일부 기능을 이용할 수 있습니다.',
                  style: const TextStyle(
                    color: Color(0xFF526079),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                if (profile.dormVerifiedAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '인증 시각: ${_formatDate(profile.dormVerifiedAt!)}',
                    style: const TextStyle(
                      color: Color(0xFF8993A5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _NoticeCard(
            icon: Icons.location_searching_rounded,
            text: verified
                ? '기숙사 인증 상태는 서버에서 관리됩니다. 이 화면에서는 상태를 임의로 변경하지 않습니다.'
                : '호실 등록 후 GPS 체류 인증을 진행할 수 있습니다. 최종 인증 상태는 서버에서 관리됩니다.',
          ),
          if (!verified) ...[
            const SizedBox(height: 14),
            _Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'GPS 위치 확인',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '앱을 사용하는 동안에만 현재 위치를 한 번 측정합니다. '
                    '이 단계에서는 서버 인증을 완료하지 않습니다.',
                    style: TextStyle(
                      color: Color(0xFF526079),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openLocationVerification,
                      icon: const Icon(Icons.gps_fixed_rounded),
                      label: const Text('위치 인증 화면 열기'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF2FF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _blue, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF526079),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
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

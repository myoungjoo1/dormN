import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kakaoRedirectUrl = 'io.dormn.app://login-callback';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isLoading = false;

  Future<void> _signInWithKakao() async {
    setState(() => _isLoading = true);
    try {
      final launched = await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.kakao,
        redirectTo: kIsWeb ? null : kakaoRedirectUrl,
      );
      if (!launched && mounted) {
        _showMessage('카카오 로그인 페이지를 열 수 없습니다.');
      }
    } on AuthException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 34),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const _TopBadges(),
                      const SizedBox(height: 54),
                      const _BrandIntro(),
                      const SizedBox(height: 26),
                      const _FeatureList(),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _isLoading ? null : _signInWithKakao,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFEE500),
                            foregroundColor: const Color(0xFF191600),
                            disabledBackgroundColor: const Color(0xFFFFE94D),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                          label: Text(
                            _isLoading ? '카카오 로그인 중...' : '카카오로 시작하기',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _showMessage('로그인 후 공동구매를 이용할 수 있어요.'),
                        child: const Text('로그인 없이 둘러보기  ›'),
                      ),
                      const Text(
                        '시작 시 DormN 이용약관 및 개인정보 처리방침에 동의하게 됩니다.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF697386),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TopBadges extends StatelessWidget {
  const _TopBadges();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _InfoBadge(
          icon: Icons.circle,
          text: '수경재 거주자 전용',
          color: Color(0xFF3B63F3),
        ),
        _InfoBadge(
          icon: Icons.verified_user_outlined,
          text: '완전 안심 캠퍼스',
          color: Color(0xFF3156D9),
        ),
      ],
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, size: icon == Icons.circle ? 7 : 13, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _BrandIntro extends StatelessWidget {
  const _BrandIntro();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _BrandMark(),
        SizedBox(height: 17),
        Text(
          'DormN.',
          style: TextStyle(
            color: Color(0xFF151B2A),
            fontSize: 21,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '기숙사 룸메들과 함께하는 실속 공동구매',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 5),
        Text(
          '배송비는 아끼고, 생필품은 필요한 만큼만 쏙쏙',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF526079), fontSize: 11),
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 86,
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          Positioned(
            top: 0,
            left: 2,
            child: Container(
              width: 43,
              height: 43,
              decoration: const BoxDecoration(
                color: Color(0xFFE1E7FF),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF4566E9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.apartment_rounded, color: Colors.white, size: 25),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF65E88C),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined, size: 11, color: Color(0xFF075B25)),
                  SizedBox(width: 3),
                  Text(
                    '1/N 분할',
                    style: TextStyle(
                      color: Color(0xFF075B25),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  const _FeatureList();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _FeatureCard(
          icon: Icons.apartment_rounded,
          title: '우리 기숙사 사생 인증 기반',
          subtitle: '외부인 없는 신뢰도 100% 안전 캠퍼스 마켓',
        ),
        SizedBox(height: 10),
        _FeatureCard(
          icon: Icons.shopping_basket_outlined,
          title: '대용량 소분 & 배송비 0원',
          subtitle: '생수, 세제, 햇반도 보관 걱정 없이 소량 분할',
        ),
        SizedBox(height: 10),
        _FeatureCard(
          icon: Icons.lock_outline_rounded,
          title: '안전한 룸키 필요 & 익명 소통',
          subtitle: '개인정보 노출 없이 동/호실 기반 간편 수령',
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F3FF),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: const Color(0xFF3156D9), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF526079), fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

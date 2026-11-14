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
        _showMessage('로그인 페이지를 열 수 없습니다.');
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
      body: Center(
        child: FilledButton.icon(
          onPressed: _isLoading ? null : _signInWithKakao,
          icon: const Icon(Icons.login),
          label: Text(_isLoading ? '로그인 중...' : '카카오로 로그인'),
        ),
      ),
    );
  }
}

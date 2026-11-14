import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabasePublishableKey =
    String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const kakaoRedirectUrl = 'io.dormn.app://login-callback';
const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);

bool get isSupabaseConfigured =>
    supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isSupabaseConfigured) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  }

  runApp(const DormNApp());
}

SupabaseClient get supabase => Supabase.instance.client;

class DormNApp extends StatelessWidget {
  const DormNApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DormN',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.indigo)),
      home: isSupabaseConfigured
          ? const AuthGate()
          : const ConfigurationPage(),
    );
  }
}

class ConfigurationPage extends StatelessWidget {
  const ConfigurationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Supabase 설정이 없습니다.\n\n'
            'SUPABASE_URL과 SUPABASE_PUBLISHABLE_KEY를\n'
            '--dart-define으로 전달해 주세요.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Session? _session;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _session = supabase.auth.currentSession;
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) {
      if (mounted) {
        setState(() => _session = data.session);
      }
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _session == null ? const LoginPage() : const AccountPage();
  }
}

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
      final launched = await supabase.auth.signInWithOAuth(
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

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  String _serverMessage = 'FastAPI 사용자 정보 확인 중...';

  @override
  void initState() {
    super.initState();
    _loadMyProfile();
  }

  Future<void> _loadMyProfile() async {
    final session = supabase.auth.currentSession;
    if (session == null) {
      setState(() => _serverMessage = 'Supabase 로그인 세션이 없습니다.');
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/users/me'),
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );

      if (!mounted) return;
      setState(() {
        _serverMessage = response.statusCode == 200
            ? 'FastAPI 연결 성공\n${response.body}'
            : 'FastAPI 응답 오류 (${response.statusCode})\n${response.body}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _serverMessage = 'FastAPI 연결 실패\n$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = supabase.auth.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('DormN')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('카카오 로그인이 완료되었습니다.'),
            const SizedBox(height: 8),
            Text(user?.id ?? '사용자 UUID 없음'),
            const SizedBox(height: 24),
            Text(_serverMessage),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => supabase.auth.signOut(),
              child: const Text('로그아웃'),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dormn_api.dart';
import '../../models/settlement.dart';

const _blue = Color(0xFF3156D9);
const _pageBackground = Color(0xFFF7F8FC);

class SettlementAccountPage extends StatefulWidget {
  const SettlementAccountPage({super.key});

  @override
  State<SettlementAccountPage> createState() => _SettlementAccountPageState();
}

class _SettlementAccountPageState extends State<SettlementAccountPage> {
  final _api = const DormNApi();
  final _bankController = TextEditingController();
  final _numberController = TextEditingController();
  final _holderController = TextEditingController();

  SettlementAccount? _account;
  String? _error;
  String? _formError;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  @override
  void dispose() {
    _bankController.dispose();
    _numberController.dispose();
    _holderController.dispose();
    super.dispose();
  }

  Session? _currentSession() {
    try {
      return Supabase.instance.client.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadAccount() async {
    final session = _currentSession();
    final userId = session?.user.id;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
        _formError = null;
        _account = null;
      });
      _clearForm();
    }

    if (session == null || session.accessToken.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '로그인이 필요합니다. 다시 로그인해주세요.';
      });
      return;
    }

    try {
      final account = await _api.getMySettlementAccount(
        accessToken: session.accessToken,
      );
      if (!mounted || _currentSession()?.user.id != userId) return;
      setState(() {
        _account = account;
        _isLoading = false;
      });
      _setForm(account);
    } on ApiException catch (error) {
      if (!mounted || _currentSession()?.user.id != userId) return;
      setState(() {
        _isLoading = false;
        _error = _errorMessage(error);
      });
    } catch (_) {
      if (!mounted || _currentSession()?.user.id != userId) return;
      setState(() {
        _isLoading = false;
        _error = '기본 정산 계좌를 불러오지 못했습니다. 다시 시도해주세요.';
      });
    }
  }

  void _clearForm() {
    _bankController.clear();
    _numberController.clear();
    _holderController.clear();
  }

  void _setForm(SettlementAccount? account) {
    _bankController.text = account?.bankName ?? '';
    _numberController.text = account?.accountNumber ?? '';
    _holderController.text = account?.accountHolderName ?? '';
  }

  String _errorMessage(ApiException error) {
    switch (error.code) {
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다. 다시 로그인해주세요.';
      case 'SETTLEMENT_ACCOUNT_UNAVAILABLE':
        return '정산 계좌 서비스를 이용할 수 없습니다. 잠시 후 다시 시도해주세요.';
      default:
        return error.message;
    }
  }

  String? _validateInput() {
    final bankName = _bankController.text.trim();
    final accountNumber = _numberController.text.trim();
    final holderName = _holderController.text.trim();
    if (bankName.isEmpty || accountNumber.isEmpty || holderName.isEmpty) {
      return '은행명, 계좌번호, 예금주를 모두 입력해주세요.';
    }
    if (bankName.length > 100 ||
        accountNumber.length > 100 ||
        holderName.length > 100) {
      return '각 입력값은 100자 이내로 입력해주세요.';
    }
    return null;
  }

  bool _sameAsAccount(String bankName, String accountNumber, String holderName) {
    final account = _account;
    return account != null &&
        account.bankName == bankName &&
        account.accountNumber == accountNumber &&
        account.accountHolderName == holderName;
  }

  Future<void> _saveAccount() async {
    if (_isSaving) return;
    final validationError = _validateInput();
    if (validationError != null) {
      setState(() => _formError = validationError);
      return;
    }

    final bankName = _bankController.text.trim();
    final accountNumber = _numberController.text.trim();
    final holderName = _holderController.text.trim();
    if (_sameAsAccount(bankName, accountNumber, holderName)) {
      _showMessage('변경된 계좌 정보가 없습니다.');
      return;
    }

    final session = _currentSession();
    if (session == null || session.accessToken.isEmpty) {
      _showMessage('로그인이 필요합니다. 다시 로그인해주세요.');
      return;
    }

    setState(() {
      _isSaving = true;
      _formError = null;
    });

    try {
      final saved = await _api.upsertMySettlementAccount(
        bankName: bankName,
        accountNumber: accountNumber,
        accountHolderName: holderName,
        accessToken: session.accessToken,
      );
      if (!mounted || _currentSession()?.user.id != session.user.id) return;
      setState(() => _account = saved);
      _setForm(saved);
      _showMessage('기본 정산 계좌를 저장했습니다.');
    } on ApiException catch (error) {
      if (mounted) _showMessage(_errorMessage(error));
    } catch (_) {
      await _reconcileUncertainSave(
        session: session,
        attemptedBankName: bankName,
        attemptedAccountNumber: accountNumber,
        attemptedHolderName: holderName,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _reconcileUncertainSave({
    required Session session,
    required String attemptedBankName,
    required String attemptedAccountNumber,
    required String attemptedHolderName,
  }) async {
    if (!mounted) return;
    try {
      final refreshed = await _api.getMySettlementAccount(
        accessToken: session.accessToken,
      );
      if (!mounted || _currentSession()?.user.id != session.user.id) return;
      setState(() => _account = refreshed);
      if (refreshed != null &&
          refreshed.bankName == attemptedBankName &&
          refreshed.accountNumber == attemptedAccountNumber &&
          refreshed.accountHolderName == attemptedHolderName) {
        _showMessage('저장 결과를 확인했습니다.');
      } else {
        _showMessage('저장 결과를 확인하지 못했습니다. 입력값을 확인해주세요.');
      }
    } catch (_) {
      if (mounted) {
        _showMessage('저장 결과를 확인하지 못했습니다. 입력값을 유지했습니다.');
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _maskedAccountNumber(String value) {
    final maskLength = value.length <= 4 ? value.length : value.length - 4;
    final mask = List.filled(maskLength, '•').join();
    if (value.length <= 4) return mask;
    return '$mask${value.substring(value.length - 4)}';
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
          '정산 계좌 관리',
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
        onRefresh: _loadAccount,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.65,
              child: _ErrorState(message: _error!, onRetry: _loadAccount),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAccount,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        children: [
          _buildCurrentAccountCard(),
          const SizedBox(height: 14),
          _buildFormCard(),
          const SizedBox(height: 14),
          const _NoticeCard(
            icon: Icons.lock_outline_rounded,
            text:
                '이 계좌는 앞으로 확정할 거래에 사용하는 기본 계좌입니다. 이미 거래별로 확정된 계좌 snapshot은 기본 계좌를 수정해도 바뀌지 않습니다.',
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentAccountCard() {
    final account = _account;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '현재 기본 정산 계좌'),
          const SizedBox(height: 12),
          if (account == null)
            const Text(
              '아직 등록된 기본 계좌가 없습니다. 아래에 계좌 정보를 입력해주세요.',
              style: TextStyle(color: Color(0xFF697386), fontSize: 13),
            )
          else ...[
            _InfoRow(label: '은행명', value: account.bankName),
            _InfoRow(
              label: '계좌번호',
              value: _maskedAccountNumber(account.accountNumber),
            ),
            _InfoRow(label: '예금주', value: account.accountHolderName),
          ],
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(title: _account == null ? '기본 계좌 등록' : '기본 계좌 수정'),
          const SizedBox(height: 12),
          _AccountTextField(
            controller: _bankController,
            label: '은행명',
            hint: '예: 카카오뱅크',
          ),
          const SizedBox(height: 10),
          _AccountTextField(
            controller: _numberController,
            label: '계좌번호',
            hint: '계좌번호를 입력해주세요',
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 10),
          _AccountTextField(
            controller: _holderController,
            label: '예금주',
            hint: '예금주명을 입력해주세요',
          ),
          if (_formError != null) ...[
            const SizedBox(height: 8),
            Text(
              _formError!,
              style: const TextStyle(color: Color(0xFFD14343), fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _isSaving ? null : _saveAccount,
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: _isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('저장하기'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTextField extends StatelessWidget {
  const _AccountTextField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: 100,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        counterText: '',
        filled: true,
        fillColor: const Color(0xFFF7F8FC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: const TextStyle(fontWeight: FontWeight.w800));
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF697386), fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
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

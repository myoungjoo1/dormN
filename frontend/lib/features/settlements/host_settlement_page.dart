import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dormn_api.dart';
import '../../models/post.dart';
import '../../models/pickup.dart';
import '../../models/settlement.dart';

const _blue = Color(0xFF3156D9);
const _pageBackground = Color(0xFFF7F8FC);

class HostSettlementPage extends StatefulWidget {
  const HostSettlementPage({required this.postId, super.key});

  final int postId;

  @override
  State<HostSettlementPage> createState() => _HostSettlementPageState();
}

class _HostSettlementPageState extends State<HostSettlementPage> {
  final _api = const DormNApi();

  Post? _post;
  HostSettlementSummary? _summary;
  PickupSummary? _pickupSummary;
  SettlementAccount? _defaultAccount;
  SettlementAccount? _settlementAccount;
  String? _loadError;
  String? _refreshNotice;
  String? _pickupMessage;
  String? _accountMessage;
  bool _isLoading = true;
  bool _isAccountSaving = false;
  bool _isAccountConfirming = false;
  bool _accountConfirmationNeedsRefresh = false;
  bool _isStatusUpdating = false;
  bool _hasChanges = false;
  final _confirmingSettlementIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String? _accessToken() {
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadData({
    HostSettlementSummary? fallbackSummary,
    PickupSummary? fallbackPickupSummary,
    bool showLoading = true,
    String? fallbackNotice,
  }) async {
    if (!mounted) return;
    setState(() {
      if (showLoading) _isLoading = true;
      _loadError = null;
      _refreshNotice = null;
    });

    final accessToken = _accessToken();
    if (accessToken == null || accessToken.isEmpty) {
      if (!mounted) return;
      if (fallbackSummary != null && _summary != null) {
        setState(() {
          _summary = fallbackSummary;
          _pickupSummary = fallbackPickupSummary ?? _pickupSummary;
          _isLoading = false;
          _refreshNotice = fallbackNotice ?? '최신 정보를 다시 불러오지 못했습니다.';
        });
      } else {
        setState(() {
          _isLoading = false;
          _loadError = '로그인이 필요합니다.';
        });
      }
      return;
    }

    try {
      final post = await _api.getPost(widget.postId);
      final summary = await _api.getHostSettlements(
        postId: widget.postId,
        accessToken: accessToken,
      );
      PickupSummary? pickupSummary = fallbackPickupSummary ?? _pickupSummary;
      String? pickupMessage;
      try {
        pickupSummary = await _api.getPostPickups(
          postId: widget.postId,
          accessToken: accessToken,
        );
      } on ApiException catch (error) {
        pickupMessage = _pickupErrorMessage(error.code);
      } catch (_) {
        pickupMessage = '픽업 현황을 불러오지 못했습니다. 새로고침해주세요.';
      }
      SettlementAccount? defaultAccount;
      SettlementAccount? settlementAccount;
      String? accountMessage;
      try {
        defaultAccount = await _api.getMySettlementAccount(
          accessToken: accessToken,
        );
      } on ApiException {
        accountMessage = '기본 계좌를 불러오지 못했습니다.';
      }
      if (post.status != 'RECRUITING' && post.status != 'CANCELLED') {
        try {
          settlementAccount = await _api.getPostSettlementAccount(
            postId: widget.postId,
            accessToken: accessToken,
          );
        } on ApiException catch (error) {
          if (error.code != 'SETTLEMENT_ACCOUNT_NOT_FIXED') {
            accountMessage = '거래별 확정 계좌를 불러오지 못했습니다.';
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _post = post;
        _summary = summary;
        _pickupSummary = pickupSummary;
        _defaultAccount = defaultAccount;
        _settlementAccount = settlementAccount;
        _accountMessage = accountMessage;
        _pickupMessage = pickupMessage;
        _accountConfirmationNeedsRefresh = false;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      if (fallbackSummary != null && _summary != null) {
        setState(() {
          _summary = fallbackSummary;
          _pickupSummary = fallbackPickupSummary ?? _pickupSummary;
          _isLoading = false;
          _refreshNotice = fallbackNotice ?? '최신 정보를 다시 불러오지 못했습니다.';
        });
      } else {
        setState(() {
          _isLoading = false;
          _loadError = _loadErrorMessage(error.code);
        });
      }
    } catch (_) {
      if (!mounted) return;
      if (fallbackSummary != null && _summary != null) {
        setState(() {
          _summary = fallbackSummary;
          _pickupSummary = fallbackPickupSummary ?? _pickupSummary;
          _isLoading = false;
          _refreshNotice = fallbackNotice ?? '최신 정보를 다시 불러오지 못했습니다.';
        });
      } else {
        setState(() {
          _isLoading = false;
          _loadError = '정산 목록을 불러오지 못했습니다. 다시 시도해주세요.';
        });
      }
    }
  }

  String _loadErrorMessage(String code) {
    switch (code) {
      case 'DORM_VERIFICATION_REQUIRED':
        return '기숙사 인증을 완료한 사용자만 정산 기능을 이용할 수 있어요.';
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다.';
      case 'POST_AUTHOR_REQUIRED':
        return '모집자만 정산 목록을 확인할 수 있습니다.';
      case 'POST_NOT_FOUND':
        return '게시글을 찾을 수 없습니다.';
      default:
        return '정산 목록을 불러오지 못했습니다. 다시 시도해주세요.';
    }
  }

  String _pickupErrorMessage(String code) {
    switch (code) {
      case 'DORM_VERIFICATION_REQUIRED':
        return '기숙사 인증을 완료한 사용자만 픽업 기능을 이용할 수 있어요.';
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다.';
      case 'POST_AUTHOR_REQUIRED':
        return '모집자만 픽업 현황을 확인할 수 있습니다.';
      case 'POST_NOT_FOUND':
        return '게시글을 찾을 수 없습니다.';
      default:
        return '픽업 현황을 불러오지 못했습니다. 새로고침해주세요.';
    }
  }

  int get _confirmedCount {
    return _summary!.participants
        .where((participant) => participant.paymentStatus == 'CONFIRMED')
        .length;
  }

  int get _confirmedAmount {
    return _summary!.participants
        .where((participant) => participant.paymentStatus == 'CONFIRMED')
        .fold(0, (total, participant) => total + (participant.amount ?? 0));
  }

  int get _pendingAmount {
    final pending = _summary!.participantTotalAmount - _confirmedAmount;
    return pending < 0 ? 0 : pending;
  }

  double get _paymentProgress {
    final total = _summary!.participantTotalAmount;
    if (total == 0) return 0;
    return (_confirmedAmount / total).clamp(0.0, 1.0).toDouble();
  }

  String _dateText(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return local.year.toString() +
        '-' +
        two(local.month) +
        '-' +
        two(local.day) +
        ' ' +
        two(local.hour) +
        ':' +
        two(local.minute);
  }

  String get _statusLabel {
    switch (_summary!.status) {
      case 'CLOSED':
        return '모집 마감';
      case 'ORDERED':
        return '상품 주문 완료';
      case 'ARRIVED':
        return '상품 도착';
      case 'PICKUP':
        return '픽업 진행';
      case 'COMPLETED':
        return '거래 완료';
      case 'CANCELLED':
        return '거래 취소';
      default:
        return _summary!.status;
    }
  }

  int get _statusIndex {
    switch (_summary!.status) {
      case 'ORDERED':
        return 1;
      case 'ARRIVED':
        return 2;
      case 'PICKUP':
        return 3;
      case 'COMPLETED':
        return 4;
      default:
        return 0;
    }
  }

  Future<void> _confirmParticipantPayment(
    HostSettlementParticipant participant,
  ) async {
    final settlementId = participant.settlementId;
    if (settlementId == null ||
        participant.paymentStatus != 'SENT' ||
        _confirmingSettlementIds.contains(settlementId)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('입금 확인'),
        content: Text((participant.roomNumber ?? '참여자') + '의 실제 입금을 확인했나요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('입금 확인'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final accessToken = _accessToken();
    if (accessToken == null || accessToken.isEmpty) {
      _showMessage('로그인이 필요합니다.');
      return;
    }

    setState(() => _confirmingSettlementIds.add(settlementId));
    try {
      final response = await _api.confirmSettlement(
        settlementId: settlementId,
        accessToken: accessToken,
      );
      final updatedSummary = _summaryWithParticipant(
        participant,
        participant.copyWith(
          paymentStatus: response.paymentStatus,
          confirmedAt: response.confirmedAt,
        ),
      );
      if (!mounted) return;
      setState(() {
        _summary = updatedSummary;
        _confirmingSettlementIds.remove(settlementId);
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('입금 확인을 반영했습니다.')));

      // Do not repeat the successful POST if this refresh fails.
      await _loadData(
        fallbackSummary: updatedSummary,
        fallbackPickupSummary: _pickupSummary,
        fallbackNotice: '입금 확인은 반영됐지만 최신 정보를 다시 불러오지 못했습니다.',
        showLoading: false,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _confirmingSettlementIds.remove(settlementId));
      _showMessage(_confirmErrorMessage(error.code));
      if (error.code == 'SETTLEMENT_NOT_SENT' ||
          error.code == 'SETTLEMENT_NOT_FOUND') {
        await _loadData(showLoading: false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _confirmingSettlementIds.remove(settlementId));
      _showMessage('네트워크 오류로 입금 상태를 확인하지 못했습니다. 목록을 새로고침해주세요.');
    }
  }

  HostSettlementSummary _summaryWithParticipant(
    HostSettlementParticipant original,
    HostSettlementParticipant updated,
  ) {
    final summary = _summary!;
    return HostSettlementSummary(
      postId: summary.postId,
      status: summary.status,
      totalPrice: summary.totalPrice,
      participantTotalAmount: summary.participantTotalAmount,
      hostAmount: summary.hostAmount,
      participants: summary.participants
          .map(
            (participant) => participant.settlementId == original.settlementId
                ? updated
                : participant,
          )
          .toList(),
    );
  }

  HostSettlementSummary _summaryWithStatus(String status) {
    final summary = _summary!;
    return HostSettlementSummary(
      postId: summary.postId,
      status: status,
      totalPrice: summary.totalPrice,
      participantTotalAmount: summary.participantTotalAmount,
      hostAmount: summary.hostAmount,
      participants: summary.participants,
    );
  }

  Future<void> _editAccount() async {
    if (_isAccountSaving) return;
    final account = _defaultAccount;
    final bankController = TextEditingController(text: account?.bankName ?? '');
    final numberController = TextEditingController(
      text: account?.accountNumber ?? '',
    );
    final holderController = TextEditingController(
      text: account?.accountHolderName ?? '',
    );

    final values = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(account == null ? '기본 계좌 등록' : '기본 계좌 수정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bankController,
                decoration: const InputDecoration(labelText: '은행명'),
              ),
              TextField(
                controller: numberController,
                decoration: const InputDecoration(labelText: '계좌번호'),
              ),
              TextField(
                controller: holderController,
                decoration: const InputDecoration(labelText: '예금주'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final bankName = bankController.text.trim();
              final accountNumber = numberController.text.trim();
              final holderName = holderController.text.trim();
              if (bankName.isEmpty ||
                  accountNumber.isEmpty ||
                  holderName.isEmpty) {
                return;
              }
              Navigator.of(context).pop([bankName, accountNumber, holderName]);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    bankController.dispose();
    numberController.dispose();
    holderController.dispose();

    if (!mounted || values == null) return;
    final accessToken = _accessToken();
    if (accessToken == null || accessToken.isEmpty) {
      _showMessage('로그인이 필요합니다.');
      return;
    }

    setState(() => _isAccountSaving = true);
    try {
      final saved = await _api.upsertMySettlementAccount(
        bankName: values[0],
        accountNumber: values[1],
        accountHolderName: values[2],
        accessToken: accessToken,
      );
      if (!mounted) return;
      setState(() => _defaultAccount = saved);
      try {
        final refreshed = await _api.getMySettlementAccount(
          accessToken: accessToken,
        );
        if (!mounted) return;
        setState(() => _defaultAccount = refreshed ?? saved);
        _showMessage('기본 계좌를 저장했습니다.');
      } catch (_) {
        if (!mounted) return;
        _showMessage('기본 계좌는 저장됐지만 최신 정보 재조회에 실패했습니다.');
      }
    } on ApiException catch (error) {
      if (mounted) _showMessage(_accountErrorMessage(error.code));
    } catch (_) {
      if (mounted) _showMessage('기본 계좌 저장에 실패했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isAccountSaving = false);
    }
  }

  Future<void> _confirmAccountSnapshot() async {
    final account = _defaultAccount;
    if (_isAccountConfirming ||
        account == null ||
        _settlementAccount != null ||
        _summary?.status != 'CLOSED') {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('거래별 계좌 확정'),
        content: Text(
          '은행: ' +
              account.bankName +
              '\n계좌번호: ' +
              account.accountNumber +
              '\n예금주: ' +
              account.accountHolderName +
              '\n\n확정 후에는 이 거래의 계좌를 변경할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('확정하기'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final accessToken = _accessToken();
    if (accessToken == null || accessToken.isEmpty) {
      _showMessage('로그인이 필요합니다.');
      return;
    }

    setState(() => _isAccountConfirming = true);
    try {
      await _api.confirmPostSettlementAccount(
        postId: widget.postId,
        accessToken: accessToken,
      );
      try {
        final snapshot = await _api.getPostSettlementAccount(
          postId: widget.postId,
          accessToken: accessToken,
        );
        if (!mounted) return;
        setState(() => _settlementAccount = snapshot);
        _showMessage('거래별 계좌를 확정했습니다.');
      } catch (_) {
        if (!mounted) return;
        setState(() => _accountConfirmationNeedsRefresh = true);
        _showMessage('계좌 확정은 처리됐지만 최신 정보 재조회에 실패했습니다. 새로고침해주세요.');
      }
    } on ApiException catch (error) {
      if (mounted) _showMessage(_accountErrorMessage(error.code));
    } catch (_) {
      if (mounted) _showMessage('거래별 계좌 확정에 실패했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isAccountConfirming = false);
    }
  }

  String _accountErrorMessage(String code) {
    switch (code) {
      case 'SETTLEMENT_ACCOUNT_NOT_REGISTERED':
        return '먼저 기본 계좌를 등록해주세요.';
      case 'SETTLEMENT_ACCOUNT_ALREADY_FIXED':
        return '이 거래의 계좌는 이미 확정되었습니다.';
      case 'SETTLEMENT_ACCOUNT_NOT_FIXED':
        return '거래별 계좌가 아직 확정되지 않았습니다.';
      case 'SETTLEMENT_ACCOUNT_POST_NOT_CLOSED':
        return '모집 마감 후에만 거래별 계좌를 확정할 수 있습니다.';
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다.';
      case 'POST_AUTHOR_REQUIRED':
        return '모집자만 이 작업을 할 수 있습니다.';
      default:
        return '계좌 처리에 실패했습니다. 잠시 후 다시 시도해주세요.';
    }
  }

  bool get _allSettlementsConfirmed {
    return _summary!.participants.every(
      (participant) => participant.paymentStatus == 'CONFIRMED',
    );
  }

  String? get _nextStatus {
    switch (_summary!.status) {
      case 'CLOSED':
        return 'ORDERED';
      case 'ORDERED':
        return 'ARRIVED';
      case 'ARRIVED':
        return 'PICKUP';
      case 'PICKUP':
        return _pickupSummary?.participants.isEmpty == true
            ? 'COMPLETED'
            : null;
      default:
        return null;
    }
  }

  String _nextStatusLabel(String status) {
    switch (status) {
      case 'ORDERED':
        return '상품 주문 완료';
      case 'ARRIVED':
        return '상품 도착 완료';
      case 'PICKUP':
        return '픽업 시작';
      case 'COMPLETED':
        return '거래 완료';
      default:
        return status;
    }
  }

  Future<void> _advanceStatus() async {
    final nextStatus = _nextStatus;
    if (_isStatusUpdating || nextStatus == null) return;
    if (_summary!.status == 'CLOSED' && !_allSettlementsConfirmed) {
      _showMessage('모든 참여자의 입금 확인 후 주문할 수 있습니다.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('거래 상태 변경'),
        content: Text(_nextStatusLabel(nextStatus) + ' 상태로 변경할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('변경하기'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final accessToken = _accessToken();
    if (accessToken == null || accessToken.isEmpty) {
      _showMessage('로그인이 필요합니다.');
      return;
    }

    final previousStatus = _summary!.status;
    final fallbackSummary = _summary!;
    final fallbackPickupSummary = _pickupSummary;
    setState(() => _isStatusUpdating = true);
    try {
      await _api.updatePostStatus(
        postId: widget.postId,
        status: nextStatus,
        accessToken: accessToken,
      );
      final updatedSummary = _summaryWithStatus(nextStatus);
      if (!mounted) return;
      setState(() {
        _summary = updatedSummary;
        _hasChanges = true;
        _isStatusUpdating = false;
      });
      _showMessage('거래 상태를 변경했습니다.');
      // A refresh failure must not repeat the successful PATCH request.
      await _loadData(
        fallbackSummary: updatedSummary,
        fallbackPickupSummary: _pickupSummary,
        fallbackNotice: '거래 상태는 변경됐지만 최신 정보를 다시 불러오지 못했습니다.',
        showLoading: false,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isStatusUpdating = false);
      _showMessage(_statusErrorMessage(error.code));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isStatusUpdating = false);
      await _loadData(
        fallbackSummary: fallbackSummary,
        fallbackPickupSummary: fallbackPickupSummary,
        fallbackNotice: '거래 상태 변경 결과를 확인하지 못했습니다. 기존 데이터를 유지합니다.',
        showLoading: false,
      );
      if (!mounted) return;

      final statusChanged =
          _summary?.status != previousStatus || _post?.status != previousStatus;
      if (statusChanged) {
        setState(() => _hasChanges = true);
        _showMessage('서버에서 거래 상태 변경을 확인했습니다.');
      } else {
        _showMessage('거래 상태 변경 결과를 확인하지 못했습니다. 다시 시도하지 말고 새로고침해주세요.');
      }
    }
  }

  String _statusErrorMessage(String code) {
    switch (code) {
      case 'SETTLEMENTS_NOT_CONFIRMED':
        return '모든 참여자의 입금 확인 후 주문할 수 있습니다.';
      case 'PICKUPS_NOT_COMPLETED':
        return '모든 참여자의 수령 완료 후 거래를 완료할 수 있습니다.';
      case 'INVALID_POST_STATUS_TRANSITION':
        return '현재 거래 상태에서는 이 단계로 변경할 수 없습니다.';
      case 'POST_AUTHOR_REQUIRED':
        return '모집자만 거래 상태를 변경할 수 있습니다.';
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다.';
      default:
        return '거래 상태 변경에 실패했습니다. 잠시 후 다시 시도해주세요.';
    }
  }

  void _popWithResult() {
    if (!mounted) return;
    Navigator.of(context)
        .pop(_hasChanges ? <String, dynamic>{'changed': true} : null);
  }

  String _confirmErrorMessage(String code) {
    switch (code) {
      case 'SETTLEMENT_NOT_FOUND':
        return '정산 정보를 찾을 수 없습니다.';
      case 'SETTLEMENT_NOT_SENT':
        return '참여자가 아직 송금 완료로 표시하지 않았습니다.';
      case 'POST_AUTHOR_REQUIRED':
        return '모집자만 입금을 확인할 수 있습니다.';
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다.';
      default:
        return '입금 확인에 실패했습니다. 잠시 후 다시 시도해주세요.';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Map<String, dynamic>>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _popWithResult();
      },
      child: Scaffold(
        backgroundColor: _pageBackground,
        appBar: AppBar(
          backgroundColor: _pageBackground,
          elevation: 0,
          leading: IconButton(
            onPressed: _popWithResult,
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          ),
          title: const Text(
            '모집자 정산',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          centerTitle: true,
        ),
        body: _buildBody(),
        bottomNavigationBar: _summary == null ? null : _buildBottomBar(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _blue));
    }
    if (_loadError != null) {
      return _ErrorState(message: _loadError!, onRetry: _loadData);
    }

    final post = _post;
    final summary = _summary;
    if (post == null || summary == null) {
      return const Center(child: Text('정산 정보를 찾을 수 없습니다.'));
    }

    return RefreshIndicator(
      color: _blue,
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          _buildProductCard(post),
          const SizedBox(height: 12),
          if (_refreshNotice != null) ...[
            _Notice(icon: Icons.info_outline, text: _refreshNotice!),
            const SizedBox(height: 12),
          ],
          _buildSummaryCard(post),
          const SizedBox(height: 12),
          _buildAccountCard(),
          const SizedBox(height: 12),
          _buildParticipantsCard(summary),
          const SizedBox(height: 12),
          _buildPickupCard(),
          const SizedBox(height: 12),
          _buildStatusCard(summary),
        ],
      ),
    );
  }

  Widget _buildProductCard(Post post) {
    return _Card(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 78,
              height: 78,
              child: post.imageUrl == null
                  ? Container(
                      color: const Color(0xFFE9EEFF),
                      child: const Icon(
                        Icons.shopping_bag_outlined,
                        color: _blue,
                        size: 34,
                      ),
                    )
                  : Image.network(
                      post.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: const Color(0xFFE9EEFF),
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: _blue,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '공동구매 모집 관리',
                  style: TextStyle(color: _blue, fontSize: 12),
                ),
                const SizedBox(height: 5),
                Text(
                  post.productName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '게시글 #' + widget.postId.toString(),
                  style: const TextStyle(
                    color: Color(0xFF697386),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(Post post) {
    final summary = _summary!;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '전체 정산 정보'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: '전체 구매 금액',
                  value: summary.totalPrice.toString() + '원',
                ),
              ),
              Expanded(
                child: _Metric(
                  label: '전체 구매 수량',
                  value: post.totalQuantity.toString() + '개',
                ),
              ),
            ],
          ),
          const Divider(height: 26),
          _InfoRow(
            label: '참여자 수',
            value: summary.participants.length.toString() + '명',
          ),
          _InfoRow(
            label: '참여자 정산 합계',
            value: summary.participantTotalAmount.toString() + '원',
          ),
          _InfoRow(
            label: '모집자 부담 금액',
            value: summary.hostAmount.toString() + '원',
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                '입금 확인 완료',
                style: TextStyle(color: Color(0xFF697386), fontSize: 12),
              ),
              const Spacer(),
              Text(
                _confirmedAmount.toString() +
                    '/' +
                    summary.participantTotalAmount.toString() +
                    '원',
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _paymentProgress,
              minHeight: 8,
              backgroundColor: const Color(0xFFE5EAFE),
              color: _blue,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _confirmedCount.toString() +
                '/' +
                summary.participants.length.toString() +
                '명 확인 · 미확인 금액 ' +
                _pendingAmount.toString() +
                '원',
            style: const TextStyle(color: Color(0xFF697386), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    final defaultAccount = _defaultAccount;
    final fixedAccount = _settlementAccount;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SectionTitle(title: '기본 계좌'),
              const Spacer(),
              TextButton(
                onPressed: _isAccountSaving ? null : _editAccount,
                child: Text(defaultAccount == null ? '등록' : '수정'),
              ),
            ],
          ),
          if (defaultAccount == null)
            const _Notice(
              icon: Icons.account_balance_outlined,
              text: '기본 계좌를 등록하면 모집 마감 후 거래별 계좌로 확정할 수 있습니다.',
            )
          else ...[
            _InfoRow(label: '은행명', value: defaultAccount.bankName),
            _InfoRow(
              label: '계좌번호',
              value: defaultAccount.accountNumber,
              trailing: IconButton(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: defaultAccount.accountNumber),
                  );
                  if (mounted) _showMessage('계좌번호를 복사했습니다.');
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                color: _blue,
                tooltip: '계좌번호 복사',
              ),
            ),
            _InfoRow(label: '예금주', value: defaultAccount.accountHolderName),
          ],
          const Divider(height: 26),
          const _SectionTitle(title: '거래별 확정 계좌'),
          const SizedBox(height: 8),
          if (fixedAccount != null) ...[
            _InfoRow(label: '은행명', value: fixedAccount.bankName),
            _InfoRow(label: '계좌번호', value: fixedAccount.accountNumber),
            _InfoRow(label: '예금주', value: fixedAccount.accountHolderName),
            const SizedBox(height: 6),
            const _Notice(
              icon: Icons.lock_outline_rounded,
              text: '이 거래의 계좌가 확정되었습니다. 기본 계좌를 수정해도 변경되지 않습니다.',
            ),
          ] else if (_summary?.status != 'CLOSED')
            const _Notice(
              icon: Icons.schedule_rounded,
              text: '모집 마감 후 거래별 계좌를 확정할 수 있습니다.',
            )
          else if (defaultAccount == null)
            const _Notice(icon: Icons.info_outline, text: '기본 계좌를 먼저 등록해주세요.')
          else if (_accountConfirmationNeedsRefresh)
            const _Notice(
              icon: Icons.refresh_rounded,
              text: '계좌 확정 요청은 처리됐습니다. 새로고침으로 확정 상태를 확인해주세요.',
            )
          else
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: _isAccountConfirming
                    ? null
                    : _confirmAccountSnapshot,
                icon: _isAccountConfirming
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.lock_outline_rounded, size: 18),
                label: const Text('거래별 계좌로 확정하기'),
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (_accountMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _accountMessage!,
              style: const TextStyle(color: Color(0xFF697386), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildParticipantsCard(HostSettlementSummary summary) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '참여자별 입금 현황'),
          const SizedBox(height: 10),
          if (summary.participants.isEmpty)
            const _Notice(icon: Icons.people_outline, text: '아직 참여자가 없습니다.')
          else
            ...summary.participants.map(_buildParticipantTile),
        ],
      ),
    );
  }

  Widget _buildParticipantTile(HostSettlementParticipant participant) {
    final settlementId = participant.settlementId;
    final isCancelled = _summary!.status == 'CANCELLED';
    final isConfirming =
        settlementId != null && _confirmingSettlementIds.contains(settlementId);
    final canConfirm =
        participant.paymentStatus == 'SENT' &&
        settlementId != null &&
        !isConfirming;
    final amountText = participant.amount == null
        ? '정산 금액 대기'
        : participant.amount.toString() + '원';

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFE5EAFE),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_outline, color: _blue, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participant.roomNumber ?? '호실 정보 없음',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  participant.quantity.toString() + '개 · ' + amountText,
                  style: const TextStyle(
                    color: Color(0xFF697386),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '송금 ' +
                      _dateText(participant.sentAt) +
                      ' · 확인 ' +
                      _dateText(participant.confirmedAt),
                  style: const TextStyle(
                    color: Color(0xFF8A92A5),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (isConfirming)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: _blue),
            )
          else if (canConfirm)
            TextButton(
              onPressed: () => _confirmParticipantPayment(participant),
              child: const Text('입금 확인'),
            )
          else
            _PaymentBadge(
              status: isCancelled ? 'CANCELLED' : participant.paymentStatus,
            ),
        ],
      ),
    );
  }

  Widget _buildPickupCard() {
    final pickupSummary = _pickupSummary;
    if (pickupSummary == null) {
      return _Card(
        child: _Notice(
          icon: Icons.refresh_rounded,
          text: _pickupMessage ?? '픽업 현황을 불러오지 못했습니다. 새로고침해주세요.',
        ),
      );
    }

    final totalCount = pickupSummary.totalCount;
    final completedCount = pickupSummary.participants
        .where((participant) => participant.pickupCompletedAt != null)
        .length;
    final progress = totalCount == 0 ? 0.0 : completedCount / totalCount;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '참여자별 픽업 현황'),
          const SizedBox(height: 12),
          if (_pickupMessage != null) ...[
            _Notice(icon: Icons.info_outline, text: _pickupMessage!),
            const SizedBox(height: 8),
          ],
          if (totalCount == 0)
            const _Notice(icon: Icons.people_outline, text: '픽업 대상 참여자가 없습니다.')
          else ...[
            Row(
              children: [
                Expanded(
                  child: _Metric(label: '전체 픽업 대상', value: '$totalCount명'),
                ),
                Expanded(
                  child: _Metric(label: '수령 완료', value: '$completedCount명'),
                ),
                Expanded(
                  child: _Metric(
                    label: '수령 대기',
                    value: '${totalCount - completedCount}명',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: const Color(0xFFE5EAFE),
                color: _blue,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$completedCount/$totalCount명 수령 완료 · ${(progress * 100).round()}%',
              style: const TextStyle(color: Color(0xFF697386), fontSize: 12),
            ),
            const SizedBox(height: 4),
            ...pickupSummary.participants.map(_buildPickupParticipantTile),
          ],
        ],
      ),
    );
  }

  Widget _buildPickupParticipantTile(PickupParticipant participant) {
    final completed = participant.pickupCompletedAt != null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            completed ? Icons.check_circle_outline : Icons.schedule_outlined,
            color: completed
                ? const Color(0xFF087A35)
                : const Color(0xFF9A6100),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participant.roomNumber ?? '호실 정보 없음',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${participant.quantity}개 · ${completed ? '수령 완료' : '수령 대기'}',
                  style: const TextStyle(
                    color: Color(0xFF697386),
                    fontSize: 12,
                  ),
                ),
                if (completed)
                  Text(
                    _dateText(participant.pickupCompletedAt),
                    style: const TextStyle(
                      color: Color(0xFF8A92A5),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            completed ? '완료' : '대기',
            style: TextStyle(
              color: completed
                  ? const Color(0xFF087A35)
                  : const Color(0xFF9A6100),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(HostSettlementSummary summary) {
    const labels = ['모집 마감', '상품 주문', '상품 도착', '픽업 진행', '거래 완료'];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '거래 진행 상태'),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(labels.length * 2 - 1, (index) {
                if (index.isOdd) {
                  return Container(
                    width: 26,
                    height: 3,
                    color: index ~/ 2 < _statusIndex
                        ? _blue
                        : const Color(0xFFE1E5EF),
                  );
                }
                final step = index ~/ 2;
                final active = step <= _statusIndex;
                return Column(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: active ? _blue : const Color(0xFFE1E5EF),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: active
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 16,
                              )
                            : Text(
                                (step + 1).toString(),
                                style: const TextStyle(
                                  color: Color(0xFF8A92A5),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      labels[step],
                      style: TextStyle(
                        color: active ? _blue : const Color(0xFF8A92A5),
                        fontSize: 10,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
          if (summary.status == 'CANCELLED') ...[
            const SizedBox(height: 12),
            const _Notice(icon: Icons.cancel_outlined, text: '이 거래는 취소되었습니다.'),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final nextStatus = _nextStatus;
    final hasAction = nextStatus != null;
    final canAdvance =
        hasAction &&
        !_isStatusUpdating &&
        (_summary!.status != 'CLOSED' || _allSettlementsConfirmed);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 12,
              offset: Offset(0, -3),
            ),
          ],
        ),
        child: hasAction
            ? SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: canAdvance ? _advanceStatus : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    disabledBackgroundColor: const Color(0xFFD9DEEC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: _isStatusUpdating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          canAdvance
                              ? _nextStatusLabel(nextStatus!)
                              : '모든 참여자의 입금 확인 후 진행할 수 있습니다',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              )
            : Text(
                _summary!.status == 'PICKUP'
                    ? '픽업 완료 처리는 다음 픽업 단계에서 연결됩니다.'
                    : _statusLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF697386),
                  fontWeight: FontWeight.w700,
                ),
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
      width: double.infinity,
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
    return Text(
      title,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF697386), fontSize: 11),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: const TextStyle(
            color: _blue,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.trailing});

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF697386), fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          trailing ?? const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: _blue, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Color(0xFF697386), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final confirmed = status == 'CONFIRMED';
    final cancelled = status == 'CANCELLED';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: confirmed
            ? const Color(0xFFD9FFE5)
            : cancelled
            ? const Color(0xFFE8EAF0)
            : const Color(0xFFFFF0D8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        cancelled
            ? '거래 취소'
            : confirmed
            ? '확인 완료'
            : '송금 대기',
        style: TextStyle(
          color: confirmed
              ? const Color(0xFF087A35)
              : cancelled
              ? const Color(0xFF697386)
              : const Color(0xFF9A6100),
          fontSize: 11,
          fontWeight: FontWeight.w800,
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

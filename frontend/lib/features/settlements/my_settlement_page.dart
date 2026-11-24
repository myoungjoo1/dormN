import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dormn_api.dart';
import '../../models/post.dart';
import '../../models/settlement.dart';

const _blue = Color(0xFF3156D9);
const _pageBackground = Color(0xFFF7F8FC);

class MySettlementPage extends StatefulWidget {
  const MySettlementPage({required this.postId, super.key});

  final int postId;

  @override
  State<MySettlementPage> createState() => _MySettlementPageState();
}

class _MySettlementPageState extends State<MySettlementPage> {
  final _api = const DormNApi();

  Post? _post;
  Settlement? _settlement;
  SettlementAccount? _account;
  String? _loadError;
  String? _settlementMessage;
  String? _accountMessage;
  String? _refreshNotice;
  String? _postStatusOverride;
  bool _isLoading = true;
  bool _isSending = false;
  bool _isPickingUp = false;
  bool _hasChanges = false;

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
    Settlement? fallbackSettlement,
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
      setState(() {
        _isLoading = false;
        _loadError = '로그인이 필요합니다.';
      });
      return;
    }

    try {
      final post = await _api.getPost(widget.postId);
      Settlement? settlement = fallbackSettlement;
      String? settlementMessage;

      try {
        settlement = await _api.getMySettlement(
          postId: widget.postId,
          accessToken: accessToken,
        );
      } on ApiException catch (error) {
        if (error.code == 'SETTLEMENT_NOT_FOUND' &&
            fallbackSettlement == null) {
          settlementMessage = post.status == 'CANCELLED'
              ? '이 공동구매는 취소되어 정산이 생성되지 않았습니다.'
              : '정산 정보가 아직 생성되지 않았습니다. 모집 마감 후 정상 성립하면 표시됩니다.';
          settlement = null;
        } else {
          rethrow;
        }
      }

      SettlementAccount? account;
      String? accountMessage;
      if (settlement != null) {
        try {
          account = await _api.getPostSettlementAccount(
            postId: widget.postId,
            accessToken: accessToken,
          );
        } on ApiException catch (error) {
          if (error.code == 'SETTLEMENT_ACCOUNT_NOT_FIXED') {
            accountMessage = '모집자가 거래 계좌를 확정하면 송금할 수 있습니다.';
          } else if (error.code == 'SETTLEMENT_ACCOUNT_POST_NOT_CLOSED') {
            accountMessage = '아직 거래 계좌를 안내할 수 없는 상태입니다.';
          } else {
            accountMessage = '거래 계좌를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.';
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _post = post;
        _postStatusOverride = null;
        _settlement = settlement;
        _account = account;
        _settlementMessage = settlementMessage;
        _accountMessage = accountMessage;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      if (fallbackSettlement != null && _post != null) {
        setState(() {
          _settlement = fallbackSettlement;
          _isLoading = false;
          _refreshNotice =
              fallbackNotice ?? '송금 상태는 반영됐지만 최신 정보를 다시 불러오지 못했습니다.';
        });
      } else {
        setState(() {
          _isLoading = false;
          _loadError = _loadErrorMessage(error.code);
        });
      }
    } catch (_) {
      if (!mounted) return;
      if (fallbackSettlement != null && _post != null) {
        setState(() {
          _settlement = fallbackSettlement;
          _isLoading = false;
          _refreshNotice =
              fallbackNotice ?? '송금 상태는 반영됐지만 최신 정보를 다시 불러오지 못했습니다.';
        });
      } else {
        setState(() {
          _isLoading = false;
          _loadError = '정산 정보를 불러오지 못했습니다. 다시 시도해주세요.';
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
      case 'POST_NOT_FOUND':
        return '게시글을 찾을 수 없습니다.';
      default:
        return '정산 정보를 불러오지 못했습니다. 다시 시도해주세요.';
    }
  }

  int get _statusIndex {
    switch (_settlement?.paymentStatus) {
      case 'SENT':
        return 1;
      case 'CONFIRMED':
        return 2;
      default:
        return 0;
    }
  }

  String get _statusLabel {
    switch (_settlement?.paymentStatus) {
      case 'SENT':
        return '입금 확인 중';
      case 'CONFIRMED':
        return '정산 완료';
      default:
        return '송금 대기';
    }
  }

  Future<void> _copyAccountNumber() async {
    final account = _account;
    if (account == null) return;
    await Clipboard.setData(ClipboardData(text: account.accountNumber));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('계좌번호를 복사했습니다.')));
  }

  Future<void> _confirmTransfer() async {
    final settlement = _settlement;
    if (_account == null ||
        settlement == null ||
        settlement.paymentStatus != 'UNPAID' ||
        _isSending) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('송금 완료 확인'),
        content: const Text(
          '외부 은행 앱에서 실제 송금을 완료했나요?\n\n'
          '확인하면 모집자에게 입금 확인을 요청합니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('송금했어요'),
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

    setState(() => _isSending = true);
    try {
      final responseSent = await _api.markSettlementSent(
        settlementId: settlement.id,
        accessToken: accessToken,
      );
      final sent = Settlement(
        id: responseSent.id,
        participationId: responseSent.participationId,
        quantity: responseSent.quantity ?? settlement.quantity,
        pickupCompletedAt:
            responseSent.pickupCompletedAt ?? settlement.pickupCompletedAt,
        amount: responseSent.amount,
        paymentStatus: responseSent.paymentStatus,
        sentAt: responseSent.sentAt,
        confirmedAt: responseSent.confirmedAt,
        createdAt: responseSent.createdAt,
      );
      if (!mounted) return;
      setState(() {
        _settlement = sent;
        _isSending = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('송금 완료로 표시했습니다.')));

      // A refresh failure must not make the user submit the same POST again.
      await _loadData(fallbackSettlement: sent, showLoading: false);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isSending = false);
      _showMessage(_sentErrorMessage(error.code));
      if (error.code == 'SETTLEMENT_NOT_UNPAID' ||
          error.code == 'SETTLEMENT_ACCOUNT_NOT_FIXED' ||
          error.code == 'SETTLEMENT_ACCOUNT_POST_NOT_CLOSED') {
        await _loadData(showLoading: false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSending = false);
      _showMessage('네트워크 오류로 송금 상태를 확인하지 못했습니다. 새로고침 후 다시 확인해주세요.');
    }
  }

  Future<void> _confirmPickup() async {
    final post = _post;
    final settlement = _settlement;
    final postStatus = post == null ? null : _displayPostStatus(post);
    if (post == null ||
        settlement == null ||
        postStatus != 'PICKUP' ||
        settlement.pickupCompletedAt != null ||
        _isPickingUp) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('수령 완료 확인'),
        content: Text(
          '${post.productName}\n'
          '수령 수량: ${settlement.quantity ?? 0}개\n\n'
          '실제로 상품을 수령했나요?\n'
          '수령 완료 처리 후에는 취소할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('수령 완료'),
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

    setState(() => _isPickingUp = true);
    try {
      final response = await _api.completePickup(
        participationId: settlement.participationId,
        accessToken: accessToken,
      );
      final completed = Settlement(
        id: settlement.id,
        participationId: settlement.participationId,
        quantity: settlement.quantity,
        pickupCompletedAt: response.pickupCompletedAt,
        amount: settlement.amount,
        paymentStatus: settlement.paymentStatus,
        sentAt: settlement.sentAt,
        confirmedAt: settlement.confirmedAt,
        createdAt: settlement.createdAt,
      );
      if (!mounted) return;
      setState(() {
        _settlement = completed;
        _postStatusOverride = response.postStatus;
        _isPickingUp = false;
        _hasChanges = true;
      });
      _showMessage('수령 완료로 표시했습니다.');

      await _loadData(
        fallbackSettlement: completed,
        fallbackNotice: '수령 완료는 반영됐지만 최신 정보를 다시 불러오지 못했습니다.',
        showLoading: false,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isPickingUp = false);
      _showMessage(_pickupErrorMessage(error.code));
      if (_shouldRefreshPickupState(error.code)) {
        await _refreshPickupStateAfterRequest(
          previousSettlement: settlement!,
          previousPostStatus: postStatus!,
          fallbackNotice: '픽업 상태를 다시 확인해주세요.',
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isPickingUp = false);
      await _refreshPickupStateAfterRequest(
        previousSettlement: settlement!,
        previousPostStatus: postStatus!,
        fallbackNotice: '픽업 요청 결과를 확인하지 못했습니다. 현재 상태를 새로 확인해주세요.',
      );
      if (mounted && _settlement?.pickupCompletedAt == null) {
        _showMessage('픽업 상태를 확인하지 못했습니다. 중복 요청하지 말고 새로고침해주세요.');
      }
    }
  }

  Future<void> _refreshPickupStateAfterRequest({
    required Settlement previousSettlement,
    required String previousPostStatus,
    required String fallbackNotice,
  }) async {
    await _loadData(
      fallbackSettlement: previousSettlement,
      fallbackNotice: fallbackNotice,
      showLoading: false,
    );
    if (!mounted) return;

    final pickupCompleted =
        previousSettlement.pickupCompletedAt == null &&
        _settlement?.pickupCompletedAt != null;
    final postStatusChanged =
        _post?.status != null && _post!.status != previousPostStatus;
    if (pickupCompleted || postStatusChanged) {
      setState(() => _hasChanges = true);
    }
  }

  bool _shouldRefreshPickupState(String code) {
    return code == 'POST_NOT_PICKUP' ||
        code == 'POST_ALREADY_COMPLETED' ||
        code == 'PARTICIPATION_NOT_FOUND';
  }

  String _pickupErrorMessage(String code) {
    switch (code) {
      case 'DORM_VERIFICATION_REQUIRED':
        return '기숙사 인증을 완료한 사용자만 픽업 기능을 이용할 수 있어요.';
      case 'POST_NOT_PICKUP':
        return '아직 상품을 수령할 수 있는 상태가 아닙니다.';
      case 'POST_ALREADY_COMPLETED':
        return '거래가 이미 완료되었습니다. 수령 상태를 다시 확인해주세요.';
      case 'PARTICIPATION_OWNER_REQUIRED':
        return '본인의 참여 정보만 수령 완료할 수 있습니다.';
      case 'PARTICIPATION_NOT_FOUND':
        return '참여 정보를 찾을 수 없습니다.';
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다.';
      default:
        return '수령 완료 처리에 실패했습니다. 잠시 후 다시 시도해주세요.';
    }
  }

  String _sentErrorMessage(String code) {
    switch (code) {
      case 'DORM_VERIFICATION_REQUIRED':
        return '기숙사 인증을 완료한 사용자만 정산 기능을 이용할 수 있어요.';
      case 'SETTLEMENT_NOT_FOUND':
        return '정산 정보가 아직 생성되지 않았습니다.';
      case 'SETTLEMENT_NOT_UNPAID':
        return '이미 처리된 정산입니다. 최신 상태를 다시 확인해주세요.';
      case 'SETTLEMENT_ACCOUNT_NOT_FIXED':
        return '모집자가 거래 계좌를 아직 확정하지 않았습니다.';
      case 'SETTLEMENT_ACCOUNT_POST_NOT_CLOSED':
        return '현재 거래 상태에서는 송금할 수 없습니다.';
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다.';
      default:
        return '송금 상태를 변경하지 못했습니다. 잠시 후 다시 시도해주세요.';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _displayPostStatus(Post post) => _postStatusOverride ?? post.status;

  String _postStatusLabel(String status) {
    switch (status) {
      case 'CLOSED':
        return '상품 주문 대기';
      case 'ORDERED':
        return '상품 도착 대기';
      case 'ARRIVED':
        return '픽업 시작 대기';
      case 'PICKUP':
        return '상품 수령 가능';
      case 'COMPLETED':
        return '거래 완료';
      case 'CANCELLED':
        return '거래 취소';
      default:
        return status;
    }
  }

  void _popWithResult() {
    if (!mounted) return;
    Navigator.of(context)
        .pop(_hasChanges ? <String, dynamic>{'changed': true} : null);
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
            '내 정산',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          centerTitle: true,
        ),
        body: _buildBody(),
        bottomNavigationBar: _settlement == null ? null : _buildBottomBar(),
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
    if (post == null) {
      return const Center(child: Text('게시글 정보를 찾을 수 없습니다.'));
    }

    return RefreshIndicator(
      color: _blue,
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _buildProductCard(post),
          const SizedBox(height: 12),
          if (_refreshNotice != null) ...[
            _Notice(icon: Icons.info_outline, text: _refreshNotice!),
            const SizedBox(height: 12),
          ],
          if (_settlement == null)
            _Card(
              child: _Notice(
                icon: Icons.schedule_rounded,
                text: _settlementMessage ?? '정산 정보가 없습니다.',
              ),
            )
          else ...[
            _buildAmountCard(),
            const SizedBox(height: 12),
            _buildAccountCard(),
            const SizedBox(height: 12),
            _buildStatusCard(),
            const SizedBox(height: 12),
            _buildPickupCard(post),
            const SizedBox(height: 12),
            _buildDetailCard(),
          ],
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
                  '공동구매 정산',
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
                  '모집자 ' + (post.authorRoomNumber ?? '-'),
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

  Widget _buildAmountCard() {
    final settlement = _settlement!;
    return _Card(
      color: _blue,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '내 최종 정산 금액',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            settlement.amount.toString() + '원',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            (settlement.quantity ?? 0).toString() + '개 참여 · ' + _statusLabel,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    final account = _account;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '송금 계좌'),
          const SizedBox(height: 12),
          if (account == null)
            _Notice(
              icon: Icons.schedule_rounded,
              text: _accountMessage ?? '모집자의 계좌 확정을 기다려주세요.',
            )
          else ...[
            _InfoRow(label: '은행', value: account.bankName),
            _InfoRow(
              label: '계좌번호',
              value: account.accountNumber,
              trailing: IconButton(
                onPressed: _copyAccountNumber,
                icon: const Icon(Icons.copy_rounded, size: 18),
                color: _blue,
                tooltip: '계좌번호 복사',
              ),
            ),
            _InfoRow(label: '예금주', value: account.accountHolderName),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    const labels = ['송금 대기', '입금 확인 중', '정산 완료'];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '정산 상태'),
          const SizedBox(height: 18),
          Row(
            children: List.generate(labels.length * 2 - 1, (index) {
              if (index.isOdd) {
                return Expanded(
                  child: Container(
                    height: 3,
                    color: index ~/ 2 < _statusIndex
                        ? _blue
                        : const Color(0xFFE1E5EF),
                  ),
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
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildPickupCard(Post post) {
    final settlement = _settlement!;
    final status = _displayPostStatus(post);
    final pickupCompletedAt = settlement.pickupCompletedAt;
    final canCompletePickup = status == 'PICKUP' && pickupCompletedAt == null;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '픽업 및 수령'),
          const SizedBox(height: 12),
          _InfoRow(label: '거래 상태', value: _postStatusLabel(status)),
          _InfoRow(label: '픽업 장소', value: post.pickupLocation),
          _InfoRow(label: '수령 수량', value: '${settlement.quantity ?? 0}개'),
          _InfoRow(
            label: '수령 상태',
            value: pickupCompletedAt == null ? '미수령' : '수령 완료',
          ),
          if (pickupCompletedAt != null)
            _InfoRow(label: '수령 완료 시각', value: _dateText(pickupCompletedAt)),
          const SizedBox(height: 8),
          if (canCompletePickup)
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                onPressed: _isPickingUp ? null : _confirmPickup,
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isPickingUp
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '상품 수령 완료',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            )
          else
            _Notice(
              icon: pickupCompletedAt != null
                  ? Icons.check_circle_outline
                  : status == 'CANCELLED'
                  ? Icons.cancel_outlined
                  : Icons.info_outline,
              text: pickupCompletedAt != null
                  ? '수령 완료 처리되었습니다.'
                  : status == 'CANCELLED'
                  ? '취소된 거래라 상품을 수령할 수 없습니다.'
                  : '${_postStatusLabel(status)} 상태에서는 아직 수령할 수 없습니다.',
            ),
        ],
      ),
    );
  }

  Widget _buildDetailCard() {
    final settlement = _settlement!;
    return _Card(
      child: Column(
        children: [
          _InfoRow(label: '정산 ID', value: '#' + settlement.id.toString()),
          _InfoRow(
            label: '참여 ID',
            value: '#' + settlement.participationId.toString(),
          ),
          _InfoRow(label: '송금 시각', value: _dateText(settlement.sentAt)),
          _InfoRow(label: '입금 확인 시각', value: _dateText(settlement.confirmedAt)),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final settlement = _settlement!;
    final isUnpaid = settlement.paymentStatus == 'UNPAID';
    final isConfirmed = settlement.paymentStatus == 'CONFIRMED';
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
        child: isUnpaid
            ? SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _account != null && !_isSending
                      ? _confirmTransfer
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    disabledBackgroundColor: const Color(0xFFD9DEEC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _account != null ? '송금했어요' : '계좌 확정 대기 중',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              )
            : Center(
                child: Text(
                  isConfirmed ? '정산이 완료되었습니다.' : '모집자의 입금 확인을 기다리는 중입니다.',
                  style: TextStyle(
                    color: isConfirmed ? _blue : const Color(0xFF697386),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.color = Colors.white});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 86,
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  late HostSettlementSummary _summary;
  late SettlementAccount _account;
  bool _accountFixed = false;
  String _postStatus = 'CLOSED';

  final _productName = '햇반 24개 한 박스';
  final _totalQuantity = 24;

  @override
  void initState() {
    super.initState();
    _account = const SettlementAccount(
      bankName: '카카오뱅크',
      accountNumber: '000123456789',
      accountHolderName: '홍길동',
    );
    _summary = HostSettlementSummary(
      postId: widget.postId,
      status: 'CLOSED',
      totalPrice: 22900,
      participantTotalAmount: 19082,
      hostAmount: 3818,
      participants: const [
        HostSettlementParticipant(
          settlementId: 201,
          userId: 'user-717-2',
          roomNumber: '717-2호',
          quantity: 4,
          amount: 3816,
          paymentStatus: 'UNPAID',
          sentAt: null,
          confirmedAt: null,
        ),
        HostSettlementParticipant(
          settlementId: 202,
          userId: 'user-709-2',
          roomNumber: '709-2호',
          quantity: 6,
          amount: 5725,
          paymentStatus: 'SENT',
          sentAt: null,
          confirmedAt: null,
        ),
        HostSettlementParticipant(
          settlementId: 203,
          userId: 'user-717-3',
          roomNumber: '717-3호',
          quantity: 10,
          amount: 9541,
          paymentStatus: 'CONFIRMED',
          sentAt: null,
          confirmedAt: null,
        ),
      ],
    );
  }

  int get _confirmedAmount => _summary.participants
      .where((participant) => participant.paymentStatus == 'CONFIRMED')
      .fold(0, (total, participant) => total + (participant.amount ?? 0));

  bool get _allSettlementsConfirmed =>
      _summary.participants.isNotEmpty &&
      _summary.participants.every(
        (participant) => participant.paymentStatus == 'CONFIRMED',
      );

  int get _statusIndex {
    switch (_postStatus) {
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

  String get _nextStatusLabel {
    switch (_postStatus) {
      case 'CLOSED':
        return '상품 주문 완료';
      case 'ORDERED':
        return '상품 도착 표시';
      case 'ARRIVED':
        return '픽업 시작 표시';
      default:
        return '다음 단계 없음';
    }
  }

  Future<void> _copyAccountNumber() async {
    await Clipboard.setData(ClipboardData(text: _account.accountNumber));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('계좌번호를 복사했습니다.')));
  }

  Future<void> _editAccount() async {
    final bankController = TextEditingController(text: _account.bankName);
    final numberController = TextEditingController(
      text: _account.accountNumber,
    );
    final holderController = TextEditingController(
      text: _account.accountHolderName,
    );

    final result = await showDialog<SettlementAccount>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_account.bankName.isEmpty ? '계좌 등록' : '기본 계좌 수정'),
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
                keyboardType: TextInputType.number,
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
              Navigator.of(context).pop(
                SettlementAccount(
                  bankName: bankName,
                  accountNumber: accountNumber,
                  accountHolderName: holderName,
                  updatedAt: DateTime.now(),
                ),
              );
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
    bankController.dispose();
    numberController.dispose();
    holderController.dispose();

    if (!mounted || result == null) return;
    setState(() => _account = result);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('기본 계좌 정보를 수정했습니다.')));
  }

  Future<void> _confirmAccountSnapshot() async {
    if (_accountFixed || _postStatus != 'CLOSED') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('거래 계좌 확정'),
        content: const Text(
          '현재 기본 계좌를 이 공동구매의 입금 계좌로 확정할까요?\n\n'
          '확정 후에는 이 거래의 계좌를 수정할 수 없습니다.',
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
    setState(() => _accountFixed = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('거래별 입금 계좌를 확정했습니다.')));
  }

  Future<void> _confirmParticipantPayment(
    HostSettlementParticipant participant,
  ) async {
    if (participant.paymentStatus != 'SENT') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('입금 확인'),
        content: Text('${participant.roomNumber ?? '참여자'}의 입금을 확인할까요?'),
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
    setState(() {
      _summary = HostSettlementSummary(
        postId: _summary.postId,
        status: _summary.status,
        totalPrice: _summary.totalPrice,
        participantTotalAmount: _summary.participantTotalAmount,
        hostAmount: _summary.hostAmount,
        participants: _summary.participants
            .map(
              (item) => item.settlementId == participant.settlementId
                  ? item.copyWith(
                      paymentStatus: 'CONFIRMED',
                      confirmedAt: DateTime.now(),
                    )
                  : item,
            )
            .toList(),
      );
    });
  }

  void _advanceStatus() {
    if (_postStatus == 'CLOSED' && !_allSettlementsConfirmed) return;
    final next = switch (_postStatus) {
      'CLOSED' => 'ORDERED',
      'ORDERED' => 'ARRIVED',
      'ARRIVED' => 'PICKUP',
      _ => _postStatus,
    };
    if (next == _postStatus) return;
    setState(() => _postStatus = next);
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
          '모집자 관리',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProductHeader(),
              const SizedBox(height: 12),
              _buildSummaryCard(),
              const SizedBox(height: 12),
              _buildAccountCard(),
              const SizedBox(height: 12),
              _buildParticipantsCard(),
              const SizedBox(height: 12),
              _buildStatusCard(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildProductHeader() {
    return _Card(
      child: Row(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: const Color(0xFFE9EEFF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.shopping_bag_outlined,
              color: _blue,
              size: 34,
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
                  _productName,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '게시글 #${widget.postId}',
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

  Widget _buildSummaryCard() {
    final progress = _summary.participantTotalAmount == 0
        ? 0.0
        : (_confirmedAmount / _summary.participantTotalAmount)
              .clamp(0.0, 1.0)
              .toDouble();
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
                  value: '${_summary.totalPrice}원',
                ),
              ),
              Expanded(
                child: _Metric(label: '전체 구매 수량', value: '$_totalQuantity개'),
              ),
            ],
          ),
          const Divider(height: 26),
          _InfoRow(label: '참여자 수', value: '${_summary.participants.length}명'),
          _InfoRow(
            label: '참여자 정산 합계',
            value: '${_summary.participantTotalAmount}원',
          ),
          _InfoRow(label: '모집자 부담 금액', value: '${_summary.hostAmount}원'),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                '입금 확인 금액',
                style: TextStyle(color: Color(0xFF697386), fontSize: 12),
              ),
              const Spacer(),
              Text(
                '$_confirmedAmount/${_summary.participantTotalAmount}원',
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
              value: progress,
              minHeight: 8,
              backgroundColor: const Color(0xFFE5EAFE),
              color: _blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _SectionTitle(title: '정산 계좌'),
              const Spacer(),
              TextButton(
                onPressed: _editAccount,
                child: Text(_accountFixed ? '기본 계좌 보기' : '기본 계좌 수정'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _InfoRow(label: '은행', value: _account.bankName),
          _InfoRow(
            label: '계좌번호',
            value: _account.accountNumber,
            trailing: IconButton(
              onPressed: _copyAccountNumber,
              icon: const Icon(Icons.copy_rounded, size: 18),
              color: _blue,
              tooltip: '계좌번호 복사',
            ),
          ),
          _InfoRow(label: '예금주', value: _account.accountHolderName),
          const SizedBox(height: 8),
          if (_accountFixed)
            const _Notice(
              icon: Icons.lock_outline_rounded,
              text: '이 거래의 계좌가 확정되었습니다. 거래별 계좌는 수정할 수 없습니다.',
            )
          else
            SizedBox(
              width: double.infinity,
              height: 44,
              child: FilledButton.icon(
                onPressed: _confirmAccountSnapshot,
                icon: const Icon(Icons.lock_outline_rounded, size: 18),
                label: const Text('이 거래의 계좌로 확정하기'),
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildParticipantsCard() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '참여자별 입금 현황'),
          const SizedBox(height: 10),
          ..._summary.participants.map(_buildParticipantTile),
        ],
      ),
    );
  }

  Widget _buildParticipantTile(HostSettlementParticipant participant) {
    final canConfirm = participant.paymentStatus == 'SENT';
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
                  participant.roomNumber ?? '호실 미등록',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '${participant.quantity}개 · ${participant.amount ?? 0}원',
                  style: const TextStyle(
                    color: Color(0xFF697386),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (canConfirm)
            TextButton(
              onPressed: () => _confirmParticipantPayment(participant),
              child: const Text('입금 확인'),
            )
          else
            _PaymentBadge(status: participant.paymentStatus),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
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
                                '${step + 1}',
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
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final isTerminal = _postStatus == 'PICKUP' || _postStatus == 'COMPLETED';
    final canAdvance = _postStatus == 'CLOSED'
        ? _allSettlementsConfirmed && _accountFixed
        : _postStatus == 'ORDERED' || _postStatus == 'ARRIVED';
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
        child: isTerminal
            ? Text(
                _postStatus == 'COMPLETED'
                    ? '거래가 완료되었습니다.'
                    : '픽업 기능은 다음 단계에서 연결됩니다.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF697386),
                  fontWeight: FontWeight.w700,
                ),
              )
            : SizedBox(
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
                  child: Text(
                    canAdvance
                        ? _nextStatusLabel
                        : '모든 참여자의 입금 확인 후 진행할 수 있습니다',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: confirmed ? const Color(0xFFD9FFE5) : const Color(0xFFFFF0D8),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        confirmed ? '확인 완료' : '송금 대기',
        style: TextStyle(
          color: confirmed ? const Color(0xFF087A35) : const Color(0xFF9A6100),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

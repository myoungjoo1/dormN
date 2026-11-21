import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

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
  // Temporary local data until the settlement API is connected.
  late Settlement _settlement;
  final _accountConfirmed = true;
  final _bankName = '카카오뱅크';
  final _accountNumber = '000123456789';
  final _accountHolderName = '홍길동';
  final _productName = '햇반 24개 한 박스';
  final _hostRoomNumber = '717-1호';
  final _pickupLocation = '기숙사 A동 로비';

  @override
  void initState() {
    super.initState();
    _settlement = Settlement(
      id: 101,
      participationId: 42,
      quantity: 4,
      pickupCompletedAt: null,
      amount: 3817,
      paymentStatus: 'UNPAID',
      sentAt: null,
      confirmedAt: null,
      createdAt: DateTime.now(),
    );
  }

  int get _statusIndex {
    switch (_settlement.paymentStatus) {
      case 'SENT':
        return 1;
      case 'CONFIRMED':
        return 2;
      default:
        return 0;
    }
  }

  String get _statusLabel {
    switch (_settlement.paymentStatus) {
      case 'SENT':
        return '입금 확인 중';
      case 'CONFIRMED':
        return '정산 완료';
      default:
        return '송금 대기';
    }
  }

  Future<void> _copyAccountNumber() async {
    await Clipboard.setData(ClipboardData(text: _accountNumber));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('계좌번호를 복사했습니다.')));
  }

  Future<void> _confirmTransfer() async {
    if (!_accountConfirmed || _settlement.paymentStatus != 'UNPAID') return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('송금 완료 확인'),
        content: const Text(
          '외부 은행 앱에서 실제 송금을 완료했나요?\n\n'
          '확인 후 모집자가 입금을 확인합니다.',
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

    setState(() {
      _settlement = Settlement(
        id: _settlement.id,
        participationId: _settlement.participationId,
        quantity: _settlement.quantity,
        pickupCompletedAt: _settlement.pickupCompletedAt,
        amount: _settlement.amount,
        paymentStatus: 'SENT',
        sentAt: DateTime.now(),
        confirmedAt: _settlement.confirmedAt,
        createdAt: _settlement.createdAt,
      );
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('송금 완료로 표시했습니다.')));
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
          '내 정산',
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
              _buildProductCard(),
              const SizedBox(height: 12),
              _buildAmountCard(),
              const SizedBox(height: 12),
              _buildAccountCard(),
              const SizedBox(height: 12),
              _buildStatusCard(),
              const SizedBox(height: 12),
              _buildDetailCard(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildProductCard() {
    return _Card(
      child: Row(
        children: [
          Container(
            width: 78,
            height: 78,
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
                  '공동구매 정산',
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
                  '모집자 $_hostRoomNumber',
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
            '${_settlement.amount}원',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${_settlement.quantity ?? 0}개 참여 · $_statusLabel',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
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
          const _SectionTitle(title: '송금 계좌'),
          const SizedBox(height: 12),
          if (!_accountConfirmed)
            const _Notice(
              icon: Icons.schedule_rounded,
              text: '모집자가 계좌를 등록하면 송금 안내가 표시됩니다.',
            )
          else ...[
            _InfoRow(label: '은행', value: _bankName),
            _InfoRow(
              label: '계좌번호',
              value: _accountNumber,
              trailing: IconButton(
                onPressed: _copyAccountNumber,
                icon: const Icon(Icons.copy_rounded, size: 18),
                color: _blue,
                tooltip: '계좌번호 복사',
              ),
            ),
            _InfoRow(label: '예금주', value: _accountHolderName),
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

  Widget _buildDetailCard() {
    return _Card(
      child: Column(
        children: [
          _InfoRow(label: '정산 ID', value: '#${_settlement.id}'),
          _InfoRow(label: '참여 ID', value: '#${_settlement.participationId}'),
          _InfoRow(label: '픽업 장소', value: _pickupLocation),
          _InfoRow(
            label: '수령 상태',
            value: _settlement.pickupCompletedAt == null ? '미수령' : '수령 완료',
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final isUnpaid = _settlement.paymentStatus == 'UNPAID';
    final isConfirmed = _settlement.paymentStatus == 'CONFIRMED';
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
                  onPressed: _accountConfirmed ? _confirmTransfer : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    disabledBackgroundColor: const Color(0xFFD9DEEC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: Text(
                    _accountConfirmed ? '송금했어요' : '계좌 확정 대기 중',
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
            width: 76,
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

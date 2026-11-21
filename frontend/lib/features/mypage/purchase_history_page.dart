import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dormn_api.dart';
import '../../models/participation_history.dart';
import '../../models/post.dart';
import '../posts/post_detail_page.dart';
import '../settlements/host_settlement_page.dart';
import '../settlements/my_settlement_page.dart';

const _blue = Color(0xFF3156D9);
const _pageBackground = Color(0xFFF7F8FC);

enum PurchaseHistoryTab { hosted, participated }

enum _HistoryFilter { all, recruiting, inProgress, completed, cancelled }

class PurchaseHistoryPage extends StatefulWidget {
  const PurchaseHistoryPage({
    required this.initialTab,
    super.key,
  });

  final PurchaseHistoryTab initialTab;

  @override
  State<PurchaseHistoryPage> createState() => _PurchaseHistoryPageState();
}

class _PurchaseHistoryPageState extends State<PurchaseHistoryPage>
    with SingleTickerProviderStateMixin {
  final _api = const DormNApi();
  late final TabController _tabController;
  List<Post> _hostedPosts = [];
  List<ParticipationHistory> _participatedPosts = [];
  _HistoryFilter _hostedFilter = _HistoryFilter.all;
  _HistoryFilter _participatedFilter = _HistoryFilter.all;
  String? _error;
  bool _isLoading = true;
  bool _isOpeningEntry = false;
  int _requestVersion = 0;

  PurchaseHistoryTab get _selectedTab =>
      _tabController.index == 0
          ? PurchaseHistoryTab.hosted
          : PurchaseHistoryTab.participated;

  _HistoryFilter get _selectedFilter => _selectedTab == PurchaseHistoryTab.hosted
      ? _hostedFilter
      : _participatedFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab == PurchaseHistoryTab.hosted ? 0 : 1,
    )..addListener(_onTabChanged);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    setState(() {});
  }

  Session? _currentSession() {
    try {
      return Supabase.instance.client.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadHistory({bool showLoading = true}) async {
    final version = ++_requestVersion;
    if (mounted) {
      setState(() {
        if (showLoading) _isLoading = true;
        _error = null;
      });
    }

    final session = _currentSession();
    if (session == null) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _isLoading = false;
        _error = '로그인이 필요합니다. 다시 로그인해주세요.';
      });
      return;
    }

    try {
      final hostedFuture = _api.getMyPosts(accessToken: session.accessToken);
      final participatedFuture =
          _api.getMyParticipations(accessToken: session.accessToken);
      final results = await Future.wait([hostedFuture, participatedFuture]);
      if (!mounted || version != _requestVersion) return;

      setState(() {
        _hostedPosts = results[0] as List<Post>;
        _participatedPosts = results[1] as List<ParticipationHistory>;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _isLoading = false;
        _error = _errorMessage(error);
      });
    } catch (_) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _isLoading = false;
        _error = '공동구매 내역을 불러오지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
    }
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

  void _selectFilter(_HistoryFilter filter) {
    setState(() {
      if (_selectedTab == PurchaseHistoryTab.hosted) {
        _hostedFilter = filter;
      } else {
        _participatedFilter = filter;
      }
    });
  }

  List<Post> get _visibleHostedPosts =>
      _hostedPosts.where((post) => _matchesFilter(post.status, _hostedFilter)).toList();

  List<ParticipationHistory> get _visibleParticipatedPosts => _participatedPosts
      .where((item) => _matchesFilter(item.post.status, _participatedFilter))
      .toList();

  bool _matchesFilter(String status, _HistoryFilter filter) {
    switch (filter) {
      case _HistoryFilter.all:
        return true;
      case _HistoryFilter.recruiting:
        return status == 'RECRUITING';
      case _HistoryFilter.inProgress:
        return const {'CLOSED', 'ORDERED', 'ARRIVED', 'PICKUP'}.contains(status);
      case _HistoryFilter.completed:
        return status == 'COMPLETED';
      case _HistoryFilter.cancelled:
        return status == 'CANCELLED';
    }
  }

  Future<void> _openHosted(Post post) async {
    if (_isOpeningEntry) return;
    setState(() => _isOpeningEntry = true);
    final Widget page = _isInProgress(post.status)
        ? HostSettlementPage(postId: post.id)
        : PostDetailPage(postId: post.id);
    await _openPage(page);
  }

  Future<void> _openParticipated(ParticipationHistory item) async {
    if (_isOpeningEntry) return;
    setState(() => _isOpeningEntry = true);
    final Widget page = item.post.status == 'RECRUITING'
        ? PostDetailPage(postId: item.post.id)
        : _isInProgress(item.post.status)
            ? MySettlementPage(postId: item.post.id)
            : PostDetailPage(postId: item.post.id);
    await _openPage(page);
  }

  Future<void> _openPage(Widget page) async {
    try {
      final result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => page),
      );
      if (!mounted) return;
      setState(() => _isOpeningEntry = false);
      if (result?['changed'] == true) {
        await _loadHistory(showLoading: false);
      }
    } catch (_) {
      if (mounted) setState(() => _isOpeningEntry = false);
    }
  }

  bool _isInProgress(String status) =>
      const {'CLOSED', 'ORDERED', 'ARRIVED', 'PICKUP'}.contains(status);

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
          '공동구매 내역',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _blue,
          unselectedLabelColor: Color(0xFF697386),
          indicatorColor: _blue,
          tabs: const [
            Tab(text: '내가 모집한 내역'),
            Tab(text: '내가 참여한 내역'),
          ],
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
        onRefresh: _loadHistory,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.65,
              child: _ErrorState(message: _error!, onRetry: _loadHistory),
            ),
          ],
        ),
      );
    }

    final isHosted = _selectedTab == PurchaseHistoryTab.hosted;
    final hasItems = isHosted
        ? _visibleHostedPosts.isNotEmpty
        : _visibleParticipatedPosts.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _FilterRow(selected: _selectedFilter, onSelected: _selectFilter),
          const SizedBox(height: 14),
          if (!hasItems)
            _EmptyHistory(filtered: _selectedFilter != _HistoryFilter.all)
          else if (isHosted)
            ..._visibleHostedPosts.map(
              (post) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _HistoryCard(
                  post: post,
                  onTap: () => _openHosted(post),
                ),
              ),
            )
          else
            ..._visibleParticipatedPosts.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _HistoryCard(
                  post: item.post,
                  participation: item,
                  onTap: () => _openParticipated(item),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.selected, required this.onSelected});

  final _HistoryFilter selected;
  final ValueChanged<_HistoryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    const filters = [
      (_HistoryFilter.all, '전체'),
      (_HistoryFilter.recruiting, '모집 중'),
      (_HistoryFilter.inProgress, '진행 중'),
      (_HistoryFilter.completed, '완료'),
      (_HistoryFilter.cancelled, '취소'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in filters) ...[
            ChoiceChip(
              label: Text(filter.$2),
              selected: selected == filter.$1,
              onSelected: (_) => onSelected(filter.$1),
              selectedColor: _blue,
              labelStyle: TextStyle(
                color: selected == filter.$1 ? Colors.white : const Color(0xFF526079),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
              side: BorderSide.none,
              backgroundColor: Colors.white,
              showCheckmark: false,
            ),
            const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.post,
    required this.onTap,
    this.participation,
  });

  final Post post;
  final ParticipationHistory? participation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = post.totalQuantity <= 0
        ? 0.0
        : (post.filledQuantity / post.totalQuantity).clamp(0.0, 1.0).toDouble();
    final unitPrice = post.totalQuantity <= 0
        ? 0
        : (post.totalPrice / post.totalQuantity).round();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProductImage(url: post.imageUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                post.productName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusBadge(status: post.status),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_formatNumber(unitPrice)}원 / 개',
                          style: const TextStyle(
                            color: _blue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '작성일 ${_formatDate(post.createdAt)}',
                          style: const TextStyle(
                            color: Color(0xFF8993A5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress,
                minHeight: 7,
                borderRadius: BorderRadius.circular(10),
                backgroundColor: const Color(0xFFE8ECF8),
                color: _blue,
              ),
              const SizedBox(height: 7),
              Text(
                '${post.filledQuantity}/${post.totalQuantity}개 모집 · ${post.participantCount}명 참여',
                style: const TextStyle(
                  color: Color(0xFF526079),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (participation != null) ...[
                const Divider(height: 20),
                _ParticipationSummary(item: participation!),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatNumber(int value) =>
      value.toString().replaceAllMapped(RegExp(r'(?<!^)(?=(\d{3})+$)'), (match) => ',');

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
  }
}

class _ParticipationSummary extends StatelessWidget {
  const _ParticipationSummary({required this.item});

  final ParticipationHistory item;

  @override
  Widget build(BuildContext context) {
    final settlement = item.settlementAmount == null
        ? '정산 전'
        : '${_formatNumber(item.settlementAmount!)}원';
    final payment = item.paymentStatus == null
        ? '정산 대기'
        : _paymentStatusLabel(item.paymentStatus!);
    final pickup = item.pickupCompletedAt == null ? '수령 전' : '수령 완료';

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _InfoPill(label: '${item.quantity}개 참여'),
        _InfoPill(label: '확정 금액 $settlement'),
        _InfoPill(label: payment),
        _InfoPill(label: pickup),
      ],
    );
  }

  String _paymentStatusLabel(String status) {
    switch (status) {
      case 'UNPAID':
        return '송금 대기';
      case 'SENT':
        return '입금 확인 중';
      case 'CONFIRMED':
        return '정산 완료';
      default:
        return status;
    }
  }

  String _formatNumber(int value) =>
      value.toString().replaceAllMapped(RegExp(r'(?<!^)(?=(\d{3})+$)'), (match) => ',');
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4FC),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF526079),
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 74,
        height: 74,
        child: url == null || url!.isEmpty
            ? const _ImagePlaceholder()
            : Image.network(
                url!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const _ImagePlaceholder(),
              ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEFF2FA),
      child: const Icon(Icons.shopping_bag_outlined, color: _blue, size: 30),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'RECRUITING':
        return const Color(0xFF159447);
      case 'CANCELLED':
        return const Color(0xFFB7791F);
      case 'COMPLETED':
        return const Color(0xFF697386);
      default:
        return _blue;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'RECRUITING':
        return '모집 중';
      case 'CLOSED':
        return '모집 마감';
      case 'ORDERED':
        return '주문 완료';
      case 'ARRIVED':
        return '상품 도착';
      case 'PICKUP':
        return '픽업 중';
      case 'COMPLETED':
        return '거래 완료';
      case 'CANCELLED':
        return '거래 취소';
      default:
        return status;
    }
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 72),
      alignment: Alignment.center,
      child: Text(
        filtered ? '해당 상태의 공동구매 내역이 없습니다.' : '공동구매 내역이 없습니다.',
        style: const TextStyle(color: Color(0xFF697386)),
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

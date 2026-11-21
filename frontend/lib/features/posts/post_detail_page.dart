import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dormn_api.dart';
import '../../models/participation.dart';
import '../../models/post.dart';

const _blue = Color(0xFF3156D9);
const _pageBackground = Color(0xFFF7F8FC);

typedef PostLoader = Future<Post> Function(int postId);
typedef CurrentUserIdProvider = String? Function();
typedef QuoteLoader = Future<ParticipationQuote> Function(
  int postId,
  int quantity,
  String accessToken,
);
typedef ParticipationLoader = Future<MyParticipation> Function(
  int postId,
  String accessToken,
);
typedef JoinLoader = Future<Participation> Function(
  int postId,
  int quantity,
  String accessToken,
);
typedef AccessTokenProvider = String? Function();

class PostDetailPage extends StatefulWidget {
  const PostDetailPage({
    required this.postId,
    this.postLoader,
    this.currentUserIdProvider,
    this.quoteLoader,
    this.participationLoader,
    this.joinLoader,
    this.accessTokenProvider,
    super.key,
  });

  final int postId;
  final PostLoader? postLoader;
  final CurrentUserIdProvider? currentUserIdProvider;
  final QuoteLoader? quoteLoader;
  final ParticipationLoader? participationLoader;
  final JoinLoader? joinLoader;
  final AccessTokenProvider? accessTokenProvider;

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final _api = const DormNApi();
  Post? _post;
  String? _currentUserId;
  MyParticipation? _myParticipation;
  ParticipationQuote? _quote;
  String? _quoteError;
  String? _participationError;
  int _quantity = 0;
  bool _isLoading = true;
  bool _isQuoteLoading = false;
  bool _isJoining = false;
  bool _hasChanges = false;
  bool _isNotFound = false;
  Timer? _quoteDebounce;
  int _quoteRequestVersion = 0;

  bool get _isAuthor =>
      _currentUserId != null && _currentUserId == _post?.authorId;

  bool get _isJoined => _myParticipation?.isJoined == true;

  bool get _canJoin =>
      _currentUserId != null &&
      !_isAuthor &&
      !_isJoined &&
      _participationError == null &&
      _post?.status == 'RECRUITING' &&
      _post!.deadline.isAfter(DateTime.now()) &&
      _post!.remainingQuantity > 0;

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  @override
  void dispose() {
    _quoteDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadPost() async {
    final previousPost = _post;
    final previousParticipation = _myParticipation;
    _quoteDebounce?.cancel();
    _quoteRequestVersion += 1;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _isNotFound = false;
      });
    }

    try {
      final loader = widget.postLoader ?? _api.getPost;
      final post = await loader(widget.postId);
      if (!mounted) return;

      final currentUserId = _getCurrentUserId();
      final isAuthor = currentUserId != null && currentUserId == post.authorId;
      MyParticipation? myParticipation;
      String? participationError;
      final accessToken = _getAccessToken();
      if (!isAuthor && accessToken != null && accessToken.isNotEmpty) {
        try {
          final loader = widget.participationLoader ?? _api.getMyParticipation;
          myParticipation = await loader(widget.postId, accessToken);
        } on ApiException {
          participationError = '참여 여부를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.';
        } catch (_) {
          participationError = '참여 여부를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.';
        }
      }
      if (_hasChanges && previousParticipation?.isJoined == true) {
        myParticipation = previousParticipation;
        participationError = null;
      }

      final maxQuantity = post.remainingQuantity;
      final nextQuantity = maxQuantity <= 0
          ? 0
          : _quantity.clamp(1, maxQuantity).toInt();
      setState(() {
        _post = post;
        _currentUserId = currentUserId;
        _myParticipation = myParticipation;
        _participationError = participationError;
        _quote = null;
        _quoteError = null;
        _quantity = nextQuantity;
        _isLoading = false;
      });

      if (!isAuthor &&
          participationError == null &&
          myParticipation?.isJoined != true) {
        _scheduleQuote();
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _post = _hasChanges ? previousPost : null;
        _myParticipation = _hasChanges ? previousParticipation : null;
        _quote = null;
        _isLoading = false;
        _isNotFound = error.statusCode == 404 || error.code == 'POST_NOT_FOUND';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _post = _hasChanges ? previousPost : null;
        _myParticipation = _hasChanges ? previousParticipation : null;
        _quote = null;
        _isLoading = false;
        _isNotFound = false;
      });
    }
  }

  String? _getCurrentUserId() {
    if (widget.currentUserIdProvider != null) {
      return widget.currentUserIdProvider!();
    }
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  String? _getAccessToken() {
    if (widget.accessTokenProvider != null) {
      return widget.accessTokenProvider!();
    }
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } catch (_) {
      return null;
    }
  }

  void _scheduleQuote() {
    _quoteDebounce?.cancel();
    final version = ++_quoteRequestVersion;
    if (!_canJoin) {
      setState(() {
        _quote = null;
        _isQuoteLoading = false;
      });
      return;
    }

    setState(() {
      _quote = null;
      _quoteError = null;
      _isQuoteLoading = true;
    });
    _quoteDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(_fetchQuote(version, _quantity));
    });
  }

  Future<void> _fetchQuote(int version, int quantity) async {
    final accessToken = _getAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      if (mounted && version == _quoteRequestVersion) {
        setState(() {
          _isQuoteLoading = false;
          _quoteError = '예상 금액을 조회하려면 로그인이 필요합니다.';
        });
      }
      return;
    }

    try {
      final loader = widget.quoteLoader ?? _api.quoteParticipation;
      final quote = await loader(widget.postId, quantity, accessToken);
      if (!mounted ||
          version != _quoteRequestVersion ||
          _quantity != quantity) {
        return;
      }
      setState(() {
        _quote = quote;
        _isQuoteLoading = false;
        _quoteError = null;
      });
    } on ApiException {
      if (!mounted || version != _quoteRequestVersion) return;
      setState(() {
        _quote = null;
        _isQuoteLoading = false;
        _quoteError = '예상 금액을 조회하지 못했습니다. 수량을 다시 선택해주세요.';
      });
    } catch (_) {
      if (!mounted || version != _quoteRequestVersion) return;
      setState(() {
        _quote = null;
        _isQuoteLoading = false;
        _quoteError = '예상 금액을 조회하지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
    }
  }

  void _changeQuantity(int delta) {
    final post = _post;
    if (!_canJoin || post == null) return;
    final next = (_quantity + delta).clamp(1, post.remainingQuantity).toInt();
    if (next == _quantity) return;
    setState(() => _quantity = next);
    _scheduleQuote();
  }

  void _showProductLink() {
    final url = _post?.productUrl;
    if (url == null || url.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('상품 링크'),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestJoin() async {
    final post = _post;
    final quote = _quote;
    if (!_canJoin ||
        post == null ||
        quote == null ||
        quote.quantity != _quantity ||
        _isQuoteLoading ||
        _isJoining) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('공동구매 참여 확인'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              post.productName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            _DialogRow(label: '신청 수량', value: '$_quantity개'),
            _DialogRow(label: '예상 부담 금액', value: '${quote.estimatedAmount}원'),
            _DialogRow(label: '픽업 장소', value: post.pickupLocation),
            const SizedBox(height: 12),
            const Text(
              '모집 마감 후 최종 정산 금액이 확정됩니다.',
              style: TextStyle(color: Color(0xFF697386), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('참여 확정'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _isJoining = true);
    try {
      final accessToken = _getAccessToken();
      if (accessToken == null || accessToken.isEmpty) {
        _showMessage('참여하려면 로그인이 필요합니다.');
        return;
      }

      final loader = widget.joinLoader ?? _api.joinPost;
      final participation = await loader(widget.postId, _quantity, accessToken);
      if (!mounted) return;

      setState(() {
        _hasChanges = true;
        _myParticipation = MyParticipation(
          isJoined: true,
          participationId: participation.id,
          quantity: participation.quantity,
        );
      });
      _showMessage('공동구매 참여가 완료되었습니다.');
      // Reload failure must not resend the already successful join request.
      await _loadPost();
    } on ApiException catch (error) {
      if (!mounted) return;
      _showMessage(_joinErrorMessage(error));
      if (error.code == 'INSUFFICIENT_QUANTITY' ||
          error.code == 'POST_NOT_RECRUITING' ||
          error.code == 'RECRUITMENT_DEADLINE_PASSED') {
        await _loadPost();
      }
    } catch (_) {
      if (mounted) _showMessage('공동구매 참여에 실패했습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  String _joinErrorMessage(ApiException error) {
    switch (error.code) {
      case 'PARTICIPATION_ALREADY_EXISTS':
        return '이미 참여한 공동구매입니다.';
      case 'INSUFFICIENT_QUANTITY':
        return '남은 모집 수량이 부족합니다.';
      case 'POST_NOT_RECRUITING':
        return '모집이 마감된 공동구매입니다.';
      case 'RECRUITMENT_DEADLINE_PASSED':
        return '모집 마감 시간이 지났습니다.';
      case 'POST_AUTHOR_CANNOT_JOIN':
        return '모집자는 자신의 공동구매에 참여할 수 없습니다.';
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '참여하려면 로그인이 필요합니다.';
      default:
        return '공동구매 참여에 실패했습니다. 잠시 후 다시 시도해주세요.';
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _popWithResult() {
    if (!mounted) return;
    Navigator.of(context)
        .pop(_hasChanges ? <String, dynamic>{'changed': true} : null);
  }

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final showJoinBar = post != null && _currentUserId != null && !_isAuthor;
    final bottomBar = !showJoinBar
        ? null
        : _isJoined
        ? _buildJoinedBar()
        : _participationError != null
        ? _buildParticipationErrorBar()
        : _buildJoinBar();
    return PopScope<bool>(
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
            '공동구매 상세',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          centerTitle: true,
        ),
        body: _buildBody(post),
        bottomNavigationBar: bottomBar,
      ),
    );
  }

  Widget _buildBody(Post? post) {
    if (post == null) {
      if (_isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return _buildErrorState();
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadPost,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProductCard(post),
              const SizedBox(height: 12),
              _buildRecruitmentCard(post),
              const SizedBox(height: 12),
              _buildTradeInfoCard(post),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isNotFound ? Icons.search_off_rounded : Icons.cloud_off_rounded,
              color: const Color(0xFF8A92A5),
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              _isNotFound ? '게시글을 찾을 수 없습니다.' : '게시글을 불러오지 못했습니다.',
              textAlign: TextAlign.center,
            ),
            if (!_isNotFound) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _loadPost, child: const Text('다시 시도')),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProductCard(Post post) {
    return _Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProductImage(imageUrl: post.imageUrl),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _StatusBadge(status: post.status),
                    const Spacer(),
                    Text(
                      '모집자 ${post.authorRoomNumber ?? '호실 미등록'}',
                      style: const TextStyle(
                        color: Color(0xFF697386),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  post.productName,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (post.productUrl != null && post.productUrl!.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  OutlinedButton.icon(
                    onPressed: _showProductLink,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('상품 링크 보기'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _blue,
                      side: const BorderSide(color: Color(0xFFCBD5FF)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecruitmentCard(Post post) {
    final progress = post.totalQuantity <= 0
        ? 0.0
        : (post.filledQuantity / post.totalQuantity).clamp(0.0, 1.0).toDouble();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '구매 및 모집 현황'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Metric(label: '전체 구매 금액', value: '${post.totalPrice}원'),
              ),
              Expanded(
                child: _Metric(
                  label: '예상 개당 가격',
                  value: '${_unitPrice(post).round()}원',
                ),
              ),
            ],
          ),
          const Divider(height: 26),
          _InfoRow(label: '전체 상품 수량', value: '${post.totalQuantity}개'),
          _InfoRow(label: '모집자 구매 수량', value: '${post.hostQuantity}개'),
          _InfoRow(
            label: '현재 모집 현황',
            value: '${post.filledQuantity}/${post.totalQuantity}개',
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
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                post.remainingQuantity > 0
                    ? '남은 모집 수량 ${post.remainingQuantity}개'
                    : '모집 수량 소진',
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '참여자 ${post.participantCount}명',
                style: const TextStyle(color: Color(0xFF697386), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  double _unitPrice(Post post) =>
      post.totalQuantity <= 0 ? 0 : post.totalPrice / post.totalQuantity;

  Widget _buildTradeInfoCard(Post post) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(title: '거래 정보'),
          const SizedBox(height: 12),
          _InfoRow(label: '모집 마감', value: _formatDeadline(post.deadline)),
          _InfoRow(label: '픽업 장소', value: post.pickupLocation),
          _InfoRow(label: '모집 미달 처리', value: _shortfallPolicyLabel(post)),
        ],
      ),
    );
  }

  String _shortfallPolicyLabel(Post post) {
    if (post.shortfallPolicy == 'KEEP_BY_HOST') {
      return '모집자가 남은 수량을 부담하고 진행';
    }
    if (post.shortfallPolicy == 'CANCEL_IF_SHORT') {
      return '목표 수량 미달 시 거래 취소';
    }
    return post.shortfallPolicy;
  }

  Widget _buildJoinBar() {
    final post = _post!;
    final canChangeQuantity = _canJoin;
    final hasValidQuote = _quote != null && _quote!.quantity == _quantity;
    final enabled =
        canChangeQuantity && hasValidQuote && !_isQuoteLoading && !_isJoining;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  '참여 수량',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                _QuantityButton(
                  icon: Icons.remove,
                  onPressed: canChangeQuantity && !_isJoining && _quantity > 1
                      ? () => _changeQuantity(-1)
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '${canChangeQuantity ? _quantity : 0}개',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _QuantityButton(
                  icon: Icons.add,
                  onPressed:
                      canChangeQuantity &&
                          !_isJoining &&
                          _quantity < post.remainingQuantity
                      ? () => _changeQuantity(1)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text(
                  '예상 부담 금액',
                  style: TextStyle(color: Color(0xFF697386), fontSize: 12),
                ),
                const Spacer(),
                if (_isQuoteLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Text(
                    _quote == null ? '-' : '${_quote!.estimatedAmount}원',
                    style: const TextStyle(
                      color: _blue,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            if (_quote != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '참여 후 남은 모집 수량 ${_quote!.remainingQuantityAfterJoin}개',
                  style: const TextStyle(
                    color: Color(0xFF697386),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
            if (_quoteError != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  _quoteError!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: enabled ? () => _requestJoin() : null,
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  disabledBackgroundColor: const Color(0xFFD9DEEC),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: Text(
                  _isJoining
                      ? '참여 처리 중'
                      : _quoteError != null
                      ? '예상 금액을 확인해주세요'
                      : _isQuoteLoading
                      ? '예상 금액 확인 중'
                      : _joinButtonLabel(post),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinedBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: _blue),
            const SizedBox(width: 8),
            const Text('참여 완료', style: TextStyle(fontWeight: FontWeight.w800)),
            const Spacer(),
            Text(
              '신청 수량 ${_myParticipation!.quantity}개',
              style: const TextStyle(color: _blue, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParticipationErrorBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        color: Colors.white,
        child: Row(
          children: [
            Expanded(
              child: Text(
                _participationError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
            TextButton(onPressed: _loadPost, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }

  String _joinButtonLabel(Post post) {
    if (post.status == 'CANCELLED') return '취소된 공동구매';
    if (post.status == 'COMPLETED') return '완료된 거래';
    if (post.status != 'RECRUITING') return '모집이 마감되었습니다';
    if (post.remainingQuantity <= 0) return '모집 수량이 소진되었습니다';
    if (!post.deadline.isAfter(DateTime.now())) return '모집 마감 시간이 지났습니다';
    return '공동구매 참여하기';
  }
}

class _DialogRow extends StatelessWidget {
  const _DialogRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF697386), fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: double.infinity,
      height: 210,
      color: const Color(0xFFE9EEFF),
      child: const Icon(Icons.shopping_bag_outlined, color: _blue, size: 58),
    );
    if (imageUrl == null || imageUrl!.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Image.network(
        imageUrl!,
        width: double.infinity,
        height: 210,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final isRecruiting = status == 'RECRUITING';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isRecruiting ? const Color(0xFFD9FFE5) : const Color(0xFFE9EEFF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: isRecruiting ? const Color(0xFF087A35) : _blue,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
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
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuantityButton extends StatelessWidget {
  const _QuantityButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFFE9EEFF),
        foregroundColor: _blue,
        disabledBackgroundColor: const Color(0xFFF0F1F5),
        disabledForegroundColor: const Color(0xFFB8BFCE),
        minimumSize: const Size(34, 34),
        padding: EdgeInsets.zero,
      ),
    );
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
      return '픽업 진행';
    case 'COMPLETED':
      return '거래 완료';
    case 'CANCELLED':
      return '거래 취소';
    default:
      return status;
  }
}

String _formatDeadline(DateTime value) {
  final local = value.toLocal();
  final weekday = ['월', '화', '수', '목', '금', '토', '일'][local.weekday - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}.${local.month}.${local.day} ($weekday) $hour:$minute';
}

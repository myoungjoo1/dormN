import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/dormn_api.dart';
import '../../core/websocket/chat_websocket_manager.dart';
import '../../models/chat_message.dart';
import '../../models/chat_room.dart';

const _blue = Color(0xFF3156D9);
const _pageBackground = Color(0xFFF7F8FC);

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    required this.room,
    this.currentUserId,
    this.postStatus,
    super.key,
  });

  final ChatRoom room;
  final String? currentUserId;
  final String? postStatus;

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage>
    with WidgetsBindingObserver {
  final _api = const DormNApi();
  final _webSocket = ChatWebSocketManager();
  final _scrollController = ScrollController();
  final _messageController = TextEditingController();

  List<ChatMessage> _messages = [];
  String? _currentUserId;
  String? _postStatus;
  String? _error;
  String? _statusError;
  bool _isLoading = true;
  bool _isLoadingOlder = false;
  bool _isSending = false;
  bool _hasMoreMessages = true;
  bool _recoveryIncomplete = false;
  ChatWebSocketStatus _webSocketStatus = ChatWebSocketStatus.disconnected;
  StreamSubscription<ChatMessage>? _webSocketMessageSubscription;
  StreamSubscription<ChatWebSocketStatus>? _webSocketStatusSubscription;
  StreamSubscription<AuthState>? _authStateSubscription;

  bool get _isGroupStatusUnknown =>
      widget.room.isGroup && _postStatus == null;

  bool get _isReadOnly =>
      widget.room.isGroup &&
      (_postStatus == 'COMPLETED' || _postStatus == 'CANCELLED');

  bool get _canUseComposer =>
      _error == null &&
      (widget.room.isDirect ||
          (_statusError == null && !_isGroupStatusUnknown && !_isReadOnly));

  String get _composerDisabledMessage {
    if (_isReadOnly) return '거래가 종료된 채팅방입니다.';
    if (_error != null) return '채팅방을 불러온 뒤 메시지를 보낼 수 있습니다.';
    return '거래 상태를 확인할 수 없어 메시지를 보낼 수 없습니다.';
  }

  Session? _currentSession() {
    try {
      return Supabase.instance.client.auth.currentSession;
    } catch (_) {
      return null;
    }
  }

  String _errorMessage(ApiException error) {
    switch (error.code) {
      case 'DORM_VERIFICATION_REQUIRED':
        return '기숙사 인증을 완료한 사용자만 채팅을 이용할 수 있어요.';
      case 'AUTH_REQUIRED':
      case 'INVALID_ACCESS_TOKEN':
        return '로그인이 필요합니다. 다시 로그인해주세요.';
      case 'CHAT_ROOM_NOT_FOUND':
      case 'POST_NOT_FOUND':
        return '채팅방을 찾을 수 없습니다.';
      case 'CHAT_ACCESS_FORBIDDEN':
        return '이 채팅방에 접근할 권한이 없습니다.';
      case 'CHAT_ROOM_READ_ONLY':
        return '거래가 종료되어 메시지를 보낼 수 없습니다.';
      default:
        return error.message;
    }
  }

  Future<void> _loadData({
    bool jumpToLatest = true,
    bool recoverMissedMessages = false,
    bool connectWebSocket = true,
  }) async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
        _statusError = null;
        _recoveryIncomplete = false;
      });
    }

    final session = _currentSession();
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '로그인이 필요합니다. 다시 로그인해주세요.';
      });
      return;
    }

    _currentUserId = widget.currentUserId ?? session.user.id;
    _postStatus = widget.postStatus;
    if (connectWebSocket) {
      unawaited(_connectWebSocket(session.accessToken));
    }

    if (widget.room.isGroup && widget.room.postId != null) {
      try {
        final post = await _api.getPost(widget.room.postId!);
        _postStatus = post.status;
      } on ApiException catch (error) {
        _statusError = _errorMessage(error);
      } catch (_) {
        _statusError = '거래 상태를 확인하지 못해 메시지를 보낼 수 없습니다.';
      }
    }

    try {
      final knownMessageIds = _messages.map((message) => message.id).toSet();
      final lastKnownMessageId =
          _messages.isEmpty ? null : _messages.last.id;
      var messages = await _api.getRoomMessages(
        roomId: widget.room.id,
        accessToken: session.accessToken,
      );
      if (!mounted) return;

      var mergedMessages = _mergeMessages(_messages, messages);
      var recoveryIncomplete = false;
      var recoveryFailed = false;
      var recoveryPageCount = 1;
      var recoveryPage = messages;
      var reachedKnownHistory = lastKnownMessageId == null ||
          recoveryPage.any((message) => knownMessageIds.contains(message.id));

      while (recoverMissedMessages &&
          !reachedKnownHistory &&
          recoveryPage.length >= 50 &&
          recoveryPageCount < 5) {
        try {
          recoveryPage = await _api.getRoomMessages(
            roomId: widget.room.id,
            accessToken: session.accessToken,
            beforeId: recoveryPage.last.id,
          );
        } catch (_) {
          recoveryFailed = true;
          break;
        }
        recoveryPageCount += 1;
        mergedMessages = _mergeMessages(mergedMessages, recoveryPage);
        reachedKnownHistory =
            recoveryPage.any((message) => knownMessageIds.contains(message.id));
      }

      if (recoverMissedMessages &&
          (recoveryFailed ||
              (!reachedKnownHistory &&
                  recoveryPage.length >= 50 &&
                  recoveryPageCount >= 5))) {
        recoveryIncomplete = true;
      }

      final shouldJump = jumpToLatest &&
          (_messages.isEmpty || _isNearBottom());
      mergedMessages = _mergeMessages(_messages, mergedMessages);
      setState(() {
        _messages = mergedMessages;
        _hasMoreMessages = recoveryIncomplete || recoveryPage.length >= 50;
        _recoveryIncomplete = recoveryIncomplete;
        _isLoading = false;
      });
      if (shouldJump) _jumpToLatest();
      if (recoveryIncomplete) {
        _showMessage('일부 메시지만 복구되었습니다. 위로 스크롤해 더 불러와주세요.');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = _errorMessage(error);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '메시지를 불러오지 못했습니다. 잠시 후 다시 시도해주세요.';
      });
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_isLoading ||
        _isLoadingOlder ||
        !_hasMoreMessages ||
        _messages.isEmpty) {
      return;
    }

    final session = _currentSession();
    if (session == null) return;

    final previousPixels = _scrollController.hasClients
        ? _scrollController.position.pixels
        : 0.0;
    final previousMaxExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final beforeId = _messages.first.id;

    setState(() => _isLoadingOlder = true);

    try {
      final messages = await _api.getRoomMessages(
        roomId: widget.room.id,
        accessToken: session.accessToken,
        beforeId: beforeId,
      );
      if (!mounted) return;

      final previousLength = _messages.length;
      final mergedMessages = _mergeMessages(_messages, messages);

      setState(() {
        _messages = mergedMessages;
        _hasMoreMessages =
            messages.length >= 50 && mergedMessages.length > previousLength;
        _isLoadingOlder = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final addedExtent =
            _scrollController.position.maxScrollExtent - previousMaxExtent;
        final target = (previousPixels + addedExtent).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(target.toDouble());
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isLoadingOlder = false);
      _showMessage(_errorMessage(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingOlder = false);
      _showMessage('이전 메시지를 불러오지 못했습니다. 다시 시도해주세요.');
    }
  }

  void _handleScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels <= 80) {
      _loadOlderMessages();
    }
  }

  void _jumpToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  List<ChatMessage> _mergeMessages(
    Iterable<ChatMessage> current,
    Iterable<ChatMessage> incoming,
  ) {
    final byId = <int, ChatMessage>{
      for (final message in current) message.id: message,
    };
    for (final message in incoming) {
      byId[message.id] = message;
    }

    final merged = byId.values.toList()
      ..sort((first, second) => first.id.compareTo(second.id));
    return merged;
  }

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.maxScrollExtent -
            _scrollController.position.pixels <
        80;
  }

  Future<void> _connectWebSocket(String accessToken) async {
    try {
      await _webSocket.connect(
        roomId: widget.room.id,
        accessToken: accessToken,
        accessTokenProvider: () async => _currentSession()?.accessToken,
      );
    } catch (_) {
      // The REST history remains usable when real-time delivery is unavailable.
    }
  }

  void _handleWebSocketMessage(ChatMessage message) {
    if (!mounted) return;
    final alreadyExists = _messages.any((item) => item.id == message.id);
    final shouldJump = _isNearBottom();
    setState(() => _messages = _mergeMessages(_messages, [message]));
    if (!alreadyExists && shouldJump) _jumpToLatest();
  }

  void _handleWebSocketStatus(ChatWebSocketStatus status) {
    if (!mounted) return;
    setState(() => _webSocketStatus = status);
  }

  Future<void> _reconnectWebSocket() async {
    final session = _currentSession();
    if (session == null) {
      _showMessage('로그인이 필요합니다. 다시 로그인해주세요.');
      return;
    }

    await _webSocket.disconnect();
    if (!mounted) return;
    await _loadData(
      jumpToLatest: false,
      recoverMissedMessages: true,
    );
  }

  Future<void> _sendMessage() async {
    if (_isSending) return;

    final body = _messageController.text.trim();
    if (body.isEmpty) {
      _showMessage('메시지를 입력해주세요.');
      return;
    }
    if (body.length > 2000) {
      _showMessage('메시지는 2,000자 이내로 입력해주세요.');
      return;
    }
    if (!_canUseComposer) {
      _showMessage(
        _isReadOnly
            ? '거래가 종료되어 메시지를 보낼 수 없습니다.'
            : '거래 상태를 확인하지 못해 메시지를 보낼 수 없습니다.',
      );
      return;
    }

    final session = _currentSession();
    if (session == null) {
      _showMessage('로그인이 필요합니다. 다시 로그인해주세요.');
      return;
    }

    setState(() => _isSending = true);
    try {
      final sentMessage = await _api.sendChatMessage(
        roomId: widget.room.id,
        body: body,
        accessToken: session.accessToken,
      );
      if (!mounted) return;
      setState(() {
        _messages = _mergeMessages(_messages, [sentMessage]);
        _isSending = false;
      });
      _messageController.clear();
      _jumpToLatest();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _isSending = false);
      if (error.code == 'CHAT_ROOM_READ_ONLY') {
        await _refreshPostStatus();
      }
      if (mounted) _showMessage(_errorMessage(error));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSending = false);
      _showMessage('메시지를 보내지 못했습니다. 입력 내용은 유지됩니다.');
    }
  }

  Future<void> _refreshPostStatus() async {
    if (!widget.room.isGroup || widget.room.postId == null) return;

    try {
      final post = await _api.getPost(widget.room.postId!);
      if (!mounted) return;
      setState(() {
        _postStatus = post.status;
        _statusError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusError = '거래 상태를 확인하지 못했습니다. 메시지를 보낼 수 없습니다.';
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isMine(ChatMessage message) => message.senderId == _currentUserId;

  bool _isDifferentDate(ChatMessage previous, ChatMessage current) {
    final previousLocal = previous.createdAt.toLocal();
    final currentLocal = current.createdAt.toLocal();
    return previousLocal.year != currentLocal.year ||
        previousLocal.month != currentLocal.month ||
        previousLocal.day != currentLocal.day;
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year}년 ${local.month}월 ${local.day}일';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _webSocketMessageSubscription =
        _webSocket.messages.listen(_handleWebSocketMessage);
    _webSocketStatusSubscription =
        _webSocket.status.listen(_handleWebSocketStatus);
    try {
      _authStateSubscription =
          Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (state.session == null) {
          unawaited(_webSocket.disconnect());
        }
      });
    } catch (_) {
      // The page still follows the current session for ordinary requests.
    }
    _scrollController.addListener(_handleScroll);
    _loadData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(_webSocket.pause());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_resumeChat());
    }
  }

  Future<void> _resumeChat() async {
    if (!mounted || _currentSession() == null) return;
    await _webSocket.resume();
    if (!mounted) return;
    await _loadData(
      jumpToLatest: false,
      recoverMissedMessages: true,
      connectWebSocket: false,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _webSocketMessageSubscription?.cancel();
    _webSocketStatusSubscription?.cancel();
    _authStateSubscription?.cancel();
    _webSocket.dispose();
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.room.isGroup
        ? widget.room.productName ?? '공동구매 채팅방'
        : widget.room.otherUserRoomNumber ?? '1:1 채팅';
    final subtitle = widget.room.isGroup ? '공동구매 단체 채팅방' : '1:1 채팅방';

    return Scaffold(
      backgroundColor: _pageBackground,
      appBar: AppBar(
        backgroundColor: _pageBackground,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF172033),
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                color: Color(0xFF697386),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_webSocketStatus != ChatWebSocketStatus.connected)
              _ConnectionNotice(
                status: _webSocketStatus,
                onReconnect: _reconnectWebSocket,
              ),
            if (_statusError != null && widget.room.isGroup)
              _StatusNotice(message: _statusError!),
            if (_recoveryIncomplete)
              const _StatusNotice(
                message: '일부 메시지를 복구하지 못했습니다. 위로 스크롤해 더 확인해주세요.',
              ),
            Expanded(child: _buildMessages()),
            _MessageComposer(
              controller: _messageController,
              readOnly: !_canUseComposer,
              sending: _isSending,
              disabledMessage: _composerDisabledMessage,
              onSend: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _MessageError(message: _error!, onRetry: _loadData);
    }

    if (_messages.isEmpty) {
      return const _EmptyMessages();
    }

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          itemCount: _messages.length,
          itemBuilder: (context, index) {
            final message = _messages[index];
            final showDate = index == 0 ||
                _isDifferentDate(_messages[index - 1], message);

            return Column(
              children: [
                if (showDate) _DateDivider(date: _formatDate(message.createdAt)),
                _MessageBubble(
                  message: message,
                  isMine: _isMine(message),
                  time: _formatTime(message.createdAt),
                ),
              ],
            );
          },
        ),
        if (_isLoadingOlder)
          const Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.time,
  });

  final ChatMessage message;
  final bool isMine;
  final String time;

  @override
  Widget build(BuildContext context) {
    if (message.isSystemMessage) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFE9ECF2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          message.body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF697386),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 290),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isMine ? _blue : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(17),
          topRight: const Radius.circular(17),
          bottomLeft: Radius.circular(isMine ? 17 : 4),
          bottomRight: Radius.circular(isMine ? 4 : 17),
        ),
      ),
      child: Text(
        message.body,
        style: TextStyle(
          color: isMine ? Colors.white : const Color(0xFF172033),
          fontSize: 14,
          height: 1.35,
        ),
      ),
    );

    final messageContent = Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMine)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              message.senderRoomNumber ?? '사용자',
              style: const TextStyle(
                color: Color(0xFF697386),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine)
              const Padding(
                padding: EdgeInsets.only(right: 7),
                child: CircleAvatar(
                  radius: 17,
                  backgroundColor: Color(0xFFE8EDFF),
                  child: Icon(
                    Icons.person_rounded,
                    size: 19,
                    color: _blue,
                  ),
                ),
              ),
            bubble,
            Padding(
              padding: EdgeInsets.only(left: isMine ? 7 : 0),
              child: Text(
                time,
                style: const TextStyle(
                  color: Color(0xFF9AA3B2),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ],
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: messageContent,
      ),
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});

  final String date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Color(0xFFDDE2EC))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              date,
              style: const TextStyle(
                color: Color(0xFF9AA3B2),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Expanded(child: Divider(color: Color(0xFFDDE2EC))),
        ],
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.readOnly,
    required this.sending,
    required this.disabledMessage,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool readOnly;
  final bool sending;
  final String disabledMessage;
  final Future<void> Function() onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E8F0))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !readOnly && !sending,
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: readOnly ? disabledMessage : '메시지를 입력하세요',
                counterText: '',
                filled: true,
                fillColor: _pageBackground,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: readOnly || sending ? null : () => onSend(),
            tooltip: '메시지 전송',
            style: IconButton.styleFrom(
              backgroundColor: _blue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFD8DCE6),
              disabledForegroundColor: Colors.white,
            ),
            icon: sending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}

class _StatusNotice extends StatelessWidget {
  const _StatusNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFFFF4D9),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF8A6418),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ConnectionNotice extends StatelessWidget {
  const _ConnectionNotice({required this.status, required this.onReconnect});

  final ChatWebSocketStatus status;
  final Future<void> Function() onReconnect;

  @override
  Widget build(BuildContext context) {
    final isConnecting = status == ChatWebSocketStatus.connecting;
    final message = isConnecting ? '실시간 채팅 연결 중...' : '실시간 연결이 끊겼습니다.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isConnecting
          ? const Color(0xFFE9EDFF)
          : const Color(0xFFFFEAEA),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            message,
            style: TextStyle(
              color: isConnecting
                  ? _blue
                  : const Color(0xFFB44D4D),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (!isConnecting) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onReconnect,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('재연결'),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageError extends StatelessWidget {
  const _MessageError({required this.message, required this.onRetry});

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
            const Icon(Icons.cloud_off_rounded, size: 42, color: Color(0xFF8A92A5)),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}

class _EmptyMessages extends StatelessWidget {
  const _EmptyMessages();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        '아직 메시지가 없습니다.\n첫 메시지를 보내보세요.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF697386), fontSize: 13),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/chat_message.dart';
import '../api/dormn_api.dart';

typedef AccessTokenProvider = Future<String?> Function();

enum ChatWebSocketStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class ChatWebSocketManager {
  ChatWebSocketManager({String? baseUrl}) : _baseUrl = baseUrl ?? apiBaseUrl;

  static const _retryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
  ];

  final String _baseUrl;
  final _messagesController = StreamController<ChatMessage>.broadcast();
  final _statusController =
      StreamController<ChatWebSocketStatus>.broadcast();

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;
  Future<void>? _connectFuture;
  Timer? _reconnectTimer;
  ChatWebSocketStatus _status = ChatWebSocketStatus.disconnected;
  AccessTokenProvider? _accessTokenProvider;
  int? _roomId;
  int _retryCount = 0;
  int _generation = 0;
  bool _disposed = false;
  bool _paused = false;
  bool _manualDisconnect = false;
  bool _nonRetryableFailure = false;

  Stream<ChatMessage> get messages => _messagesController.stream;
  Stream<ChatWebSocketStatus> get status => _statusController.stream;
  ChatWebSocketStatus get currentStatus => _status;

  Future<void> connect({
    required int roomId,
    required String accessToken,
    AccessTokenProvider? accessTokenProvider,
  }) {
    if (_disposed) {
      return Future<void>.error(StateError('WebSocket manager is disposed'));
    }

    _paused = false;
    _manualDisconnect = false;
    _nonRetryableFailure = false;
    _retryCount = 0;
    _accessTokenProvider =
        accessTokenProvider ?? (() async => accessToken);

    if (_roomId == roomId &&
        (_status == ChatWebSocketStatus.connecting ||
            _status == ChatWebSocketStatus.connected)) {
      return _connectFuture ?? Future<void>.value();
    }

    _cancelReconnectTimer();
    final future = _open(roomId);
    _connectFuture = future;
    return future.whenComplete(() {
      if (identical(_connectFuture, future)) {
        _connectFuture = null;
      }
    });
  }

  Future<void> _open(int roomId) async {
    if (_roomId != null &&
        (_roomId != roomId ||
            _socket != null ||
            _socketSubscription != null)) {
      await _closeSocket();
    }

    final generation = ++_generation;
    _roomId = roomId;
    _setStatus(ChatWebSocketStatus.connecting);

    try {
      final accessToken = await _accessTokenProvider?.call();
      if (accessToken == null || accessToken.isEmpty) {
        throw const _WebSocketAuthenticationFailure();
      }

      final socket = await WebSocket.connect(
        _buildUri(roomId).toString(),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (_disposed ||
          _paused ||
          _manualDisconnect ||
          generation != _generation ||
          _roomId != roomId) {
        await socket.close();
        return;
      }

      _socket = socket;
      _retryCount = 0;
      _nonRetryableFailure = false;
      _setStatus(ChatWebSocketStatus.connected);
      _socketSubscription = socket.listen(
        (event) => _handleEvent(socket, event),
        onError: (Object error) {
          if (identical(_socket, socket)) {
            _nonRetryableFailure = _isNonRetryable(error);
            _setStatus(ChatWebSocketStatus.error);
          }
        },
        onDone: () {
          if (!identical(_socket, socket)) return;
          final nonRetryable =
              _nonRetryableFailure || socket.closeCode == 1008;
          _socket = null;
          _socketSubscription = null;
          _setStatus(
            nonRetryable
                ? ChatWebSocketStatus.error
                : ChatWebSocketStatus.disconnected,
          );
          if (!nonRetryable) _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (error) {
      if (!_disposed && generation == _generation) {
        _nonRetryableFailure = _isNonRetryable(error);
        _setStatus(ChatWebSocketStatus.error);
        if (!_nonRetryableFailure) _scheduleReconnect();
      }
      rethrow;
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null ||
        _disposed ||
        _paused ||
        _manualDisconnect ||
        _roomId == null ||
        _nonRetryableFailure ||
        _retryCount >= _retryDelays.length) {
      return;
    }

    final delay = _retryDelays[_retryCount++];
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      final roomId = _roomId;
      if (roomId == null || _paused || _manualDisconnect || _disposed) {
        return;
      }
      unawaited(_retryConnection(roomId));
    });
  }

  Future<void> _retryConnection(int roomId) async {
    try {
      await _open(roomId);
    } catch (_) {
      // _open schedules the next retry for transient failures.
    }
  }

  bool _isNonRetryable(Object error) {
    if (error is _WebSocketAuthenticationFailure) return true;

    final message = error.toString().toLowerCase();
    return message.contains('401') ||
        message.contains('403') ||
        message.contains('1008') ||
        message.contains('unauthorized') ||
        message.contains('forbidden');
  }

  Uri _buildUri(int roomId) {
    final base = Uri.parse(_baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;

    return base.replace(
      scheme: scheme,
      path: '$basePath/ws/chat/$roomId',
      query: null,
      fragment: null,
    );
  }

  void _handleEvent(WebSocket socket, dynamic event) {
    if (!identical(_socket, socket) || event is! String) return;

    try {
      final decoded = jsonDecode(event);
      if (decoded is! Map) return;
      final data = decoded['data'];
      if (data is! Map) return;

      _messagesController.add(
        ChatMessage.fromJson(Map<String, dynamic>.from(data)),
      );
    } catch (_) {
      // Ignore malformed events; the next REST refresh can recover messages.
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    _paused = true;
    _cancelReconnectTimer();
    ++_generation;
    await _closeSocket();
    _setStatus(ChatWebSocketStatus.disconnected);
  }

  Future<void> resume() async {
    if (_disposed || _roomId == null || _accessTokenProvider == null) return;
    if (_nonRetryableFailure) return;

    _paused = false;
    _manualDisconnect = false;
    _nonRetryableFailure = false;
    _retryCount = 0;
    if (_status == ChatWebSocketStatus.connected ||
        _status == ChatWebSocketStatus.connecting) {
      return;
    }

    try {
      await _open(_roomId!);
    } catch (_) {
      // _open schedules retry for transient failures.
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _paused = false;
    _cancelReconnectTimer();
    ++_generation;
    _roomId = null;
    _accessTokenProvider = null;
    _retryCount = 0;
    _nonRetryableFailure = false;
    await _closeSocket();
    _setStatus(ChatWebSocketStatus.disconnected);
  }

  Future<void> _closeSocket() async {
    final subscription = _socketSubscription;
    final socket = _socket;
    _socketSubscription = null;
    _socket = null;

    if (subscription != null) {
      await subscription.cancel();
    }
    if (socket != null) {
      await socket.close();
    }
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _setStatus(ChatWebSocketStatus next) {
    _status = next;
    if (!_disposed && !_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _manualDisconnect = true;
    _paused = true;
    ++_generation;
    _roomId = null;
    _cancelReconnectTimer();

    final subscription = _socketSubscription;
    final socket = _socket;
    _socketSubscription = null;
    _socket = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    if (socket != null) {
      unawaited(socket.close());
    }
    _messagesController.close();
    _statusController.close();
  }
}

class _WebSocketAuthenticationFailure implements Exception {
  const _WebSocketAuthenticationFailure();
}

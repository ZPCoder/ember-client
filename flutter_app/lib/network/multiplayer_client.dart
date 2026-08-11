import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class MultiplayerEvent {
  const MultiplayerEvent({
    required this.type,
    this.roomCode,
    this.message,
    this.playerId,
    this.peerName,
    this.action,
    this.payload = const <String, dynamic>{},
  });

  final String type;
  final String? roomCode;
  final String? message;
  final String? playerId;
  final String? peerName;
  final String? action;
  final Map<String, dynamic> payload;

  factory MultiplayerEvent.fromData(Object? data) {
    Map<String, dynamic> json;
    if (data is String) {
      final decoded = jsonDecode(data);
      json = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } else if (data is Map) {
      json = Map<String, dynamic>.from(data);
    } else {
      json = <String, dynamic>{};
    }
    final payload = json['payload'];
    return MultiplayerEvent(
      type: json['type']?.toString() ?? 'message',
      roomCode: json['room']?.toString() ?? json['roomCode']?.toString(),
      message: json['message']?.toString(),
      playerId: json['playerId']?.toString(),
      peerName: json['peerName']?.toString(),
      action: json['action']?.toString(),
      payload: payload is Map
          ? Map<String, dynamic>.from(payload)
          : const <String, dynamic>{},
    );
  }
}

class MultiplayerClient extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  String endpoint = 'ws://127.0.0.1:8787';
  String playerName = '旅者 071';
  String status = '未连接';
  String? errorMessage;
  String? roomCode;
  String? playerId;
  String? peerName;
  bool isHost = false;
  int eventSequence = 0;
  MultiplayerEvent? lastEvent;
  final List<MultiplayerEvent> events = <MultiplayerEvent>[];

  bool get isConnected => _channel != null;
  bool get hasRoom => roomCode != null;

  Future<void> connect(String rawEndpoint, {String? name}) async {
    await disconnect(notify: false);
    final parsed = Uri.tryParse(rawEndpoint.trim());
    if (parsed == null || (parsed.scheme != 'ws' && parsed.scheme != 'wss')) {
      _setError('请输入 ws:// 或 wss:// 地址');
      return;
    }
    endpoint = parsed.toString();
    playerName = name?.trim().isNotEmpty == true ? name!.trim() : playerName;
    status = '连接中';
    errorMessage = null;
    notifyListeners();
    final channel = WebSocketChannel.connect(parsed);
    try {
      await channel.ready.timeout(const Duration(seconds: 8));
      _channel = channel;
      status = '已连接';
      _subscription = channel.stream.listen(
        _handleData,
        onError: (Object error) => _setError('连接错误：$error'),
        onDone: () {
          _channel = null;
          roomCode = null;
          playerId = null;
          peerName = null;
          isHost = false;
          status = '连接已关闭';
          notifyListeners();
        },
      );
      _send(<String, dynamic>{'type': 'hello', 'name': playerName});
      notifyListeners();
    } catch (error) {
      await channel.sink.close();
      _setError('无法连接房间服务器：$error');
    }
  }

  Future<void> disconnect({bool notify = true}) async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    roomCode = null;
    playerId = null;
    peerName = null;
    isHost = false;
    status = '未连接';
    if (notify) notifyListeners();
  }

  void createRoom() {
    _send(<String, dynamic>{'type': 'create_room'});
  }

  void joinRoom(String code) {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return;
    _send(<String, dynamic>{'type': 'join_room', 'room': normalized});
  }

  void sendAction(String action, [Map<String, dynamic>? payload]) {
    _send(<String, dynamic>{
      'type': 'action',
      'action': action,
      'payload': payload ?? <String, dynamic>{},
    });
  }

  void _send(Map<String, dynamic> value) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(value));
  }

  void _handleData(dynamic raw) {
    final event = MultiplayerEvent.fromData(raw);
    if (event.type == 'welcome') {
      playerId = event.playerId;
    } else if (event.type == 'room_created') {
      roomCode = event.roomCode;
      isHost = true;
      status = '等待对手';
    } else if (event.type == 'room_joined') {
      roomCode = event.roomCode;
      isHost = false;
      status = '房间已加入';
    } else if (event.type == 'peer_joined') {
      peerName = event.peerName;
      status = '对手已连接';
    } else if (event.type == 'peer_left') {
      peerName = null;
      status = '对手已离开';
    } else if (event.type == 'room_state') {
      final players = event.payload['players'];
      if (players is List) {
        final other = players.whereType<Map>().firstWhere(
          (player) => player['id']?.toString() != playerId,
          orElse: () => const <String, dynamic>{},
        );
        peerName = other['name']?.toString();
        if (peerName != null) status = '房间已就绪';
      }
    } else if (event.type == 'error') {
      errorMessage = event.message ?? '服务器返回错误';
      status = '需要处理';
    }
    events.insert(0, event);
    lastEvent = event;
    eventSequence++;
    if (events.length > 30) events.removeLast();
    notifyListeners();
  }

  void _setError(String message) {
    errorMessage = message;
    status = '连接失败';
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}

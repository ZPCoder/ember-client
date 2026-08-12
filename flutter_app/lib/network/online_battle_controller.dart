import 'package:flutter/foundation.dart';

import '../models/card_definition.dart';
import 'multiplayer_client.dart';

class OnlineUnit {
  OnlineUnit({
    required this.instanceId,
    required this.card,
    required this.attack,
    required this.health,
    this.hasAttacked = false,
  });

  final String instanceId;
  final CardDefinition card;
  final int attack;
  int health;
  bool hasAttacked;
}

/// Thin Flutter projection of the authoritative web-worker match.
///
/// The server owns the reducer, hidden information and turn clock. This class
/// only renders the redacted snapshot and sends typed BattleCommand payloads;
/// it deliberately does not maintain a second optimistic rules engine.
class OnlineBattleController extends ChangeNotifier {
  OnlineBattleController({required this.catalog, required this.client}) {
    deckIds = _buildDeck();
    client.addListener(_handleClientEvent);
  }

  final List<CardDefinition> catalog;
  final MultiplayerClient client;
  late final List<String> deckIds;
  List<CardDefinition> hand = <CardDefinition>[];
  List<OnlineUnit> localBoard = <OnlineUnit>[];
  List<OnlineUnit> remoteBoard = <OnlineUnit>[];
  final List<String> logs = <String>[];
  int localHealth = 30;
  int remoteHealth = 30;
  int turn = 1;
  bool localReady = false;
  bool remoteReady = false;
  bool started = false;
  bool finished = false;
  bool localTurn = false;
  String? winner;
  int _lastSequence = 0;
  int _commandSequence = 0;
  int? _viewer;
  int _lastStateVersion = -1;
  bool _mulliganSent = false;

  bool get canAct => started && !finished && localTurn;

  CardDefinition? card(String id) {
    for (final item in catalog) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<String> _buildDeck() {
    final pool = catalog
        .where((item) => item.faction == '曜光' || item.faction == '中立')
        .toList();
    final selected = pool.take(30).toList();
    if (selected.length == 30) return selected.map((item) => item.id).toList();
    final fallback = pool
        .take(15)
        .expand((item) => [item.id, item.id])
        .toList();
    return List<String>.generate(
      30,
      (index) => fallback[index % fallback.length],
    );
  }

  void ready() {
    if (localReady || !client.hasRoom) return;
    localReady = true;
    _log('你已提交合法 30 张牌组，等待对手确认。');
    client.sendAction('ready', <String, dynamic>{'deckIds': deckIds});
    _tryStart();
    notifyListeners();
  }

  void playCard(
    CardDefinition card, {
    OnlineUnit? target,
    bool targetHero = false,
  }) {
    if (!canAct || !hand.any((item) => item.id == card.id)) return;
    final targetType = card.target ?? 'none';
    if (targetType != 'none') {
      final needsUnit = targetType.contains('unit');
      final friendly = targetType.startsWith('friendly');
      final unitIsValid =
          target != null &&
          ((friendly ? localBoard : remoteBoard).contains(target));
      final heroIsValid = targetHero && targetType.contains('character');
      if ((needsUnit && !unitIsValid) ||
          (!needsUnit && !unitIsValid && !heroIsValid)) {
        _log('${card.name} 的目标不满足服务器规则。');
        return;
      }
      if (targetHero && !heroIsValid) {
        _log('${card.name} 不能选择核心作为目标。');
        return;
      }
    }
    final wireTarget = targetHero
        ? <String, dynamic>{'kind': 'hero', 'player': 0}
        : target == null
        ? null
        : <String, dynamic>{'kind': 'unit', 'entityId': target.instanceId};
    final command = <String, dynamic>{'type': 'play-card', 'cardId': card.id};
    if (wireTarget != null) command['target'] = wireTarget;
    _sendCommand(command);
  }

  void attack(OnlineUnit unit) {
    if (!canAct || unit.hasAttacked || !localBoard.contains(unit)) return;
    _sendCommand(<String, dynamic>{
      'type': 'attack',
      'attackerId': unit.instanceId,
      // The worker canonicalizes hero targets for the guest role.
      'target': <String, dynamic>{'kind': 'hero', 'player': 0},
    });
  }

  void endTurn() {
    if (!canAct) return;
    _sendCommand(<String, dynamic>{'type': 'end-turn'});
  }

  void _sendCommand(Map<String, dynamic> command) {
    final commandWithId = <String, dynamic>{
      ...command,
      'commandId': '${client.playerId ?? 'mobile'}-${_commandSequence++}',
    };
    client.sendAction('command', <String, dynamic>{'command': commandWithId});
  }

  void _handleClientEvent() {
    if (client.eventSequence == _lastSequence) return;
    _lastSequence = client.eventSequence;
    final event = client.lastEvent;
    if (event == null) return;
    switch (event.type) {
      case 'match_sync':
        started = true;
        final payload = event.payload;
        _applySnapshot(payload['state']);
        break;
      case 'action':
        _handleAction(event);
        break;
      case 'action_rejected':
        _log(event.message ?? '服务器拒绝了这次联机操作。');
        client.sync();
        break;
      case 'peer_left':
        _log(event.message ?? '对手已离开房间。');
        break;
    }
    notifyListeners();
  }

  void _handleAction(MultiplayerEvent event) {
    switch (event.action) {
      case 'ready':
        if (event.playerId != client.playerId) {
          remoteReady = true;
          _log('${event.peerName ?? '对手'} 已提交牌组。');
        }
        _tryStart();
        break;
      case 'match_start':
        started = true;
        _mulliganSent = false;
        _log('权威战场已建立，正在完成起手换牌。');
        _sendMulligan();
        break;
      case 'command':
        started = true;
        _applySnapshot(event.payload['state']);
        final command = event.payload['command'];
        if (command is Map && command['type'] != null) {
          _log(_commandLabel(command['type'].toString(), event));
        }
        break;
      case 'rematch':
        started = false;
        finished = false;
        winner = null;
        _viewer = null;
        _lastStateVersion = -1;
        _mulliganSent = false;
        _log('房主已重置联机战场。');
        break;
    }
  }

  String _commandLabel(String type, MultiplayerEvent event) {
    final self = event.playerId == client.playerId;
    if (type == 'end-turn') return self ? '你结束了回合。' : '对手结束回合。';
    if (type == 'mulligan') return self ? '你的起手已确认。' : '对手已确认起手。';
    if (type == 'attack') return self ? '你发起了一次攻击。' : '对手发起了一次攻击。';
    if (type == 'play-card') return self ? '你使用了一张卡牌。' : '对手使用了一张卡牌。';
    return self ? '你的联机指令已结算。' : '对手的联机指令已结算。';
  }

  void _sendMulligan() {
    if (_mulliganSent) return;
    _mulliganSent = true;
    _sendCommand(<String, dynamic>{'type': 'mulligan', 'cardIndexes': <int>[]});
  }

  void _tryStart() {
    if (localReady && remoteReady && client.isHost && !started) {
      started = true;
      client.sendAction('match_start');
    }
  }

  void _applySnapshot(Object? raw) {
    if (raw is! Map) return;
    final snapshot = Map<String, dynamic>.from(raw);
    final rawPlayers = snapshot['players'];
    if (rawPlayers is! List || rawPlayers.length < 2) return;
    final players = rawPlayers
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (players.length < 2) return;
    final version = (snapshot['version'] as num?)?.toInt() ?? 0;
    if (version < _lastStateVersion) return;
    _lastStateVersion = version;
    _viewer ??= _findViewer(players);
    final viewer = _viewer ?? (client.isHost ? 0 : 1);
    final local = players[viewer];
    final remote = players[viewer == 0 ? 1 : 0];
    final phase = snapshot['phase']?.toString() ?? 'mulligan';
    turn = (snapshot['turn'] as num?)?.toInt() ?? turn;
    localTurn = phase == 'main' && snapshot['activePlayer'] == viewer;
    started = true;
    finished = phase == 'game-over';
    localHealth = _heroHealth(local);
    remoteHealth = _heroHealth(remote);
    hand = _parseHand(local['hand']);
    localBoard = _parseBoard(local['board']);
    remoteBoard = _parseBoard(remote['board']);
    final result = snapshot['result'];
    if (result is Map) {
      final resultWinner = result['winner'];
      winner = resultWinner == viewer ? 'player' : 'peer';
    }
  }

  int _findViewer(List<Map<String, dynamic>> players) {
    for (var index = 0; index < players.length; index++) {
      final handValue = players[index]['hand'];
      if (handValue is List &&
          handValue.any((item) => item.toString() != '__hidden-card__')) {
        return index;
      }
    }
    return client.isHost ? 0 : 1;
  }

  int _heroHealth(Map<String, dynamic> player) {
    final hero = player['hero'];
    return hero is Map ? (hero['health'] as num?)?.toInt() ?? 0 : 0;
  }

  List<CardDefinition> _parseHand(Object? raw) {
    if (raw is! List) return <CardDefinition>[];
    return raw
        .map((item) => card(item.toString()))
        .whereType<CardDefinition>()
        .toList();
  }

  List<OnlineUnit> _parseBoard(Object? raw) {
    if (raw is! List) return <OnlineUnit>[];
    return raw
        .whereType<Map>()
        .map((item) {
          final unit = Map<String, dynamic>.from(item);
          final cardId = unit['cardId']?.toString();
          final definition = cardId == null ? null : card(cardId);
          if (definition == null) return null;
          return OnlineUnit(
            instanceId: unit['entityId']?.toString() ?? definition.id,
            card: definition,
            attack: (unit['attack'] as num?)?.toInt() ?? definition.attack ?? 0,
            health: (unit['health'] as num?)?.toInt() ?? definition.health ?? 1,
            hasAttacked: unit['hasAttacked'] == true,
          );
        })
        .whereType<OnlineUnit>()
        .toList();
  }

  void _log(String message) {
    logs.insert(0, message);
    if (logs.length > 12) logs.removeLast();
  }

  @override
  void dispose() {
    client.removeListener(_handleClientEvent);
    super.dispose();
  }
}

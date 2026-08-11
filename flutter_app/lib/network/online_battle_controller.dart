import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/card_definition.dart';
import 'multiplayer_client.dart';

class OnlineUnit {
  OnlineUnit({required this.card, required this.attack, required this.health});

  final CardDefinition card;
  final int attack;
  int health;
  bool hasAttacked = false;
}

class OnlineBattleController extends ChangeNotifier {
  OnlineBattleController({required this.catalog, required this.client}) {
    hand = catalog
        .where((card) => card.faction == '曜光' || card.faction == '中立')
        .take(5)
        .toList(growable: true);
    client.addListener(_handleClientEvent);
  }

  final List<CardDefinition> catalog;
  final MultiplayerClient client;
  late final List<CardDefinition> hand;
  final List<OnlineUnit> localBoard = <OnlineUnit>[];
  final List<OnlineUnit> remoteBoard = <OnlineUnit>[];
  final List<String> logs = <String>[];
  int localHealth = 30;
  int remoteHealth = 30;
  int turn = 1;
  bool localReady = false;
  bool remoteReady = false;
  bool started = false;
  bool finished = false;
  String? winner;
  int _lastSequence = 0;

  CardDefinition? card(String id) {
    for (final item in catalog) {
      if (item.id == id) return item;
    }
    return null;
  }

  void ready() {
    if (localReady || !client.hasRoom) return;
    localReady = true;
    _log('你已准备，等待对手确认。');
    client.sendAction('ready');
    _tryStart();
    notifyListeners();
  }

  void playCard(CardDefinition card) {
    if (!started || finished || !hand.remove(card)) return;
    if (card.isUnit) {
      if (localBoard.length >= 5) {
        hand.add(card);
        return;
      }
      final unit = OnlineUnit(
        card: card,
        attack: card.attack ?? 0,
        health: card.health ?? 1,
      );
      localBoard.add(unit);
      client.sendAction('play_card', <String, dynamic>{
        'cardId': card.id,
        'attack': unit.attack,
        'health': unit.health,
      });
      _log('${card.name} 登场。');
    } else {
      final damage = _effectAmount(card, 'damage');
      if (damage > 0) remoteHealth = max(0, remoteHealth - damage);
      client.sendAction('play_card', <String, dynamic>{
        'cardId': card.id,
        'damage': damage,
      });
      _log('${card.name} 已施放。');
    }
    _checkFinished();
    notifyListeners();
  }

  void attack(OnlineUnit unit) {
    if (!started ||
        finished ||
        unit.hasAttacked ||
        !localBoard.contains(unit)) {
      return;
    }
    unit.hasAttacked = true;
    remoteHealth = max(0, remoteHealth - unit.attack);
    client.sendAction('attack', <String, dynamic>{
      'cardId': unit.card.id,
      'damage': unit.attack,
    });
    _log('${unit.card.name} 造成 ${unit.attack} 点伤害。');
    _checkFinished();
    notifyListeners();
  }

  void endTurn() {
    if (!started || finished) return;
    turn++;
    for (final unit in localBoard) {
      unit.hasAttacked = false;
    }
    _draw();
    client.sendAction('end_turn', <String, dynamic>{'turn': turn});
    _log('第 $turn 回合开始。');
    notifyListeners();
  }

  int _effectAmount(CardDefinition card, String kind) => card.effect
      .where((effect) => effect['kind'] == kind)
      .fold<int>(
        0,
        (sum, effect) => sum + ((effect['amount'] as num?)?.toInt() ?? 0),
      );

  void _handleClientEvent() {
    if (client.eventSequence == _lastSequence) return;
    _lastSequence = client.eventSequence;
    final event = client.lastEvent;
    if (event == null || event.type != 'action') return;
    if (event.playerId == client.playerId) return;
    final payload = event.payload;
    switch (event.action) {
      case 'ready':
        remoteReady = true;
        _log('${event.peerName ?? '对手'} 已准备。');
        _tryStart();
        break;
      case 'battle_start':
        started = true;
        _log('联机演算开始。');
        break;
      case 'play_card':
        final cardId = payload['cardId']?.toString();
        final remoteCard = cardId == null ? null : card(cardId);
        if (remoteCard != null && remoteCard.isUnit) {
          remoteBoard.add(
            OnlineUnit(
              card: remoteCard,
              attack:
                  (payload['attack'] as num?)?.toInt() ??
                  remoteCard.attack ??
                  0,
              health:
                  (payload['health'] as num?)?.toInt() ??
                  remoteCard.health ??
                  1,
            ),
          );
          _log('${event.peerName ?? '对手'} 部署 ${remoteCard.name}。');
        }
        final spellDamage = (payload['damage'] as num?)?.toInt() ?? 0;
        if (spellDamage > 0) {
          localHealth = max(0, localHealth - spellDamage);
          _log('受到 $spellDamage 点战术伤害。');
        }
        _checkFinished();
        break;
      case 'attack':
        final damage = (payload['damage'] as num?)?.toInt() ?? 0;
        localHealth = max(0, localHealth - damage);
        _log('${event.peerName ?? '对手'} 造成 $damage 点伤害。');
        _checkFinished();
        break;
      case 'end_turn':
        turn = max(turn, (payload['turn'] as num?)?.toInt() ?? turn);
        for (final unit in remoteBoard) {
          unit.hasAttacked = false;
        }
        _log('对手进入第 $turn 回合。');
        break;
    }
    notifyListeners();
  }

  void _tryStart() {
    if (localReady && remoteReady && !started) {
      started = true;
      _log('双方已准备，联机演算开始。');
      client.sendAction('battle_start');
    }
  }

  void _draw() {
    final next = catalog
        .where((card) => card.faction == '曜光' || card.faction == '中立')
        .skip(hand.length + turn)
        .firstOrNull;
    if (next != null && hand.length < 10) hand.add(next);
  }

  void _checkFinished() {
    if (finished || (localHealth > 0 && remoteHealth > 0)) return;
    finished = true;
    winner = remoteHealth <= 0 ? 'player' : 'peer';
    _log(winner == 'player' ? '联机胜利。' : '联机演算结束。');
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

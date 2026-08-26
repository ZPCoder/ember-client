import 'package:flutter/foundation.dart';

import '../data/formats.dart';
import '../data/catalog.dart';
import '../models/card_definition.dart';
import 'multiplayer_client.dart';

class OnlineUnit {
  OnlineUnit({
    required this.instanceId,
    required this.card,
    required this.attack,
    required this.health,
    required this.maxHealth,
    this.keywords = const <String>[],
    this.minionTypes = const <String>[],
    this.hasAttacked = false,
    this.attacksMade = 0,
    this.summoningSick = false,
    this.rushOnly = false,
    this.stealthActive = false,
    this.frozenTurns = 0,
    this.stars = 1,
    this.silenced = false,
  });

  final String instanceId;
  final CardDefinition card;
  final int attack;
  final int maxHealth;
  int health;
  final List<String> keywords;
  final List<String> minionTypes;
  final bool hasAttacked;
  final int attacksMade;
  final bool summoningSick;
  final bool rushOnly;
  final bool stealthActive;
  final int frozenTurns;
  final int stars;
  final bool silenced;

  bool get hasTaunt => keywords.contains('taunt');
  bool get hasWindfury => keywords.contains('windfury');
  bool get hasDivineShield => keywords.contains('shield');
  bool get isFrozen => frozenTurns > 0;
  int get attackLimit => hasWindfury ? 2 : 1;
  bool get canAttack =>
      attack > 0 && !summoningSick && !isFrozen && attacksMade < attackLimit;
}

/// Thin Flutter projection of the authoritative web-worker match.
///
/// The server owns the reducer, hidden information and turn clock. This class
/// only renders the redacted snapshot and sends typed BattleCommand payloads;
/// it deliberately does not maintain a second optimistic rules engine.
class OnlineBattleController extends ChangeNotifier {
  OnlineBattleController({
    required this.catalog,
    required this.client,
    List<String>? preferredDeckIds,
    this.rankedFormat = RankedFormat.standard,
  }) {
    final preferred = preferredDeckIds ?? const <String>[];
    deckIds = _isValidDeck(preferred)
        ? List<String>.from(preferred)
        : _buildDeck();
    client.addListener(_handleClientEvent);
  }

  final List<CardDefinition> catalog;
  final MultiplayerClient client;
  final RankedFormat rankedFormat;
  late final List<String> deckIds;
  List<CardDefinition> hand = <CardDefinition>[];
  List<int> handCostReductions = <int>[];
  List<HandFragment?> handFragments = <HandFragment?>[];
  List<OnlineUnit> localBoard = <OnlineUnit>[];
  List<OnlineUnit> remoteBoard = <OnlineUnit>[];
  final List<String> logs = <String>[];
  int localHealth = 30;
  int remoteHealth = 30;
  int localArmor = 0;
  int remoteArmor = 0;
  int localMana = 0;
  int localMaxMana = 0;
  int remoteMana = 0;
  int remoteMaxMana = 0;
  int localOverloadLocked = 0;
  int localHeraldCount = 0;
  int remoteHeraldCount = 0;
  List<String> localSpellSchoolsThisTurn = <String>[];
  List<String> localSpellSchoolsLastTurn = <String>[];
  List<String> remoteSpellSchoolsThisTurn = <String>[];
  List<String> remoteSpellSchoolsLastTurn = <String>[];
  List<BattleDeathRecord> localDeathHistory = <BattleDeathRecord>[];
  List<BattleDeathRecord> remoteDeathHistory = <BattleDeathRecord>[];
  String? localHeroName;
  String? remoteHeroName;
  int localHeroAttackBonus = 0;
  int remoteHeroAttackBonus = 0;
  bool localCoinAvailable = false;
  bool localHeroPowerUsed = false;
  bool localHeroHasAttacked = false;
  HeroPowerDefinition? localHeroPower;
  CardDefinition? localWeaponCard;
  int localWeaponAttack = 0;
  int localWeaponDurability = 0;
  int localWeaponMaxDurability = 0;
  int turn = 1;
  bool localReady = false;
  bool remoteReady = false;
  bool started = false;
  bool finished = false;
  bool localTurn = false;
  String? winner;
  String phase = 'mulligan';
  List<String> discoverChoices = <String>[];
  String? discoverSourceCardId;
  List<Map<String, dynamic>> chooseOneOptions = <Map<String, dynamic>>[];
  String? chooseOneSourceCardId;
  int chooseOneRemaining = 1;
  String chooseOneSourceKind = 'spell';
  int _lastSequence = 0;
  int _commandSequence = 0;
  int? _viewer;
  int _lastStateVersion = -1;
  bool _mulliganSent = false;

  bool get canAct => started && !finished && localTurn && phase == 'main';
  bool get canChooseDiscover =>
      started &&
      !finished &&
      localTurn &&
      phase == 'discover' &&
      discoverChoices.isNotEmpty;
  bool get canChooseOne =>
      started &&
      !finished &&
      localTurn &&
      phase == 'choose-one' &&
      chooseOneOptions.isNotEmpty;

  CardDefinition? card(String id) {
    for (final item in catalog) {
      if (item.id == id) return item;
    }
    for (final item in generatedBattleCards) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<String> _buildDeck() {
    final pool = catalog
        .where(
          (item) =>
              cardAvailableInRankedFormat(item, rankedFormat) &&
              (item.faction == '曜光' || item.faction == '中立'),
        )
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

  bool _isValidDeck(List<String> ids) {
    if (ids.length != 30) return false;
    final cards = ids.map(card).whereType<CardDefinition>().toList();
    if (cards.length != ids.length) return false;
    if (cards.any((item) => !cardAvailableInRankedFormat(item, rankedFormat))) {
      return false;
    }
    final factions = cards
        .map((item) => item.faction)
        .where((faction) => faction != '中立')
        .toSet();
    if (factions.length > 1) return false;
    final counts = <String, int>{};
    for (final item in cards) {
      counts[item.id] = (counts[item.id] ?? 0) + 1;
      final limit = item.rarity == '传说' ? 1 : 2;
      if (counts[item.id]! > limit) return false;
    }
    return true;
  }

  void ready() {
    if (localReady || !client.hasRoom) return;
    localReady = true;
    _log('你已提交合法 30 张牌组，等待对手确认。');
    client.sendAction('ready', <String, dynamic>{
      'deckIds': deckIds,
      'rankedFormat': rankedFormat.wireValue,
    });
    _tryStart();
    notifyListeners();
  }

  void playCard(
    CardDefinition card, {
    int? handIndex,
    OnlineUnit? target,
    bool targetHero = false,
    String placement = 'friendly',
  }) {
    final resolvedHandIndex = _resolveHandIndex(card, handIndex);
    if (!canAct || resolvedHandIndex < 0) return;
    if (placement != 'friendly' &&
        (placement != 'enemy' || !card.isUnit || !card.disguised)) {
      return;
    }
    final recipientBoard = placement == 'enemy' ? remoteBoard : localBoard;
    if (card.isUnit &&
        recipientBoard.length >= 7 &&
        !recipientBoard.any(
          (unit) => unit.card.id == card.id && unit.stars == 1,
        )) {
      return;
    }
    final targetType = card.target ?? 'none';
    if (targetType != 'none') {
      final needsUnit = targetType.contains('unit');
      final friendly = targetType.startsWith('friendly');
      final unitIsValid =
          target != null &&
          ((friendly ? localBoard : remoteBoard).contains(target));
      final heroIsValid = targetHero && targetType.contains('character');
      if (unitIsValid && !friendly && target.stealthActive) {
        _log('${card.name} 不能直接选择潜行单位。');
        return;
      }
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
        ? <String, dynamic>{
            'kind': 'hero',
            'player': targetType.startsWith('friendly') ? 0 : 1,
          }
        : target == null
        ? null
        : <String, dynamic>{'kind': 'unit', 'entityId': target.instanceId};
    final command = <String, dynamic>{
      'type': 'play-card',
      'cardId': card.id,
      'handIndex': resolvedHandIndex,
      'placement': placement,
    };
    if (wireTarget != null) command['target'] = wireTarget;
    _sendCommand(command);
  }

  void attack(OnlineUnit unit) {
    if (!canAct ||
        !unit.canAttack ||
        unit.rushOnly ||
        !localBoard.contains(unit) ||
        _visibleRemoteTaunts.isNotEmpty) {
      return;
    }
    _sendCommand(<String, dynamic>{
      'type': 'attack',
      'attackerId': unit.instanceId,
      // The worker canonicalizes hero targets for the guest role.
      'target': <String, dynamic>{'kind': 'hero', 'player': 1},
    });
  }

  void attackUnit(OnlineUnit attacker, OnlineUnit target) {
    if (!canAct ||
        !attacker.canAttack ||
        !localBoard.contains(attacker) ||
        !remoteBoard.contains(target) ||
        target.stealthActive ||
        (_visibleRemoteTaunts.isNotEmpty && !target.hasTaunt)) {
      return;
    }
    _sendCommand(<String, dynamic>{
      'type': 'attack',
      'attackerId': attacker.instanceId,
      'target': <String, dynamic>{
        'kind': 'unit',
        'entityId': target.instanceId,
      },
    });
  }

  void heroAttack({OnlineUnit? target, bool targetHero = false}) {
    if (!canAct ||
        localWeaponAttack + localHeroAttackBonus <= 0 ||
        (localWeaponCard != null && localWeaponDurability <= 0) ||
        localHeroHasAttacked) {
      return;
    }
    final taunts = _visibleRemoteTaunts;
    if (target == null) {
      if (taunts.isNotEmpty) return;
    } else if (!remoteBoard.contains(target) ||
        target.stealthActive ||
        (taunts.isNotEmpty && !target.hasTaunt)) {
      return;
    }
    final command = <String, dynamic>{'type': 'hero-attack'};
    command['target'] = targetHero
        ? <String, dynamic>{'kind': 'hero', 'player': 1}
        : target == null
        ? <String, dynamic>{'kind': 'hero', 'player': 1}
        : <String, dynamic>{'kind': 'unit', 'entityId': target.instanceId};
    _sendCommand(command);
  }

  void useCoin() {
    if (!canAct || !localCoinAvailable) return;
    _sendCommand(<String, dynamic>{'type': 'use-coin'});
  }

  void tradeCard(CardDefinition card, {int? handIndex}) {
    final resolvedHandIndex = _resolveHandIndex(card, handIndex);
    if (!canAct || !card.tradeable || !hand.any((item) => item.id == card.id)) {
      return;
    }
    _sendCommand(<String, dynamic>{
      'type': 'trade-card',
      'cardId': card.id,
      'handIndex': resolvedHandIndex,
    });
  }

  void prepareCard(CardDefinition card, {int? handIndex}) {
    final resolvedHandIndex = _resolveHandIndex(card, handIndex);
    if (!canAct ||
        !card.preparable ||
        localMana < 1 ||
        resolvedHandIndex < 0 ||
        handCostReduction(resolvedHandIndex) > 0) {
      return;
    }
    _sendCommand(<String, dynamic>{
      'type': 'prepare-card',
      'cardId': card.id,
      'handIndex': resolvedHandIndex,
    });
  }

  void useHeroPower({OnlineUnit? target, bool targetHero = false}) {
    final power = localHeroPower;
    if (!canAct ||
        power == null ||
        localHeroPowerUsed ||
        localMana < power.cost) {
      return;
    }
    final command = <String, dynamic>{'type': 'hero-power'};
    final targetType = power.target ?? 'none';
    if (target != null) {
      final friendly = targetType.startsWith('friendly');
      final board = friendly ? localBoard : remoteBoard;
      if (!board.contains(target) || (!friendly && target.stealthActive)) {
        return;
      }
    }
    if (targetType.contains('character') && targetHero) {
      command['target'] = <String, dynamic>{
        'kind': 'hero',
        'player': targetType.startsWith('friendly') ? 0 : 1,
      };
    } else if (target != null) {
      command['target'] = <String, dynamic>{
        'kind': 'unit',
        'entityId': target.instanceId,
      };
    }
    _sendCommand(command);
  }

  void chooseDiscover(String cardId) {
    if (!canChooseDiscover || !discoverChoices.contains(cardId)) return;
    _sendCommand(<String, dynamic>{
      'type': 'choose-discover',
      'cardId': cardId,
    });
  }

  void chooseOne(int optionIndex) {
    if (!canChooseOne ||
        optionIndex < 0 ||
        optionIndex >= chooseOneOptions.length) {
      return;
    }
    _sendCommand(<String, dynamic>{
      'type': 'choose-one',
      'optionIndex': optionIndex,
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
    if (type == 'prepare-card') return self ? '你完成了一次预备。' : '对手完成了一次预备。';
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
    phase = snapshot['phase']?.toString() ?? 'mulligan';
    turn = (snapshot['turn'] as num?)?.toInt() ?? turn;
    localTurn = snapshot['activePlayer'] == viewer && phase != 'game-over';
    started = true;
    finished = phase == 'game-over';
    localHealth = _heroHealth(local);
    remoteHealth = _heroHealth(remote);
    _parseSide(local, localSide: true);
    _parseSide(remote, localSide: false);
    hand = _parseHand(local['hand']);
    handCostReductions = _parseHandCostReductions(
      local['handCostReductions'],
      hand.length,
    );
    handFragments = _parseHandFragments(local['handFragments'], hand.length);
    localBoard = _parseBoard(local['board']);
    remoteBoard = _parseBoard(remote['board']);
    final discover = snapshot['discover'];
    if (discover is Map && discover['player'] == viewer) {
      discoverChoices = (discover['choices'] is List)
          ? (discover['choices'] as List)
                .map((item) => item.toString())
                .where((id) => card(id) != null)
                .toList()
          : <String>[];
      discoverSourceCardId = discover['sourceCardId']?.toString();
    } else {
      discoverChoices = <String>[];
      discoverSourceCardId = null;
    }
    final chooseOne = snapshot['chooseOne'];
    if (chooseOne is Map && chooseOne['player'] == viewer) {
      chooseOneOptions = (chooseOne['options'] is List)
          ? (chooseOne['options'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];
      chooseOneSourceCardId = chooseOne['sourceCardId']?.toString();
      chooseOneRemaining =
          (chooseOne['remainingChoices'] as num?)?.toInt() ?? 1;
      chooseOneSourceKind = chooseOne['sourceKind']?.toString() == 'hero-card'
          ? 'hero-card'
          : 'spell';
    } else {
      chooseOneOptions = <Map<String, dynamic>>[];
      chooseOneSourceCardId = null;
      chooseOneRemaining = 1;
      chooseOneSourceKind = 'spell';
    }
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

  void _parseSide(Map<String, dynamic> side, {required bool localSide}) {
    final hero = side['hero'];
    final mana = (side['mana'] as num?)?.toInt() ?? 0;
    final maxMana = (side['maxMana'] as num?)?.toInt() ?? 0;
    final armor = (hero is Map ? (hero['armor'] as num?)?.toInt() : null) ?? 0;
    final heroName = hero is Map ? hero['name']?.toString() : null;
    final heroAttackBonus = (side['heroAttackBonus'] as num?)?.toInt() ?? 0;
    final heraldCount = (side['heraldCount'] as num?)?.toInt() ?? 0;
    List<String> spellSchools(Object? value) => value is List
        ? value.map((item) => item.toString()).toList(growable: false)
        : <String>[];
    final schoolsThisTurn = spellSchools(side['spellSchoolsPlayedThisTurn']);
    final schoolsLastTurn = spellSchools(side['spellSchoolsPlayedLastTurn']);
    final deathHistory = _parseDeathHistory(side['deathHistory']);
    if (localSide) {
      localMana = mana;
      localMaxMana = maxMana;
      localArmor = armor;
      localHeroName = heroName;
      localHeroAttackBonus = heroAttackBonus;
      localOverloadLocked = (side['overloadLocked'] as num?)?.toInt() ?? 0;
      localHeraldCount = heraldCount;
      localSpellSchoolsThisTurn = schoolsThisTurn;
      localSpellSchoolsLastTurn = schoolsLastTurn;
      localDeathHistory = deathHistory;
      localCoinAvailable = side['coinAvailable'] == true;
      localHeroPowerUsed = side['heroPowerUsed'] == true;
      localHeroHasAttacked = side['heroHasAttacked'] == true;
      final rawPower = side['heroPower'];
      if (rawPower is Map) {
        localHeroPower = HeroPowerDefinition(
          id: rawPower['id']?.toString() ?? 'core-pulse',
          faction: rawPower['faction']?.toString() ?? '中立',
          name: rawPower['name']?.toString() ?? '核心脉冲',
          description: rawPower['description']?.toString() ?? '',
          cost: (rawPower['cost'] as num?)?.toInt() ?? 2,
          target: rawPower['target']?.toString(),
          effect: rawPower['effect'] is Map
              ? Map<String, dynamic>.from(rawPower['effect'] as Map)
              : const <String, dynamic>{},
        );
      }
      final rawWeapon = side['weapon'];
      if (rawWeapon is Map) {
        localWeaponCard = card(rawWeapon['cardId']?.toString() ?? '');
        localWeaponAttack = (rawWeapon['attack'] as num?)?.toInt() ?? 0;
        localWeaponDurability = (rawWeapon['durability'] as num?)?.toInt() ?? 0;
        localWeaponMaxDurability =
            (rawWeapon['maxDurability'] as num?)?.toInt() ??
            localWeaponDurability;
      } else {
        localWeaponCard = null;
        localWeaponAttack = 0;
        localWeaponDurability = 0;
        localWeaponMaxDurability = 0;
      }
    } else {
      remoteMana = mana;
      remoteMaxMana = maxMana;
      remoteArmor = armor;
      remoteHeroName = heroName;
      remoteHeroAttackBonus = heroAttackBonus;
      remoteHeraldCount = heraldCount;
      remoteSpellSchoolsThisTurn = schoolsThisTurn;
      remoteSpellSchoolsLastTurn = schoolsLastTurn;
      remoteDeathHistory = deathHistory;
    }
  }

  List<BattleDeathRecord> _parseDeathHistory(Object? raw) {
    if (raw is! List) return <BattleDeathRecord>[];
    return raw
        .whereType<Map>()
        .map((entry) {
          final record = Map<String, dynamic>.from(entry);
          final minionTypes = record['minionTypes'] is List
              ? (record['minionTypes'] as List)
                    .map((item) => item.toString())
                    .toList(growable: false)
              : const <String>[];
          return BattleDeathRecord(
            entityId: record['entityId']?.toString() ?? '',
            cardId: record['cardId']?.toString() ?? '',
            name: record['name']?.toString() ?? '未知单位',
            controller: (record['controller'] as num?)?.toInt() ?? 0,
            diedTurn: (record['diedTurn'] as num?)?.toInt() ?? 1,
            deathOrder: (record['deathOrder'] as num?)?.toInt() ?? 1,
            minionTypes: minionTypes,
          );
        })
        .toList(growable: false);
  }

  List<CardDefinition> _parseHand(Object? raw) {
    if (raw is! List) return <CardDefinition>[];
    return raw
        .map((item) => card(item.toString()))
        .whereType<CardDefinition>()
        .toList();
  }

  List<int> _parseHandCostReductions(Object? raw, int handLength) {
    final values = raw is List ? raw : const <Object?>[];
    return List<int>.generate(handLength, (index) {
      if (index >= values.length || values[index] is! num) return 0;
      final reduction = (values[index] as num).toInt();
      if (reduction < 0) return 0;
      return reduction > 1000 ? 1000 : reduction;
    });
  }

  List<HandFragment?> _parseHandFragments(Object? raw, int handLength) {
    final values = raw is List ? raw : const <Object?>[];
    return List<HandFragment?>.generate(handLength, (index) {
      if (index >= values.length || values[index] is! Map) return null;
      final fragment = Map<String, dynamic>.from(values[index] as Map);
      final groupId = fragment['groupId']?.toString();
      final piece = fragment['piece']?.toString();
      if (groupId == null ||
          groupId.isEmpty ||
          (piece != 'left' && piece != 'right')) {
        return null;
      }
      return HandFragment(groupId: groupId, piece: piece!);
    });
  }

  HandFragment? handFragment(int handIndex) =>
      handIndex >= 0 && handIndex < handFragments.length
      ? handFragments[handIndex]
      : null;

  CardDefinition handDisplayCard(int handIndex) {
    final definition = hand[handIndex];
    final fragment = handFragment(handIndex);
    if (fragment == null) return definition;
    final label = fragment.isLeft ? '左片' : '右片';
    final rawEffects = definition.shatter?[fragment.piece];
    final effects = rawEffects is List
        ? rawEffects
              .whereType<Map>()
              .map((effect) => Map<String, dynamic>.from(effect))
              .toList(growable: false)
        : <Map<String, dynamic>>[];
    final target =
        definition.shatter?['${fragment.piece}Target']?.toString() ??
        definition.target ??
        'none';
    return definition.copyWith(
      name: '${definition.name} · $label',
      description:
          '破碎$label：单独使用时只结算这一半效果；与同组另一片相邻后自动重组。${definition.description}',
      target: target,
      effect: effects,
    );
  }

  int _resolveHandIndex(CardDefinition card, int? preferredIndex) {
    if (preferredIndex != null &&
        preferredIndex >= 0 &&
        preferredIndex < hand.length &&
        hand[preferredIndex].id == card.id) {
      return preferredIndex;
    }
    return hand.indexWhere((item) => item.id == card.id);
  }

  int handCostReduction(int handIndex) =>
      handIndex >= 0 && handIndex < handCostReductions.length
      ? handCostReductions[handIndex]
      : 0;

  int handCost(int handIndex) {
    if (handIndex < 0 || handIndex >= hand.length) return 0;
    final discounted = hand[handIndex].cost - handCostReduction(handIndex);
    return discounted < 0 ? 0 : discounted;
  }

  List<OnlineUnit> _parseBoard(Object? raw) {
    if (raw is! List) return <OnlineUnit>[];
    return raw
        .whereType<Map>()
        .map((item) {
          final unit = Map<String, dynamic>.from(item);
          final cardId = unit['cardId']?.toString();
          final silenced = unit['silenced'] == true;
          final rawKeywords = unit['keywords'];
          final keywords = rawKeywords is List
              ? rawKeywords.map((item) => item.toString()).toList()
              : <String>[];
          final rawMinionTypes = unit['minionTypes'];
          final minionTypes = rawMinionTypes is List
              ? rawMinionTypes.map((item) => item.toString()).toList()
              : <String>[];
          final catalogDefinition = cardId == null ? null : card(cardId);
          final definition =
              catalogDefinition ??
              (cardId == null
                  ? null
                  : CardDefinition(
                      id: cardId,
                      name: unit['name']?.toString() ?? '衍生附肢',
                      description: '由权威对局状态生成的战场单位。',
                      faction: '中立',
                      type: 'unit',
                      cost: 0,
                      rarity: '衍生',
                      attack: (unit['attack'] as num?)?.toInt() ?? 0,
                      health:
                          (unit['maxHealth'] as num?)?.toInt() ??
                          (unit['health'] as num?)?.toInt() ??
                          1,
                      keywords: keywords,
                      minionTypes: minionTypes,
                    ));
          if (definition == null) return null;
          final projectedKeywords = rawKeywords is List
              ? keywords
              : silenced
              ? <String>[]
              : List<String>.from(definition.keywords);
          final hasAttacked = unit['hasAttacked'] == true;
          return OnlineUnit(
            instanceId: unit['entityId']?.toString() ?? definition.id,
            card: definition,
            attack: (unit['attack'] as num?)?.toInt() ?? definition.attack ?? 0,
            health: (unit['health'] as num?)?.toInt() ?? definition.health ?? 1,
            maxHealth:
                (unit['maxHealth'] as num?)?.toInt() ?? definition.health ?? 1,
            keywords: projectedKeywords,
            minionTypes: minionTypes.isNotEmpty
                ? minionTypes
                : List<String>.from(definition.minionTypes),
            hasAttacked: hasAttacked,
            attacksMade:
                (unit['attacksMade'] as num?)?.toInt() ?? (hasAttacked ? 1 : 0),
            summoningSick: unit['summoningSick'] == true,
            rushOnly: unit['rushOnly'] == true,
            stealthActive: unit['stealthActive'] == true,
            frozenTurns: (unit['frozenTurns'] as num?)?.toInt() ?? 0,
            stars: (unit['stars'] as num?)?.toInt() ?? 1,
            silenced: silenced,
          );
        })
        .whereType<OnlineUnit>()
        .toList();
  }

  List<OnlineUnit> get _visibleRemoteTaunts => remoteBoard
      .where((unit) => unit.health > 0 && !unit.stealthActive && unit.hasTaunt)
      .toList(growable: false);

  List<OnlineUnit> attackTargetsFor(OnlineUnit attacker) {
    if (!localBoard.contains(attacker) || !attacker.canAttack) {
      return const <OnlineUnit>[];
    }
    final visible = remoteBoard
        .where((unit) => unit.health > 0 && !unit.stealthActive)
        .toList(growable: false);
    final taunts = visible
        .where((unit) => unit.hasTaunt)
        .toList(growable: false);
    return taunts.isNotEmpty ? taunts : visible;
  }

  bool canAttackHeroWith(OnlineUnit attacker) =>
      canAct &&
      localBoard.contains(attacker) &&
      attacker.canAttack &&
      !attacker.rushOnly &&
      _visibleRemoteTaunts.isEmpty;

  bool hasLegalAttackTarget(OnlineUnit attacker) =>
      attackTargetsFor(attacker).isNotEmpty || canAttackHeroWith(attacker);

  List<OnlineUnit> get heroAttackTargets {
    final visible = remoteBoard
        .where((unit) => unit.health > 0 && !unit.stealthActive)
        .toList(growable: false);
    final taunts = visible
        .where((unit) => unit.hasTaunt)
        .toList(growable: false);
    return taunts.isNotEmpty ? taunts : visible;
  }

  bool get canHeroAttackEnemyHero =>
      canAct &&
      localWeaponAttack + localHeroAttackBonus > 0 &&
      (localWeaponCard == null || localWeaponDurability > 0) &&
      !localHeroHasAttacked &&
      _visibleRemoteTaunts.isEmpty;

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

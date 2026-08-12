import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalog.dart';
import '../models/card_definition.dart';

class GameController extends ChangeNotifier {
  GameController();

  List<CardDefinition> catalog = const [];
  final Map<String, int> collection = <String, int>{};
  final List<String> deckIds = <String>[];
  BattleState? battle;
  bool isLoading = true;
  String? errorMessage;
  String commanderName = '旅者 071';
  int gold = 1280;
  int dust = 360;
  int packs = 1;
  int wins = 0;
  int losses = 0;
  int matchesPlayed = 0;
  bool isResolvingTurn = false;

  final Random _random = Random(20260809);
  SharedPreferences? _prefs;
  Timer? _turnTimer;

  Map<String, CardDefinition> get cardsById => {
    for (final card in catalog) card.id: card,
  };

  Future<void> initialize() async {
    try {
      catalog = await loadCatalog();
      _prefs = await SharedPreferences.getInstance();
      _restoreState();
      if (deckIds.isEmpty) _seedStarterDeck();
      if (collection.isEmpty) {
        for (final card in catalog) {
          collection[card.id] =
              card.id.startsWith('sun-') || card.id.startsWith('neutral-')
              ? 2
              : 0;
        }
        _persistCollection();
      }
    } catch (error) {
      errorMessage = '卡牌档案加载失败：$error';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void _restoreState() {
    final storedDeck = _prefs?.getStringList('deck_ids');
    if (storedDeck != null) deckIds.addAll(storedDeck);
    final storedCollection = _prefs?.getString('collection');
    if (storedCollection != null) {
      final decoded = jsonDecode(storedCollection);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.value is num) {
            collection[entry.key.toString()] = (entry.value as num).toInt();
          }
        }
      }
    }
    commanderName = _prefs?.getString('commander_name') ?? commanderName;
    gold = _prefs?.getInt('gold') ?? gold;
    dust = _prefs?.getInt('dust') ?? dust;
    packs = _prefs?.getInt('packs') ?? packs;
    wins = _prefs?.getInt('wins') ?? wins;
    losses = _prefs?.getInt('losses') ?? losses;
    matchesPlayed = _prefs?.getInt('matches') ?? matchesPlayed;
  }

  void _seedStarterDeck() {
    final starter = catalog
        .where((card) => card.faction == '曜光' || card.id.startsWith('neutral-'))
        .take(15);
    for (final card in starter) {
      deckIds.add(card.id);
      deckIds.add(card.id);
    }
  }

  CardDefinition? card(String id) => cardsById[id];

  int owned(String id) => collection[id] ?? 0;

  bool addToDeck(CardDefinition card) {
    if (deckIds.length >= 30 ||
        owned(card.id) <= deckIds.where((id) => id == card.id).length) {
      return false;
    }
    if (card.rarity == '传说' &&
        deckIds.where((id) => id == card.id).isNotEmpty) {
      return false;
    }
    final faction = _deckFaction;
    if (card.faction != '中立' && faction != null && faction != card.faction) {
      return false;
    }
    deckIds.add(card.id);
    notifyListeners();
    return true;
  }

  void removeFromDeck(String id) {
    final index = deckIds.lastIndexOf(id);
    if (index >= 0) {
      deckIds.removeAt(index);
      notifyListeners();
    }
  }

  String? get _deckFaction {
    for (final id in deckIds) {
      final faction = card(id)?.faction;
      if (faction != null && faction != '中立') return faction;
    }
    return null;
  }

  Set<String> get _deckFactions => deckIds
      .map((id) => card(id)?.faction)
      .whereType<String>()
      .where((faction) => faction != '中立')
      .toSet();

  bool get deckValid => deckIds.length == 30 && _deckFactions.length <= 1;

  String get deckStatus {
    if (deckIds.length != 30) return '还差 ${30 - deckIds.length} 张卡牌';
    if (_deckFactions.length > 1) return '不能混合两个非中立阵营';
    return '卡组协议有效';
  }

  Future<void> saveDeck() async {
    await _prefs?.setStringList('deck_ids', deckIds);
    await _prefs?.setString('commander_name', commanderName);
    notifyListeners();
  }

  void openPack() {
    if (packs <= 0 || catalog.isEmpty) return;
    packs--;
    final eligible = catalog
        .where((card) => (collection[card.id] ?? 0) < _copyLimit(card))
        .toList();
    final normalPool = eligible.isNotEmpty ? eligible : catalog;
    final rarePool = normalPool.where((card) => card.rarity != '普通').toList();
    final guaranteedRarePool = rarePool.isNotEmpty
        ? rarePool
        : catalog.where((card) => card.rarity != '普通').toList();
    final drawn = <String, int>{};
    for (var i = 0; i < 5; i++) {
      final available = normalPool
          .where(
            (card) =>
                (collection[card.id] ?? 0) + (drawn[card.id] ?? 0) <
                _copyLimit(card),
          )
          .toList();
      final pool = i == 0
          ? guaranteedRarePool
          : (available.isNotEmpty ? available : normalPool);
      final picked = pool[_random.nextInt(pool.length)];
      drawn[picked.id] = (drawn[picked.id] ?? 0) + 1;
      collection[picked.id] = (collection[picked.id] ?? 0) + 1;
    }
    gold += 50;
    _prefs?.setInt('packs', packs);
    _prefs?.setInt('gold', gold);
    _persistCollection();
    notifyListeners();
  }

  int _copyLimit(CardDefinition card) => card.rarity == '传说' ? 1 : 2;

  HeroPowerDefinition _heroPowerForFaction(String faction) {
    switch (faction) {
      case '曜光':
        return const HeroPowerDefinition(
          id: 'radiance-mend',
          faction: '曜光',
          name: '日耀修复',
          description: '为一个友方角色恢复 2 点生命。',
          cost: 2,
          target: 'friendly-character',
          effect: {'kind': 'heal-friendly-character', 'amount': 2},
        );
      case '幽潮':
        return const HeroPowerDefinition(
          id: 'tide-pulse',
          faction: '幽潮',
          name: '潮汐脉冲',
          description: '对敌方核心造成 1 点伤害。',
          cost: 2,
          effect: {'kind': 'damage-enemy-hero', 'amount': 1},
        );
      case '烬火':
        return const HeroPowerDefinition(
          id: 'ember-scorch',
          faction: '烬火',
          name: '熔火灼痕',
          description: '对一个敌方单位造成 2 点伤害。',
          cost: 2,
          target: 'enemy-unit',
          effect: {'kind': 'damage-enemy-unit', 'amount': 2},
        );
      case '星穹':
        return const HeroPowerDefinition(
          id: 'astral-insight',
          faction: '星穹',
          name: '星穹洞见',
          description: '抽一张牌。',
          cost: 2,
          effect: {'kind': 'draw', 'count': 1},
        );
      case '苍林':
        return const HeroPowerDefinition(
          id: 'verdant-growth',
          faction: '苍林',
          name: '苍林生长',
          description: '召唤一个 1/2 的苔径奔行兽。',
          cost: 2,
          effect: {
            'kind': 'summon',
            'cardId': 'neutral-moss-runner',
            'count': 1,
          },
        );
      case '雷铸':
        return const HeroPowerDefinition(
          id: 'storm-plating',
          faction: '雷铸',
          name: '雷铸装甲',
          description: '为你的核心获得 2 点护甲。',
          cost: 2,
          effect: {'kind': 'armor', 'amount': 2},
        );
      default:
        return const HeroPowerDefinition(
          id: 'core-pulse',
          faction: '中立',
          name: '核心脉冲',
          description: '对敌方核心造成 1 点伤害。',
          cost: 2,
          effect: {'kind': 'damage-enemy-hero', 'amount': 1},
        );
    }
  }

  String _factionForCards(List<CardDefinition> cards) => cards
      .map((item) => item.faction)
      .firstWhere((faction) => faction != '中立', orElse: () => '中立');

  void _persistCollection() {
    _prefs?.setString('collection', jsonEncode(collection));
  }

  void startBattle() {
    if (catalog.isEmpty || isResolvingTurn) return;
    _turnTimer?.cancel();
    final deck = deckIds.length == 30
        ? deckIds
        : catalog
              .where((card) => card.faction == '曜光' || card.faction == '中立')
              .take(15)
              .expand((card) => [card.id, card.id])
              .toList();
    final playerDeck = deck.map((id) => card(id)!).toList()..shuffle(_random);
    final playerFaction = _factionForCards(playerDeck);
    final availableAiFactions = catalog
        .map((card) => card.faction)
        .where((faction) => faction != '中立')
        .toSet()
        .toList();
    final aiFaction = availableAiFactions.isEmpty
        ? '幽潮'
        : availableAiFactions[_random.nextInt(availableAiFactions.length)];
    final aiCandidates =
        catalog
            .where((card) => card.faction == aiFaction || card.faction == '中立')
            .toList()
          ..sort((left, right) => left.cost.compareTo(right.cost));
    final aiSingles = aiCandidates.take(15).toList();
    final aiDeck = aiSingles.expand((card) => [card, card]).toList()
      ..shuffle(_random);
    final player = BattleSide(
      heroHealth: 30,
      maxHeroHealth: 30,
      mana: 1,
      maxMana: 1,
      deck: playerDeck,
      hand: [],
      board: [],
    );
    final ai = BattleSide(
      heroHealth: 30,
      maxHeroHealth: 30,
      mana: 1,
      maxMana: 1,
      deck: aiDeck,
      hand: [],
      board: [],
      coinAvailable: true,
    );
    battle = BattleState(
      player: player,
      ai: ai,
      playerHeroPower: _heroPowerForFaction(playerFaction),
      aiHeroPower: _heroPowerForFaction(aiFaction),
      turn: 1,
      activePlayer: 'player',
      phase: 'mulligan',
      aiFaction: aiFaction,
      logs: ['对局开始：请选择要替换的起手牌。'],
    );
    for (var i = 0; i < 3; i++) {
      _draw(player);
      _draw(ai);
    }
    // The second player sees one extra card and receives the Coin. The local
    // client keeps the human on the first-player seat, so the AI owns it.
    _draw(ai);
    _autoMulligan(ai);
    _emitFx(
      'start',
      '战斗开始',
      '抽取起始手牌，准备部署你的第一支部队。',
      Icons.sports_kabaddi,
      0xFF69CFC3,
    );
    notifyListeners();
  }

  void toggleMulligan(int index) {
    final state = battle;
    if (state == null || state.phase != 'mulligan' || state.mulliganDone) {
      return;
    }
    if (index < 0 || index >= state.player.hand.length) return;
    if (!state.mulliganSelected.add(index)) {
      state.mulliganSelected.remove(index);
    }
    notifyListeners();
  }

  void confirmMulligan() {
    final state = battle;
    if (state == null || state.phase != 'mulligan' || state.mulliganDone) {
      return;
    }
    final selected = state.mulliganSelected.toList()..sort();
    final returned = <CardDefinition>[];
    for (final index in selected.reversed) {
      if (index >= 0 && index < state.player.hand.length) {
        returned.add(state.player.hand.removeAt(index));
      }
    }
    for (var i = 0; i < returned.length; i++) {
      _draw(state.player);
    }
    if (returned.isNotEmpty) {
      state.player.deck.addAll(returned);
      state.player.deck.shuffle(_random);
    }
    state.mulliganSelected.clear();
    state.mulliganDone = true;
    state.phase = 'main';
    state.player.maxMana = 1;
    state.player.mana = 1;
    state.heroPowerUsed = false;
    state.logs.insert(
      0,
      returned.isEmpty ? '起手牌已确认。' : '起手换牌完成，替换 ${returned.length} 张牌。',
    );
    _emitFx(
      'turn',
      '第一回合开始',
      '获得 1 点法力，部署你的战术。',
      Icons.hourglass_top,
      0xFF69CFC3,
    );
    _draw(state.player);
    _startTurnTimer();
    notifyListeners();
  }

  void _autoMulligan(BattleSide side) {
    final indexed = side.hand.asMap().entries.toList()
      ..sort((left, right) => left.value.cost.compareTo(right.value.cost));
    final keep = <int>{};
    final keptIds = <String>{};
    for (final entry in indexed) {
      if (keep.length >= 2 ||
          entry.value.cost > 2 ||
          !keptIds.add(entry.value.id)) {
        continue;
      }
      keep.add(entry.key);
    }
    if (keep.isEmpty && indexed.isNotEmpty) keep.add(indexed.first.key);
    final returned = <CardDefinition>[];
    for (final index
        in side.hand
            .asMap()
            .keys
            .where((index) => !keep.contains(index))
            .toList()
            .reversed) {
      returned.add(side.hand.removeAt(index));
    }
    for (var i = 0; i < returned.length; i++) {
      if (side.deck.isNotEmpty) side.hand.add(side.deck.removeLast());
    }
    side.deck.addAll(returned);
    side.deck.shuffle(_random);
  }

  void _startTurnTimer() {
    _turnTimer?.cancel();
    final state = battle;
    if (state == null || state.finished || state.activePlayer != 'player') {
      return;
    }
    state.turnSecondsLeft = 75;
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = battle;
      if (current == null ||
          current.finished ||
          current.activePlayer != 'player') {
        _turnTimer?.cancel();
        return;
      }
      current.turnSecondsLeft--;
      if (current.turnSecondsLeft <= 0 && !isResolvingTurn) {
        _turnTimer?.cancel();
        endTurn();
      }
      notifyListeners();
    });
  }

  void _draw(BattleSide side) {
    if (side.deck.isNotEmpty) {
      final drawn = side.deck.removeLast();
      if (side.hand.length < 10) {
        side.hand.add(drawn);
        return;
      }
      stateLog(
        _ownerOf(side) == 'player' ? '手牌已满' : '敌方手牌已满',
        ' ${drawn.name} 被燃毁。',
      );
      _emitFx(
        'burn',
        '手牌燃毁',
        '${drawn.name} 因手牌已满被销毁',
        Icons.local_fire_department,
        0xFFE46D3F,
        sourceId: drawn.id,
      );
      return;
    }
    if (side.deck.isEmpty) {
      side.fatigue++;
      _damageHero(side, side.fatigue);
      stateLog(
        _ownerOf(side) == 'player' ? '疲劳伤害' : '敌方疲劳伤害',
        '受到 ${side.fatigue} 点疲劳伤害。',
      );
      _emitFx(
        'fatigue',
        '疲劳伤害',
        '牌库为空，受到 ${side.fatigue} 点伤害',
        Icons.hourglass_disabled,
        0xFFE46D3F,
        amount: side.fatigue,
      );
    }
  }

  bool playCard(
    CardDefinition card, {
    BattleUnit? target,
    bool targetHero = false,
  }) {
    final state = battle;
    if (state == null ||
        state.finished ||
        state.activePlayer != 'player' ||
        state.phase != 'main' ||
        state.player.mana < card.cost) {
      return false;
    }
    if (!_validHandCard(state.player, card) ||
        (card.isUnit && state.player.board.length >= 7) ||
        !_validTarget(card, state.player, state.ai, target)) {
      return false;
    }
    _playCardForSide(
      card,
      source: state.player,
      enemy: state.ai,
      owner: 'player',
      target: target,
      targetHero: targetHero,
    );
    _checkFinished();
    notifyListeners();
    return true;
  }

  bool tradeCard(CardDefinition card) {
    final state = battle;
    if (state == null ||
        state.finished ||
        state.activePlayer != 'player' ||
        state.phase != 'main' ||
        !card.tradeable ||
        state.player.mana < 1) {
      return false;
    }
    final index = state.player.hand.indexWhere((item) => item.id == card.id);
    if (index < 0) return false;
    state.player.hand.removeAt(index);
    state.player.mana--;
    state.player.deck.add(card);
    state.player.deck.shuffle(_random);
    _draw(state.player);
    state.logs.insert(0, '${card.name} 已交易，抽取一张替代档案。');
    _emitFx(
      'trade',
      '可交易',
      '${card.name} 回到牌库并抽取替代牌',
      Icons.swap_horiz,
      0xFF65CDDA,
      sourceId: card.id,
    );
    notifyListeners();
    return true;
  }

  bool heroAttack({BattleUnit? target, bool targetHero = false}) {
    final state = battle;
    final weapon = state?.player.weapon;
    if (state == null ||
        state.finished ||
        state.phase != 'main' ||
        state.activePlayer != 'player' ||
        weapon == null ||
        weapon.durability <= 0 ||
        state.player.heroHasAttacked) {
      return false;
    }
    final taunts = state.ai.board
        .where((unit) => unit.hasTaunt && !unit.stealthActive)
        .toList();
    if (taunts.isNotEmpty && (target == null || !target.hasTaunt)) return false;
    if (target != null && !state.ai.board.contains(target)) return false;
    if (target?.stealthActive ?? false) return false;
    if (target == null) {
      _triggerSecrets(
        state.ai,
        'opponent-attacks-hero',
        triggeringSide: state.player,
      );
      if (state.player.heroHealth <= 0) {
        _processDeaths();
        _checkFinished();
        notifyListeners();
        return false;
      }
    }
    final dealt = target == null
        ? _damageHero(state.ai, weapon.attack)
        : _damageUnit(target, weapon.attack, combat: true);
    state.player.heroHasAttacked = true;
    weapon.durability--;
    state.logs.insert(
      0,
      target == null
          ? '英雄使用 ${weapon.card.name} 攻击敌方核心，造成 $dealt 点伤害。'
          : '英雄使用 ${weapon.card.name} 攻击 ${target.card.name}。',
    );
    _emitFx(
      'attack',
      '英雄发起攻击',
      target == null ? '对敌方核心造成 $dealt 点伤害' : '与 ${target.card.name} 交战',
      Icons.flash_on,
      0xFFE46D3F,
      sourceId: 'player-hero',
      targetId: target?.instanceId ?? 'ai-hero',
      amount: dealt,
    );
    if (weapon.durability <= 0) {
      state.logs.insert(0, '${weapon.card.name} 耐久耗尽。');
      state.player.weapon = null;
      _emitFx(
        'death',
        '${weapon.card.name} 损毁',
        '武器耐久耗尽，已离开装备区',
        Icons.broken_image_outlined,
        0xFF9D7567,
      );
    }
    _checkFinished();
    notifyListeners();
    return true;
  }

  bool useHeroPower({BattleUnit? target, bool targetHero = false}) {
    final state = battle;
    if (state == null ||
        state.finished ||
        state.activePlayer != 'player' ||
        state.phase != 'main' ||
        state.heroPowerUsed ||
        !_canResolveHeroPower(
          state.playerHeroPower,
          source: state.player,
          enemy: state.ai,
          target: target,
          targetHero: targetHero,
        )) {
      return false;
    }
    final resolved = _resolveHeroPower(
      state.playerHeroPower,
      source: state.player,
      enemy: state.ai,
      owner: 'player',
      target: target,
      targetHero: targetHero,
    );
    if (!resolved) return false;
    _checkFinished();
    notifyListeners();
    return true;
  }

  bool _canResolveHeroPower(
    HeroPowerDefinition power, {
    required BattleSide source,
    required BattleSide enemy,
    BattleUnit? target,
    required bool targetHero,
  }) {
    if (source.mana < power.cost) return false;
    final targetType = power.target ?? 'none';
    if (targetType == 'enemy-unit') {
      return target != null &&
          enemy.board.contains(target) &&
          !target.stealthActive;
    }
    if (targetType == 'friendly-unit') {
      return target != null && source.board.contains(target);
    }
    if (targetType == 'friendly-character') {
      return targetHero || (target != null && source.board.contains(target));
    }
    return true;
  }

  bool _resolveHeroPower(
    HeroPowerDefinition power, {
    required BattleSide source,
    required BattleSide enemy,
    required String owner,
    BattleUnit? target,
    required bool targetHero,
  }) {
    final state = battle;
    if (state == null ||
        !_canResolveHeroPower(
          power,
          source: source,
          enemy: enemy,
          target: target,
          targetHero: targetHero,
        )) {
      return false;
    }
    source.mana -= power.cost;
    if (owner == 'player') {
      state.heroPowerUsed = true;
    } else {
      state.aiHeroPowerUsed = true;
    }
    final effect = power.effect;
    final kind = effect['kind']?.toString();
    final amount = (effect['amount'] as num?)?.toInt() ?? 0;
    final sourceId = owner == 'player' ? 'player-hero-power' : 'ai-hero-power';
    switch (kind) {
      case 'damage-enemy-hero':
        final dealt = _damageHero(enemy, amount);
        stateLog(power.name, '对敌方核心造成 $dealt 点伤害。');
        _emitFx(
          'hero-power',
          power.name,
          '英雄技能造成 $dealt 点核心伤害',
          Icons.bolt,
          0xFF65CDDA,
          sourceId: sourceId,
          targetId: owner == 'player' ? 'ai-hero' : 'player-hero',
          amount: dealt,
        );
        break;
      case 'damage-enemy-unit':
        if (target == null || !enemy.board.contains(target)) return false;
        final dealt = _damageUnit(target, amount);
        stateLog(power.name, '对 ${target.card.name} 造成 $dealt 点伤害。');
        _emitFx(
          'hero-power',
          power.name,
          '英雄技能命中 ${target.card.name}',
          Icons.bolt,
          0xFFE46D3F,
          sourceId: sourceId,
          targetId: target.instanceId,
          amount: dealt,
        );
        break;
      case 'heal-friendly-character':
        if (targetHero) {
          final before = source.heroHealth;
          source.heroHealth = min(
            source.maxHeroHealth,
            source.heroHealth + amount,
          );
          stateLog(power.name, '核心恢复 ${source.heroHealth - before} 点生命。');
        } else if (target != null && source.board.contains(target)) {
          target.health = min(target.maxHealth, target.health + amount);
          stateLog(power.name, '${target.card.name} 恢复 $amount 点生命。');
        } else {
          return false;
        }
        _emitFx(
          'hero-power',
          power.name,
          power.description,
          Icons.favorite,
          0xFF79B980,
          sourceId: sourceId,
          targetId: targetHero ? '$owner-hero' : target?.instanceId,
          amount: amount,
        );
        break;
      case 'heal-friendly-unit':
        if (target == null || !source.board.contains(target)) return false;
        target.health = min(target.maxHealth, target.health + amount);
        stateLog(power.name, '${target.card.name} 恢复 $amount 点生命。');
        break;
      case 'draw':
        final count = (effect['count'] as num?)?.toInt() ?? 1;
        for (var i = 0; i < count; i++) {
          _draw(source);
        }
        stateLog(power.name, '抽取 $count 张牌。');
        break;
      case 'summon':
        final cardId = effect['cardId']?.toString();
        final summonCard = cardId == null ? null : card(cardId);
        final count = (effect['count'] as num?)?.toInt() ?? 1;
        if (summonCard == null || !summonCard.isUnit) return false;
        for (var i = 0; i < count && source.board.length < 7; i++) {
          final unit = _summonUnit(summonCard, owner: owner);
          source.board.add(unit);
          _emitFx(
            'summon',
            '${power.name} · ${summonCard.name}',
            '英雄技能召唤一个新的战场单位',
            Icons.auto_awesome,
            factionColors[summonCard.faction] ?? 0xFF69CFC3,
            sourceId: sourceId,
          );
        }
        break;
      case 'armor':
        source.armor += amount;
        stateLog(power.name, '核心获得 $amount 点护甲。');
        _emitFx(
          'armor',
          power.name,
          '核心获得 $amount 点护甲',
          Icons.shield,
          0xFFE7BD7A,
          sourceId: sourceId,
          amount: amount,
        );
        break;
      default:
        return false;
    }
    _processDeaths();
    return true;
  }

  bool useCoin() {
    final state = battle;
    if (state == null ||
        state.finished ||
        state.phase != 'main' ||
        state.activePlayer != 'player' ||
        !state.player.coinAvailable) {
      return false;
    }
    state.player.coinAvailable = false;
    final absorbsOverloadDebt =
        state.player.overloadLocked > state.player.maxMana;
    if (absorbsOverloadDebt) {
      state.player.overloadLocked -= 1;
      state.logs.insert(0, '你使用幸运币，抵消 1 点过载锁定。');
    } else {
      state.player.mana += 1;
      state.logs.insert(0, '你使用幸运币，获得 1 点临时法力。');
    }
    _emitFx(
      'coin',
      '幸运币',
      absorbsOverloadDebt ? '抵消 1 点过载锁定' : '获得 1 点临时法力',
      Icons.monetization_on,
      0xFFE7BD7A,
      amount: 1,
    );
    notifyListeners();
    return true;
  }

  BattleUnit _summonUnit(
    CardDefinition card, {
    required String owner,
    int? healthOverride,
    bool reborn = false,
  }) {
    final rush = card.keywords.contains('rush');
    final charge = card.keywords.contains('charge');
    return BattleUnit(
      instanceId:
          '$owner-${DateTime.now().microsecondsSinceEpoch}-${card.id}-${_random.nextInt(9999)}',
      card: card,
      owner: owner,
      attack: card.attack ?? 0,
      health: healthOverride ?? card.health ?? 1,
      maxHealth: healthOverride ?? card.health ?? 1,
      hasAttacked: !charge && !rush,
      divineShield: card.keywords.contains('shield') && !reborn,
      summoningSick: !charge && !rush,
      rushOnly: rush,
      stealthActive: card.keywords.contains('stealth'),
      rebornUsed: reborn,
    );
  }

  void _playCardForSide(
    CardDefinition card, {
    required BattleSide source,
    required BattleSide enemy,
    required String owner,
    BattleUnit? target,
    bool targetHero = false,
  }) {
    final handIndex = source.hand.indexWhere((item) => item.id == card.id);
    if (handIndex < 0) return;
    source.hand.removeAt(handIndex);
    source.mana -= card.cost;
    final comboActive = source.cardsPlayedThisTurn > 0;
    source.cardsPlayedThisTurn++;
    if (card.type == 'spell' &&
        _triggerSecrets(
          enemy,
          'opponent-plays-spell',
          triggeringSide: source,
        )) {
      stateLog(
        owner == 'player' ? '${card.name} 被奥秘反制。' : '敌方的 ${card.name} 被奥秘反制。',
      );
      _processDeaths();
      return;
    }
    source.overloadLocked += card.overload;
    if (card.type == 'weapon') {
      final maxDurability = max(1, card.durability ?? card.health ?? 1);
      source.weapon = BattleWeapon(
        card: card,
        attack: card.attack ?? 0,
        durability: maxDurability,
        maxDurability: maxDurability,
      );
      source.heroHasAttacked = false;
      stateLog(owner == 'player' ? '${card.name} 已装备。' : '敌方装备 ${card.name}。');
      _emitFx(
        'weapon',
        '${card.name} 装备',
        '${card.attack ?? 0} 攻击 · $maxDurability 耐久',
        Icons.shield_moon,
        factionColors[card.faction] ?? 0xFFE7BD7A,
        sourceId: card.id,
      );
    } else if (card.isUnit) {
      final unit = _summonUnit(card, owner: owner);
      source.board.add(unit);
      _triggerSecrets(enemy, 'opponent-summons-unit', triggeringSide: source);
      source.board.length == 1 && owner == 'player'
          ? _emitFx(
              'summon',
              '${card.name} 登场',
              card.description,
              Icons.auto_awesome,
              factionColors[card.faction] ?? 0xFF69CFC3,
              sourceId: unit.instanceId,
            )
          : _emitFx(
              'summon',
              owner == 'player' ? '${card.name} 登场' : '敌方部署 ${card.name}',
              card.description,
              Icons.auto_awesome,
              factionColors[card.faction] ?? 0xFF69CFC3,
              sourceId: unit.instanceId,
            );
      stateLog(owner == 'player' ? '${card.name} 登场。' : '敌方部署 ${card.name}。');
      _resolveEffects(
        card.onPlay,
        source: source,
        enemy: enemy,
        target: target ?? (card.target == null ? unit : null),
        targetHero: targetHero,
        sourceName: card.name,
        sourceCard: card,
      );
      if (comboActive && card.combo.isNotEmpty && battle?.phase == 'main') {
        _resolveEffects(
          card.combo,
          source: source,
          enemy: enemy,
          target: target,
          targetHero: targetHero,
          sourceName: '${card.name} · 连击',
          sourceCard: card,
        );
      }
    } else {
      _emitFx(
        'spell',
        '${card.name} 释放',
        card.description,
        Icons.auto_awesome,
        factionColors[card.faction] ?? 0xFFA692D1,
        sourceId: card.id,
        amount: _cardEffectAmount(card),
      );
      _resolveEffects(
        card.effect,
        source: source,
        enemy: enemy,
        target: target,
        targetHero: targetHero,
        sourceName: card.name,
        sourceCard: card,
      );
      if (comboActive && card.combo.isNotEmpty && battle?.phase == 'main') {
        _resolveEffects(
          card.combo,
          source: source,
          enemy: enemy,
          target: target,
          targetHero: targetHero,
          sourceName: '${card.name} · 连击',
          sourceCard: card,
        );
      }
      if (battle?.phase == 'main') {
        _resolveSpellTriggers(source: source, enemy: enemy);
      }
      stateLog(card.name, card.description);
    }
    _processDeaths();
  }

  bool _validHandCard(BattleSide side, CardDefinition card) =>
      side.hand.any((item) => item.id == card.id);

  bool _validTarget(
    CardDefinition card,
    BattleSide source,
    BattleSide enemy,
    BattleUnit? target,
  ) {
    final targetType = card.target ?? '';
    if (!targetType.contains('unit')) return true;
    if (target == null) {
      return false;
    }
    if (target.stealthActive) return false;
    final friendly = targetType.startsWith('friendly');
    return friendly
        ? source.board.contains(target)
        : enemy.board.contains(target);
  }

  int _spellDamageBonus(BattleSide side) => side.board
      .where((unit) => !unit.silenced)
      .fold(0, (total, unit) => total + unit.card.spellDamage);

  void _resolveSpellTriggers({
    required BattleSide source,
    required BattleSide enemy,
  }) {
    for (final unit in [...source.board]) {
      if (!source.board.contains(unit) ||
          unit.silenced ||
          unit.card.onSpellPlayed.isEmpty) {
        continue;
      }
      _resolveEffects(
        unit.card.onSpellPlayed,
        source: source,
        enemy: enemy,
        target: unit,
        sourceName: '${unit.card.name} · 法术触发',
      );
    }
  }

  void _resolveEffects(
    List<Map<String, dynamic>> effects, {
    required BattleSide source,
    required BattleSide enemy,
    BattleUnit? target,
    bool targetHero = false,
    required String sourceName,
    CardDefinition? sourceCard,
  }) {
    for (final effect in effects) {
      final kind = effect['kind']?.toString();
      final amount = (effect['amount'] as num?)?.toInt() ?? 0;
      final spellBonus = sourceCard?.type == 'spell'
          ? _spellDamageBonus(source)
          : 0;
      final damageAmount = amount + spellBonus;
      switch (kind) {
        case 'secret':
          final secretId = effect['secretId']?.toString();
          final trigger = effect['trigger']?.toString();
          final secretEffect = effect['effect'];
          if (secretId != null &&
              trigger != null &&
              secretEffect is Map &&
              source.secrets.length < 5 &&
              !source.secrets.any((secret) => secret.secretId == secretId)) {
            source.secrets.add(
              BattleSecret(
                card:
                    sourceCard ??
                    catalog.firstWhere(
                      (item) => sourceName.startsWith(item.name),
                      orElse: () => catalog.first,
                    ),
                secretId: secretId,
                trigger: trigger,
                effect: Map<String, dynamic>.from(secretEffect),
              ),
            );
            stateLog(sourceName, '已暗置奥秘。');
          }
          break;
        case 'discover':
          final choices = effect['choices'];
          final state = battle;
          if (state != null && choices is List) {
            final validChoices = choices
                .map((item) => item.toString())
                .where((id) => card(id) != null)
                .toList();
            if (validChoices.isNotEmpty) {
              state.phase = 'discover';
              state.discoverChoices = validChoices;
              state.discoverSource = sourceCard?.id ?? sourceName;
              state.discoverOwner = _ownerOf(source);
              stateLog(sourceName, '从候选档案中发现一张卡牌。');
              _emitFx(
                'discover',
                '发现选择',
                '从 ${validChoices.length} 张候选卡牌中选择一张',
                Icons.travel_explore,
                0xFFA692D1,
              );
              return;
            }
          }
          break;
        case 'damage':
          if (target != null && enemy.board.contains(target)) {
            _damageUnit(target, damageAmount);
          } else {
            final dealt = _damageHero(enemy, damageAmount);
            stateLog('$sourceName：', '对敌方核心造成 $dealt 点伤害');
          }
          break;
        case 'damage-all-enemies':
          final dealt = _damageHero(enemy, damageAmount);
          for (final unit in [...enemy.board]) {
            _damageUnit(unit, damageAmount);
          }
          stateLog(sourceName, '对敌方核心和战场造成 $damageAmount 点范围伤害（核心实际 $dealt）。');
          break;
        case 'freeze':
          if (target != null && enemy.board.contains(target)) {
            target.frozenTurns = max(target.frozenTurns, max(1, amount));
            stateLog(sourceName, '${target.card.name} 被冻结。');
          }
          break;
        case 'random-enemy-freeze':
          final candidates = enemy.board
              // Hearthstone random effects may hit Stealth units. Stealth
              // only prevents explicit targeting and attacks.
              .where((unit) => unit.health > 0)
              .toList();
          if (candidates.isNotEmpty) {
            final frozen = candidates[_random.nextInt(candidates.length)];
            frozen.frozenTurns = max(frozen.frozenTurns, max(1, amount));
            stateLog(sourceName, '${frozen.card.name} 被冻结。');
          }
          break;
        case 'random-enemy-damage':
          final candidates = [...enemy.board];
          if (candidates.isEmpty) {
            _damageHero(enemy, damageAmount);
          } else {
            final targets = <Object>[enemy, ...candidates];
            final picked = targets[_random.nextInt(targets.length)];
            if (picked is BattleSide) {
              _damageHero(picked, damageAmount);
            } else {
              _damageUnit(picked as BattleUnit, damageAmount);
            }
          }
          break;
        case 'heal':
          if (target != null && source.board.contains(target)) {
            target.health = min(target.maxHealth, target.health + amount);
          } else {
            final before = source.heroHealth;
            source.heroHealth = min(
              source.maxHeroHealth,
              source.heroHealth + amount,
            );
            final healed = source.heroHealth - before;
            stateLog('$sourceName：', '恢复 $healed 点核心生命');
          }
          break;
        case 'draw':
          final count = (effect['count'] as num?)?.toInt() ?? 1;
          for (var i = 0; i < count; i++) {
            _draw(source);
          }
          break;
        case 'buff':
          final unit = target != null && source.board.contains(target)
              ? target
              : source.board.isEmpty
              ? null
              : source.board.last;
          if (unit != null) {
            final attack = (effect['attack'] as num?)?.toInt() ?? 0;
            final health = (effect['health'] as num?)?.toInt() ?? 0;
            unit.attack += attack;
            unit.maxHealth += health;
            unit.health += health;
            unit.permanentAttackBonus += attack;
            unit.permanentHealthBonus += health;
            stateLog('$sourceName：', '${unit.card.name} 获得 +$attack/+$health');
          }
          break;
        case 'buff-all-friendly':
          final attack = (effect['attack'] as num?)?.toInt() ?? 0;
          final health = (effect['health'] as num?)?.toInt() ?? 0;
          for (final unit in [...source.board]) {
            unit.attack += attack;
            unit.maxHealth += health;
            unit.health += health;
            unit.permanentAttackBonus += attack;
            unit.permanentHealthBonus += health;
          }
          stateLog(sourceName, '友方全体获得 +$attack/+$health。');
          break;
        case 'temporary-buff':
          final unit = target != null && source.board.contains(target)
              ? target
              : source.board.isEmpty
              ? null
              : source.board.last;
          if (unit != null) {
            final attack = (effect['attack'] as num?)?.toInt() ?? 0;
            final health = (effect['health'] as num?)?.toInt() ?? 0;
            unit.attack += attack;
            unit.maxHealth += health;
            unit.health += health;
            unit.temporaryAttackBonus += attack;
            unit.temporaryHealthBonus += health;
            stateLog(sourceName, '${unit.card.name} 获得临时 +$attack/+$health。');
          }
          break;
        case 'silence':
          if (target == null) break;
          final targetSide = source.board.contains(target)
              ? source
              : enemy.board.contains(target)
              ? enemy
              : null;
          if (targetSide == null) break;
          target.attack = target.card.attack ?? 0;
          target.maxHealth = target.card.health ?? 1;
          target.health = min(target.health, target.maxHealth);
          target.permanentAttackBonus = 0;
          target.permanentHealthBonus = 0;
          target.temporaryAttackBonus = 0;
          target.temporaryHealthBonus = 0;
          target.silenced = true;
          target.divineShield = false;
          target.stealthActive = false;
          target.frozenTurns = 0;
          target.freezeBlocked = false;
          target.rushOnly = false;
          target.rebornUsed = true;
          stateLog(sourceName, '${target.card.name} 被沉默。');
          break;
        case 'transform':
          if (target == null) break;
          final cardId = effect['cardId']?.toString();
          final transformed = cardId == null ? null : card(cardId);
          if (transformed == null || !transformed.isUnit) break;
          final targetSide = source.board.contains(target)
              ? source
              : enemy.board.contains(target)
              ? enemy
              : null;
          if (targetSide == null) break;
          final index = targetSide.board.indexOf(target);
          if (index < 0) break;
          final replacement = _summonUnit(transformed, owner: target.owner);
          targetSide.board[index] = replacement;
          stateLog(sourceName, '${target.card.name} 变形为 ${transformed.name}。');
          break;
        case 'choose-one':
          final options = effect['options'];
          final state = battle;
          if (state != null && options is List && options.length >= 2) {
            state.phase = 'choose-one';
            state.chooseOneOptions = options
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
            state.chooseOneSource = sourceName;
            state.chooseOneOwner = _ownerOf(source);
            state.chooseOneTarget = target;
            stateLog(sourceName, '请选择一个战术分支。');
            _emitFx(
              'choose-one',
              '抉择分支',
              '从多个效果中选择一个',
              Icons.alt_route,
              0xFFA692D1,
            );
            return;
          }
          break;
        case 'armor':
          source.armor += amount;
          break;
        case 'summon':
          final cardId = effect['cardId']?.toString();
          final summonCard = cardId == null ? null : card(cardId);
          final count = (effect['count'] as num?)?.toInt() ?? 1;
          if (summonCard != null && summonCard.isUnit) {
            for (var i = 0; i < count && source.board.length < 7; i++) {
              final unit = _summonUnit(summonCard, owner: _ownerOf(source));
              source.board.add(unit);
              _emitFx(
                'summon',
                '${summonCard.name} 被召唤',
                '效果生成一个新的战场单位',
                Icons.auto_awesome,
                factionColors[summonCard.faction] ?? 0xFF69CFC3,
                sourceId: unit.instanceId,
              );
            }
          }
          break;
      }
      _processDeaths();
    }
  }

  bool _triggerSecrets(
    BattleSide owner,
    String trigger, {
    required BattleSide triggeringSide,
    BattleUnit? attackingUnit,
  }) {
    final pending = owner.secrets
        .where((secret) => secret.trigger == trigger)
        .toList();
    if (pending.isEmpty) return false;
    var countered = false;
    for (final secret in pending) {
      owner.secrets.remove(secret);
      final kind = secret.effect['kind']?.toString();
      final amount = (secret.effect['amount'] as num?)?.toInt() ?? 0;
      switch (kind) {
        case 'counterspell':
          countered = true;
          stateLog('奥秘触发', '${secret.card.name} 反制了这张战术。');
          break;
        case 'damage-enemy-hero':
          final dealt = _damageHero(triggeringSide, amount);
          stateLog('奥秘触发', '${secret.card.name} 造成 $dealt 点核心伤害。');
          _emitFx(
            'secret',
            '${secret.card.name} 触发',
            '对敌方核心造成 $dealt 点伤害',
            Icons.auto_awesome,
            0xFFE46D3F,
            amount: dealt,
          );
          break;
        case 'damage-attacker':
          if (attackingUnit != null) {
            final dealt = _damageUnit(attackingUnit, amount);
            stateLog('奥秘触发', '${secret.card.name} 对攻击者造成 $dealt 点伤害。');
          } else {
            final dealt = _damageHero(triggeringSide, amount);
            stateLog('奥秘触发', '${secret.card.name} 对英雄造成 $dealt 点伤害。');
          }
          break;
        case 'armor':
          owner.armor += amount;
          stateLog('奥秘触发', '${secret.card.name} 让核心获得 $amount 点护甲。');
          break;
        case 'draw':
          final count = (secret.effect['count'] as num?)?.toInt() ?? 1;
          for (var i = 0; i < count; i++) {
            _draw(owner);
          }
          break;
      }
    }
    return countered;
  }

  bool chooseDiscover(String cardId) {
    final state = battle;
    if (state == null ||
        state.phase != 'discover' ||
        !state.discoverChoices.contains(cardId)) {
      return false;
    }
    final discovered = card(cardId);
    if (discovered == null) return false;
    final owner = state.discoverOwner == 'ai' ? state.ai : state.player;
    final enemy = identical(owner, state.player) ? state.ai : state.player;
    if (owner.hand.length < 10) {
      owner.hand.add(discovered);
    } else {
      stateLog('发现失败', '${discovered.name} 因手牌已满被燃毁。');
    }
    state.phase = 'main';
    state.discoverChoices = <String>[];
    state.discoverSource = null;
    state.discoverOwner = 'player';
    stateLog('发现完成', '${discovered.name} 已加入手牌。');
    _resolveSpellTriggers(source: owner, enemy: enemy);
    _emitFx(
      'discover',
      '发现完成',
      '${discovered.name} 已加入手牌',
      Icons.check_circle_outline,
      0xFFA692D1,
    );
    notifyListeners();
    return true;
  }

  bool chooseOne(int optionIndex) {
    final state = battle;
    if (state == null ||
        state.phase != 'choose-one' ||
        optionIndex < 0 ||
        optionIndex >= state.chooseOneOptions.length) {
      return false;
    }
    final option = state.chooseOneOptions[optionIndex];
    final effects = option['effects'];
    if (effects is! List) return false;
    final source = state.chooseOneOwner == 'ai' ? state.ai : state.player;
    final enemy = identical(source, state.player) ? state.ai : state.player;
    final parsed = effects
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final sourceName = state.chooseOneSource ?? '抉择';
    final target = state.chooseOneTarget;
    state.phase = 'main';
    state.chooseOneOptions = <Map<String, dynamic>>[];
    state.chooseOneSource = null;
    state.chooseOneOwner = 'player';
    state.chooseOneTarget = null;
    _resolveEffects(
      parsed,
      source: source,
      enemy: enemy,
      target: target,
      sourceName: '$sourceName · ${option['label'] ?? '分支'}',
    );
    if (state.phase == 'main') {
      _resolveSpellTriggers(source: source, enemy: enemy);
    }
    stateLog('抉择完成', '已选择 ${option['label'] ?? '一个分支'}。');
    _processDeaths();
    _checkFinished();
    notifyListeners();
    return true;
  }

  bool attack(BattleUnit attacker, {BattleUnit? target}) {
    final state = battle;
    if (state == null ||
        state.finished ||
        state.activePlayer != 'player' ||
        state.phase != 'main' ||
        !attacker.canAttack ||
        !state.player.board.contains(attacker)) {
      return false;
    }
    final taunts = state.ai.board
        .where((unit) => unit.hasTaunt && !unit.stealthActive)
        .toList();
    if (taunts.isNotEmpty && (target == null || !target.hasTaunt)) {
      return false;
    }
    if (target != null && !state.ai.board.contains(target)) return false;
    if (target?.stealthActive ?? false) return false;
    if (target == null && attacker.rushOnly) return false;
    _performAttack(attacker, state.ai, target);
    _checkFinished();
    notifyListeners();
    return true;
  }

  void _performAttack(
    BattleUnit attacker,
    BattleSide defender,
    BattleUnit? target,
  ) {
    if (target == null) {
      _triggerSecrets(
        defender,
        'opponent-attacks-hero',
        triggeringSide: _sideFor(attacker),
        attackingUnit: attacker,
      );
      if (attacker.health <= 0 ||
          !_sideFor(attacker).board.contains(attacker)) {
        _processDeaths();
        return;
      }
    }
    attacker.stealthActive = false;
    attacker.attacksMade++;
    attacker.hasAttacked = true;
    final defenderName = target?.card.name ?? '敌方核心';
    final outgoing = target == null
        ? _damageHero(defender, attacker.attack)
        : _damageUnit(target, attacker.attack, source: attacker, combat: true);
    if (attacker.hasLifesteal && outgoing > 0) {
      final before = _sideFor(attacker).heroHealth;
      final side = _sideFor(attacker);
      side.heroHealth = min(side.maxHeroHealth, side.heroHealth + outgoing);
      stateLog('${attacker.card.name}：', '汲取 $outgoing 点生命');
      if (side.heroHealth > before) {
        _emitFx(
          'heal',
          '生命汲取',
          '${attacker.card.name} 恢复自身核心',
          Icons.favorite,
          0xFF79B980,
        );
      }
    }
    if (target != null && target.health > 0) {
      final reflected = _damageUnit(
        attacker,
        target.attack,
        source: target,
        combat: true,
      );
      if (target.hasLifesteal && reflected > 0) {
        final side = _sideFor(target);
        side.heroHealth = min(side.maxHeroHealth, side.heroHealth + reflected);
      }
    }
    _emitFx(
      'attack',
      '${attacker.card.name} 发起攻击',
      target == null ? '对敌方核心造成 $outgoing 点伤害' : '与 $defenderName 发生交战',
      Icons.flash_on,
      0xFFE46D3F,
      sourceId: attacker.instanceId,
      targetId: target?.instanceId ?? 'ai-hero',
      amount: outgoing,
    );
    stateLog(
      attacker.card.name,
      target == null ? '对敌方核心造成 $outgoing 点伤害。' : '与 $defenderName 交战。',
    );
    _processDeaths();
  }

  int _damageHero(BattleSide side, int amount) {
    if (amount <= 0) return 0;
    final absorbed = min(side.armor, amount);
    side.armor -= absorbed;
    final healthDamage = amount - absorbed;
    side.heroHealth = max(0, side.heroHealth - healthDamage);
    return healthDamage;
  }

  int _damageUnit(
    BattleUnit unit,
    int amount, {
    BattleUnit? source,
    bool combat = false,
  }) {
    if (amount <= 0 || unit.health <= 0) return 0;
    if (unit.divineShield) {
      unit.divineShield = false;
      _emitFx(
        'shield',
        '护盾破碎',
        '${unit.card.name} 的护盾抵消了伤害',
        Icons.shield,
        0xFFE7BD7A,
        sourceId: unit.instanceId,
        targetId: unit.instanceId,
      );
      return 0;
    }
    final applied = min(unit.health, amount);
    unit.health = max(0, unit.health - amount);
    if (source?.hasPoisonous == true && applied > 0 && unit.health > 0) {
      unit.health = 0;
      stateLog('${source!.card.name}：', '${unit.card.name} 受到剧毒。');
      _emitFx(
        'poison',
        '剧毒生效',
        '${unit.card.name} 被剧毒摧毁',
        Icons.coronavirus,
        0xFF79B980,
        sourceId: source.instanceId,
        targetId: unit.instanceId,
      );
    }
    if (combat && unit.hasFury && !unit.furyTriggered && unit.health > 0) {
      unit.furyTriggered = true;
      unit.attack += 1;
      stateLog('${unit.card.name}：', '激昂触发，攻击力 +1');
      _emitFx(
        'fury',
        '激昂触发',
        '${unit.card.name} 获得 +1 攻击',
        Icons.whatshot,
        0xFFE46D3F,
        sourceId: unit.instanceId,
        targetId: unit.instanceId,
      );
    }
    return applied;
  }

  BattleSide _sideFor(BattleUnit unit) {
    final state = battle!;
    return unit.owner == 'player' ? state.player : state.ai;
  }

  String _ownerOf(BattleSide side) {
    final state = battle!;
    return identical(side, state.player) ? 'player' : 'ai';
  }

  void _processDeaths() {
    final state = battle;
    if (state == null) return;
    for (final side in [state.player, state.ai]) {
      final dead = side.board.where((unit) => unit.health <= 0).toList();
      final enemy = identical(side, state.player) ? state.ai : state.player;
      for (final unit in dead) {
        side.board.remove(unit);
        stateLog('亡语回响', '${unit.card.name} 离开战场。');
        _emitFx(
          'death',
          '${unit.card.name} 被摧毁',
          '战场位置已释放',
          Icons.blur_on,
          0xFF9D7567,
          sourceId: unit.instanceId,
          targetId: unit.instanceId,
        );
        if (unit.card.hasDeathrattle && !unit.silenced) {
          _resolveEffects(
            unit.card.onDeath,
            source: side,
            enemy: enemy,
            sourceName: '${unit.card.name} 的亡语',
            sourceCard: unit.card,
          );
        }
        if (unit.hasReborn && !unit.rebornUsed && side.board.length < 7) {
          final reborn = _summonUnit(
            unit.card,
            owner: unit.owner,
            healthOverride: 1,
            reborn: true,
          );
          side.board.add(reborn);
          _emitFx(
            'reborn',
            '${unit.card.name} 复生',
            '以 1 点生命重新回到战场',
            Icons.autorenew,
            0xFFA692D1,
            sourceId: reborn.instanceId,
          );
        }
      }
    }
  }

  Future<void> endTurn() async {
    final state = battle;
    if (state == null ||
        state.finished ||
        state.phase != 'main' ||
        state.activePlayer != 'player') {
      return;
    }
    if (isResolvingTurn) return;
    isResolvingTurn = true;
    _turnTimer?.cancel();
    _resolveTurnTriggers(state.player, start: false);
    _clearTemporaryBuffs(state.player);
    _settleFreezeAtEndOfTurn(state.player);
    _processDeaths();
    _checkFinished();
    if (state.finished) {
      isResolvingTurn = false;
      notifyListeners();
      return;
    }
    state.phase = 'end';
    state.activePlayer = 'ai';
    state.logs.insert(0, '你结束回合，敌方演算体获得行动权。');
    _emitFx('turn', '回合交接', '敌方演算体开始行动', Icons.swap_vert, 0xFFA692D1);
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await _aiTurn(state);
    if (!state.finished) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      state.turn++;
      state.activePlayer = 'player';
      state.phase = 'main';
      state.heroPowerUsed = false;
      _refillMana(state.player);
      _refreshSideForTurn(state.player);
      _resolveTurnTriggers(state.player, start: true);
      _draw(state.player);
      state.logs.insert(0, '第 ${state.turn} 回合开始，法力恢复至 ${state.player.mana}。');
      _emitFx(
        'turn',
        '第 ${state.turn} 回合',
        '你的法力已恢复，轮到你行动',
        Icons.hourglass_top,
        0xFF69CFC3,
      );
      _startTurnTimer();
    }
    isResolvingTurn = false;
    notifyListeners();
  }

  Future<void> _aiTurn(BattleState state) async {
    state.phase = 'main';
    _refreshSideForTurn(state.ai);
    if (state.turn > 1) {
      _refillMana(state.ai);
    } else {
      state.ai.mana = state.ai.maxMana;
    }
    _resolveTurnTriggers(state.ai, start: true);
    _processDeaths();
    _checkFinished();
    if (state.finished) return;
    if (state.ai.coinAvailable &&
        state.ai.hand.any(
          (card) => card.cost > state.ai.mana && card.cost <= state.ai.mana + 1,
        )) {
      state.ai.coinAvailable = false;
      state.ai.mana += 1;
      state.logs.insert(0, '敌方演算体使用幸运币，获得 1 点临时法力。');
      _emitFx(
        'coin',
        '敌方使用幸运币',
        '演算体获得 1 点临时法力',
        Icons.monetization_on,
        0xFFE7BD7A,
        amount: 1,
      );
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
    state.aiHeroPowerUsed = false;
    final aiPowerTarget = _aiHeroPowerTarget(state);
    final aiPowerTargetsHero =
        aiPowerTarget == null &&
        state.aiHeroPower.target == 'friendly-character' &&
        state.ai.heroHealth < state.ai.maxHeroHealth;
    if (!state.aiHeroPowerUsed &&
        _canResolveHeroPower(
          state.aiHeroPower,
          source: state.ai,
          enemy: state.player,
          target: aiPowerTarget,
          targetHero: aiPowerTargetsHero,
        ) &&
        _resolveHeroPower(
          state.aiHeroPower,
          source: state.ai,
          enemy: state.player,
          owner: 'ai',
          target: aiPowerTarget,
          targetHero: aiPowerTargetsHero,
        )) {
      _checkFinished();
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 1050));
    }
    final playable = [...state.ai.hand]
      ..sort((a, b) => a.cost.compareTo(b.cost));
    for (final card in playable) {
      if (state.finished || card.cost > state.ai.mana) continue;
      if (card.isUnit && state.ai.board.length >= 7) continue;
      final target = _aiTarget(card, state);
      if (!_validTarget(card, state.ai, state.player, target)) continue;
      _playCardForSide(
        card,
        source: state.ai,
        enemy: state.player,
        owner: 'ai',
        target: target,
      );
      if (state.phase == 'discover' &&
          state.discoverOwner == 'ai' &&
          state.discoverChoices.isNotEmpty) {
        chooseDiscover(state.discoverChoices.first);
      }
      if (state.phase == 'choose-one' &&
          state.chooseOneOwner == 'ai' &&
          state.chooseOneOptions.isNotEmpty) {
        chooseOne(0);
      }
      _checkFinished();
      notifyListeners();
      // Leave enough room for the client-side cast, card flight and impact
      // beats to finish before the next AI action starts.
      await Future<void>.delayed(const Duration(milliseconds: 1280));
    }
    if (state.finished) return;
    final attackers = [...state.ai.board];
    final taunts = state.player.board
        .where((unit) => unit.hasTaunt && !unit.stealthActive)
        .toList();
    for (final unit in attackers) {
      if (state.finished || !unit.canAttack || !state.ai.board.contains(unit)) {
        continue;
      }
      final visibleUnits = state.player.board
          .where((candidate) => !candidate.stealthActive)
          .toList();
      if (unit.rushOnly && visibleUnits.isEmpty) continue;
      final targetPool = taunts.isNotEmpty ? taunts : visibleUnits;
      final target = unit.rushOnly || taunts.isNotEmpty
          ? (targetPool.isEmpty
                ? null
                : targetPool[_random.nextInt(targetPool.length)])
          : null;
      _performAttack(unit, state.player, target);
      _checkFinished();
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 1380));
    }
    if (!state.finished &&
        state.ai.weapon != null &&
        !state.ai.heroHasAttacked &&
        state.ai.weapon!.durability > 0) {
      final taunts = state.player.board
          .where((unit) => unit.hasTaunt && !unit.stealthActive)
          .toList();
      final visible = state.player.board
          .where((unit) => !unit.stealthActive)
          .toList();
      final targetPool = taunts.isNotEmpty ? taunts : visible;
      final target = targetPool.isEmpty
          ? null
          : targetPool[_random.nextInt(targetPool.length)];
      _aiHeroAttack(state, target);
      _checkFinished();
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 1380));
    }
    _resolveTurnTriggers(state.ai, start: false);
    _clearTemporaryBuffs(state.ai);
    _settleFreezeAtEndOfTurn(state.ai);
    _processDeaths();
    _draw(state.ai);
    _checkFinished();
  }

  void _aiHeroAttack(BattleState state, BattleUnit? target) {
    final weapon = state.ai.weapon;
    if (weapon == null || weapon.durability <= 0) return;
    if (target == null) {
      _triggerSecrets(
        state.player,
        'opponent-attacks-hero',
        triggeringSide: state.ai,
      );
      if (state.ai.heroHealth <= 0) {
        _processDeaths();
        _checkFinished();
        return;
      }
    }
    final dealt = target == null
        ? _damageHero(state.player, weapon.attack)
        : _damageUnit(target, weapon.attack, combat: true);
    state.ai.heroHasAttacked = true;
    weapon.durability--;
    state.logs.insert(
      0,
      target == null
          ? '敌方英雄使用 ${weapon.card.name} 攻击核心，造成 $dealt 点伤害。'
          : '敌方英雄使用 ${weapon.card.name} 攻击 ${target.card.name}。',
    );
    _emitFx(
      'attack',
      '敌方英雄攻击',
      target == null ? '你的核心受到 $dealt 点伤害' : '英雄与 ${target.card.name} 交战',
      Icons.flash_on,
      0xFFE46D3F,
      sourceId: 'ai-hero',
      targetId: target?.instanceId ?? 'player-hero',
      amount: dealt,
    );
    if (weapon.durability <= 0) state.ai.weapon = null;
  }

  void _refreshSideForTurn(BattleSide side) {
    side.heroHasAttacked = false;
    side.cardsPlayedThisTurn = 0;
    for (final unit in side.board) {
      unit.attacksMade = 0;
      if (unit.frozenTurns > 0) {
        unit.attacksMade = unit.attackLimit;
        unit.hasAttacked = true;
        unit.summoningSick = false;
        unit.freezeBlocked = true;
      } else {
        unit.hasAttacked = false;
        unit.summoningSick = false;
        unit.rushOnly = false;
        unit.freezeBlocked = false;
      }
    }
  }

  /// Consume Freeze after the character has actually lost its next attack.
  /// A character frozen after attacking carries the lock into its next turn;
  /// a character frozen before it could attack thaws at this turn's end.
  void _settleFreezeAtEndOfTurn(BattleSide side) {
    for (final unit in side.board) {
      if (unit.frozenTurns <= 0) {
        unit.freezeBlocked = false;
        continue;
      }
      final missedCurrentTurnAttack =
          !unit.summoningSick && unit.attack > 0 && unit.attacksMade == 0;
      if (unit.freezeBlocked || missedCurrentTurnAttack) {
        unit.frozenTurns = max(0, unit.frozenTurns - 1);
        unit.freezeBlocked = false;
      }
    }
  }

  void _resolveTurnTriggers(BattleSide side, {required bool start}) {
    final state = battle;
    if (state == null) return;
    final enemy = identical(side, state.player) ? state.ai : state.player;
    for (final unit in [...side.board]) {
      if (!side.board.contains(unit) || unit.silenced) continue;
      final effects = start ? unit.card.onTurnStart : unit.card.onTurnEnd;
      if (effects.isEmpty) continue;
      _resolveEffects(
        effects,
        source: side,
        enemy: enemy,
        target: unit,
        sourceName: '${unit.card.name} · ${start ? '回合开始' : '回合结束'}',
        sourceCard: unit.card,
      );
      if (state.finished) break;
    }
  }

  void _clearTemporaryBuffs(BattleSide side) {
    for (final unit in side.board) {
      if (unit.temporaryAttackBonus != 0) {
        unit.attack -= unit.temporaryAttackBonus;
        unit.temporaryAttackBonus = 0;
      }
      if (unit.temporaryHealthBonus != 0) {
        unit.maxHealth -= unit.temporaryHealthBonus;
        unit.health = min(unit.health, unit.maxHealth);
        unit.temporaryHealthBonus = 0;
      }
    }
  }

  void _refillMana(BattleSide side) {
    side.maxMana = min(10, side.maxMana + 1);
    final locked = min(side.maxMana, side.overloadLocked);
    side.overloadLocked = 0;
    side.mana = side.maxMana - locked;
    if (locked > 0) {
      stateLog(
        identical(battle?.player, side) ? '过载' : '敌方过载',
        '下回合锁定 $locked 个法力水晶。',
      );
      _emitFx(
        'overload',
        '过载锁定',
        '本回合可用法力减少 $locked',
        Icons.lock_clock,
        0xFFE46D3F,
        amount: locked,
      );
    }
  }

  BattleUnit? _aiTarget(CardDefinition card, BattleState state) {
    final type = card.target ?? '';
    if (type.startsWith('friendly')) {
      if (type.contains('unit')) {
        return state.ai.board.isEmpty ? null : state.ai.board.first;
      }
      return null;
    }
    if (type.startsWith('enemy') && type.contains('unit')) {
      return state.player.board.isEmpty ? null : state.player.board.first;
    }
    return null;
  }

  BattleUnit? _aiHeroPowerTarget(BattleState state) {
    switch (state.aiHeroPower.target) {
      case 'enemy-unit':
        final visible =
            state.player.board
                .where((unit) => !unit.stealthActive && unit.health > 0)
                .toList()
              ..sort((left, right) => left.health.compareTo(right.health));
        return visible.isEmpty ? null : visible.first;
      case 'friendly-unit':
      case 'friendly-character':
        final damaged =
            state.ai.board
                .where(
                  (unit) => unit.health > 0 && unit.health < unit.maxHealth,
                )
                .toList()
              ..sort(
                (left, right) => (left.maxHealth - left.health).compareTo(
                  right.maxHealth - right.health,
                ),
              );
        return damaged.isEmpty ? null : damaged.first;
      default:
        return null;
    }
  }

  void _checkFinished() {
    final state = battle;
    if (state == null || state.finished) return;
    if (state.player.heroHealth <= 0 || state.ai.heroHealth <= 0) {
      state.finished = true;
      _turnTimer?.cancel();
      state.winner = state.ai.heroHealth <= 0 ? 'player' : 'ai';
      if (state.winner == 'player') {
        wins++;
        gold += 60;
      } else {
        losses++;
        gold += 20;
      }
      matchesPlayed++;
      _prefs?.setInt('wins', wins);
      _prefs?.setInt('losses', losses);
      _prefs?.setInt('matches', matchesPlayed);
      _prefs?.setInt('gold', gold);
      final victory = state.winner == 'player';
      state.logs.insert(0, victory ? '演算胜利，获得 60 金币。' : '演算结束，获得 20 金币。');
      _emitFx(
        victory ? 'victory' : 'defeat',
        victory ? '演算胜利' : '演算结束',
        victory ? '战报已归档，获得 60 金币' : '保留战术日志，获得 20 金币',
        victory ? Icons.emoji_events : Icons.close,
        victory ? 0xFFE7BD7A : 0xFFE46D3F,
      );
    }
  }

  void stateLog(String title, [String? description]) {
    final state = battle;
    if (state == null) return;
    state.logs.insert(0, description == null ? title : '$title$description');
    if (state.logs.length > 20) state.logs.removeLast();
  }

  void _emitFx(
    String kind,
    String title,
    String subtitle,
    IconData icon,
    int color, {
    String? sourceId,
    String? targetId,
    int? amount,
  }) {
    final state = battle;
    if (state == null) return;
    state.fxSequence++;
    state.fx = BattleFxEvent(
      kind: kind,
      title: title,
      subtitle: subtitle,
      icon: icon.codePoint,
      color: color,
      sequence: state.fxSequence,
      sourceId: sourceId,
      targetId: targetId,
      amount: amount,
    );
  }

  int? _cardEffectAmount(CardDefinition card) {
    for (final effect in [...card.effect, ...card.onPlay]) {
      final value = effect['amount'];
      if (value is num && value > 0) return value.toInt();
    }
    return null;
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    super.dispose();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:astra_protocol/data/catalog.dart';
import 'package:astra_protocol/data/deck_code.dart';
import 'package:astra_protocol/data/deck_recipes.dart';
import 'package:astra_protocol/data/deck_share.dart';
import 'package:astra_protocol/data/formats.dart';
import 'package:astra_protocol/game/game_controller.dart';
import 'package:astra_protocol/main.dart';
import 'package:astra_protocol/models/card_definition.dart';
import 'package:astra_protocol/models/local_saved_deck.dart';
import 'package:astra_protocol/network/multiplayer_client.dart';
import 'package:astra_protocol/network/online_battle_controller.dart';

void main() {
  test(
    'mobile catalog includes the complete Hearthstone-style rule fields',
    () async {
      final catalog = await loadCatalog();
      expect(catalog, hasLength(1000));
      expect(catalog.map((card) => card.faction).toSet(), hasLength(20));
      expect(cardSetDefinitions, hasLength(4));
      expect(rankedFormatCardCount(catalog, RankedFormat.standard), 800);
      expect(rankedFormatCardCount(catalog, RankedFormat.wild), 1000);
      expect(
        catalog.where((card) => card.setId == 'pegasus-2024'),
        hasLength(200),
      );
      expect(factionOrder, hasLength(20));
      expect(catalog.where((card) => card.type == 'weapon'), hasLength(20));
      expect(catalog.where((card) => card.type == 'hero'), hasLength(1));
      expect(
        catalog.singleWhere((card) => card.type == 'hero').heroCard,
        isNotNull,
      );
      expect(
        catalog.where((card) => card.keywords.contains('secret')),
        isNotEmpty,
      );
      expect(
        catalog.where((card) => card.keywords.contains('discover')),
        hasLength(7),
      );
      expect(
        catalog.where((card) => card.keywords.contains('choose-one')),
        hasLength(1),
      );
      expect(catalog.any((card) => card.overload > 0), isTrue);
      expect(catalog.any((card) => card.tradeable), isTrue);
      expect(catalog.where((card) => card.preparable), hasLength(22));
      expect(catalog.where((card) => card.bribe), hasLength(20));
      expect(catalog.where((card) => card.disguised), hasLength(20));
      expect(catalog.where((card) => card.hasShatter), hasLength(5));
      expect(catalog.where((card) => card.hasHerald), hasLength(12));
      expect(catalog.where((card) => card.hasColossal), hasLength(6));
      final typedUnits = catalog
          .where((card) => card.isUnit && card.minionTypes.isNotEmpty)
          .toList();
      expect(typedUnits.length, greaterThanOrEqualTo(100));
      expect(
        typedUnits.expand((card) => card.minionTypes).toSet(),
        containsAll(minionTypeOrder),
      );
      expect(
        catalog
            .singleWhere((card) => card.id == 'neutral-clockwork-beetle')
            .minionTypes,
        ['beast', 'construct'],
      );
      expect(
        hasMinionType(
          catalog.singleWhere((card) => card.id == 'void-echo-mimic'),
          'dragon',
        ),
        isTrue,
      );
      expect(
        catalog
            .where((card) => card.hasShatter)
            .every(
              (card) =>
                  card.setId == 'raptor-2025' &&
                  card.type == 'spell' &&
                  card.keywords.contains('shatter') &&
                  card.shatter?['left'] is List &&
                  card.shatter?['right'] is List,
            ),
        isTrue,
      );
      expect(
        catalog
            .where((card) => card.disguised)
            .every(
              (card) =>
                  card.setId == 'scarab-2026' &&
                  card.isUnit &&
                  card.cost == 3 &&
                  card.keywords.contains('disguised') &&
                  card.onTurnEnd.any(
                    (effect) => effect['kind'] == 'damage-friendly-hero',
                  ),
            ),
        isTrue,
      );
      expect(
        catalog
            .where((card) => card.preparable)
            .every(
              (card) =>
                  card.setId == 'scarab-2026' &&
                  card.cost == 8 &&
                  card.keywords.contains('prepare'),
            ),
        isTrue,
      );
      expect(catalog.any((card) => card.onTurnStart.isNotEmpty), isTrue);
      expect(catalog.any((card) => card.onSpellPlayed.isNotEmpty), isTrue);
      expect(
        catalog
            .singleWhere((card) => card.id == 'sun-zenith-golem')
            .onDeath
            .where((effect) => effect['kind'] == 'summon'),
        hasLength(1),
      );
      expect(
        catalog
            .singleWhere((card) => card.id == 'void-ink-storm')
            .effect
            .where((effect) => effect['kind'] == 'random-enemy-freeze'),
        hasLength(1),
      );
      expect(
        catalog
            .singleWhere((card) => card.id == 'gloomwood-season-spell-03')
            .effect
            .single['kind'],
        'resurrect-friendly-unit',
      );
      expect(
        catalog
            .singleWhere((card) => card.id == 'dusk-season-spell-10')
            .effect
            .single['kind'],
        'return-unit-to-hand',
      );
      expect(
        catalog
            .singleWhere((card) => card.id == 'void-blackwake-torpedo')
            .effect
            .any((effect) => effect['kind'] == 'discard-random'),
        isTrue,
      );
      expect(
        catalog
            .singleWhere((card) => card.id == 'void-season-spell-02')
            .onDiscard
            .single['kind'],
        'random-enemy-damage',
      );
      expect(
        catalog
            .singleWhere((card) => card.id == 'void-season-13')
            .onPlay
            .single['kind'],
        'recover-discarded',
      );
      expect(generatedBattleCards, hasLength(18));
      expect(
        generatedBattleCards
            .where(
              (card) =>
                  card.id.endsWith('-appendage') ||
                  card.id.endsWith('-appendage-soldier'),
            )
            .length,
        12,
      );
    },
  );

  test('card definition parses the catalog schema', () {
    final card = CardDefinition.fromJson({
      'id': 'sun-test',
      'name': '曙光测试',
      'description': '测试卡牌',
      'faction': '曜光',
      'type': 'unit',
      'cost': 2,
      'rarity': '稀有',
      'set': 'scarab-2026',
      'attack': 3,
      'health': 4,
      'preparable': true,
      'bribe': true,
      'disguised': true,
      'keywords': ['护盾'],
      'traits': ['晨辉'],
      'minionTypes': ['beast', 'construct'],
    });

    expect(card.name, '曙光测试');
    expect(card.isUnit, isTrue);
    expect(card.attack, 3);
    expect(card.keywords, contains('护盾'));
    expect(card.setId, 'scarab-2026');
    expect(card.preparable, isTrue);
    expect(card.bribe, isTrue);
    expect(card.disguised, isTrue);
    expect(card.minionTypes, ['beast', 'construct']);
  });

  test('multiplayer events parse relay payloads', () {
    final event = MultiplayerEvent.fromData(
      '{"type":"action","room":"A7KQ","playerId":"p-2",'
      '"peerName":"星图旅者","action":"ready",'
      '"payload":{"turn":3}}',
    );

    expect(event.type, 'action');
    expect(event.roomCode, 'A7KQ');
    expect(event.peerName, '星图旅者');
    expect(event.payload['turn'], 3);
  });

  test('opening hand supports mulligan and temporary Coin mana', () {
    CardDefinition card(String id, int cost, String rarity) => CardDefinition(
      id: id,
      name: id,
      description: '测试卡牌',
      faction: '曜光',
      type: 'unit',
      cost: cost,
      rarity: rarity,
      attack: 1,
      health: 1,
    );

    final cheap = card('cheap', 1, '普通');
    final expensive = card('expensive', 8, '史诗');
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [cheap, expensive]
      ..deckIds.addAll(List.filled(30, cheap.id));

    controller.startBattle();
    final state = controller.battle!;
    expect(state.phase, 'mulligan');
    state.player.hand
      ..clear()
      ..addAll([expensive, cheap, cheap]);
    state.player.deck
      ..clear()
      ..addAll(List.filled(10, cheap));
    controller.toggleMulligan(0);
    expect(state.mulliganSelected, contains(0));
    controller.confirmMulligan();
    expect(state.phase, 'main');
    expect(state.mulliganDone, isTrue);
    expect(state.player.hand.length, 4);
    expect(state.player.mana, 1);

    state.player.coinAvailable = true;
    expect(controller.useCoin(), isTrue);
    expect(state.player.coinAvailable, isFalse);
    expect(state.player.mana, 2);
    controller.dispose();
  });

  test('mobile Prepare discounts only the selected hand instance once', () {
    final filler = CardDefinition(
      id: 'prepare-filler',
      name: '预备占位牌',
      description: '测试手牌槽位对齐。',
      faction: '烬火',
      type: 'spell',
      cost: 1,
      rarity: '普通',
    );
    final preparable = CardDefinition(
      id: 'prepare-eight-cost',
      name: '预备八费牌',
      description: '预备。',
      faction: '烬火',
      type: 'spell',
      cost: 8,
      rarity: '史诗',
      preparable: true,
      keywords: const ['prepare'],
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [filler, preparable]
      ..deckIds.addAll(List.filled(30, filler.id));

    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    state.player.hand
      ..clear()
      ..addAll([preparable, preparable]);
    state.player.handCostReductions.clear();
    state.player.mana = 3;

    expect(controller.prepareCard(preparable, handIndex: 1), isTrue);
    expect(state.player.mana, 0);
    expect(state.player.handCostReductions, [0, 4]);
    expect(controller.playerHandCost(0), 8);
    expect(controller.playerHandCost(1), 4);
    expect(controller.prepareCard(preparable, handIndex: 1), isFalse);

    state.player.mana = 4;
    expect(controller.playCard(preparable, handIndex: 1), isTrue);
    expect(state.player.mana, 0);
    expect(state.player.hand, [preparable]);
    expect(state.player.handCostReductions, [0]);
    controller.dispose();
  });

  test(
    'mobile AI prepares an unaffordable high-cost card before passing',
    () async {
      final filler = CardDefinition(
        id: 'prepare-ai-filler',
        name: 'AI 预备占位牌',
        description: '测试 AI 预备。',
        faction: '烬火',
        type: 'spell',
        cost: 1,
        rarity: '普通',
      );
      final preparable = CardDefinition(
        id: 'prepare-ai-eight-cost',
        name: 'AI 预备八费牌',
        description: '预备。',
        faction: '烬火',
        type: 'spell',
        cost: 8,
        rarity: '史诗',
        preparable: true,
        keywords: const ['prepare'],
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = [filler, preparable]
        ..deckIds.addAll(List.filled(30, filler.id));

      controller.startBattle();
      await controller.confirmMulligan();
      final state = controller.battle!;
      state.ai.hand
        ..clear()
        ..add(preparable);
      state.ai.handCostReductions.clear();
      state.ai.deck.clear();

      await controller.endTurn();
      expect(state.ai.handCostReductions, [2]);
      expect(state.logs.any((log) => log.contains('敌方完成预备')), isTrue);
      controller.dispose();
    },
  );

  test(
    'mobile discard history triggers discarded cards and recovers printed copies',
    () async {
      final filler = CardDefinition(
        id: 'discard-filler',
        name: '弃牌占位单位',
        description: '测试牌库。',
        faction: '幽潮',
        type: 'unit',
        cost: 9,
        rarity: '普通',
        attack: 0,
        health: 1,
      );
      final echo = CardDefinition(
        id: 'discard-echo',
        name: '弃牌回响',
        description: '使用或弃掉时造成伤害。',
        faction: '幽潮',
        type: 'spell',
        cost: 1,
        rarity: '普通',
        effect: const [
          {'kind': 'random-enemy-damage', 'amount': 2},
        ],
        onDiscard: const [
          {'kind': 'random-enemy-damage', 'amount': 2},
        ],
      );
      final discard = CardDefinition(
        id: 'discard-source',
        name: '弃牌鱼雷',
        description: '造成伤害，随机弃一张牌。',
        faction: '幽潮',
        type: 'spell',
        cost: 1,
        rarity: '稀有',
        target: 'enemy-character',
        effect: const [
          {'kind': 'damage', 'amount': 3},
          {'kind': 'discard-random', 'count': 1},
        ],
      );
      final recover = CardDefinition(
        id: 'discard-recover',
        name: '弃牌拾荒者',
        description: '战吼：找回弃牌。',
        faction: '幽潮',
        type: 'unit',
        cost: 1,
        rarity: '稀有',
        attack: 2,
        health: 2,
        onPlay: const [
          {'kind': 'recover-discarded', 'count': 2},
        ],
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = [filler, echo, discard, recover]
        ..deckIds.addAll(List.filled(30, filler.id));
      controller.startBattle();
      await controller.confirmMulligan();
      final state = controller.battle!;
      state.player.hand
        ..clear()
        ..addAll([discard, echo]);
      state.player.handCostReductions
        ..clear()
        ..addAll([0, 0]);
      state.player.handFragments
        ..clear()
        ..addAll([null, null]);
      state.player.mana = 10;
      state.ai.board.clear();
      final beforeHealth = state.ai.heroHealth;

      expect(
        controller.playCard(discard, handIndex: 0, targetHero: true),
        isTrue,
      );
      expect(state.ai.heroHealth, beforeHealth - 5);
      expect(state.player.hand, isEmpty);
      expect(state.player.discardHistory.single.cardId, echo.id);

      state.player.hand
        ..clear()
        ..add(recover);
      state.player.handCostReductions
        ..clear()
        ..add(0);
      state.player.handFragments
        ..clear()
        ..add(null);
      state.player.mana = 1;
      expect(controller.playCard(recover, handIndex: 0), isTrue);
      expect(state.player.hand.single, echo);
      expect(state.player.handCostReductions, [0]);
      expect(state.player.discardHistory, hasLength(1));
      controller.dispose();
    },
  );

  test(
    'mobile Bribe resolves its main effect and draws for the opponent',
    () async {
      final filler = CardDefinition(
        id: 'bribe-draw-filler',
        name: '贿赂收益牌',
        description: '测试对手抽牌。',
        faction: '幽潮',
        type: 'unit',
        cost: 1,
        rarity: '普通',
        attack: 1,
        health: 1,
      );
      final bribe = CardDefinition(
        id: 'mobile-bribe',
        name: '移动端贿赂',
        description: '贿赂：对手抽 1 张牌。造成 6 点伤害。',
        faction: '烬火',
        type: 'spell',
        cost: 6,
        rarity: '史诗',
        bribe: true,
        keywords: const ['bribe'],
        target: 'enemy-character',
        effect: const [
          {'kind': 'damage', 'amount': 6},
          {'kind': 'draw-opponent', 'count': 1},
        ],
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = [filler, bribe]
        ..deckIds.addAll(List.filled(30, filler.id));

      controller.startBattle();
      await controller.confirmMulligan();
      final state = controller.battle!;
      state.player.hand
        ..clear()
        ..add(bribe);
      state.player.handCostReductions.clear();
      state.player.mana = 6;
      state.ai.heroHealth = 30;
      state.ai.hand.clear();
      state.ai.handCostReductions.clear();
      state.ai.deck
        ..clear()
        ..add(filler);

      expect(controller.playCard(bribe, targetHero: true), isTrue);
      expect(state.ai.heroHealth, 24);
      expect(state.ai.hand, [filler]);
      expect(state.logs.any((log) => log.contains('贿赂收益')), isTrue);
      controller.dispose();
    },
  );

  test('mobile minion types drive buffs and targeted deck searches', () async {
    const plain = CardDefinition(
      id: 'type-plain',
      name: '无类型单位',
      description: '不响应类型联动。',
      faction: '中立',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 1,
      health: 1,
    );
    const construct = CardDefinition(
      id: 'type-construct',
      name: '测试构装',
      description: '构装单位。',
      faction: '中立',
      type: 'unit',
      cost: 6,
      rarity: '普通',
      attack: 3,
      health: 4,
      minionTypes: ['construct'],
    );
    const allType = CardDefinition(
      id: 'type-all',
      name: '测试万象',
      description: '视为所有类型。',
      faction: '中立',
      type: 'unit',
      cost: 2,
      rarity: '史诗',
      attack: 2,
      health: 2,
      minionTypes: ['all'],
    );
    const handler = CardDefinition(
      id: 'type-handler',
      name: '类型驯养师',
      description: '使其他友方构装获得 +1/+1。',
      faction: '中立',
      type: 'unit',
      cost: 4,
      rarity: '史诗',
      attack: 4,
      health: 5,
      minionTypes: ['construct'],
      onPlay: [
        {
          'kind': 'buff-friendly-minion-type',
          'minionType': 'construct',
          'attack': 1,
          'health': 1,
          'excludeSource': true,
        },
      ],
    );
    const appraiser = CardDefinition(
      id: 'type-appraiser',
      name: '类型估价师',
      description: '从牌库抽一张构装。',
      faction: '中立',
      type: 'unit',
      cost: 2,
      rarity: '稀有',
      attack: 2,
      health: 2,
      onPlay: [
        {'kind': 'draw-minion-type', 'minionType': 'construct', 'count': 1},
      ],
    );
    BattleUnit deployed(String id, CardDefinition card) => BattleUnit(
      instanceId: id,
      card: card,
      owner: 'player',
      attack: card.attack ?? 0,
      health: card.health ?? 1,
      maxHealth: card.health ?? 1,
    );

    final controller = GameController(startingPlayer: 'player')
      ..catalog = [plain, construct, allType, handler, appraiser]
      ..deckIds.addAll(List.filled(30, plain.id));
    controller.startBattle();
    await controller.confirmMulligan();
    final state = controller.battle!;
    state.player.board
      ..clear()
      ..addAll([
        deployed('typed-construct', construct),
        deployed('typed-all', allType),
        deployed('typed-plain', plain),
      ]);
    state.player.hand
      ..clear()
      ..add(handler);
    state.player.handCostReductions
      ..clear()
      ..add(0);
    state.player.handFragments
      ..clear()
      ..add(null);
    state.player.mana = 4;

    expect(controller.playCard(handler, handIndex: 0), isTrue);
    expect(
      state.player.board.map(
        (unit) => [unit.card.id, unit.attack, unit.maxHealth],
      ),
      [
        [construct.id, 4, 5],
        [allType.id, 3, 3],
        [plain.id, 1, 1],
        [handler.id, 4, 5],
      ],
    );

    state.player.hand
      ..clear()
      ..add(appraiser);
    state.player.handCostReductions
      ..clear()
      ..add(0);
    state.player.handFragments
      ..clear()
      ..add(null);
    state.player.deck
      ..clear()
      ..addAll([plain, construct]);
    state.player.deckCostOverrides
      ..clear()
      ..addAll([null, 1]);
    state.player.mana = 2;
    expect(controller.playCard(appraiser, handIndex: 0), isTrue);
    expect(state.player.deck, [plain]);
    expect(state.player.deckCostOverrides, [null]);
    expect(state.player.hand.single, construct);
    expect(state.player.handCostReductions.single, 5);

    state.player.hand
      ..clear()
      ..add(appraiser);
    state.player.handCostReductions
      ..clear()
      ..add(0);
    state.player.handFragments
      ..clear()
      ..add(null);
    state.player.deck
      ..clear()
      ..add(plain);
    state.player.deckCostOverrides
      ..clear()
      ..add(null);
    state.player.fatigue = 0;
    state.player.mana = 2;
    expect(controller.playCard(appraiser, handIndex: 0), isTrue);
    expect(state.player.deck, [plain]);
    expect(state.player.hand, isEmpty);
    expect(state.player.fatigue, 0);
    controller.dispose();
  });

  test(
    'mobile spell schools support searches, payoffs and turn history',
    () async {
      const filler = CardDefinition(
        id: 'school-filler',
        name: '派系占位单位',
        description: '测试派系历史。',
        faction: '中立',
        type: 'unit',
        cost: 1,
        rarity: '普通',
        attack: 1,
        health: 1,
      );
      const astralTarget = CardDefinition(
        id: 'school-astral-target',
        name: '星术目标',
        description: '可被派系检索。',
        faction: '中立',
        type: 'spell',
        cost: 1,
        rarity: '普通',
        school: 'astral',
      );
      const tacticalMap = CardDefinition(
        id: 'school-tactical-map',
        name: '派系战术图',
        description: '从牌库抽一张星术战术。',
        faction: '中立',
        type: 'spell',
        cost: 2,
        rarity: '普通',
        school: 'construct',
        effect: [
          {'kind': 'draw-spell-school', 'school': 'astral', 'count': 1},
        ],
      );
      const resonance = CardDefinition(
        id: 'school-resonance',
        name: '双派系共鸣',
        description: '完成施放两个不同派系后抽两张牌。',
        faction: '中立',
        type: 'spell',
        cost: 5,
        rarity: '稀有',
        school: 'astral',
        effect: [
          {
            'kind': 'spell-school-payoff',
            'window': 'this-turn',
            'minimumDistinct': 2,
            'effects': [
              {'kind': 'draw', 'count': 2},
            ],
          },
        ],
      );
      const historian = CardDefinition(
        id: 'school-historian',
        name: '派系史官',
        description: '上一回合施放两个不同派系时抽两张牌。',
        faction: '中立',
        type: 'unit',
        cost: 2,
        rarity: '稀有',
        attack: 2,
        health: 2,
        onPlay: [
          {
            'kind': 'spell-school-payoff',
            'window': 'last-turn',
            'minimumDistinct': 2,
            'effects': [
              {'kind': 'draw', 'count': 2},
            ],
          },
        ],
      );

      final controller = GameController(startingPlayer: 'player')
        ..catalog = [filler, astralTarget, tacticalMap, resonance, historian]
        ..deckIds.addAll(List.filled(30, filler.id));
      controller.startBattle();
      await controller.confirmMulligan();
      final state = controller.battle!;
      state.player.hand
        ..clear()
        ..addAll([tacticalMap, resonance]);
      state.player.handCostReductions
        ..clear()
        ..addAll([0, 0]);
      state.player.handFragments
        ..clear()
        ..addAll([null, null]);
      state.player.deck
        ..clear()
        ..addAll([filler, filler, astralTarget]);
      state.player.deckCostOverrides
        ..clear()
        ..addAll([null, 1, 0]);
      state.player.mana = 10;

      expect(controller.playCard(tacticalMap, handIndex: 0), isTrue);
      expect(state.player.hand.last, astralTarget);
      expect(state.player.handCostReductions.last, 1);
      expect(state.player.spellSchoolsPlayedThisTurn, ['construct']);
      expect(controller.playCard(resonance, handIndex: 0), isTrue);
      expect(state.player.spellSchoolsPlayedThisTurn, ['construct', 'astral']);
      expect(state.player.deck, isEmpty);
      expect(state.player.hand.length, 3);

      state.ai.hand.clear();
      state.ai.deck
        ..clear()
        ..add(filler);
      state.ai.deckCostOverrides
        ..clear()
        ..add(null);
      await controller.endTurn();
      expect(state.player.spellSchoolsPlayedThisTurn, isEmpty);
      expect(state.player.spellSchoolsPlayedLastTurn, ['construct', 'astral']);

      state.player.hand
        ..clear()
        ..add(historian);
      state.player.handCostReductions
        ..clear()
        ..add(0);
      state.player.handFragments
        ..clear()
        ..add(null);
      state.player.deck
        ..clear()
        ..addAll([filler, filler]);
      state.player.deckCostOverrides
        ..clear()
        ..addAll([null, null]);
      state.player.mana = 2;
      expect(controller.playCard(historian, handIndex: 0), isTrue);
      expect(state.player.deck, isEmpty);
      expect(state.player.hand, [filler, filler]);
      controller.dispose();
    },
  );

  test(
    'mobile death history supports fresh resurrection and buff-clearing bounce',
    () async {
      final filler = CardDefinition(
        id: 'zone-filler',
        name: '区域占位牌',
        description: '测试牌库。',
        faction: '曜光',
        type: 'unit',
        cost: 9,
        rarity: '普通',
        attack: 0,
        health: 1,
      );
      final victim = CardDefinition(
        id: 'zone-victim',
        name: '墓地测试单位',
        description: '用于验证区域移动。',
        faction: '曜光',
        type: 'unit',
        cost: 2,
        rarity: '普通',
        attack: 2,
        health: 2,
        minionTypes: const ['construct'],
      );
      final settleDeaths = CardDefinition(
        id: 'zone-settle',
        name: '结算死亡',
        description: '触发死亡结算。',
        faction: '曜光',
        type: 'spell',
        cost: 0,
        rarity: '普通',
        effect: const [
          {'kind': 'armor', 'amount': 0},
        ],
      );
      final resurrect = CardDefinition(
        id: 'zone-resurrect',
        name: '墓地重构',
        description: '复活最近死亡的友方单位。',
        faction: '曜光',
        type: 'spell',
        cost: 0,
        rarity: '稀有',
        effect: const [
          {'kind': 'resurrect-friendly-unit', 'count': 1},
        ],
      );
      final bounce = CardDefinition(
        id: 'zone-bounce',
        name: '战场撤回',
        description: '使一个敌方单位返回手牌。',
        faction: '曜光',
        type: 'spell',
        cost: 0,
        rarity: '稀有',
        target: 'enemy-unit',
        effect: const [
          {'kind': 'return-unit-to-hand'},
        ],
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = [filler, victim, settleDeaths, resurrect, bounce]
        ..deckIds.addAll(List.filled(30, filler.id));
      controller.startBattle();
      await controller.confirmMulligan();
      final state = controller.battle!;
      state.player.board.add(
        BattleUnit(
          instanceId: 'dead-zone-unit',
          card: victim,
          owner: 'player',
          attack: 8,
          health: 0,
          maxHealth: 9,
          permanentAttackBonus: 6,
          permanentHealthBonus: 7,
        ),
      );
      state.player.hand
        ..clear()
        ..addAll([settleDeaths, resurrect, bounce]);
      state.player.handCostReductions
        ..clear()
        ..addAll([0, 0, 0]);
      state.player.handFragments
        ..clear()
        ..addAll([null, null, null]);
      state.player.mana = 10;

      expect(controller.playCard(settleDeaths, handIndex: 0), isTrue);
      expect(state.player.deathHistory.single.cardId, victim.id);
      expect(state.player.board, isEmpty);
      expect(controller.playCard(resurrect, handIndex: 0), isTrue);
      expect(state.player.deathHistory, hasLength(1));
      expect(state.player.board.single.attack, 2);
      expect(state.player.board.single.health, 2);
      expect(state.player.board.single.maxHealth, 2);

      state.ai.hand.clear();
      state.ai.handCostReductions.clear();
      state.ai.handFragments.clear();
      final bounced = BattleUnit(
        instanceId: 'bounce-zone-unit',
        card: victim,
        owner: 'ai',
        attack: 9,
        health: 8,
        maxHealth: 8,
        temporaryAttackBonus: 7,
        temporaryHealthBonus: 6,
      );
      state.ai.board.add(bounced);
      expect(
        controller.playCard(bounce, handIndex: 0, target: bounced),
        isTrue,
      );
      expect(state.ai.board, isEmpty);
      expect(state.ai.hand.single, victim);
      expect(state.ai.handCostReductions, [0]);
      expect(state.ai.deathHistory, isEmpty);

      final generated = generatedBattleCards.singleWhere(
        (card) => card.id == 'storm-season-08-appendage-soldier',
      );
      state.player.hand
        ..clear()
        ..addAll([generated, settleDeaths, resurrect]);
      state.player.handCostReductions
        ..clear()
        ..addAll([0, 0, 0]);
      state.player.handFragments
        ..clear()
        ..addAll([null, null, null]);
      state.player.mana = 10;
      state.player.armor = 0;
      expect(controller.playCard(generated, handIndex: 0), isTrue);
      expect(state.player.armor, 1);
      final generatedUnit = state.player.board.last;
      expect(generatedUnit.card.id, generated.id);
      generatedUnit
        ..attack = 9
        ..health = 0
        ..maxHealth = 9;
      expect(controller.playCard(settleDeaths, handIndex: 0), isTrue);
      expect(state.player.deathHistory.last.cardId, generated.id);
      expect(controller.playCard(resurrect, handIndex: 0), isTrue);
      expect(state.player.board.last.card.id, generated.id);
      expect(state.player.board.last.attack, 2);
      expect(state.player.board.last.health, 4);
      controller.dispose();
    },
  );

  test(
    'mobile Disguised deploys under the recipient and damages that controller',
    () async {
      final filler = CardDefinition(
        id: 'disguised-filler',
        name: '伪装占位牌',
        description: '测试牌库与战场容量。',
        faction: '曜光',
        type: 'unit',
        cost: 9,
        rarity: '普通',
        attack: 0,
        health: 1,
      );
      final disguised = CardDefinition(
        id: 'mobile-disguised',
        name: '移动端伪装者',
        description: '伪装。回合结束：对其控制者的核心造成 1 点伤害。',
        faction: '曜光',
        type: 'unit',
        cost: 1,
        rarity: '史诗',
        attack: 0,
        health: 4,
        disguised: true,
        keywords: const ['disguised', 'end-of-turn'],
        onTurnEnd: const [
          {'kind': 'damage-friendly-hero', 'amount': 1},
        ],
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = [filler, disguised]
        ..deckIds.addAll(List.filled(30, filler.id));

      controller.startBattle();
      await controller.confirmMulligan();
      final state = controller.battle!;
      state.player.hand
        ..clear()
        ..add(disguised);
      state.player.handCostReductions
        ..clear()
        ..add(0);
      state.player.mana = 1;
      state.ai.deck
        ..clear()
        ..addAll(List.filled(3, filler));

      expect(
        controller.playCard(disguised, handIndex: 0, placement: 'enemy'),
        isTrue,
      );
      expect(state.player.board, isEmpty);
      expect(state.ai.board.single.card.id, disguised.id);
      expect(state.ai.board.single.owner, 'ai');
      expect(state.ai.heroHealth, 30);

      await controller.endTurn();
      expect(state.ai.heroHealth, 29);
      expect(state.player.heroHealth, 30);
      controller.dispose();
    },
  );

  test('mobile AI uses Disguised to occupy the opponent final slot', () async {
    final filler = CardDefinition(
      id: 'ai-disguised-filler',
      name: 'AI 伪装占位牌',
      description: '测试 AI 敌方落点。',
      faction: '曜光',
      type: 'unit',
      cost: 9,
      rarity: '普通',
      attack: 0,
      health: 1,
    );
    final disguised = CardDefinition(
      id: 'ai-mobile-disguised',
      name: 'AI 移动端伪装者',
      description: '伪装。',
      faction: '曜光',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 0,
      health: 2,
      disguised: true,
      keywords: const ['disguised'],
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [filler, disguised]
      ..deckIds.addAll(List.filled(30, filler.id));
    controller.startBattle();
    await controller.confirmMulligan();
    final state = controller.battle!;
    state.player.board.addAll(
      List.generate(
        6,
        (index) => BattleUnit(
          instanceId: 'ai-placement-$index',
          card: filler,
          owner: 'player',
          attack: 0,
          health: 1,
          maxHealth: 1,
        ),
      ),
    );
    state.ai.hand
      ..clear()
      ..add(disguised);
    state.ai.handCostReductions
      ..clear()
      ..add(0);
    state.ai.deck
      ..clear()
      ..add(filler);

    await controller.endTurn();

    expect(state.player.board, hasLength(7));
    expect(state.player.board.last.card.id, disguised.id);
    expect(state.player.board.last.owner, 'player');
    expect(state.ai.board, isEmpty);
    controller.dispose();
  });

  test(
    'mobile Shatter splits to both hand edges and reassembles after the bridge card',
    () async {
      final catalog = await loadCatalog();
      final shatter = catalog.singleWhere(
        (card) => card.id == 'ember-cinder-dispatch',
      );
      final filler = catalog.singleWhere((card) => card.id == 'sun-dawn-scout');
      final controller = GameController(startingPlayer: 'player')
        ..catalog = catalog
        ..deckIds.addAll(List.filled(30, filler.id));
      controller.startBattle();
      await controller.confirmMulligan();
      final state = controller.battle!;
      state.player.hand
        ..clear()
        ..add(filler);
      state.player.handCostReductions
        ..clear()
        ..add(0);
      state.player.handFragments
        ..clear()
        ..add(null);
      state.player.deck
        ..clear()
        ..add(filler);
      state.phase = 'discover';
      state.discoverOwner = 'player';
      state.discoverChoices = [shatter.id];

      expect(controller.chooseDiscover(shatter.id), isTrue);
      expect(state.player.hand.map((card) => card.id), [
        shatter.id,
        filler.id,
        shatter.id,
      ]);
      expect(state.player.hand.first.name, contains('左片'));
      expect(state.player.hand.last.name, contains('右片'));
      expect(state.player.handFragments.first?.piece, 'left');
      expect(state.player.handFragments.last?.piece, 'right');
      expect(
        state.player.handFragments.first?.groupId,
        state.player.handFragments.last?.groupId,
      );

      state.player.mana = 3;
      expect(controller.playCard(filler, handIndex: 1), isTrue);
      expect(state.player.hand, hasLength(1));
      expect(state.player.hand.single.id, shatter.id);
      expect(state.player.hand.single.name, shatter.name);
      expect(state.player.handFragments, [null]);
      expect(state.logs.any((log) => log.contains('破碎重组')), isTrue);

      expect(controller.playCard(shatter, handIndex: 0), isTrue);
      expect(state.ai.heroHealth, 29);
      expect(state.player.hand.map((card) => card.id), contains(filler.id));
      controller.dispose();
    },
  );

  test(
    'mobile AI prioritizes a playable card between matching Shatter pieces',
    () async {
      final catalog = await loadCatalog();
      final shatter = catalog.singleWhere(
        (card) => card.id == 'ember-cinder-dispatch',
      );
      final filler = catalog.singleWhere((card) => card.id == 'sun-dawn-scout');
      final left = shatter.copyWith(
        name: '${shatter.name} · 左片',
        target: 'none',
        effect: const [
          {'kind': 'draw', 'count': 1},
        ],
      );
      final right = shatter.copyWith(
        name: '${shatter.name} · 右片',
        target: 'none',
        effect: const [
          {'kind': 'random-enemy-damage', 'amount': 1},
        ],
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = catalog
        ..deckIds.addAll(List.filled(30, filler.id));
      controller.startBattle();
      await controller.confirmMulligan();
      final state = controller.battle!;
      state.ai.hand
        ..clear()
        ..addAll([left, filler, right]);
      state.ai.handCostReductions
        ..clear()
        ..addAll([0, 0, 0]);
      state.ai.handFragments
        ..clear()
        ..addAll(const [
          HandFragment(groupId: 'ai-shatter', piece: 'left'),
          null,
          HandFragment(groupId: 'ai-shatter', piece: 'right'),
        ]);
      state.ai.maxMana = 5;
      state.ai.deck
        ..clear()
        ..add(filler);
      state.player.deck
        ..clear()
        ..add(filler);

      await controller.endTurn();

      expect(state.logs.any((log) => log.contains('破碎重组')), isTrue);
      expect(state.ai.handFragments.whereType<HandFragment>(), isEmpty);
      controller.dispose();
    },
  );

  test('mobile Herald scales its soldiers and the linked Colossal', () async {
    const part = <String, dynamic>{
      'id': 'test-colossal-appendage',
      'name': '测试巨鳍',
      'attack': 2,
      'health': 3,
      'keywords': <String>['lifesteal'],
      'effect': <Map<String, dynamic>>[
        <String, dynamic>{'kind': 'armor', 'amount': 1},
      ],
    };
    const colossal = CardDefinition(
      id: 'test-colossal',
      name: '测试巨型',
      description: '巨型。',
      faction: '幽潮',
      type: 'unit',
      cost: 8,
      rarity: '传说',
      attack: 5,
      health: 6,
      keywords: <String>['colossal'],
      colossal: <String, dynamic>{
        'parts': <Map<String, dynamic>>[part],
      },
    );
    const heraldOne = CardDefinition(
      id: 'test-herald-one',
      name: '测试先驱一',
      description: '先驱。',
      faction: '幽潮',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 1,
      health: 1,
      keywords: <String>['herald'],
      herald: <String, dynamic>{'colossalCardId': 'test-colossal'},
    );
    const heraldTwo = CardDefinition(
      id: 'test-herald-two',
      name: '测试先驱二',
      description: '先驱。',
      faction: '幽潮',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 1,
      health: 1,
      keywords: <String>['herald'],
      herald: <String, dynamic>{'colossalCardId': 'test-colossal'},
    );
    const filler = CardDefinition(
      id: 'test-colossal-filler',
      name: '测试占位',
      description: '战场占位。',
      faction: '幽潮',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 1,
      health: 1,
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = const [filler, heraldOne, heraldTwo, colossal]
      ..deckIds.addAll(List.filled(30, filler.id));
    controller.startBattle();
    await controller.confirmMulligan();
    final state = controller.battle!;
    state.player.hand
      ..clear()
      ..addAll(const [heraldOne, heraldTwo, colossal]);
    state.player.handCostReductions
      ..clear()
      ..addAll(const [0, 0, 0]);
    state.player.handFragments
      ..clear()
      ..addAll(const [null, null, null]);
    state.player.mana = 10;

    expect(controller.playCard(heraldOne, handIndex: 0), isTrue);
    expect(state.player.heraldCount, 1);
    expect(state.player.board.last.card.id, 'test-colossal-appendage-soldier');
    expect(state.player.board.last.attack, 2);
    expect(state.player.armor, 1);

    expect(controller.playCard(heraldTwo, handIndex: 0), isTrue);
    expect(state.player.heraldCount, 2);
    expect(state.player.board.last.attack, 4);
    expect(state.player.board.last.health, 6);
    expect(state.player.armor, 3);

    expect(controller.playCard(colossal, handIndex: 0), isTrue);
    final body = state.player.board.singleWhere(
      (unit) => unit.card.id == colossal.id,
    );
    final appendage = state.player.board.singleWhere(
      (unit) => unit.card.id == part['id'],
    );
    expect(body.attack, 10);
    expect(body.health, 12);
    expect(appendage.attack, 4);
    expect(appendage.health, 6);
    expect(state.player.armor, 5);

    state.player.board
      ..clear()
      ..addAll(
        List.generate(
          6,
          (index) => BattleUnit(
            instanceId: 'colossal-filler-$index',
            card: filler,
            owner: 'player',
            attack: 1,
            health: 1,
            maxHealth: 1,
          ),
        ),
      );
    state.player.hand
      ..clear()
      ..add(colossal);
    state.player.handCostReductions
      ..clear()
      ..add(0);
    state.player.handFragments
      ..clear()
      ..add(null);
    state.player.heraldCount = 4;
    state.player.mana = 8;
    expect(controller.playCard(colossal, handIndex: 0), isTrue);
    expect(state.player.board, hasLength(7));
    expect(state.player.board.last.card.id, colossal.id);
    expect(state.player.board.last.attack, 20);
    expect(
      state.player.board.any((unit) => unit.card.id == part['id']),
      isFalse,
    );
    controller.dispose();
  });

  test(
    'mobile rejects fake enemy placement and upgrades on a full recipient board',
    () async {
      final filler = CardDefinition(
        id: 'placement-filler',
        name: '落点占位牌',
        description: '测试战场容量。',
        faction: '曜光',
        type: 'unit',
        cost: 1,
        rarity: '普通',
        attack: 1,
        health: 1,
      );
      final disguised = CardDefinition(
        id: 'placement-disguised',
        name: '满场伪装者',
        description: '伪装。',
        faction: '曜光',
        type: 'unit',
        cost: 1,
        rarity: '普通',
        attack: 2,
        health: 2,
        disguised: true,
        keywords: const ['disguised'],
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = [filler, disguised]
        ..deckIds.addAll(List.filled(30, filler.id));
      controller.startBattle();
      await controller.confirmMulligan();
      final state = controller.battle!;

      state.player.hand
        ..clear()
        ..add(filler);
      state.player.handCostReductions
        ..clear()
        ..add(0);
      state.player.mana = 1;
      expect(
        controller.playCard(filler, handIndex: 0, placement: 'enemy'),
        isFalse,
      );
      expect(state.player.hand, [filler]);

      state.player.hand[0] = disguised;
      state.ai.board
        ..clear()
        ..add(
          BattleUnit(
            instanceId: 'upgrade-target',
            card: disguised,
            owner: 'ai',
            attack: 2,
            health: 2,
            maxHealth: 2,
          ),
        )
        ..addAll(
          List.generate(
            6,
            (index) => BattleUnit(
              instanceId: 'capacity-$index',
              card: filler,
              owner: 'ai',
              attack: 1,
              health: 1,
              maxHealth: 1,
            ),
          ),
        );
      expect(
        controller.playCard(disguised, handIndex: 0, placement: 'enemy'),
        isTrue,
      );
      expect(state.ai.board, hasLength(7));
      expect(state.ai.board.first.stars, 2);
      expect(state.ai.board.first.attack, 3);
      expect(state.ai.board.first.health, 3);
      controller.dispose();
    },
  );

  test('AI-first opening gives the human the fourth card and Coin', () async {
    final cards = List.generate(
      15,
      (index) => CardDefinition(
        id: 'ai-first-$index',
        name: '后手测试 $index',
        description: '验证先后手和首回合抽牌。',
        faction: '曜光',
        type: 'unit',
        cost: 8,
        rarity: '普通',
        attack: 1,
        health: 1,
      ),
    );
    final controller = GameController(startingPlayer: 'ai')
      ..catalog = cards
      ..deckIds.addAll(cards.expand((card) => [card.id, card.id]));

    controller.startBattle();
    final state = controller.battle!;
    expect(state.activePlayer, 'ai');
    expect(state.phase, 'mulligan');
    expect(state.ai.hand, hasLength(3));
    expect(state.ai.coinAvailable, isFalse);
    expect(state.player.hand, hasLength(4));
    expect(state.player.coinAvailable, isTrue);

    await controller.confirmMulligan();

    // The AI drew at the start of its first turn, then passed. The human now
    // starts their own first turn with one mana and a normal turn draw.
    expect(state.ai.hand, hasLength(4));
    expect(state.ai.maxMana, 1);
    expect(state.aiTurnsStarted, 1);
    expect(state.player.hand, hasLength(5));
    expect(state.player.maxMana, 1);
    expect(state.player.mana, 1);
    expect(state.playerTurnsStarted, 1);
    expect(state.player.coinAvailable, isTrue);
    expect(state.activePlayer, 'player');
    expect(state.phase, 'main');
    expect(state.turn, 1);

    await controller.endTurn();
    expect(state.aiTurnsStarted, 2);
    expect(state.ai.maxMana, 2);
    expect(state.playerTurnsStarted, 2);
    expect(state.player.maxMana, 2);
    expect(state.turn, 2);
    controller.dispose();
  });

  test('simultaneous core lethal is a draw and does not count as a loss', () {
    final filler = CardDefinition(
      id: 'simultaneous-core-filler',
      name: '双方核心测试',
      description: '验证平局。',
      faction: '曜光',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 1,
      health: 1,
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [filler]
      ..deckIds.addAll(List.filled(30, filler.id));
    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    final winsBefore = controller.wins;
    final lossesBefore = controller.losses;
    final matchesBefore = controller.matchesPlayed;
    final goldBefore = controller.gold;
    state.player.heroHealth = 0;
    state.ai.heroHealth = 0;
    state.player.coinAvailable = true;

    expect(controller.useCoin(), isTrue);
    expect(state.finished, isTrue);
    expect(state.phase, 'game-over');
    expect(state.winner, isNull);
    expect(state.endReason, 'draw');
    expect(state.fx?.kind, 'draw');
    expect(controller.wins, winsBefore);
    expect(controller.losses, lossesBefore);
    expect(controller.matchesPlayed, matchesBefore + 1);
    expect(controller.gold, goldBefore);
    controller.dispose();
  });

  test(
    'a later effect in the same primary phase can heal a hero above zero',
    () {
      final recovery = CardDefinition(
        id: 'same-phase-recovery',
        name: '绝境恢复',
        description: '抽一张牌，然后恢复 2 点生命。',
        faction: '曜光',
        type: 'spell',
        cost: 0,
        rarity: '普通',
        effect: [
          {'kind': 'draw', 'count': 1},
          {'kind': 'heal', 'amount': 2},
        ],
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = [recovery]
        ..deckIds.addAll(List.filled(30, recovery.id));
      controller.startBattle();
      controller.confirmMulligan();
      final state = controller.battle!;
      state.player.heroHealth = 1;
      state.player.fatigue = 0;
      state.player.mana = 1;
      state.player.deck.clear();
      state.player.hand
        ..clear()
        ..add(recovery);

      expect(controller.playCard(recovery), isTrue);
      expect(state.player.fatigue, 1);
      expect(state.player.heroHealth, 2);
      expect(state.playerHeroMarkedForDeath, isFalse);
      expect(state.finished, isFalse);
      controller.dispose();
    },
  );

  test(
    'Deathrattle healing cannot rescue a hero marked in the death window',
    () {
      final healer = CardDefinition(
        id: 'death-window-healer',
        name: '迟到的治疗者',
        description: '亡语：恢复 5 点核心生命。',
        faction: '曜光',
        type: 'unit',
        cost: 1,
        rarity: '普通',
        attack: 1,
        health: 1,
        keywords: ['deathrattle'],
        onDeath: [
          {'kind': 'heal', 'amount': 5},
        ],
      );
      final sweep = CardDefinition(
        id: 'death-window-lethal',
        name: '终局扫击',
        description: '对所有敌人造成 1 点伤害。',
        faction: '曜光',
        type: 'spell',
        cost: 0,
        rarity: '普通',
        effect: [
          {'kind': 'damage-all-enemies', 'amount': 1},
        ],
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = [healer, sweep]
        ..deckIds.addAll(List.filled(30, sweep.id));
      controller.startBattle();
      controller.confirmMulligan();
      final state = controller.battle!;
      state.player.mana = 1;
      state.player.hand
        ..clear()
        ..add(sweep);
      state.ai.heroHealth = 1;
      state.ai.board
        ..clear()
        ..add(
          BattleUnit(
            instanceId: 'late-healer',
            card: healer,
            owner: 'ai',
            attack: 1,
            health: 1,
            maxHealth: 1,
          ),
        );

      expect(controller.playCard(sweep), isTrue);
      expect(state.ai.heroHealth, 0);
      expect(state.aiHeroMarkedForDeath, isTrue);
      expect(
        state.logs.any(
          (log) => log.contains(healer.name) && log.contains('恢复'),
        ),
        isFalse,
      );
      expect(state.finished, isTrue);
      expect(state.winner, 'player');
      expect(state.endReason, 'hero-defeated');
      controller.dispose();
    },
  );

  test(
    'later Deathrattles can mark the other hero and turn loss into draw',
    () {
      final healer = CardDefinition(
        id: 'draw-window-healer',
        name: '平局治疗者',
        description: '亡语：恢复 5 点核心生命。',
        faction: '曜光',
        type: 'unit',
        cost: 1,
        rarity: '普通',
        attack: 1,
        health: 1,
        keywords: ['deathrattle'],
        onDeath: [
          {'kind': 'heal', 'amount': 5},
        ],
      );
      final retaliation = CardDefinition(
        id: 'draw-window-retaliation',
        name: '平局反噬者',
        description: '亡语：对所有敌人造成 1 点伤害。',
        faction: '曜光',
        type: 'unit',
        cost: 1,
        rarity: '普通',
        attack: 1,
        health: 1,
        keywords: ['deathrattle'],
        onDeath: [
          {'kind': 'damage-all-enemies', 'amount': 1},
        ],
      );
      final sweep = CardDefinition(
        id: 'draw-window-sweep',
        name: '平局扫击',
        description: '对所有敌人造成 1 点伤害。',
        faction: '曜光',
        type: 'spell',
        cost: 0,
        rarity: '普通',
        effect: [
          {'kind': 'damage-all-enemies', 'amount': 1},
        ],
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = [healer, retaliation, sweep]
        ..deckIds.addAll(List.filled(30, sweep.id));
      controller.startBattle();
      controller.confirmMulligan();
      final state = controller.battle!;
      state.player.mana = 1;
      state.player.heroHealth = 1;
      state.player.hand
        ..clear()
        ..add(sweep);
      state.ai.heroHealth = 1;
      state.ai.board
        ..clear()
        ..addAll([
          BattleUnit(
            instanceId: 'draw-healer',
            card: healer,
            owner: 'ai',
            attack: 1,
            health: 1,
            maxHealth: 1,
          ),
          BattleUnit(
            instanceId: 'draw-retaliation',
            card: retaliation,
            owner: 'ai',
            attack: 1,
            health: 1,
            maxHealth: 1,
          ),
        ]);

      expect(controller.playCard(sweep), isTrue);
      expect(state.ai.heroHealth, 0);
      expect(state.playerHeroMarkedForDeath, isTrue);
      expect(state.aiHeroMarkedForDeath, isTrue);
      expect(state.finished, isTrue);
      expect(state.winner, isNull);
      expect(state.endReason, 'draw');
      controller.dispose();
    },
  );

  test('the 90th action window never opens and ends in a draw', () async {
    final filler = CardDefinition(
      id: 'turn-limit-filler',
      name: '回合上限测试',
      description: '验证第 90 个行动窗口。',
      faction: '曜光',
      type: 'unit',
      cost: 8,
      rarity: '普通',
      attack: 1,
      health: 1,
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [filler]
      ..deckIds.addAll(List.filled(30, filler.id));
    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    state.actionWindow = maxBattleActionWindows;
    final aiTurnsBefore = state.aiTurnsStarted;

    await controller.endTurn();

    expect(state.actionWindow, maxBattleActionWindows + 1);
    expect(state.finished, isTrue);
    expect(state.phase, 'game-over');
    expect(state.winner, isNull);
    expect(state.endReason, 'draw');
    expect(state.aiTurnsStarted, aiTurnsBefore);
    expect(state.logs.first, contains('第 90 个窗口不会开启'));
    controller.dispose();
  });

  test('pack opening protects the first slot with a rare-or-better card', () {
    CardDefinition card(String id, String rarity) => CardDefinition(
      id: id,
      name: id,
      description: '测试卡牌',
      faction: '曜光',
      type: 'unit',
      cost: 1,
      rarity: rarity,
      attack: 1,
      health: 1,
    );
    final common = card('common', '普通');
    final rare = card('rare', '稀有');
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [common, rare]
      ..packs = 1
      ..collection[common.id] = 2
      ..collection[rare.id] = 0;

    controller.openPack();
    expect(controller.packs, 0);
    expect(controller.owned(rare.id), greaterThan(0));
    controller.dispose();
  });

  test('weapon cards equip and allow one hero attack per turn', () {
    final weapon = CardDefinition(
      id: 'weapon',
      name: '测试刃',
      description: '测试武器',
      faction: '曜光',
      type: 'weapon',
      cost: 1,
      rarity: '稀有',
      attack: 3,
      durability: 2,
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [weapon]
      ..deckIds.addAll(List.filled(30, weapon.id));
    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    state.ai.heroHealth = 30;
    state.player.mana = 10;
    state.player.hand
      ..clear()
      ..add(weapon);
    expect(controller.playCard(weapon), isTrue);
    expect(state.player.weapon?.durability, 2);
    expect(controller.heroAttack(targetHero: true), isTrue);
    expect(state.ai.heroHealth, 27);
    expect(state.player.weapon?.durability, 1);
    expect(controller.heroAttack(targetHero: true), isFalse);
    controller.dispose();
  });

  test('lethal unit combat still deals simultaneous retaliation damage', () {
    CardDefinition unit(String id, int attack, int health) => CardDefinition(
      id: id,
      name: id,
      description: '同时战斗伤害测试。',
      faction: '曜光',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: attack,
      health: health,
    );

    final attackerCard = unit('simultaneous-attacker', 4, 2);
    final defenderCard = unit('simultaneous-defender', 2, 1);
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [attackerCard, defenderCard]
      ..deckIds.addAll(List.filled(30, attackerCard.id));
    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    state.player.board.clear();
    state.ai.board.clear();
    final attacker = BattleUnit(
      instanceId: 'simultaneous-attacker-unit',
      card: attackerCard,
      owner: 'player',
      attack: 4,
      health: 2,
      maxHealth: 2,
      summoningSick: false,
    );
    final defender = BattleUnit(
      instanceId: 'simultaneous-defender-unit',
      card: defenderCard,
      owner: 'ai',
      attack: 2,
      health: 1,
      maxHealth: 1,
    );
    state.player.board.add(attacker);
    state.ai.board.add(defender);

    expect(controller.attack(attacker, target: defender), isTrue);
    expect(state.player.board.contains(attacker), isFalse);
    expect(state.ai.board.contains(defender), isFalse);
    controller.dispose();
  });

  test('a weapon attack against a unit receives retaliation', () {
    final weapon = CardDefinition(
      id: 'retaliation-weapon',
      name: '反击测试刃',
      description: '测试英雄战斗。',
      faction: '曜光',
      type: 'weapon',
      cost: 1,
      rarity: '普通',
      attack: 3,
      durability: 2,
    );
    final defenderCard = CardDefinition(
      id: 'hero-retaliation-defender',
      name: '反击防守者',
      description: '反击英雄。',
      faction: '幽潮',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 4,
      health: 1,
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [weapon, defenderCard]
      ..deckIds.addAll(List.filled(30, weapon.id));
    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    state.player.mana = 10;
    state.player.hand
      ..clear()
      ..add(weapon);
    expect(controller.playCard(weapon), isTrue);
    final defender = BattleUnit(
      instanceId: 'hero-retaliation-target',
      card: defenderCard,
      owner: 'ai',
      attack: 4,
      health: 1,
      maxHealth: 1,
    );
    state.ai.board
      ..clear()
      ..add(defender);
    state.player.heroHealth = 30;

    expect(controller.heroAttack(target: defender), isTrue);
    expect(state.player.heroHealth, 26);
    expect(state.ai.board.contains(defender), isFalse);
    expect(state.player.weapon?.durability, 1);
    controller.dispose();
  });

  test('a full board rejects pure summons before spending resources', () {
    final moss = CardDefinition(
      id: 'neutral-moss-runner',
      name: '苔径奔行兽',
      description: '召唤物。',
      faction: '中立',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 1,
      health: 2,
    );
    final verdant = CardDefinition(
      id: 'verdant-deck-unit',
      name: '苍林卡组单位',
      description: '决定英雄技能。',
      faction: '苍林',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 1,
      health: 2,
    );
    final pureSummon = CardDefinition(
      id: 'pure-summon-spell',
      name: '纯召唤战术',
      description: '召唤一个单位。',
      faction: '苍林',
      type: 'spell',
      cost: 2,
      rarity: '普通',
      effect: [
        {'kind': 'summon', 'cardId': moss.id, 'count': 1},
      ],
    );
    final mixedSummon = CardDefinition(
      id: 'mixed-summon-spell',
      name: '混合召唤战术',
      description: '召唤一个单位并获得护甲。',
      faction: '苍林',
      type: 'spell',
      cost: 2,
      rarity: '普通',
      effect: [
        {'kind': 'summon', 'cardId': moss.id, 'count': 1},
        {'kind': 'armor', 'amount': 2},
      ],
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [moss, verdant, pureSummon, mixedSummon]
      ..deckIds.addAll(List.filled(30, verdant.id));
    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    state.player.board.clear();
    for (var index = 0; index < 7; index++) {
      state.player.board.add(
        BattleUnit(
          instanceId: 'full-board-$index',
          card: moss,
          owner: 'player',
          attack: 1,
          health: 2,
          maxHealth: 2,
        ),
      );
    }
    state.player.mana = 10;
    state.player.hand
      ..clear()
      ..addAll([pureSummon, mixedSummon]);

    expect(controller.playCard(pureSummon), isFalse);
    expect(state.player.mana, 10);
    expect(state.player.hand, contains(pureSummon));
    expect(state.player.cardsPlayedThisTurn, 0);

    expect(controller.useHeroPower(), isFalse);
    expect(state.player.mana, 10);
    expect(state.heroPowerUsed, isFalse);

    expect(controller.playCard(mixedSummon), isTrue);
    expect(state.player.mana, 8);
    expect(state.player.board, hasLength(7));
    expect(state.player.armor, 2);
    controller.dispose();
  });

  test('all simultaneous Deathrattles resolve before queued Reborn', () {
    CardDefinition unit(
      String id,
      String name, {
      int health = 2,
      List<String> keywords = const [],
      List<Map<String, dynamic>> onDeath = const [],
    }) => CardDefinition(
      id: id,
      name: name,
      description: '死亡窗口测试。',
      faction: '曜光',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 1,
      health: health,
      keywords: keywords,
      onDeath: onDeath,
    );

    final token = unit('death-window-token', '亡语衍生物', health: 1);
    final survivor = unit('death-window-survivor', '存活单位', health: 3);
    final rebornCard = unit(
      'death-window-reborn',
      '排队复生者',
      health: 1,
      keywords: ['reborn'],
    );
    final summoner = unit(
      'death-window-summoner',
      '双生亡语者',
      health: 1,
      keywords: ['deathrattle'],
      onDeath: [
        {'kind': 'summon', 'cardId': token.id, 'count': 2},
      ],
    );
    final sweep = CardDefinition(
      id: 'death-window-sweep',
      name: '死亡窗口扫击',
      description: '对所有敌人造成 1 点伤害。',
      faction: '曜光',
      type: 'spell',
      cost: 1,
      rarity: '普通',
      effect: [
        {'kind': 'damage-all-enemies', 'amount': 1},
      ],
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [token, survivor, rebornCard, summoner, sweep]
      ..deckIds.addAll(List.filled(30, survivor.id));
    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    state.player.mana = 10;
    state.player.hand
      ..clear()
      ..add(sweep);
    state.ai.board
      ..clear()
      ..addAll([
        BattleUnit(
          instanceId: 'queued-reborn',
          card: rebornCard,
          owner: 'ai',
          attack: 1,
          health: 1,
          maxHealth: 1,
        ),
        BattleUnit(
          instanceId: 'queued-summoner',
          card: summoner,
          owner: 'ai',
          attack: 1,
          health: 1,
          maxHealth: 1,
        ),
        for (var index = 0; index < 5; index++)
          BattleUnit(
            instanceId: 'death-window-survivor-$index',
            card: survivor,
            owner: 'ai',
            attack: 1,
            health: 3,
            maxHealth: 3,
          ),
      ]);

    expect(controller.playCard(sweep), isTrue);
    expect(state.ai.board, hasLength(7));
    expect(
      state.ai.board.where((unit) => unit.card.id == token.id),
      hasLength(2),
    );
    expect(
      state.ai.board.any((unit) => unit.card.id == rebornCard.id),
      isFalse,
    );
    controller.dispose();
  });

  test('Deathrattle-created death waves resolve before Reborn', () {
    CardDefinition unit(
      String id,
      String name, {
      int health = 1,
      List<String> keywords = const [],
      List<Map<String, dynamic>> onDeath = const [],
    }) => CardDefinition(
      id: id,
      name: name,
      description: '后续死亡波测试。',
      faction: '曜光',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 1,
      health: health,
      keywords: keywords,
      onDeath: onDeath,
    );

    final rebornCard = unit(
      'wave-reborn',
      '波次复生者',
      health: 4,
      keywords: ['reborn'],
    );
    final waveMaker = unit(
      'wave-maker',
      '死亡波引擎',
      keywords: ['deathrattle'],
      onDeath: [
        {'kind': 'damage-all-enemies', 'amount': 1},
      ],
    );
    final laterDeath = unit(
      'later-wave-death',
      '后续亡语单位',
      keywords: ['deathrattle'],
      onDeath: [
        {'kind': 'armor', 'amount': 1},
      ],
    );
    final sweep = CardDefinition(
      id: 'wave-sweep',
      name: '波次扫击',
      description: '对所有敌人造成 1 点伤害。',
      faction: '曜光',
      type: 'spell',
      cost: 1,
      rarity: '普通',
      effect: [
        {'kind': 'damage-all-enemies', 'amount': 1},
      ],
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [rebornCard, waveMaker, laterDeath, sweep]
      ..deckIds.addAll(List.filled(30, sweep.id));
    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    state.player.mana = 10;
    state.player.hand
      ..clear()
      ..add(sweep);
    state.player.board
      ..clear()
      ..add(
        BattleUnit(
          instanceId: 'later-wave-unit',
          card: laterDeath,
          owner: 'player',
          attack: 1,
          health: 1,
          maxHealth: 1,
        ),
      );
    state.ai.board
      ..clear()
      ..addAll([
        BattleUnit(
          instanceId: 'wave-reborn-unit',
          card: rebornCard,
          owner: 'ai',
          attack: 1,
          health: 1,
          maxHealth: 4,
        ),
        BattleUnit(
          instanceId: 'wave-maker-unit',
          card: waveMaker,
          owner: 'ai',
          attack: 1,
          health: 1,
          maxHealth: 1,
        ),
      ]);

    expect(controller.playCard(sweep), isTrue);
    expect(state.player.armor, 1);
    final returned = state.ai.board.singleWhere(
      (unit) => unit.card.id == rebornCard.id,
    );
    expect(returned.health, 1);
    expect(returned.maxHealth, 4);
    expect(returned.rebornUsed, isTrue);
    final rebornLog = state.logs.indexWhere((log) => log.contains('复生回响'));
    final laterDeathLog = state.logs.indexWhere(
      (log) => log.contains(laterDeath.name) && log.contains('离开战场'),
    );
    expect(rebornLog, greaterThanOrEqualTo(0));
    expect(laterDeathLog, greaterThan(rebornLog));
    controller.dispose();
  });

  test(
    'overload locks next-turn crystals and tradeable cards cycle the deck',
    () async {
      final filler = CardDefinition(
        id: 'filler',
        name: '替代档案',
        description: '抽取用',
        faction: '曜光',
        type: 'unit',
        cost: 1,
        rarity: '普通',
        attack: 1,
        health: 1,
      );
      final overload = CardDefinition(
        id: 'overload',
        name: '过载脉冲',
        description: '造成伤害并过载。',
        faction: '雷铸',
        type: 'spell',
        cost: 1,
        rarity: '稀有',
        overload: 2,
        effect: [
          {'kind': 'damage', 'amount': 1},
        ],
      );
      final tradeCard = CardDefinition(
        id: 'trade',
        name: '可交易档案',
        description: '可交易。',
        faction: '曜光',
        type: 'spell',
        cost: 4,
        rarity: '普通',
        tradeable: true,
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = [filler, overload, tradeCard]
        ..deckIds.addAll(List.filled(30, filler.id));
      controller.startBattle();
      controller.confirmMulligan();
      final state = controller.battle!;
      state.ai.hand.clear();
      state.player.maxMana = 3;
      state.player.mana = 10;
      state.player.hand
        ..clear()
        ..add(overload);
      expect(controller.playCard(overload), isTrue);
      expect(state.player.overloadLocked, 2);
      await controller.endTurn();
      expect(state.player.mana, 2);

      state.player.hand
        ..clear()
        ..add(tradeCard);
      state.player.deck
        ..clear()
        ..add(filler);
      state.player.mana = 2;
      expect(controller.tradeCard(tradeCard), isTrue);
      expect(state.player.mana, 1);
      expect(state.player.hand.map((card) => card.id), [filler.id]);
      expect(state.player.deck.map((card) => card.id), [tradeCard.id]);

      state.player.hand
        ..clear()
        ..add(tradeCard);
      state.player.deck.clear();
      state.player.mana = 2;
      expect(controller.tradeCard(tradeCard), isFalse);
      expect(state.player.mana, 2);
      expect(state.player.hand.map((card) => card.id), [tradeCard.id]);
      controller.dispose();
    },
  );

  test('Coin pays excess overload debt before creating temporary mana', () {
    final card = CardDefinition(
      id: 'coin-filler',
      name: '资源测试单位',
      description: '测试资源循环。',
      faction: '雷铸',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 1,
      health: 1,
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [card]
      ..deckIds.addAll(List.filled(30, card.id));
    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    state.player.maxMana = 3;
    state.player.mana = 3;
    state.player.overloadLocked = 4;
    state.player.coinAvailable = true;
    expect(controller.useCoin(), isTrue);
    expect(state.player.overloadLocked, 3);
    expect(state.player.mana, 3);
    controller.dispose();
  });

  test('Coin is a spell for Counterspell, spell listeners, and Combo', () {
    final filler = CardDefinition(
      id: 'coin-rules-filler',
      name: '幸运币规则单位',
      description: '用于验证幸运币。',
      faction: '曜光',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 1,
      health: 3,
      onSpellPlayed: [
        {'kind': 'armor', 'amount': 1},
      ],
    );
    final combo = CardDefinition(
      id: 'coin-combo-followup',
      name: '连击后续',
      description: '连击：获得 2 点护甲。',
      faction: '曜光',
      type: 'spell',
      cost: 0,
      rarity: '普通',
      combo: [
        {'kind': 'armor', 'amount': 2},
      ],
    );
    final counterSecret = CardDefinition(
      id: 'coin-counter-secret',
      name: '幸运币反制',
      description: '反制一张法术。',
      faction: '幽潮',
      type: 'spell',
      cost: 1,
      rarity: '史诗',
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [filler, combo, counterSecret]
      ..deckIds.addAll(List.filled(30, filler.id));
    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    state.player.mana = 1;
    state.player.cardsPlayedThisTurn = 0;
    state.player.coinAvailable = true;
    state.player.board
      ..clear()
      ..add(
        BattleUnit(
          instanceId: 'coin-listener',
          card: filler,
          owner: 'player',
          attack: 1,
          health: 3,
          maxHealth: 3,
        ),
      );
    state.ai.secrets.add(
      BattleSecret(
        card: counterSecret,
        secretId: counterSecret.id,
        trigger: 'opponent-plays-spell',
        effect: const {'kind': 'counterspell'},
      ),
    );

    expect(controller.useCoin(), isTrue);
    expect(state.player.coinAvailable, isFalse);
    expect(state.player.cardsPlayedThisTurn, 1);
    expect(state.player.mana, 1);
    expect(state.player.armor, 0);
    expect(state.ai.secrets, isEmpty);

    state.player.coinAvailable = true;
    expect(controller.useCoin(), isTrue);
    expect(state.player.cardsPlayedThisTurn, 2);
    expect(state.player.mana, 2);
    expect(state.player.armor, 1);

    state.player.hand
      ..clear()
      ..add(combo);
    expect(controller.playCard(combo), isTrue);
    // Combo grants 2 armor and the spell listener grants another 1.
    expect(state.player.armor, 4);
    controller.dispose();
  });

  test('the Coin occupies one of the ten hand slots', () {
    final drawCard = CardDefinition(
      id: 'coin-hand-slot-card',
      name: '幸运币手牌测试',
      description: '测试手牌上限。',
      faction: '星穹',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 1,
      health: 1,
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [drawCard]
      ..deckIds.addAll(List.filled(30, drawCard.id));
    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    state.player.mana = 10;
    state.player.coinAvailable = true;
    state.player.hand
      ..clear()
      ..addAll(List.filled(9, drawCard));
    state.player.deck
      ..clear()
      ..add(drawCard);

    expect(controller.useHeroPower(), isTrue);
    expect(state.player.hand, hasLength(9));
    expect(state.player.deck, isEmpty);
    expect(state.logs.any((log) => log.contains('燃毁')), isTrue);
    controller.dispose();
  });

  test('deck validation enforces copy, legendary, and faction limits', () {
    CardDefinition unit(String id, String faction, {String rarity = '普通'}) =>
        CardDefinition(
          id: id,
          name: id,
          description: '卡组校验。',
          faction: faction,
          type: 'unit',
          cost: 1,
          rarity: rarity,
          attack: 1,
          health: 1,
        );

    final sunCards = List.generate(16, (index) => unit('sun-$index', '曜光'));
    final legendary = unit('sun-legendary', '曜光', rarity: '传说');
    final offFaction = unit('void-card', '幽潮');
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [...sunCards, legendary, offFaction];

    controller.deckIds.addAll(
      sunCards.take(15).expand((card) => [card.id, card.id]),
    );
    expect(controller.deckValid, isTrue);

    controller.deckIds[29] = sunCards.first.id;
    expect(controller.deckValid, isFalse);
    expect(controller.deckStatus, contains('最多 2 张'));

    controller.deckIds
      ..clear()
      ..addAll(sunCards.take(14).expand((card) => [card.id, card.id]))
      ..addAll([legendary.id, legendary.id]);
    expect(controller.deckValid, isFalse);
    expect(controller.deckStatus, contains('最多 1 张'));

    controller.deckIds
      ..clear()
      ..addAll(sunCards.take(15).expand((card) => [card.id, card.id]));
    controller.deckIds[29] = offFaction.id;
    expect(controller.deckValid, isFalse);
    expect(controller.deckStatus, contains('不能混合'));

    controller.collection[sunCards.first.id] = 99;
    controller.deckIds.clear();
    expect(controller.addToDeck(sunCards.first), isTrue);
    expect(controller.addToDeck(sunCards.first), isTrue);
    expect(controller.addToDeck(sunCards.first), isFalse);

    controller.deckIds
      ..clear()
      ..addAll(List.filled(30, 'missing-card'));
    expect(controller.deckValid, isFalse);
    expect(controller.deckStatus, contains('未知'));
    controller.startBattle();
    expect(controller.battle, isNotNull);
    expect(
      [
        ...controller.battle!.player.hand,
        ...controller.battle!.player.deck,
      ].every((card) => controller.cardsById.containsKey(card.id)),
      isTrue,
    );
    controller.dispose();
  });

  test(
    'mobile decks enforce Standard rotation and preserve Wild legality',
    () async {
      final catalog = await loadCatalog();
      final wildCards = catalog
          .where((card) => card.faction == '曜光' && card.setId == 'pegasus-2024')
          .take(10)
          .toList();
      final standardCards = catalog
          .where(
            (card) =>
                card.faction == '曜光' &&
                cardAvailableInRankedFormat(card, RankedFormat.standard),
          )
          .take(5)
          .toList();
      final controller = GameController(startingPlayer: 'player')
        ..catalog = catalog
        ..deckIds.addAll(
          [...wildCards, ...standardCards].expand((card) => [card.id, card.id]),
        );

      expect(controller.deckFormat, RankedFormat.standard);
      expect(controller.deckValid, isFalse);
      expect(controller.deckStatus, contains('飞马年'));
      expect(controller.cardsAvailableForDeck, hasLength(800));

      controller.setDeckFormat(RankedFormat.wild);
      expect(controller.deckValid, isTrue);
      expect(controller.deckStatus, contains('狂野模式'));
      expect(controller.cardsAvailableForDeck, hasLength(1000));

      final rotated = wildCards.first;
      controller.deckIds.clear();
      controller.collection[rotated.id] = 2;
      controller.setDeckFormat(RankedFormat.standard);
      expect(controller.addToDeck(rotated), isFalse);
      controller.setDeckFormat(RankedFormat.wild);
      expect(controller.addToDeck(rotated), isTrue);
      controller.dispose();
    },
  );

  test(
    'smart completion uses owned cards and creates a legal Standard deck',
    () async {
      final catalog = await loadCatalog();
      final candidates = catalog
          .where(
            (card) =>
                card.faction == '曜光' &&
                card.rarity != '传说' &&
                cardAvailableInRankedFormat(card, RankedFormat.standard),
          )
          .take(15)
          .toList();
      expect(candidates, hasLength(15));
      final seed = [candidates[0].id, candidates[1].id];
      final controller = GameController()
        ..catalog = catalog
        ..deckIds.addAll(seed);
      for (final card in candidates) {
        controller.collection[card.id] = 2;
      }

      expect(controller.autoCompleteDeck(), 28);
      expect(controller.deckIds.take(seed.length), seed);
      expect(controller.deckIds, hasLength(30));
      expect(controller.deckValid, isTrue);
      expect(controller.deckPlayable, isTrue);
      for (final cardId in controller.deckIds.toSet()) {
        expect(
          controller.deckIds.where((candidate) => candidate == cardId).length,
          lessThanOrEqualTo(controller.collection[cardId] ?? 0),
        );
      }
      expect(controller.autoCompleteDeck(), 0);
      controller.dispose();
    },
  );

  test(
    'every faction has three legal deterministic Standard recipes',
    () async {
      final catalog = await loadCatalog();
      final factions = catalog
          .map((card) => card.faction)
          .where((faction) => faction != '中立')
          .toSet();
      expect(factions, hasLength(19));

      for (final faction in factions) {
        final recipes = deckRecipesForFaction(faction, catalog);
        expect(recipes.map((recipe) => recipe.kind), [
          DeckRecipeKind.core,
          DeckRecipeKind.raptor,
          DeckRecipeKind.scarab,
        ]);
        expect(
          deckRecipesForFaction(
            faction,
            catalog,
          ).map((recipe) => recipe.cardIds),
          recipes.map((recipe) => recipe.cardIds),
        );
        for (final recipe in recipes) {
          expect(recipe.cardIds, hasLength(30));
          final cards = recipe.cardIds
              .map((cardId) => catalog.singleWhere((card) => card.id == cardId))
              .toList();
          expect(
            cards.every(
              (card) => card.faction == faction || card.faction == '中立',
            ),
            isTrue,
          );
          expect(cards.every((card) => card.setId != 'pegasus-2024'), isTrue);
          expect(
            cards.where((card) => card.setId == recipe.focusSetId).length,
            greaterThanOrEqualTo(10),
          );
          if (recipe.kind == DeckRecipeKind.core) {
            expect(cards.every((card) => card.setId == 'core'), isTrue);
          }
          final controller = GameController()
            ..catalog = catalog
            ..deckIds.addAll(recipe.cardIds);
          expect(controller.deckValid, isTrue);
          controller.dispose();
        }
      }
    },
  );

  test(
    'mobile applies a recommended recipe as a new missing-aware draft',
    () async {
      final catalog = await loadCatalog();
      final recipe = deckRecipesForFaction('曜光', catalog)[1];
      final controller = GameController()
        ..catalog = catalog
        ..deckName = '原牌组'
        ..deckIds.addAll(recipe.cardIds.take(2))
        ..collection['missing-sentinel'] = 0;

      expect(controller.applyDeckRecipe(recipe), 30);
      expect(controller.activeDeckId, isNull);
      expect(controller.deckName, recipe.name);
      expect(controller.deckFormat, RankedFormat.standard);
      expect(controller.deckIds, recipe.cardIds);
      expect(controller.deckValid, isTrue);
      expect(controller.deckPlayable, isFalse);
      expect(controller.missingDeckCount, 30);

      for (final cardId in recipe.cardIds) {
        controller.collection[cardId] = 2;
      }
      expect(controller.applyDeckRecipe(recipe), 0);
      expect(controller.deckPlayable, isTrue);
      controller.dispose();
    },
  );

  test(
    'mobile deck library creates, copies, switches and deletes safely',
    () async {
      final catalog = await loadCatalog();
      final initialCards = catalog
          .where(
            (card) =>
                card.faction == '曜光' &&
                cardAvailableInRankedFormat(card, RankedFormat.standard),
          )
          .take(15)
          .expand((card) => [card.id, card.id])
          .toList();
      final controller = GameController(startingPlayer: 'player')
        ..catalog = catalog
        ..deckName = '第一套'
        ..deckIds.addAll(initialCards);

      expect(await controller.saveDeck(), isTrue);
      final firstId = controller.activeDeckId;
      expect(firstId, isNotNull);
      expect(controller.savedDecks, hasLength(1));
      expect(controller.savedDecks.single.name, '第一套');

      expect(await controller.duplicateActiveDeck(), isTrue);
      final copyId = controller.activeDeckId;
      expect(copyId, isNot(firstId));
      expect(controller.savedDecks, hasLength(2));
      expect(controller.deckName, '第一套 副本');
      expect(controller.deckIds, initialCards);

      controller.setDeckName('复制后改名');
      expect(await controller.selectDeck(firstId!), isTrue);
      expect(controller.deckName, '第一套');
      expect(
        controller.savedDecks.singleWhere((deck) => deck.id == copyId).name,
        '复制后改名',
      );

      expect(await controller.createNewDeck(), isTrue);
      expect(controller.savedDecks, hasLength(3));
      expect(controller.deckFormat, RankedFormat.standard);
      expect(controller.deckIds, hasLength(30));
      final newId = controller.activeDeckId!;
      expect(await controller.deleteDeck(newId), isTrue);
      expect(controller.savedDecks, hasLength(2));
      expect(controller.activeDeckId, isNot(newId));

      expect(await controller.deleteDeck(firstId), isTrue);
      expect(controller.savedDecks, hasLength(1));
      expect(await controller.deleteDeck(copyId!), isTrue);
      expect(controller.savedDecks, hasLength(1));
      expect(controller.deckName, '新建战术卡组');
      expect(controller.deckIds, hasLength(30));
      controller.dispose();
    },
  );

  test('ASTRA2 deck codes and readable shares match web', () async {
    const expected =
        'QVNUUkEyfHdpbGR8JUU2JUEwJTg3JUU1JTg3JTg2JTIwJUU3JTgxJUFCJUU4JThBJUIxfHN1bi1kYXduLXNjb3V0LG5ldXRyYWwtbW9zcy1ydW5uZXI';
    final code = encodeDeckCode(
      format: RankedFormat.wild,
      name: '标准 火花',
      cardIds: const ['sun-dawn-scout', 'neutral-moss-runner'],
    );
    expect(code, expected);
    final decoded = decodeDeckCode(code);
    expect(decoded.version, 2);
    expect(decoded.format, RankedFormat.wild);
    expect(decoded.name, '标准 火花');
    expect(decoded.cardIds, ['sun-dawn-scout', 'neutral-moss-runner']);

    final shareText = formatDeckShareText(
      format: RankedFormat.wild,
      name: '标准 火花',
      cardIds: const ['sun-dawn-scout', 'neutral-moss-runner'],
      catalog: await loadCatalog(),
    );
    expect(
      shareText,
      [
        '# 余烬协议牌组：标准 火花',
        '# 模式：狂野模式',
        '# 2 张卡牌 · 2 种',
        '',
        '1x (1) 苔径奔行兽',
        '1x (1) 晨辉斥候',
        '',
        '# 卡组代码',
        expected,
        '',
        '# 复制完整牌表或仅复制上方代码，均可在余烬协议中导入。',
      ].join('\n'),
    );
    final decodedShare = decodeDeckCode(shareText);
    expect(decodedShare.version, 2);
    expect(decodedShare.format, RankedFormat.wild);
    expect(decodedShare.name, '标准 火花');
    expect(decodedShare.cardIds, ['sun-dawn-scout', 'neutral-moss-runner']);
    expect(decodeDeckCode('# 卡组代码：$expected').cardIds, [
      'sun-dawn-scout',
      'neutral-moss-runner',
    ]);

    final legacy = decodeDeckCode(
      'QVNUUkExfHN1bi1kYXduLXNjb3V0LG5ldXRyYWwtbW9zcy1ydW5uZXI',
    );
    expect(legacy.version, 1);
    expect(legacy.format, isNull);
    expect(legacy.name, isNull);
    expect(legacy.cardIds, ['sun-dawn-scout', 'neutral-moss-runner']);
    expect(
      () => decodeDeckCode('ASTRA2|arena|bad|sun-dawn-scout'),
      throwsFormatException,
    );
  });

  test('mobile imports a deck code into a new format-aware slot', () async {
    final catalog = await loadCatalog();
    final cards = catalog
        .where((card) => card.faction == '曜光' && card.rarity != '传说')
        .toList();
    final rotated = cards.firstWhere((card) => card.setId == 'pegasus-2024');
    final selected = [
      rotated,
      ...cards.where((card) => card.id != rotated.id).take(14),
    ];
    final ids = selected.expand((card) => [card.id, card.id]).toList();
    final controller = GameController()
      ..catalog = catalog
      ..deckIds.addAll(ids);
    for (final id in ids) {
      controller.collection[id] = 2;
    }
    controller.setDeckFormat(RankedFormat.wild);
    controller.setDeckName('移动狂野');
    expect(await controller.saveDeck(), isTrue);
    final originalId = controller.activeDeckId;
    final shareText = controller.exportActiveDeckShareText();
    expect(shareText, contains('# 卡组代码'));
    final preview = controller.previewClipboardDeckCode(shareText);
    expect(preview?.name, '移动狂野');
    expect(preview?.format, RankedFormat.wild);
    expect(preview?.missingCount, 0);
    controller.declineClipboardDeckCode(shareText);
    expect(controller.previewClipboardDeckCode(shareText), isNull);

    controller.setDeckFormat(RankedFormat.standard);
    final result = await controller.importDeckCode(shareText);
    expect(result.success, isTrue);
    expect(controller.savedDecks, hasLength(1));
    expect(controller.activeDeckId, isNull);
    expect(controller.deckFormat, RankedFormat.wild);
    expect(controller.deckName, '移动狂野');
    expect(controller.deckIds, ids);
    expect(controller.deckPlayable, isTrue);
    expect(controller.previewClipboardDeckCode(shareText), isNotNull);
    expect(await controller.saveDeck(), isTrue);
    expect(controller.savedDecks, hasLength(2));
    expect(controller.activeDeckId, isNot(originalId));

    final extra = cards.firstWhere((card) => !ids.contains(card.id));
    controller.collection[extra.id] = 2;
    controller.collection[ids.first] = 0;
    final missingResult = await controller.importDeckCode(shareText);
    expect(missingResult.success, isTrue);
    expect(missingResult.message, contains('缺少 2 张'));
    expect(controller.deckValid, isTrue);
    expect(controller.deckPlayable, isFalse);
    expect(controller.missingDeckCount, 2);
    controller.startBattle();
    expect(controller.battle, isNull);
    expect(
      controller.replacementSuggestions(ids.first).map((card) => card.id),
      contains(extra.id),
    );
    expect(controller.replaceMissingDeckCard(ids.first, extra.id), isTrue);
    expect(controller.missingDeckCount, 1);
    expect(controller.replaceMissingDeckCard(ids.first, extra.id), isTrue);
    expect(controller.missingDeckCount, 0);
    expect(controller.deckPlayable, isTrue);
    expect(controller.savedDecks, hasLength(2));
    controller.dispose();
  });

  test('mobile deck library enforces all 27 local slots', () async {
    final catalog = await loadCatalog();
    final cards = catalog
        .where((card) => card.faction == '曜光')
        .take(15)
        .expand((card) => [card.id, card.id])
        .toList();
    final controller = GameController()
      ..catalog = catalog
      ..deckIds.addAll(cards);
    expect(await controller.saveDeck(), isTrue);
    while (controller.savedDecks.length < maxSavedDecks) {
      expect(await controller.duplicateActiveDeck(), isTrue);
    }
    expect(controller.savedDecks, hasLength(maxSavedDecks));
    expect(controller.canCreateDeck, isFalse);
    expect(await controller.createNewDeck(), isFalse);
    expect(await controller.duplicateActiveDeck(), isFalse);
    final importResult = await controller.importDeckCode(
      'ASTRA1|sun-dawn-scout,neutral-moss-runner',
    );
    expect(importResult.success, isFalse);
    expect(importResult.message, contains('27'));
    controller.dispose();
  });

  test(
    'legacy single mobile deck migrates into the saved deck library',
    () async {
      final legacyIds = List<String>.filled(30, 'sun-dawn-scout');
      SharedPreferences.setMockInitialValues(<String, Object>{
        'deck_ids': legacyIds,
        'deck_format': 'wild',
      });
      final controller = GameController();
      await controller.initialize();

      expect(controller.savedDecks, hasLength(1));
      expect(controller.savedDecks.single.name, '迁移牌组');
      expect(controller.savedDecks.single.format, RankedFormat.wild);
      expect(controller.savedDecks.single.cardIds, legacyIds);
      expect(controller.activeDeckId, controller.savedDecks.single.id);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('saved_decks'), isNotNull);
      controller.dispose();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    },
  );

  test(
    'drawing with a full hand burns the drawn card instead of hiding it',
    () {
      final drawCard = CardDefinition(
        id: 'astral-draw',
        name: '洞见测试单位',
        description: '星穹阵营测试。',
        faction: '星穹',
        type: 'unit',
        cost: 1,
        rarity: '普通',
        attack: 1,
        health: 1,
      );
      final filler = CardDefinition(
        id: 'draw-filler',
        name: '被燃毁的档案',
        description: '测试燃毁。',
        faction: '中立',
        type: 'unit',
        cost: 1,
        rarity: '普通',
        attack: 1,
        health: 1,
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = [drawCard, filler]
        ..deckIds.addAll(List.filled(30, drawCard.id));
      controller.startBattle();
      controller.confirmMulligan();
      final state = controller.battle!;
      state.ai.hand.clear();
      state.player.mana = 10;
      state.player.hand
        ..clear()
        ..addAll(List.filled(10, drawCard));
      state.player.deck
        ..clear()
        ..add(filler);
      expect(controller.useHeroPower(), isTrue);
      expect(state.player.hand, hasLength(10));
      expect(state.player.deck, isEmpty);
      expect(state.logs.any((log) => log.contains('燃毁')), isTrue);
      controller.dispose();
    },
  );

  test('online controller renders a redacted authoritative snapshot', () async {
    final catalog = await loadCatalog();
    final preferredDeck = catalog
        .where((card) => card.faction == '曜光')
        .take(15)
        .expand((card) => [card.id, card.id])
        .toList();
    final client = MultiplayerClient()
      ..playerId = 'p-local'
      ..isHost = true;
    final controller = OnlineBattleController(
      catalog: catalog,
      client: client,
      preferredDeckIds: preferredDeck,
    );
    expect(controller.deckIds, preferredDeck);
    client.lastEvent = MultiplayerEvent(
      type: 'action',
      playerId: 'p-local',
      action: 'command',
      payload: {
        'state': {
          'version': 4,
          'turn': 2,
          'phase': 'main',
          'activePlayer': 0,
          'result': null,
          'players': [
            {
              'hero': {'health': 28},
              'hand': ['sun-dawn-scout'],
              'spellSchoolsPlayedThisTurn': ['construct', 'astral'],
              'spellSchoolsPlayedLastTurn': ['radiance'],
              'deathHistory': [
                {
                  'entityId': 'dead-1',
                  'cardId': 'sun-dawn-scout',
                  'name': '晨辉斥候',
                  'controller': 0,
                  'diedTurn': 1,
                  'deathOrder': 4,
                  'minionTypes': ['beast'],
                },
              ],
              'discardHistory': [
                {
                  'discardId': 'discard-1',
                  'cardId': 'void-season-spell-02',
                  'name': '夜鳍回响·02',
                  'player': 0,
                  'discardedTurn': 1,
                  'discardOrder': 6,
                },
              ],
              'board': [
                {
                  'entityId': 'u1',
                  'cardId': 'neutral-clockwork-beetle',
                  'attack': 3,
                  'health': 3,
                  'minionTypes': ['beast', 'construct'],
                  'hasAttacked': false,
                },
              ],
            },
            {
              'hero': {'health': 24},
              'hand': ['__hidden-card__', '__hidden-card__'],
              'deathHistory': [
                {
                  'entityId': 'dead-2',
                  'cardId': 'neutral-clockwork-beetle',
                  'name': '齿轮圣甲虫',
                  'controller': 1,
                  'diedTurn': 2,
                  'deathOrder': 5,
                  'minionTypes': ['beast', 'construct'],
                },
              ],
              'discardHistory': [
                {
                  'discardId': 'discard-2',
                  'cardId': 'void-blackwake-torpedo',
                  'name': '黑浪鱼雷',
                  'player': 1,
                  'discardedTurn': 2,
                  'discardOrder': 7,
                  'fragment': 'left',
                },
              ],
              'board': [],
            },
          ],
        },
      },
    );
    client.eventSequence = 1;
    client.notifyListeners();
    expect(controller.localHealth, 28);
    expect(controller.remoteHealth, 24);
    expect(controller.hand.single.id, 'sun-dawn-scout');
    expect(controller.localBoard.single.instanceId, 'u1');
    expect(controller.localBoard.single.minionTypes, ['beast', 'construct']);
    expect(controller.localSpellSchoolsThisTurn, ['construct', 'astral']);
    expect(controller.localSpellSchoolsLastTurn, ['radiance']);
    expect(controller.localDeathHistory.single.cardId, 'sun-dawn-scout');
    expect(controller.remoteDeathHistory.single.minionTypes, [
      'beast',
      'construct',
    ]);
    expect(
      controller.localDiscardHistory.single.cardId,
      'void-season-spell-02',
    );
    expect(controller.remoteDiscardHistory.single.fragment, 'left');
    expect(controller.canAct, isTrue);

    client.lastEvent = MultiplayerEvent(
      type: 'action',
      playerId: 'p-local',
      action: 'command',
      payload: {
        'state': {
          'version': 5,
          'turn': 2,
          'phase': 'discover',
          'activePlayer': 0,
          'result': null,
          'discover': {
            'player': 0,
            'sourceCardId': 'discover-card',
            'choices': ['sun-dawn-scout'],
          },
          'players': [
            {
              'hero': {'health': 28, 'armor': 1},
              'hand': ['sun-dawn-scout'],
              'board': [],
            },
            {
              'hero': {'health': 24, 'armor': 0},
              'hand': ['__hidden-card__'],
              'board': [],
            },
          ],
        },
      },
    );
    client.eventSequence = 2;
    client.notifyListeners();
    expect(controller.phase, 'discover');
    expect(controller.canChooseDiscover, isTrue);
    expect(controller.discoverChoices, ['sun-dawn-scout']);

    client.lastEvent = MultiplayerEvent(
      type: 'action',
      playerId: 'p-local',
      action: 'command',
      payload: {
        'state': {
          'version': 6,
          'turn': 2,
          'phase': 'choose-one',
          'activePlayer': 0,
          'result': null,
          'chooseOne': {
            'player': 0,
            'sourceCardId': 'neutral-season-08',
            'remainingChoices': 2,
            'sourceKind': 'hero-card',
            'options': [
              {'label': '护甲协议', 'effects': []},
              {'label': '抽取协议', 'effects': []},
            ],
          },
          'players': [
            {
              'hero': {'health': 28, 'armor': 12, 'name': '赤曜灭世者'},
              'heroAttackBonus': 5,
              'hand': ['generated-emberwing-matriarch'],
              'board': [],
            },
            {
              'hero': {'health': 24, 'armor': 0, 'name': '敌方英雄'},
              'hand': ['__hidden-card__'],
              'board': [],
            },
          ],
        },
      },
    );
    client.eventSequence = 3;
    client.notifyListeners();
    expect(controller.phase, 'choose-one');
    expect(controller.canChooseOne, isTrue);
    expect(controller.chooseOneOptions, hasLength(2));
    expect(controller.chooseOneRemaining, 2);
    expect(controller.chooseOneSourceKind, 'hero-card');
    expect(controller.localHeroName, '赤曜灭世者');
    expect(controller.remoteHeroName, '敌方英雄');
    expect(controller.localHeroAttackBonus, 5);
    expect(controller.hand.single.id, 'generated-emberwing-matriarch');
    controller.dispose();
    client.dispose();
  });

  test('online readiness carries the selected ranked format', () async {
    final catalog = await loadCatalog();
    final deck = [
      ...catalog.where(
        (card) => card.faction == '曜光' && card.setId == 'pegasus-2024',
      ),
      ...catalog.where(
        (card) =>
            card.faction == '曜光' &&
            cardAvailableInRankedFormat(card, RankedFormat.standard),
      ),
    ].take(15).expand((card) => [card.id, card.id]).toList();
    final client = _RecordingMultiplayerClient()..roomCode = 'A7KQ';
    final controller = OnlineBattleController(
      catalog: catalog,
      client: client,
      preferredDeckIds: deck,
      rankedFormat: RankedFormat.wild,
    );

    expect(controller.deckIds, deck);
    controller.ready();
    expect(client.actions, hasLength(1));
    expect(client.actions.single['action'], 'ready');
    final payload = client.actions.single['payload'] as Map<String, dynamic>;
    expect(payload['rankedFormat'], 'wild');
    expect(payload['deckIds'], deck);
    controller.dispose();
    client.dispose();
  });

  test(
    'online Prepare preserves hand-slot discount and sends its index',
    () async {
      final catalog = await loadCatalog();
      final preparable = catalog.firstWhere((card) => card.preparable);
      final client = _RecordingMultiplayerClient()
        ..playerId = 'p-local'
        ..isHost = true;
      final controller = OnlineBattleController(
        catalog: catalog,
        client: client,
      );

      void sync(int version, int mana, int reduction) {
        client.lastEvent = MultiplayerEvent(
          type: 'action',
          playerId: 'p-local',
          action: 'command',
          payload: {
            'state': {
              'version': version,
              'turn': 3,
              'phase': 'main',
              'activePlayer': 0,
              'players': [
                {
                  'hero': {'health': 30},
                  'mana': mana,
                  'maxMana': 3,
                  'hand': [preparable.id],
                  'handCostReductions': [reduction],
                  'board': [],
                },
                {
                  'hero': {'health': 30},
                  'hand': ['__hidden-card__'],
                  'handCostReductions': [0],
                  'board': [],
                },
              ],
            },
          },
        );
        client.eventSequence++;
        client.notifyListeners();
      }

      sync(1, 3, 0);
      expect(controller.hand.single.preparable, isTrue);
      expect(controller.handCost(0), 8);
      controller.prepareCard(preparable, handIndex: 0);
      final payload = client.actions.single['payload'] as Map<String, dynamic>;
      final command = payload['command'] as Map<String, dynamic>;
      expect(command['type'], 'prepare-card');
      expect(command['cardId'], preparable.id);
      expect(command['handIndex'], 0);

      sync(2, 0, 4);
      expect(controller.handCostReduction(0), 4);
      expect(controller.handCost(0), 4);
      controller.dispose();
      client.dispose();
    },
  );

  test('online Disguised sends the actor-relative enemy placement', () async {
    final catalog = await loadCatalog();
    final disguised = catalog.firstWhere((card) => card.disguised);
    final client = _RecordingMultiplayerClient()
      ..playerId = 'p-local'
      ..isHost = true;
    final controller = OnlineBattleController(catalog: catalog, client: client);
    client.lastEvent = MultiplayerEvent(
      type: 'action',
      playerId: 'p-local',
      action: 'command',
      payload: {
        'state': {
          'version': 1,
          'turn': 3,
          'phase': 'main',
          'activePlayer': 0,
          'players': [
            {
              'hero': {'health': 30},
              'mana': 3,
              'maxMana': 3,
              'hand': [disguised.id],
              'handCostReductions': [0],
              'board': [],
            },
            {
              'hero': {'health': 30},
              'hand': ['__hidden-card__'],
              'handCostReductions': [0],
              'board': [],
            },
          ],
        },
      },
    );
    client.eventSequence++;
    client.notifyListeners();

    controller.playCard(disguised, handIndex: 0, placement: 'enemy');

    final payload = client.actions.single['payload'] as Map<String, dynamic>;
    final command = payload['command'] as Map<String, dynamic>;
    expect(command['type'], 'play-card');
    expect(command['cardId'], disguised.id);
    expect(command['handIndex'], 0);
    expect(command['placement'], 'enemy');
    controller.dispose();
    client.dispose();
  });

  test(
    'online Shatter snapshot exposes fragment target and preserves hand index',
    () async {
      final catalog = await loadCatalog();
      final shatter = catalog.singleWhere(
        (card) => card.id == 'astral-lucid-script',
      );
      final client = _RecordingMultiplayerClient()
        ..playerId = 'p-local'
        ..isHost = true;
      final controller = OnlineBattleController(
        catalog: catalog,
        client: client,
      );
      client.lastEvent = MultiplayerEvent(
        type: 'action',
        playerId: 'p-local',
        action: 'command',
        payload: {
          'state': {
            'version': 1,
            'turn': 3,
            'phase': 'main',
            'activePlayer': 0,
            'players': [
              {
                'hero': {'health': 30},
                'mana': 2,
                'maxMana': 2,
                'hand': [shatter.id],
                'handCostReductions': [0],
                'handFragments': [
                  {'groupId': 'online-piece', 'piece': 'left'},
                ],
                'board': [],
              },
              {
                'hero': {'health': 30},
                'hand': ['__hidden-card__'],
                'handCostReductions': [0],
                'handFragments': [null],
                'board': [],
              },
            ],
          },
        },
      );
      client.eventSequence++;
      client.notifyListeners();

      final display = controller.handDisplayCard(0);
      expect(controller.handFragment(0)?.piece, 'left');
      expect(display.name, contains('左片'));
      expect(display.target, 'none');
      expect(display.effect.single['kind'], 'draw');
      controller.playCard(display, handIndex: 0);

      final payload = client.actions.single['payload'] as Map<String, dynamic>;
      final command = payload['command'] as Map<String, dynamic>;
      expect(command['type'], 'play-card');
      expect(command['cardId'], shatter.id);
      expect(command['handIndex'], 0);
      expect(command.containsKey('target'), isFalse);
      controller.dispose();
      client.dispose();
    },
  );

  test(
    'online projects Herald progress and synthetic Colossal tokens',
    () async {
      final catalog = await loadCatalog();
      final client = MultiplayerClient()
        ..playerId = 'p-local'
        ..isHost = true;
      final controller = OnlineBattleController(
        catalog: catalog,
        client: client,
      );
      client.lastEvent = MultiplayerEvent(
        type: 'action',
        playerId: 'p-local',
        action: 'command',
        payload: {
          'state': {
            'version': 1,
            'turn': 5,
            'phase': 'main',
            'activePlayer': 0,
            'players': [
              {
                'hero': {'health': 30},
                'heraldCount': 2,
                'hand': <String>[],
                'board': [
                  {
                    'entityId': 'synthetic-soldier',
                    'cardId': 'void-season-08-appendage-soldier',
                    'name': '深潮巨鳍士兵',
                    'attack': 4,
                    'health': 6,
                    'maxHealth': 6,
                    'keywords': ['lifesteal'],
                  },
                ],
              },
              {
                'hero': {'health': 30},
                'heraldCount': 4,
                'hand': <String>[],
                'board': <Object>[],
              },
            ],
          },
        },
      );
      client.eventSequence++;
      client.notifyListeners();

      expect(controller.localHeraldCount, 2);
      expect(controller.remoteHeraldCount, 4);
      expect(controller.localBoard, hasLength(1));
      expect(controller.localBoard.single.card.name, '深潮巨鳍士兵');
      expect(controller.localBoard.single.attack, 4);
      expect(controller.localBoard.single.keywords, contains('lifesteal'));
      controller.dispose();
      client.dispose();
    },
  );

  test(
    'online units project authoritative combat state and legal attacks',
    () async {
      final catalog = await loadCatalog();
      final preferredDeck = catalog
          .where((card) => card.faction == '曜光')
          .take(15)
          .expand((card) => [card.id, card.id])
          .toList();
      final client = _RecordingMultiplayerClient()
        ..playerId = 'p-local'
        ..isHost = true;
      final controller = OnlineBattleController(
        catalog: catalog,
        client: client,
        preferredDeckIds: preferredDeck,
      );
      client.lastEvent = MultiplayerEvent(
        type: 'action',
        playerId: 'p-local',
        action: 'command',
        payload: {
          'state': {
            'version': 8,
            'turn': 4,
            'phase': 'main',
            'activePlayer': 0,
            'result': null,
            'players': [
              {
                'hero': {'health': 30, 'armor': 0},
                'hand': ['sun-dawn-scout'],
                'board': [
                  {
                    'entityId': 'windfury-ready',
                    'cardId': 'void-nightfin-raider',
                    'attack': 3,
                    'health': 4,
                    'maxHealth': 5,
                    'keywords': ['windfury'],
                    'hasAttacked': true,
                    'attacksMade': 1,
                    'summoningSick': false,
                    'rushOnly': false,
                    'frozenTurns': 0,
                    'stars': 2,
                  },
                  {
                    'entityId': 'frozen-unit',
                    'cardId': 'sun-dawn-scout',
                    'attack': 2,
                    'health': 1,
                    'maxHealth': 1,
                    'keywords': ['charge'],
                    'hasAttacked': false,
                    'attacksMade': 0,
                    'summoningSick': false,
                    'frozenTurns': 1,
                  },
                  {
                    'entityId': 'rush-unit',
                    'cardId': 'sun-horizon-hunter',
                    'attack': 3,
                    'health': 2,
                    'maxHealth': 2,
                    'keywords': ['rush'],
                    'hasAttacked': false,
                    'attacksMade': 0,
                    'summoningSick': false,
                    'rushOnly': true,
                    'frozenTurns': 0,
                  },
                ],
                'mana': 5,
                'maxMana': 5,
              },
              {
                'hero': {'health': 30, 'armor': 0},
                'hand': ['__hidden-card__'],
                'board': [
                  {
                    'entityId': 'stealth-target',
                    'cardId': 'astral-eclipse-stalker',
                    'attack': 2,
                    'health': 3,
                    'maxHealth': 3,
                    'keywords': ['stealth'],
                    'stealthActive': true,
                  },
                  {
                    'entityId': 'taunt-target',
                    'cardId': 'neutral-caravan-guard',
                    'attack': 1,
                    'health': 4,
                    'maxHealth': 4,
                    'keywords': ['taunt'],
                  },
                ],
                'mana': 4,
                'maxMana': 4,
              },
            ],
          },
        },
      );
      client.eventSequence = 1;
      client.notifyListeners();

      final windfury = controller.localBoard[0];
      final frozen = controller.localBoard[1];
      final rush = controller.localBoard[2];
      final stealth = controller.remoteBoard[0];
      final taunt = controller.remoteBoard[1];
      expect(windfury.hasAttacked, isTrue);
      expect(windfury.attacksMade, 1);
      expect(windfury.hasWindfury, isTrue);
      expect(windfury.maxHealth, 5);
      expect(windfury.stars, 2);
      expect(windfury.canAttack, isTrue);
      expect(frozen.canAttack, isFalse);
      expect(stealth.stealthActive, isTrue);
      expect(controller.attackTargetsFor(windfury), [taunt]);
      expect(controller.canAttackHeroWith(windfury), isFalse);
      expect(controller.hasLegalAttackTarget(rush), isTrue);

      controller.attack(windfury);
      controller.attackUnit(windfury, stealth);
      controller.attack(rush);
      expect(client.actions, isEmpty);

      controller.attackUnit(windfury, taunt);
      expect(client.actions, hasLength(1));
      final payload = client.actions.single['payload'] as Map<String, dynamic>;
      final command = payload['command'] as Map<String, dynamic>;
      expect(command['type'], 'attack');
      expect(command['attackerId'], 'windfury-ready');
      expect(
        (command['target'] as Map<String, dynamic>)['entityId'],
        'taunt-target',
      );

      client.actions.clear();
      final directDamage = catalog.singleWhere(
        (card) => card.id == 'sun-focused-ray',
      );
      controller.hand = [directDamage];
      controller.playCard(directDamage, targetHero: true);
      final damagePayload =
          client.actions.single['payload'] as Map<String, dynamic>;
      final damageCommand = damagePayload['command'] as Map<String, dynamic>;
      expect(damageCommand['type'], 'play-card');
      expect((damageCommand['target'] as Map<String, dynamic>)['player'], 1);

      client.actions.clear();
      controller.remoteBoard = [];
      expect(controller.hasLegalAttackTarget(rush), isFalse);
      controller.dispose();
      client.dispose();
    },
  );

  test('battle rules enforce taunt, shield and hero power', () {
    CardDefinition unit(
      String id,
      String name,
      String faction,
      int cost,
      int attack,
      int health,
      List<String> keywords,
    ) {
      return CardDefinition(
        id: id,
        name: name,
        description: keywords.join('、'),
        faction: faction,
        type: 'unit',
        cost: cost,
        rarity: '普通',
        attack: attack,
        health: health,
        keywords: keywords,
      );
    }

    final charge = unit('sun-charge', '冲锋斥候', '曜光', 1, 4, 2, ['charge']);
    final taunt = unit('void-taunt', '逆流卫士', '幽潮', 2, 2, 5, [
      'taunt',
      'shield',
    ]);
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [charge, taunt]
      ..deckIds.addAll(List.filled(30, charge.id));
    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    state.ai.heroHealth = 30;
    state.player.mana = 10;
    state.player.hand
      ..clear()
      ..add(charge);
    state.ai.board.add(
      BattleUnit(
        instanceId: 'enemy-1',
        card: taunt,
        owner: 'ai',
        attack: 2,
        health: 5,
        maxHealth: 5,
        divineShield: true,
      ),
    );
    final attacker = BattleUnit(
      instanceId: 'player-1',
      card: charge,
      owner: 'player',
      attack: 4,
      health: 2,
      maxHealth: 2,
    );
    state.player.board.add(attacker);

    expect(controller.attack(attacker), isFalse);
    expect(controller.attack(attacker, target: state.ai.board.first), isTrue);
    expect(state.ai.board.first.divineShield, isFalse);
    expect(state.ai.board.first.health, 5);
    expect(controller.useHeroPower(targetHero: true), isTrue);
    expect(state.player.heroHealth, 30);
    controller.dispose();
  });

  test('mobile hero powers follow their faction and target rules', () {
    CardDefinition factionCard(String id, String faction) => CardDefinition(
      id: id,
      name: id,
      description: '阵营测试单位',
      faction: faction,
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 2,
      health: 4,
    );
    final moss = factionCard('neutral-moss-runner', '中立');

    GameController launch(String faction) {
      final card = factionCard('hero-$faction', faction);
      final controller = GameController(startingPlayer: 'player')
        ..catalog = [card, moss]
        ..deckIds.addAll(List.filled(30, card.id));
      controller.startBattle();
      controller.confirmMulligan();
      controller.battle!.player.mana = 10;
      controller.battle!.ai.hand.clear();
      return controller;
    }

    final radiance = launch('曜光');
    final radianceState = radiance.battle!;
    radianceState.player.heroHealth = 25;
    expect(radianceState.playerHeroPower.name, '日耀修复');
    expect(radiance.useHeroPower(targetHero: true), isTrue);
    expect(radianceState.player.heroHealth, 27);
    radiance.dispose();

    final tide = launch('幽潮');
    final tideState = tide.battle!;
    expect(tideState.playerHeroPower.name, '潮汐脉冲');
    expect(tide.useHeroPower(), isTrue);
    expect(tideState.ai.heroHealth, 29);
    tide.dispose();

    final ember = launch('烬火');
    final emberState = ember.battle!;
    final emberTarget = BattleUnit(
      instanceId: 'ember-target',
      card: moss,
      owner: 'ai',
      attack: 1,
      health: 4,
      maxHealth: 4,
    );
    emberState.ai.board.add(emberTarget);
    expect(ember.useHeroPower(target: emberTarget), isTrue);
    expect(emberTarget.health, 2);
    ember.dispose();

    final astral = launch('星穹');
    final astralState = astral.battle!;
    astralState.player.hand.clear();
    astralState.player.deck
      ..clear()
      ..add(moss);
    expect(astral.useHeroPower(), isTrue);
    expect(astralState.player.hand, hasLength(1));
    astral.dispose();

    final verdant = launch('苍林');
    final verdantState = verdant.battle!;
    verdantState.player.board.clear();
    expect(verdant.useHeroPower(), isTrue);
    expect(verdantState.player.board.single.card.id, 'neutral-moss-runner');
    verdant.dispose();

    final storm = launch('雷铸');
    final stormState = storm.battle!;
    expect(storm.useHeroPower(), isTrue);
    expect(stormState.player.armor, 2);
    storm.dispose();
  });

  test(
    'battle keywords support rush, windfury, poisonous, freeze, deathrattle and reborn',
    () {
      CardDefinition unit(
        String id,
        String name,
        List<String> keywords, {
        int attack = 2,
        int health = 6,
        List<Map<String, dynamic>> onDeath = const [],
      }) {
        return CardDefinition(
          id: id,
          name: name,
          description: keywords.join('、'),
          faction: '中立',
          type: 'unit',
          cost: 1,
          rarity: '普通',
          attack: attack,
          health: health,
          keywords: keywords,
          onDeath: onDeath,
        );
      }

      final rush = unit('rush', '突袭斥候', ['rush']);
      final windfury = unit('windfury', '双刃猎手', ['windfury'], attack: 1);
      final poisonous = unit('poisonous', '剧毒甲虫', ['poisonous'], attack: 1);
      final reborn = unit('reborn', '灰烬重生体', ['reborn'], health: 1);
      final deathrattle = unit(
        'deathrattle',
        '亡语守卫',
        ['deathrattle'],
        health: 1,
        onDeath: [
          {'kind': 'summon', 'cardId': 'token', 'count': 1},
        ],
      );
      final token = unit('token', '亡语余烬', [], attack: 1, health: 1);
      final freeze = CardDefinition(
        id: 'freeze',
        name: '寒潮锁定',
        description: '冻结一个敌方单位。',
        faction: '中立',
        type: 'spell',
        cost: 1,
        rarity: '普通',
        target: 'enemy-unit',
        effect: [
          {'kind': 'freeze', 'amount': 1},
        ],
      );

      final controller = GameController(startingPlayer: 'player')
        ..catalog = [
          rush,
          windfury,
          poisonous,
          reborn,
          deathrattle,
          token,
          freeze,
        ]
        ..deckIds.addAll(List.filled(30, rush.id));
      controller.startBattle();
      controller.confirmMulligan();
      final state = controller.battle!;
      state.player.mana = 10;
      state.ai.board.clear();

      final rushUnit = BattleUnit(
        instanceId: 'rush-1',
        card: rush,
        owner: 'player',
        attack: 2,
        health: 6,
        maxHealth: 6,
        summoningSick: false,
        rushOnly: true,
      );
      final target = BattleUnit(
        instanceId: 'target-1',
        card: token,
        owner: 'ai',
        attack: 1,
        health: 8,
        maxHealth: 8,
      );
      state.player.board.add(rushUnit);
      state.ai.board.add(target);
      expect(controller.attack(rushUnit), isFalse);
      expect(controller.attack(rushUnit, target: target), isTrue);

      final windUnit = BattleUnit(
        instanceId: 'wind-1',
        card: windfury,
        owner: 'player',
        attack: 1,
        health: 6,
        maxHealth: 6,
        summoningSick: false,
      );
      state.player.board.add(windUnit);
      expect(controller.attack(windUnit, target: target), isTrue);
      expect(controller.attack(windUnit, target: target), isTrue);
      expect(controller.attack(windUnit, target: target), isFalse);

      final venom = BattleUnit(
        instanceId: 'venom-1',
        card: poisonous,
        owner: 'player',
        attack: 1,
        health: 6,
        maxHealth: 6,
        summoningSick: false,
      );
      final largeTarget = BattleUnit(
        instanceId: 'large-target',
        card: token,
        owner: 'ai',
        attack: 1,
        health: 8,
        maxHealth: 8,
      );
      state.player.board.add(venom);
      state.ai.board.add(largeTarget);
      expect(controller.attack(venom, target: largeTarget), isTrue);
      expect(state.ai.board.contains(largeTarget), isFalse);

      final frozen = BattleUnit(
        instanceId: 'freeze-target',
        card: token,
        owner: 'ai',
        attack: 1,
        health: 5,
        maxHealth: 5,
      );
      state.ai.board.add(frozen);
      state.player.hand.add(freeze);
      expect(controller.playCard(freeze, target: frozen), isTrue);
      expect(frozen.frozenTurns, 1);

      final deathTarget = BattleUnit(
        instanceId: 'death-target',
        card: deathrattle,
        owner: 'ai',
        attack: 0,
        health: 1,
        maxHealth: 1,
      );
      final finisher = BattleUnit(
        instanceId: 'finisher',
        card: poisonous,
        owner: 'player',
        attack: 2,
        health: 6,
        maxHealth: 6,
        summoningSick: false,
      );
      state.player.board.add(finisher);
      state.ai.board.add(deathTarget);
      expect(controller.attack(finisher, target: deathTarget), isTrue);
      expect(state.ai.board.any((unit) => unit.card.id == token.id), isTrue);

      final rebornTarget = BattleUnit(
        instanceId: 'reborn-target',
        card: reborn,
        owner: 'ai',
        attack: 0,
        health: 1,
        maxHealth: 1,
      );
      final rebornKiller = BattleUnit(
        instanceId: 'reborn-killer',
        card: poisonous,
        owner: 'player',
        attack: 2,
        health: 6,
        maxHealth: 6,
        summoningSick: false,
      );
      state.player.board.add(rebornKiller);
      state.ai.board.add(rebornTarget);
      expect(controller.attack(rebornKiller, target: rebornTarget), isTrue);
      expect(state.ai.board.any((unit) => unit.card.id == reborn.id), isTrue);
      expect(
        state.ai.board.where((unit) => unit.card.id == reborn.id).single.health,
        1,
      );
      controller.dispose();
    },
  );

  test(
    'fury only reacts to combat damage and random effects can hit stealth',
    () {
      CardDefinition unit(
        String id,
        String name,
        List<String> keywords, {
        int attack = 2,
        int health = 6,
      }) {
        return CardDefinition(
          id: id,
          name: name,
          description: keywords.join('、'),
          faction: '中立',
          type: 'unit',
          cost: 1,
          rarity: '普通',
          attack: attack,
          health: health,
          keywords: keywords,
        );
      }

      final fury = unit('fury-test', '激昂守卫', ['fury'], attack: 2, health: 8);
      final attacker = unit('combat-test', '交战者', [], attack: 1, health: 5);
      final stealth = unit('stealth-test', '隐匿目标', ['stealth']);
      final spell = CardDefinition(
        id: 'fury-spell-test',
        name: '远程脉冲',
        description: '对一个敌方单位造成 1 点伤害。',
        faction: '中立',
        type: 'spell',
        cost: 1,
        rarity: '普通',
        target: 'enemy-unit',
        effect: [
          {'kind': 'damage', 'amount': 1},
        ],
      );
      final randomFreeze = CardDefinition(
        id: 'random-freeze-test',
        name: '随机寒潮',
        description: '随机冻结一个敌方单位。',
        faction: '中立',
        type: 'spell',
        cost: 1,
        rarity: '普通',
        effect: [
          {'kind': 'random-enemy-freeze', 'amount': 1},
        ],
      );

      final controller = GameController(startingPlayer: 'player')
        ..catalog = [fury, attacker, stealth, spell, randomFreeze]
        ..deckIds.addAll(List.filled(30, fury.id));
      controller.startBattle();
      controller.confirmMulligan();
      final state = controller.battle!;
      state.player.mana = 10;
      state.player.hand
        ..clear()
        ..add(randomFreeze);
      final stealthTarget = BattleUnit(
        instanceId: 'stealth-target',
        card: stealth,
        owner: 'ai',
        attack: 1,
        health: 4,
        maxHealth: 4,
      );
      stealthTarget.stealthActive = true;
      state.ai.board
        ..clear()
        ..add(stealthTarget);
      expect(controller.playCard(randomFreeze), isTrue);
      expect(stealthTarget.frozenTurns, 1);

      final furyTarget = BattleUnit(
        instanceId: 'fury-target',
        card: fury,
        owner: 'ai',
        attack: 2,
        health: 8,
        maxHealth: 8,
      );
      final combatAttacker = BattleUnit(
        instanceId: 'combat-attacker',
        card: attacker,
        owner: 'player',
        attack: 1,
        health: 5,
        maxHealth: 5,
        summoningSick: false,
      );
      state.ai.board
        ..clear()
        ..add(furyTarget);
      state.player.board.add(combatAttacker);
      state.player.hand.add(spell);
      expect(controller.playCard(spell, target: furyTarget), isTrue);
      expect(furyTarget.health, 7);
      expect(furyTarget.furyTriggered, isFalse);
      expect(furyTarget.attack, 2);

      expect(controller.attack(combatAttacker, target: furyTarget), isTrue);
      expect(furyTarget.furyTriggered, isTrue);
      expect(furyTarget.attack, 3);
      controller.dispose();
    },
  );

  test('mobile freeze remains through an already-used attack', () async {
    final card = CardDefinition(
      id: 'freeze-rule-unit',
      name: '冻结规则单位',
      description: '测试冻结时序',
      faction: '中立',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 2,
      health: 4,
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [card]
      ..deckIds.addAll(List.filled(30, card.id));
    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    state.ai.hand.clear();
    state.ai.board.clear();
    state.ai.deck.clear();
    final frozen = BattleUnit(
      instanceId: 'freeze-rule-target',
      card: card,
      owner: 'player',
      attack: 2,
      health: 4,
      maxHealth: 4,
      summoningSick: false,
      attacksMade: 1,
      hasAttacked: true,
      frozenTurns: 1,
    );
    state.player.board
      ..clear()
      ..add(frozen);

    await controller.endTurn();
    expect(frozen.frozenTurns, 1);
    expect(frozen.freezeBlocked, isTrue);
    expect(frozen.canAttack, isFalse);

    await controller.endTurn();
    expect(frozen.frozenTurns, 0);
    expect(frozen.freezeBlocked, isFalse);
    expect(frozen.canAttack, isTrue);
    controller.dispose();
  });

  test(
    'mobile Windfury freeze consumes the remaining attack this turn',
    () async {
      final card = CardDefinition(
        id: 'windfury-freeze-rule-unit',
        name: '风怒冻结规则单位',
        description: '测试风怒冻结时序',
        faction: '中立',
        type: 'unit',
        cost: 1,
        rarity: '普通',
        attack: 2,
        health: 4,
        keywords: ['windfury'],
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = [card]
        ..deckIds.addAll(List.filled(30, card.id));
      controller.startBattle();
      controller.confirmMulligan();
      final state = controller.battle!;
      state.ai.hand.clear();
      state.ai.board.clear();
      state.ai.deck.clear();
      final frozen = BattleUnit(
        instanceId: 'windfury-freeze-target',
        card: card,
        owner: 'player',
        attack: 2,
        health: 4,
        maxHealth: 4,
        summoningSick: false,
        attacksMade: 1,
        hasAttacked: true,
        frozenTurns: 1,
      );
      state.player.board
        ..clear()
        ..add(frozen);

      await controller.endTurn();
      expect(frozen.frozenTurns, 0);
      expect(frozen.freezeBlocked, isFalse);
      expect(frozen.attacksMade, 0);
      expect(frozen.canAttack, isTrue);
      controller.dispose();
    },
  );

  test(
    'discover pauses the match and secret counters an enemy spell',
    () async {
      final choice = CardDefinition(
        id: 'discover-choice',
        name: '发现候选',
        description: '候选卡牌',
        faction: '曜光',
        type: 'unit',
        cost: 1,
        rarity: '普通',
        attack: 1,
        health: 1,
      );
      final discover = CardDefinition(
        id: 'discover-card',
        name: '星图勘探',
        description: '发现一张卡牌。',
        faction: '曜光',
        type: 'spell',
        cost: 1,
        rarity: '稀有',
        keywords: ['discover'],
        effect: [
          {
            'kind': 'discover',
            'choices': [choice.id],
          },
        ],
      );
      final secret = CardDefinition(
        id: 'counter-secret',
        name: '虚空反制',
        description: '奥秘：反制敌方战术。',
        faction: '幽潮',
        type: 'spell',
        cost: 1,
        rarity: '史诗',
        keywords: ['secret'],
        effect: [
          {
            'kind': 'secret',
            'secretId': 'counter-secret',
            'trigger': 'opponent-plays-spell',
            'effect': {'kind': 'counterspell'},
          },
        ],
      );
      final enemySpell = CardDefinition(
        id: 'enemy-spell',
        name: '敌方战术',
        description: '造成伤害。',
        faction: '幽潮',
        type: 'spell',
        cost: 1,
        rarity: '普通',
        effect: [
          {'kind': 'damage', 'amount': 4},
        ],
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = [choice, discover, secret, enemySpell]
        ..deckIds.addAll(List.filled(30, discover.id));
      controller.startBattle();
      controller.confirmMulligan();
      final state = controller.battle!;
      state.player.mana = 10;
      state.player.hand
        ..clear()
        ..add(discover);
      expect(controller.playCard(discover), isTrue);
      expect(state.phase, 'discover');
      expect(state.discoverChoices, [choice.id]);
      expect(controller.chooseDiscover(choice.id), isTrue);
      expect(state.phase, 'main');
      expect(state.player.hand.any((card) => card.id == choice.id), isTrue);

      state.player.hand
        ..clear()
        ..add(secret);
      expect(controller.playCard(secret), isTrue);
      expect(state.player.secrets.single.secretId, 'counter-secret');
      state.ai.hand
        ..clear()
        ..add(enemySpell);
      state.ai.mana = 10;
      final beforeHealth = state.player.heroHealth;
      await controller.endTurn();
      expect(state.player.heroHealth, beforeHealth);
      expect(state.player.secrets, isEmpty);
      expect(state.logs.any((log) => log.contains('反制')), isTrue);
      controller.dispose();
    },
  );

  test('choose-one and start-of-turn triggers resolve on mobile', () async {
    final branchCard = CardDefinition(
      id: 'branch-card',
      name: '分支战术',
      description: '抉择：获得护甲或抽牌。',
      faction: '曜光',
      type: 'spell',
      cost: 1,
      rarity: '稀有',
      effect: [
        {
          'kind': 'choose-one',
          'options': [
            {
              'label': '护甲协议',
              'effects': [
                {'kind': 'armor', 'amount': 2},
              ],
            },
            {
              'label': '抽取协议',
              'effects': [
                {'kind': 'draw', 'count': 1},
              ],
            },
          ],
        },
      ],
    );
    final triggerUnit = CardDefinition(
      id: 'trigger-unit',
      name: '回合守望者',
      description: '回合开始时获得护甲。',
      faction: '曜光',
      type: 'unit',
      cost: 1,
      rarity: '普通',
      attack: 1,
      health: 3,
      onTurnStart: [
        {'kind': 'armor', 'amount': 1},
      ],
    );
    final controller = GameController(startingPlayer: 'player')
      ..catalog = [branchCard, triggerUnit]
      ..deckIds.addAll(List.filled(30, branchCard.id));
    controller.startBattle();
    controller.confirmMulligan();
    final state = controller.battle!;
    state.ai.hand.clear();
    state.player.mana = 10;
    state.player.hand
      ..clear()
      ..add(branchCard);
    expect(controller.playCard(branchCard), isTrue);
    expect(state.phase, 'choose-one');
    expect(state.chooseOneOptions, hasLength(2));
    expect(controller.chooseOne(0), isTrue);
    expect(state.phase, 'main');
    expect(state.player.armor, 2);

    state.player.board.add(
      BattleUnit(
        instanceId: 'turn-trigger-1',
        card: triggerUnit,
        owner: 'player',
        attack: 1,
        health: 3,
        maxHealth: 3,
        summoningSick: false,
      ),
    );
    await controller.endTurn();
    expect(state.player.armor, greaterThanOrEqualTo(3));
    controller.dispose();
  });

  test(
    'mobile Hero Card transforms, replaces its power and attacks without a weapon',
    () async {
      final catalog = await loadCatalog();
      final heroCard = catalog.singleWhere(
        (card) => card.id == 'neutral-season-08',
      );
      final filler = catalog.firstWhere(
        (card) => card.isUnit && card.cost <= 2 && card.rarity != '传说',
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = catalog
        ..deckIds.addAll(List.filled(30, filler.id));
      controller.startBattle();
      await controller.confirmMulligan();
      final state = controller.battle!;
      state.player.hand
        ..clear()
        ..add(heroCard);
      state.player.handCostReductions
        ..clear()
        ..add(0);
      state.player.handFragments
        ..clear()
        ..add(null);
      state.player.mana = 12;
      state.ai.heroHealth = 30;
      state.ai.board.clear();

      expect(controller.playCard(heroCard), isTrue);
      expect(state.player.heroName, '赤曜灭世者');
      expect(state.player.armor, 12);
      expect(state.playerHeroPower.name, '残酷撕裂');
      expect(state.phase, 'choose-one');
      expect(state.chooseOneRemaining, 1);
      expect(state.chooseOneSourceKind, 'hero-card');

      final summonIndex = state.chooseOneOptions.indexWhere(
        (option) => option['label']?.toString().contains('龙裔君临') ?? false,
      );
      expect(controller.chooseOne(summonIndex), isTrue);
      expect(state.phase, 'main');
      expect(state.player.board.single.attack, 12);
      expect(controller.useHeroPower(), isTrue);
      expect(state.player.heroAttackBonus, 5);
      expect(state.player.weapon, isNull);
      expect(controller.heroAttack(targetHero: true), isTrue);
      expect(state.ai.heroHealth, 25);
      controller.dispose();
    },
  );

  test(
    'two mobile Heralds grant two unique Cataclysms and one-cost dragon draws',
    () async {
      final catalog = await loadCatalog();
      final heroCard = catalog.singleWhere(
        (card) => card.id == 'neutral-season-08',
      );
      final filler = catalog.firstWhere(
        (card) => card.isUnit && card.cost <= 2 && card.rarity != '传说',
      );
      final controller = GameController(startingPlayer: 'player')
        ..catalog = catalog
        ..deckIds.addAll(List.filled(30, filler.id));
      controller.startBattle();
      await controller.confirmMulligan();
      final state = controller.battle!;
      state.player.heraldCount = 2;
      state.player.deck.clear();
      state.player.deckCostOverrides.clear();
      state.player.hand
        ..clear()
        ..add(heroCard);
      state.player.handCostReductions
        ..clear()
        ..add(0);
      state.player.handFragments
        ..clear()
        ..add(null);
      state.player.mana = 10;

      expect(controller.playCard(heroCard), isTrue);
      expect(state.chooseOneRemaining, 2);
      final shuffleIndex = state.chooseOneOptions.indexWhere(
        (option) => option['label']?.toString().contains('役龙') ?? false,
      );
      final chosenLabel = state.chooseOneOptions[shuffleIndex]['label'];
      expect(controller.chooseOne(shuffleIndex), isTrue);
      expect(state.phase, 'choose-one');
      expect(state.chooseOneRemaining, 1);
      expect(state.chooseOneOptions, hasLength(3));
      expect(
        state.chooseOneOptions.any((option) => option['label'] == chosenLabel),
        isFalse,
      );
      expect(state.player.deck, hasLength(5));
      expect(
        state.player.deck.every((card) => card.id.startsWith('generated-')),
        isTrue,
      );
      expect(state.player.deckCostOverrides, everyElement(1));

      expect(controller.chooseOne(0), isTrue);
      expect(state.phase, 'main');
      await controller.endTurn();
      final generatedIndex = state.player.hand.indexWhere(
        (card) => card.id.startsWith('generated-'),
      );
      expect(generatedIndex, greaterThanOrEqualTo(0));
      expect(controller.playerHandCost(generatedIndex), 1);
      controller.dispose();
    },
  );

  testWidgets('app shows the loading shell before catalog initialization', (
    tester,
  ) async {
    await tester.pumpWidget(
      AstraProtocolApp(controller: GameController(startingPlayer: 'player')),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('new deck detects and offers a valid clipboard deck code', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = (await tester.runAsync(loadCatalog))!;
    final ids = catalog
        .where(
          (card) =>
              card.faction == '曜光' &&
              card.rarity != '传说' &&
              cardAvailableInRankedFormat(card, RankedFormat.standard),
        )
        .take(15)
        .expand((card) => [card.id, card.id])
        .toList();
    final controller = GameController()
      ..catalog = catalog
      ..isLoading = false
      ..deckIds.addAll(ids);
    for (final id in ids) {
      controller.collection[id] = 2;
    }
    await controller.saveDeck();
    final clipboardShare = formatDeckShareText(
      format: RankedFormat.wild,
      name: '剪贴板狂野',
      cardIds: ids,
      catalog: catalog,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, Object?>{'text': clipboardShare};
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(AstraProtocolApp(controller: controller));
    await tester.tap(find.text('卡组'));
    await tester.pump();
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();

    expect(find.text('检测到卡组代码'), findsOneWidget);
    expect(find.textContaining('剪贴板狂野'), findsOneWidget);
    expect(find.text('导入剪贴板牌组'), findsOneWidget);
    await tester.tap(find.text('导入剪贴板牌组'));
    await tester.pumpAndSettle();
    expect(controller.activeDeckId, isNull);
    expect(controller.deckName, '剪贴板狂野');
    expect(controller.deckFormat, RankedFormat.wild);
    expect(controller.deckIds, ids);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('deck workshop exposes the 27-slot mobile library controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final catalog = (await tester.runAsync(loadCatalog))!;
    final ids = catalog
        .where((card) => card.faction == '曜光')
        .take(15)
        .expand((card) => [card.id, card.id])
        .toList();
    final controller = GameController()
      ..catalog = catalog
      ..isLoading = false
      ..deckIds.addAll(ids);
    for (final id in ids) {
      controller.collection[id] = 2;
    }
    await controller.saveDeck();
    final extra = catalog.firstWhere(
      (card) =>
          card.faction == '曜光' && card.rarity != '传说' && !ids.contains(card.id),
    );
    controller.collection[extra.id] = 2;
    controller.collection[ids.first] = 0;

    await tester.pumpWidget(AstraProtocolApp(controller: controller));
    await tester.tap(find.text('卡组'));
    await tester.pump();

    expect(find.text('本机牌组库'), findsOneWidget);
    expect(find.text('1 / 27 栏位'), findsOneWidget);
    expect(find.text('新建'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('复制牌表'), findsOneWidget);
    expect(find.text('智能补全'), findsOneWidget);
    expect(find.text('推荐牌组配方'), findsOneWidget);
    expect(find.byKey(const ValueKey('deck-recipe-faction')), findsOneWidget);
    expect(find.text('套用此配方'), findsNWidgets(3));
    expect(find.text('导入代码'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.byKey(const ValueKey('deck-format-selector')), findsOneWidget);
    expect(find.text('缺少 2 张卡牌'), findsOneWidget);
    expect(find.textContaining('点击建议'), findsOneWidget);
    final battleButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '投入演算'),
    );
    expect(battleButton.onPressed, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

class _RecordingMultiplayerClient extends MultiplayerClient {
  final List<Map<String, Object?>> actions = <Map<String, Object?>>[];

  @override
  void sendAction(String action, [Map<String, dynamic>? payload]) {
    actions.add(<String, Object?>{
      'action': action,
      'payload': payload ?? <String, dynamic>{},
    });
  }
}

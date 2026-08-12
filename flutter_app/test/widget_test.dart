import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:astra_protocol/game/game_controller.dart';
import 'package:astra_protocol/main.dart';
import 'package:astra_protocol/models/card_definition.dart';
import 'package:astra_protocol/network/multiplayer_client.dart';

void main() {
  test('card definition parses the catalog schema', () {
    final card = CardDefinition.fromJson({
      'id': 'sun-test',
      'name': '曙光测试',
      'description': '测试卡牌',
      'faction': '曜光',
      'type': 'unit',
      'cost': 2,
      'rarity': '稀有',
      'attack': 3,
      'health': 4,
      'keywords': ['护盾'],
      'traits': ['晨辉'],
    });

    expect(card.name, '曙光测试');
    expect(card.isUnit, isTrue);
    expect(card.attack, 3);
    expect(card.keywords, contains('护盾'));
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
    final controller = GameController()
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
    final controller = GameController()
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
    final controller = GameController()
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
      final controller = GameController()
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
      state.player.mana = 2;
      expect(controller.tradeCard(tradeCard), isTrue);
      expect(state.player.mana, 1);
      expect(state.player.hand, isNotEmpty);
      controller.dispose();
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
    final controller = GameController()
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
    expect(controller.useHeroPower(), isTrue);
    expect(state.ai.heroHealth, 28);
    controller.dispose();
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

      final controller = GameController()
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
      final controller = GameController()
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

  testWidgets('app shows the loading shell before catalog initialization', (
    tester,
  ) async {
    await tester.pumpWidget(AstraProtocolApp(controller: GameController()));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}

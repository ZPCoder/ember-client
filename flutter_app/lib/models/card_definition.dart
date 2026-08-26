class CardDefinition {
  const CardDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.faction,
    required this.type,
    required this.cost,
    required this.rarity,
    this.setId = 'core',
    this.attack,
    this.health,
    this.durability,
    this.overload = 0,
    this.tradeable = false,
    this.preparable = false,
    this.spellDamage = 0,
    this.keywords = const [],
    this.traits = const [],
    this.school,
    this.target,
    this.combo = const [],
    this.onTurnStart = const [],
    this.onTurnEnd = const [],
    this.onSpellPlayed = const [],
    this.onPlay = const [],
    this.onDeath = const [],
    this.effect = const [],
  });

  final String id;
  final String name;
  final String description;
  final String faction;
  final String type;
  final int cost;
  final String rarity;
  final String setId;
  final int? attack;
  final int? health;
  final int? durability;
  final int overload;
  final bool tradeable;
  final bool preparable;
  final int spellDamage;
  final List<String> keywords;
  final List<String> traits;
  final String? school;
  final String? target;
  final List<Map<String, dynamic>> combo;
  final List<Map<String, dynamic>> onTurnStart;
  final List<Map<String, dynamic>> onTurnEnd;
  final List<Map<String, dynamic>> onSpellPlayed;
  final List<Map<String, dynamic>> onPlay;
  final List<Map<String, dynamic>> onDeath;
  final List<Map<String, dynamic>> effect;

  bool get isUnit => type == 'unit';
  bool get hasBattlecry => keywords.contains('battlecry') || onPlay.isNotEmpty;
  bool get hasDeathrattle =>
      keywords.contains('deathrattle') || onDeath.isNotEmpty;

  CardDefinition copyWith({
    String? description,
    List<String>? keywords,
    String? target,
    List<Map<String, dynamic>>? combo,
    List<Map<String, dynamic>>? onTurnStart,
    List<Map<String, dynamic>>? onTurnEnd,
    List<Map<String, dynamic>>? onSpellPlayed,
    List<Map<String, dynamic>>? onPlay,
    List<Map<String, dynamic>>? onDeath,
    List<Map<String, dynamic>>? effect,
  }) {
    return CardDefinition(
      id: id,
      name: name,
      description: description ?? this.description,
      faction: faction,
      type: type,
      cost: cost,
      rarity: rarity,
      setId: setId,
      attack: attack,
      health: health,
      durability: durability,
      overload: overload,
      tradeable: tradeable,
      preparable: preparable,
      spellDamage: spellDamage,
      keywords: keywords ?? this.keywords,
      traits: traits,
      school: school,
      target: target ?? this.target,
      combo: combo ?? this.combo,
      onTurnStart: onTurnStart ?? this.onTurnStart,
      onTurnEnd: onTurnEnd ?? this.onTurnEnd,
      onSpellPlayed: onSpellPlayed ?? this.onSpellPlayed,
      onPlay: onPlay ?? this.onPlay,
      onDeath: onDeath ?? this.onDeath,
      effect: effect ?? this.effect,
    );
  }

  factory CardDefinition.fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? value) => value is List
        ? value.map((item) => item.toString()).toList(growable: false)
        : const [];
    List<Map<String, dynamic>> effects(Object? value) => value is List
        ? value
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : const [];

    return CardDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      faction: json['faction'] as String,
      type: json['type'] as String,
      cost: (json['cost'] as num?)?.toInt() ?? 0,
      rarity: json['rarity'] as String? ?? '普通',
      setId: json['set'] as String? ?? 'core',
      attack: (json['attack'] as num?)?.toInt(),
      health: (json['health'] as num?)?.toInt(),
      durability: (json['durability'] as num?)?.toInt(),
      overload: (json['overload'] as num?)?.toInt() ?? 0,
      tradeable: json['tradeable'] == true,
      preparable:
          json['preparable'] == true ||
          strings(json['keywords']).contains('prepare'),
      spellDamage: (json['spellDamage'] as num?)?.toInt() ?? 0,
      keywords: strings(json['keywords']),
      traits: strings(json['traits']),
      school: json['school'] as String?,
      target: json['target'] as String?,
      combo: effects(json['combo']),
      onTurnStart: effects(json['onTurnStart']),
      onTurnEnd: effects(json['onTurnEnd']),
      onSpellPlayed: effects(json['onSpellPlayed']),
      onPlay: effects(json['onPlay']),
      onDeath: effects(json['onDeath']),
      effect: effects(json['effect']),
    );
  }
}

class HeroPowerDefinition {
  const HeroPowerDefinition({
    required this.id,
    required this.faction,
    required this.name,
    required this.description,
    required this.cost,
    this.target,
    required this.effect,
  });

  final String id;
  final String faction;
  final String name;
  final String description;
  final int cost;
  final String? target;
  final Map<String, dynamic> effect;
}

class BattleUnit {
  BattleUnit({
    required this.instanceId,
    required this.card,
    required this.owner,
    required this.attack,
    required this.health,
    required this.maxHealth,
    this.hasAttacked = false,
    this.stars = 1,
    this.divineShield = false,
    this.furyTriggered = false,
    this.attacksMade = 0,
    this.summoningSick = false,
    this.rushOnly = false,
    this.stealthActive = false,
    this.frozenTurns = 0,
    this.freezeBlocked = false,
    this.rebornUsed = false,
    this.permanentAttackBonus = 0,
    this.permanentHealthBonus = 0,
    this.temporaryAttackBonus = 0,
    this.temporaryHealthBonus = 0,
    this.silenced = false,
  });

  final String instanceId;
  final CardDefinition card;
  final String owner;
  int attack;
  int health;
  int maxHealth;
  bool hasAttacked;
  int stars;
  bool divineShield;
  bool furyTriggered;
  int attacksMade;
  bool summoningSick;
  bool rushOnly;
  bool stealthActive;
  int frozenTurns;

  /// True when Freeze has consumed this unit's current-turn attack.
  bool freezeBlocked;
  bool rebornUsed;
  int permanentAttackBonus;
  int permanentHealthBonus;
  int temporaryAttackBonus;
  int temporaryHealthBonus;
  bool silenced;

  bool get hasTaunt => !silenced && card.keywords.contains('taunt');
  bool get hasLifesteal => !silenced && card.keywords.contains('lifesteal');
  bool get hasFury => !silenced && card.keywords.contains('fury');
  bool get hasCharge => !silenced && card.keywords.contains('charge');
  bool get hasRush => !silenced && card.keywords.contains('rush');
  bool get hasWindfury => !silenced && card.keywords.contains('windfury');
  bool get hasPoisonous => !silenced && card.keywords.contains('poisonous');
  bool get hasStealth => !silenced && card.keywords.contains('stealth');
  bool get hasReborn => !silenced && card.keywords.contains('reborn');
  bool get isFrozen => frozenTurns > 0;
  int get attackLimit => hasWindfury ? 2 : 1;
  bool get canAttack =>
      !summoningSick && !isFrozen && attacksMade < attackLimit;
}

class BattleSide {
  BattleSide({
    required this.heroHealth,
    required this.maxHeroHealth,
    required this.mana,
    required this.maxMana,
    this.armor = 0,
    this.fatigue = 0,
    required this.deck,
    required this.hand,
    List<int>? handCostReductions,
    required this.board,
    this.coinAvailable = false,
    this.weapon,
    this.overloadLocked = 0,
    List<BattleSecret>? secrets,
  }) : handCostReductions = handCostReductions ?? <int>[],
       secrets = secrets ?? <BattleSecret>[];

  int heroHealth;
  final int maxHeroHealth;
  int mana;
  int maxMana;
  int armor;
  int fatigue;
  final List<CardDefinition> deck;
  final List<CardDefinition> hand;
  final List<int> handCostReductions;
  final List<BattleUnit> board;
  bool coinAvailable;
  BattleWeapon? weapon;
  int overloadLocked;
  int cardsPlayedThisTurn = 0;
  bool heroHasAttacked = false;
  final List<BattleSecret> secrets;
}

class BattleWeapon {
  BattleWeapon({
    required this.card,
    required this.attack,
    required this.durability,
    required this.maxDurability,
  });

  final CardDefinition card;
  int attack;
  int durability;
  final int maxDurability;
}

class BattleSecret {
  BattleSecret({
    required this.card,
    required this.secretId,
    required this.trigger,
    required this.effect,
  });

  final CardDefinition card;
  final String secretId;
  final String trigger;
  final Map<String, dynamic> effect;
}

class BattleState {
  BattleState({
    required this.player,
    required this.ai,
    required this.playerHeroPower,
    required this.aiHeroPower,
    required this.turn,
    required this.activePlayer,
    required this.logs,
    this.phase = 'main',
    this.heroPowerUsed = false,
    this.turnSecondsLeft = 75,
    this.finished = false,
    this.winner,
    this.endReason,
    this.actionWindow = 1,
    this.aiFaction = '幽潮',
    Set<int>? mulliganSelected,
    List<String>? discoverChoices,
    List<Map<String, dynamic>>? chooseOneOptions,
  }) : mulliganSelected = mulliganSelected ?? <int>{},
       discoverChoices = discoverChoices ?? <String>[],
       chooseOneOptions = chooseOneOptions ?? <Map<String, dynamic>>[];

  final BattleSide player;
  final BattleSide ai;
  final HeroPowerDefinition playerHeroPower;
  final HeroPowerDefinition aiHeroPower;
  int turn;
  String activePlayer;
  String phase;
  bool heroPowerUsed;
  bool aiHeroPowerUsed = false;
  int playerTurnsStarted = 0;
  int aiTurnsStarted = 0;
  bool playerHeroMarkedForDeath = false;
  bool aiHeroMarkedForDeath = false;
  int turnSecondsLeft;
  final List<String> logs;
  bool finished;
  String? winner;
  String? endReason;
  int actionWindow;
  String aiFaction;
  bool mulliganDone = false;
  final Set<int> mulliganSelected;
  List<String> discoverChoices;
  String? discoverSource;
  String discoverOwner = 'player';
  List<Map<String, dynamic>> chooseOneOptions;
  String? chooseOneSource;
  String chooseOneOwner = 'player';
  BattleUnit? chooseOneTarget;
  BattleFxEvent? fx;
  int fxSequence = 0;
}

class BattleFxEvent {
  const BattleFxEvent({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.sequence,
    this.sourceId,
    this.targetId,
    this.amount,
  });

  final String kind;
  final String title;
  final String subtitle;
  final int icon;
  final int color;
  final int sequence;
  final String? sourceId;
  final String? targetId;
  final int? amount;
}

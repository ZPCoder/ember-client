class CardDefinition {
  const CardDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.faction,
    required this.type,
    required this.cost,
    required this.rarity,
    this.attack,
    this.health,
    this.durability,
    this.overload = 0,
    this.tradeable = false,
    this.spellDamage = 0,
    this.keywords = const [],
    this.traits = const [],
    this.school,
    this.target,
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
  final int? attack;
  final int? health;
  final int? durability;
  final int overload;
  final bool tradeable;
  final int spellDamage;
  final List<String> keywords;
  final List<String> traits;
  final String? school;
  final String? target;
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
      attack: attack,
      health: health,
      durability: durability,
      overload: overload,
      tradeable: tradeable,
      spellDamage: spellDamage,
      keywords: keywords ?? this.keywords,
      traits: traits,
      school: school,
      target: target ?? this.target,
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
      attack: (json['attack'] as num?)?.toInt(),
      health: (json['health'] as num?)?.toInt(),
      durability: (json['durability'] as num?)?.toInt(),
      overload: (json['overload'] as num?)?.toInt() ?? 0,
      tradeable: json['tradeable'] == true,
      spellDamage: (json['spellDamage'] as num?)?.toInt() ?? 0,
      keywords: strings(json['keywords']),
      traits: strings(json['traits']),
      school: json['school'] as String?,
      target: json['target'] as String?,
      onPlay: effects(json['onPlay']),
      onDeath: effects(json['onDeath']),
      effect: effects(json['effect']),
    );
  }
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
    this.rebornUsed = false,
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
  bool rebornUsed;

  bool get hasTaunt => card.keywords.contains('taunt');
  bool get hasLifesteal => card.keywords.contains('lifesteal');
  bool get hasFury => card.keywords.contains('fury');
  bool get hasCharge => card.keywords.contains('charge');
  bool get hasRush => card.keywords.contains('rush');
  bool get hasWindfury => card.keywords.contains('windfury');
  bool get hasPoisonous => card.keywords.contains('poisonous');
  bool get hasStealth => card.keywords.contains('stealth');
  bool get hasReborn => card.keywords.contains('reborn');
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
    required this.board,
    this.coinAvailable = false,
    this.weapon,
    this.overloadLocked = 0,
    List<BattleSecret>? secrets,
  }) : secrets = secrets ?? <BattleSecret>[];

  int heroHealth;
  final int maxHeroHealth;
  int mana;
  int maxMana;
  int armor;
  int fatigue;
  final List<CardDefinition> deck;
  final List<CardDefinition> hand;
  final List<BattleUnit> board;
  bool coinAvailable;
  BattleWeapon? weapon;
  int overloadLocked;
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
    required this.turn,
    required this.activePlayer,
    required this.logs,
    this.phase = 'main',
    this.heroPowerUsed = false,
    this.turnSecondsLeft = 75,
    this.finished = false,
    this.winner,
    this.aiFaction = '幽潮',
    Set<int>? mulliganSelected,
    List<String>? discoverChoices,
  }) : mulliganSelected = mulliganSelected ?? <int>{},
       discoverChoices = discoverChoices ?? <String>[];

  final BattleSide player;
  final BattleSide ai;
  int turn;
  String activePlayer;
  String phase;
  bool heroPowerUsed;
  int turnSecondsLeft;
  final List<String> logs;
  bool finished;
  String? winner;
  String aiFaction;
  bool mulliganDone = false;
  final Set<int> mulliganSelected;
  List<String> discoverChoices;
  String? discoverSource;
  String discoverOwner = 'player';
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

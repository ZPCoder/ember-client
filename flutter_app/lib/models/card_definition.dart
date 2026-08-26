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
    this.bribe = false,
    this.disguised = false,
    this.shatter,
    this.herald,
    this.colossal,
    this.heroCard,
    this.collectible = true,
    this.spellDamage = 0,
    this.keywords = const [],
    this.traits = const [],
    this.minionTypes = const [],
    this.school,
    this.target,
    this.combo = const [],
    this.onTurnStart = const [],
    this.onTurnEnd = const [],
    this.onSpellPlayed = const [],
    this.onDiscard = const [],
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
  final bool bribe;
  final bool disguised;
  final Map<String, dynamic>? shatter;
  final Map<String, dynamic>? herald;
  final Map<String, dynamic>? colossal;
  final Map<String, dynamic>? heroCard;
  final bool collectible;
  final int spellDamage;
  final List<String> keywords;
  final List<String> traits;
  final List<String> minionTypes;
  final String? school;
  final String? target;
  final List<Map<String, dynamic>> combo;
  final List<Map<String, dynamic>> onTurnStart;
  final List<Map<String, dynamic>> onTurnEnd;
  final List<Map<String, dynamic>> onSpellPlayed;
  final List<Map<String, dynamic>> onDiscard;
  final List<Map<String, dynamic>> onPlay;
  final List<Map<String, dynamic>> onDeath;
  final List<Map<String, dynamic>> effect;

  bool get isUnit => type == 'unit';
  bool get isHero => type == 'hero';
  bool get hasShatter => shatter != null;
  bool get hasHerald => herald != null;
  bool get hasColossal => colossal != null;
  bool get hasBattlecry => keywords.contains('battlecry') || onPlay.isNotEmpty;
  bool get hasDeathrattle =>
      keywords.contains('deathrattle') || onDeath.isNotEmpty;

  CardDefinition copyWith({
    String? name,
    String? description,
    List<String>? keywords,
    List<String>? minionTypes,
    String? target,
    List<Map<String, dynamic>>? combo,
    List<Map<String, dynamic>>? onTurnStart,
    List<Map<String, dynamic>>? onTurnEnd,
    List<Map<String, dynamic>>? onSpellPlayed,
    List<Map<String, dynamic>>? onDiscard,
    List<Map<String, dynamic>>? onPlay,
    List<Map<String, dynamic>>? onDeath,
    List<Map<String, dynamic>>? effect,
    Map<String, dynamic>? shatter,
    Map<String, dynamic>? herald,
    Map<String, dynamic>? colossal,
    Map<String, dynamic>? heroCard,
  }) {
    return CardDefinition(
      id: id,
      name: name ?? this.name,
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
      bribe: bribe,
      disguised: disguised,
      shatter: shatter ?? this.shatter,
      herald: herald ?? this.herald,
      colossal: colossal ?? this.colossal,
      heroCard: heroCard ?? this.heroCard,
      collectible: collectible,
      spellDamage: spellDamage,
      keywords: keywords ?? this.keywords,
      traits: traits,
      minionTypes: minionTypes ?? this.minionTypes,
      school: school,
      target: target ?? this.target,
      combo: combo ?? this.combo,
      onTurnStart: onTurnStart ?? this.onTurnStart,
      onTurnEnd: onTurnEnd ?? this.onTurnEnd,
      onSpellPlayed: onSpellPlayed ?? this.onSpellPlayed,
      onDiscard: onDiscard ?? this.onDiscard,
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
      bribe:
          json['bribe'] == true || strings(json['keywords']).contains('bribe'),
      disguised:
          json['disguised'] == true ||
          strings(json['keywords']).contains('disguised'),
      shatter: json['shatter'] is Map
          ? Map<String, dynamic>.from(json['shatter'] as Map)
          : null,
      herald: json['herald'] is Map
          ? Map<String, dynamic>.from(json['herald'] as Map)
          : null,
      colossal: json['colossal'] is Map
          ? Map<String, dynamic>.from(json['colossal'] as Map)
          : null,
      heroCard: json['heroCard'] is Map
          ? Map<String, dynamic>.from(json['heroCard'] as Map)
          : null,
      collectible: json['collectible'] != false,
      spellDamage: (json['spellDamage'] as num?)?.toInt() ?? 0,
      keywords: strings(json['keywords']),
      traits: strings(json['traits']),
      minionTypes: strings(json['minionTypes']),
      school: json['school'] as String?,
      target: json['target'] as String?,
      combo: effects(json['combo']),
      onTurnStart: effects(json['onTurnStart']),
      onTurnEnd: effects(json['onTurnEnd']),
      onSpellPlayed: effects(json['onSpellPlayed']),
      onDiscard: effects(json['onDiscard']),
      onPlay: effects(json['onPlay']),
      onDeath: effects(json['onDeath']),
      effect: effects(json['effect']),
    );
  }
}

class HandFragment {
  const HandFragment({required this.groupId, required this.piece});

  final String groupId;
  final String piece;

  bool get isLeft => piece == 'left';
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
  String owner;
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

class BattleDeathRecord {
  const BattleDeathRecord({
    required this.entityId,
    required this.cardId,
    required this.name,
    required this.controller,
    required this.diedTurn,
    required this.deathOrder,
    this.minionTypes = const <String>[],
  });

  final String entityId;
  final String cardId;
  final String name;
  final int controller;
  final int diedTurn;
  final int deathOrder;
  final List<String> minionTypes;
}

class BattleDiscardRecord {
  const BattleDiscardRecord({
    required this.discardId,
    required this.cardId,
    required this.name,
    required this.player,
    required this.discardedTurn,
    required this.discardOrder,
    this.fragment,
  });

  final String discardId;
  final String cardId;
  final String name;
  final int player;
  final int discardedTurn;
  final int discardOrder;
  final String? fragment;
}

class BattleSide {
  BattleSide({
    required this.faction,
    required this.heroHealth,
    required this.maxHeroHealth,
    required this.mana,
    required this.maxMana,
    this.armor = 0,
    this.fatigue = 0,
    required this.deck,
    List<int?>? deckCostOverrides,
    List<bool>? deckStartedInDeck,
    required this.hand,
    List<int>? handCostReductions,
    List<HandFragment?>? handFragments,
    List<bool>? handStartedInDeck,
    required this.board,
    this.coinAvailable = false,
    this.weapon,
    this.overloadLocked = 0,
    this.heraldCount = 0,
    this.heroId = 'faction-commander',
    this.heroName = '远征指挥官',
    this.heroAttackBonus = 0,
    List<String>? spellSchoolsPlayedThisTurn,
    List<String>? spellSchoolsPlayedLastTurn,
    List<String>? spellsPlayedThisGame,
    List<bool>? spellsPlayedFromStartingDeck,
    this.nonDeckSpellRecastUsed = false,
    List<BattleDeathRecord>? deathHistory,
    List<BattleDiscardRecord>? discardHistory,
    List<BattleSecret>? secrets,
  }) : deckCostOverrides = List<int?>.from(deckCostOverrides ?? const <int?>[]),
       deckStartedInDeck = List<bool>.from(
         deckStartedInDeck ?? List<bool>.filled(deck.length, true),
       ),
       handCostReductions = handCostReductions ?? <int>[],
       handFragments = handFragments ?? <HandFragment?>[],
       handStartedInDeck = List<bool>.from(
         handStartedInDeck ?? List<bool>.filled(hand.length, true),
       ),
       spellSchoolsPlayedThisTurn = spellSchoolsPlayedThisTurn ?? <String>[],
       spellSchoolsPlayedLastTurn = spellSchoolsPlayedLastTurn ?? <String>[],
       spellsPlayedThisGame = spellsPlayedThisGame ?? <String>[],
       spellsPlayedFromStartingDeck = spellsPlayedFromStartingDeck ?? <bool>[],
       deathHistory = deathHistory ?? <BattleDeathRecord>[],
       discardHistory = discardHistory ?? <BattleDiscardRecord>[],
       secrets = secrets ?? <BattleSecret>[];

  final String faction;
  int heroHealth;
  final int maxHeroHealth;
  int mana;
  int maxMana;
  int armor;
  int fatigue;
  final List<CardDefinition> deck;
  final List<int?> deckCostOverrides;
  final List<bool> deckStartedInDeck;
  final List<CardDefinition> hand;
  final List<int> handCostReductions;
  final List<HandFragment?> handFragments;
  final List<bool> handStartedInDeck;
  final List<BattleUnit> board;
  bool coinAvailable;
  BattleWeapon? weapon;
  int overloadLocked;
  int heraldCount;
  String heroId;
  String heroName;
  int heroAttackBonus;
  int cardsPlayedThisTurn = 0;
  final List<String> spellSchoolsPlayedThisTurn;
  final List<String> spellSchoolsPlayedLastTurn;
  final List<String> spellsPlayedThisGame;
  final List<bool> spellsPlayedFromStartingDeck;
  bool nonDeckSpellRecastUsed;
  final List<BattleDeathRecord> deathHistory;
  final List<BattleDiscardRecord> discardHistory;
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
    List<int>? discoverCostReductions,
    List<String?>? discoverFragments,
    List<Map<String, dynamic>>? chooseOneOptions,
  }) : mulliganSelected = mulliganSelected ?? <int>{},
       discoverChoices = discoverChoices ?? <String>[],
       discoverCostReductions = discoverCostReductions ?? <int>[],
       discoverFragments = discoverFragments ?? <String?>[],
       chooseOneOptions = chooseOneOptions ?? <Map<String, dynamic>>[];

  final BattleSide player;
  final BattleSide ai;
  HeroPowerDefinition playerHeroPower;
  HeroPowerDefinition aiHeroPower;
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
  List<int> discoverCostReductions;
  List<String?> discoverFragments;
  String? discoverSource;
  String discoverOwner = 'player';
  String? discoverCopiedFrom;
  List<Map<String, dynamic>> chooseOneOptions;
  String? chooseOneSource;
  String chooseOneOwner = 'player';
  BattleUnit? chooseOneTarget;
  int chooseOneRemaining = 1;
  String chooseOneSourceKind = 'spell';
  final List<String> chooseOneChosenLabels = <String>[];
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

import '../models/card_definition.dart';

// A small evergreen rules layer keeps the generated card art/catalog stable
// while giving the battle client real Hearthstone-style archetypes to play.
// The overrides are intentionally distributed across all seven factions so
// every starter matchup exposes more than just attack/health keywords.
const _extraKeywords = <String, List<String>>{
  'sun-horizon-hunter': ['rush'],
  'sun-zenith-golem': ['deathrattle'],
  'void-nightfin-raider': ['windfury'],
  'void-ink-storm': ['freeze'],
  'neutral-repair-sprite': ['poisonous'],
  'neutral-stonehorn': ['reborn'],
  'ember-ashwing-phoenix': ['reborn', 'deathrattle'],
  'ember-crimson-duelist': ['windfury'],
  'astral-eclipse-stalker': ['stealth'],
  'verdant-ancient-bough-guardian': ['deathrattle'],
  'verdant-seedvault-engineer': ['reborn'],
};

const _deathEffects = <String, List<Map<String, dynamic>>>{
  'sun-zenith-golem': [
    {'kind': 'summon', 'cardId': 'sun-dawn-scout', 'count': 1},
  ],
  'ember-ashwing-phoenix': [
    {'kind': 'armor', 'amount': 1},
  ],
  'verdant-ancient-bough-guardian': [
    {'kind': 'summon', 'cardId': 'verdant-seedsong-sprite', 'count': 1},
  ],
};

CardDefinition enrichCardRules(CardDefinition card) {
  final keywords = <String>{...card.keywords};
  keywords.addAll(_extraKeywords[card.id] ?? const []);
  if (card.onPlay.isNotEmpty) keywords.add('battlecry');
  final onDeath = <Map<String, dynamic>>[
    ...card.onDeath,
    ...(_deathEffects[card.id] ?? const []),
  ];
  if (onDeath.isNotEmpty) keywords.add('deathrattle');

  var effects = card.effect;
  if (card.id == 'void-ink-storm') {
    effects = [
      ...effects,
      {'kind': 'random-enemy-freeze', 'amount': 1},
    ];
  }

  return card.copyWith(
    keywords: keywords.toList(growable: false),
    onDeath: onDeath,
    effect: effects,
  );
}

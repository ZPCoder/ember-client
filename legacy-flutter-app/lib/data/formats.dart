import '../models/card_definition.dart';

enum RankedFormat { standard, wild }

extension RankedFormatDetails on RankedFormat {
  String get wireValue => switch (this) {
    RankedFormat.standard => 'standard',
    RankedFormat.wild => 'wild',
  };

  String get label => switch (this) {
    RankedFormat.standard => '标准',
    RankedFormat.wild => '狂野',
  };

  String get fullLabel => '$label模式';

  String get description => switch (this) {
    RankedFormat.standard => '核心系列、猛禽年与圣甲虫年',
    RankedFormat.wild => '全部系列，包括已轮换的飞马年',
  };
}

RankedFormat rankedFormatFromWire(String? value) =>
    value == RankedFormat.wild.wireValue
    ? RankedFormat.wild
    : RankedFormat.standard;

class CardSetDefinition {
  const CardSetDefinition({
    required this.id,
    required this.label,
    required this.year,
    required this.standard,
  });

  final String id;
  final String label;
  final int? year;
  final bool standard;
}

const cardSetDefinitions = <String, CardSetDefinition>{
  'core': CardSetDefinition(
    id: 'core',
    label: '核心系列',
    year: null,
    standard: true,
  ),
  'raptor-2025': CardSetDefinition(
    id: 'raptor-2025',
    label: '猛禽年',
    year: 2025,
    standard: true,
  ),
  'scarab-2026': CardSetDefinition(
    id: 'scarab-2026',
    label: '圣甲虫年',
    year: 2026,
    standard: true,
  ),
  'pegasus-2024': CardSetDefinition(
    id: 'pegasus-2024',
    label: '飞马年',
    year: 2024,
    standard: false,
  ),
};

CardSetDefinition cardSetDefinition(String setId) =>
    cardSetDefinitions[setId] ?? cardSetDefinitions['core']!;

bool cardAvailableInRankedFormat(CardDefinition card, RankedFormat format) {
  if (format == RankedFormat.wild) return true;
  return cardSetDefinitions[card.setId]?.standard == true;
}

int rankedFormatCardCount(
  Iterable<CardDefinition> catalog,
  RankedFormat format,
) => catalog.where((card) => cardAvailableInRankedFormat(card, format)).length;

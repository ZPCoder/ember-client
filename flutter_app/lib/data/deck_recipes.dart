import '../models/card_definition.dart';
import 'deck_replacements.dart';
import 'formats.dart';

enum DeckRecipeKind { core, raptor, scarab }

class DeckRecipe {
  const DeckRecipe({
    required this.id,
    required this.kind,
    required this.faction,
    required this.name,
    required this.description,
    required this.format,
    required this.focusSetId,
    required this.cardIds,
  });

  final String id;
  final DeckRecipeKind kind;
  final String faction;
  final String name;
  final String description;
  final RankedFormat format;
  final String focusSetId;
  final List<String> cardIds;
}

const _recipeDefinitions =
    <
      ({
        DeckRecipeKind kind,
        String focusSetId,
        List<String> allowedSetIds,
        String nameSuffix,
        String description,
      })
    >[
      (
        kind: DeckRecipeKind.core,
        focusSetId: 'core',
        allowedSetIds: ['core'],
        nameSuffix: '核心基石',
        description: '仅由核心系列组成，提供稳定曲线与通用战术。',
      ),
      (
        kind: DeckRecipeKind.raptor,
        focusSetId: 'raptor-2025',
        allowedSetIds: ['core', 'raptor-2025'],
        nameSuffix: '猛禽攻势',
        description: '围绕猛禽年卡牌构筑，并用核心系列补足协同。',
      ),
      (
        kind: DeckRecipeKind.scarab,
        focusSetId: 'scarab-2026',
        allowedSetIds: ['core', 'raptor-2025', 'scarab-2026'],
        nameSuffix: '圣甲虫新锐',
        description: '聚焦圣甲虫年新卡，调用当前标准卡池完成配合。',
      ),
    ];

DeckRecipe _buildRecipe(
  String faction,
  ({
    DeckRecipeKind kind,
    String focusSetId,
    List<String> allowedSetIds,
    String nameSuffix,
    String description,
  })
  definition,
  List<CardDefinition> catalog,
) {
  final allowed = catalog
      .where(
        (card) =>
            definition.allowedSetIds.contains(card.setId) &&
            (card.faction == faction || card.faction == '中立'),
      )
      .toList(growable: false);
  final focusCards = allowed
      .where(
        (card) =>
            card.faction == faction && card.setId == definition.focusSetId,
      )
      .take(12)
      .toList(growable: false);
  final collection = {
    for (final card in allowed) card.id: card.rarity == '传说' ? 1 : 2,
  };
  final completion = completeDeckFromCollection(
    cardIds: focusCards.map((card) => card.id).toList(growable: false),
    collection: collection,
    format: RankedFormat.standard,
    catalog: allowed,
  );
  return DeckRecipe(
    id: '$faction-${definition.kind.name}',
    kind: definition.kind,
    faction: faction,
    name: '$faction${definition.nameSuffix}',
    description: definition.description,
    format: RankedFormat.standard,
    focusSetId: definition.focusSetId,
    cardIds: completion.cardIds,
  );
}

List<DeckRecipe> deckRecipesForFaction(
  String faction,
  List<CardDefinition> catalog,
) {
  if (faction == '中立') return const [];
  return _recipeDefinitions
      .map((definition) => _buildRecipe(faction, definition, catalog))
      .toList(growable: false);
}

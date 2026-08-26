import '../models/card_definition.dart';
import 'formats.dart';

class MissingDeckCard {
  const MissingDeckCard({
    required this.cardId,
    required this.requiredCount,
    required this.ownedCount,
  });

  final String cardId;
  final int requiredCount;
  final int ownedCount;

  int get missingCount => requiredCount - ownedCount;
}

List<MissingDeckCard> findMissingDeckCards(
  List<String> cardIds,
  Map<String, int> collection,
) {
  final required = <String, int>{};
  for (final cardId in cardIds) {
    required[cardId] = (required[cardId] ?? 0) + 1;
  }
  return [
    for (final entry in required.entries)
      if ((collection[entry.key] ?? 0) < entry.value)
        MissingDeckCard(
          cardId: entry.key,
          requiredCount: entry.value,
          ownedCount: (collection[entry.key] ?? 0).clamp(0, entry.value),
        ),
  ];
}

List<CardDefinition> suggestDeckReplacements({
  required List<String> cardIds,
  required String missingCardId,
  required Map<String, int> collection,
  required RankedFormat format,
  required List<CardDefinition> catalog,
  int limit = 3,
}) {
  final byId = {for (final card in catalog) card.id: card};
  final target = byId[missingCardId];
  final targetIndex = cardIds.lastIndexOf(missingCardId);
  if (target == null || targetIndex < 0 || limit <= 0) return const [];

  final counts = <String, int>{};
  for (final cardId in cardIds) {
    counts[cardId] = (counts[cardId] ?? 0) + 1;
  }
  final targetKeywords = target.keywords.toSet();
  final targetTraits = target.traits.toSet();
  final ranked = <({CardDefinition card, int score})>[];

  for (final candidate in catalog) {
    if (candidate.id == missingCardId ||
        !cardAvailableInRankedFormat(candidate, format)) {
      continue;
    }
    final currentCopies = counts[candidate.id] ?? 0;
    final ownedCopies = (collection[candidate.id] ?? 0).clamp(0, 2);
    final copyLimit = candidate.rarity == '传说' ? 1 : 2;
    if (currentCopies >= (ownedCopies < copyLimit ? ownedCopies : copyLimit)) {
      continue;
    }

    final replaced = List<String>.from(cardIds);
    replaced[targetIndex] = candidate.id;
    if (!_validDeckShape(replaced, format, byId)) continue;

    final sharedKeywords = candidate.keywords
        .where(targetKeywords.contains)
        .length;
    final sharedTraits = candidate.traits.where(targetTraits.contains).length;
    final score =
        160 -
        (candidate.cost - target.cost).abs() * 18 +
        (candidate.type == target.type ? 46 : 0) +
        (candidate.faction == target.faction ? 20 : 0) +
        (candidate.rarity == target.rarity ? 6 : 0) +
        sharedKeywords * 12 +
        sharedTraits * 10;
    ranked.add((card: candidate, score: score));
  }

  ranked.sort((left, right) {
    final score = right.score.compareTo(left.score);
    if (score != 0) return score;
    final cost = left.card.cost.compareTo(right.card.cost);
    if (cost != 0) return cost;
    return left.card.id.compareTo(right.card.id);
  });
  return ranked.take(limit).map((item) => item.card).toList(growable: false);
}

bool _validDeckShape(
  List<String> cardIds,
  RankedFormat format,
  Map<String, CardDefinition> byId,
) {
  if (cardIds.length != 30) return false;
  final factions = <String>{};
  final counts = <String, int>{};
  for (final cardId in cardIds) {
    final card = byId[cardId];
    if (card == null || !cardAvailableInRankedFormat(card, format)) {
      return false;
    }
    if (card.faction != '中立') factions.add(card.faction);
    if (factions.length > 1) return false;
    counts[cardId] = (counts[cardId] ?? 0) + 1;
    if (counts[cardId]! > (card.rarity == '传说' ? 1 : 2)) return false;
  }
  return true;
}

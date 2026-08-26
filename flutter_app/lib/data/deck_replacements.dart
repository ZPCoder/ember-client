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

class DeckCompletionResult {
  const DeckCompletionResult({
    required this.cardIds,
    required this.addedCardIds,
    required this.faction,
  });

  final List<String> cardIds;
  final List<String> addedCardIds;
  final String? faction;
}

const _smartCurveTargets = [2, 5, 6, 5, 4, 3, 3, 2];
const _smartTypeTargets = {'unit': 18, 'spell': 10, 'weapon': 2};

int _smartCurveBucket(int cost) => cost.clamp(0, 7);

DeckCompletionResult completeDeckFromCollection({
  required List<String> cardIds,
  required Map<String, int> collection,
  required RankedFormat format,
  required List<CardDefinition> catalog,
}) {
  final original = List<String>.from(cardIds);
  final byId = {for (final card in catalog) card.id: card};
  final counts = <String, int>{};
  final factions = <String>{};

  DeckCompletionResult unchanged() => DeckCompletionResult(
    cardIds: original,
    addedCardIds: const [],
    faction: factions.length == 1 ? factions.first : null,
  );

  if (original.length > 30) return unchanged();
  for (final cardId in original) {
    final card = byId[cardId];
    if (card == null || !cardAvailableInRankedFormat(card, format)) {
      return unchanged();
    }
    final nextCount = (counts[cardId] ?? 0) + 1;
    final copyLimit = card.rarity == '传说' ? 1 : 2;
    final owned = (collection[cardId] ?? 0).clamp(0, copyLimit);
    if (nextCount > owned) return unchanged();
    counts[cardId] = nextCount;
    if (card.faction != '中立') factions.add(card.faction);
  }
  if (factions.length > 1) return unchanged();

  String? faction = factions.length == 1 ? factions.first : null;
  if (faction == null) {
    final factionCapacity = <String, int>{};
    for (final card in catalog) {
      if (card.faction == '中立' || !cardAvailableInRankedFormat(card, format)) {
        continue;
      }
      final copyLimit = card.rarity == '传说' ? 1 : 2;
      final owned = (collection[card.id] ?? 0).clamp(0, copyLimit);
      factionCapacity[card.faction] =
          (factionCapacity[card.faction] ?? 0) + owned;
    }
    var bestCapacity = 0;
    for (final entry in factionCapacity.entries) {
      if (entry.value > bestCapacity) {
        faction = entry.key;
        bestCapacity = entry.value;
      }
    }
  }

  final completed = List<String>.from(original);
  final addedCardIds = <String>[];
  final curveCounts = List<int>.filled(8, 0);
  final typeCounts = {'unit': 0, 'spell': 0, 'weapon': 0};
  final keywordCounts = <String, int>{};
  final traitCounts = <String, int>{};

  void registerCard(CardDefinition card) {
    curveCounts[_smartCurveBucket(card.cost)] += 1;
    typeCounts[card.type] = (typeCounts[card.type] ?? 0) + 1;
    for (final keyword in card.keywords) {
      keywordCounts[keyword] = (keywordCounts[keyword] ?? 0) + 1;
    }
    for (final trait in card.traits) {
      traitCounts[trait] = (traitCounts[trait] ?? 0) + 1;
    }
  }

  for (final cardId in completed) {
    registerCard(byId[cardId]!);
  }

  while (completed.length < 30) {
    CardDefinition? bestCard;
    int? bestScore;
    for (final card in catalog) {
      if (!cardAvailableInRankedFormat(card, format) ||
          (card.faction != '中立' && card.faction != faction)) {
        continue;
      }
      final currentCopies = counts[card.id] ?? 0;
      final copyLimit = card.rarity == '传说' ? 1 : 2;
      final owned = (collection[card.id] ?? 0).clamp(0, copyLimit);
      if (currentCopies >= owned) continue;

      final bucket = _smartCurveBucket(card.cost);
      final curveNeed = _smartCurveTargets[bucket] - curveCounts[bucket];
      final typeNeed =
          (_smartTypeTargets[card.type] ?? 0) - (typeCounts[card.type] ?? 0);
      final keywordSynergy = card.keywords.fold<int>(
        0,
        (score, keyword) => score + (keywordCounts[keyword] ?? 0).clamp(0, 4),
      );
      final traitSynergy = card.traits.fold<int>(
        0,
        (score, trait) => score + (traitCounts[trait] ?? 0).clamp(0, 4),
      );
      final score =
          curveNeed * 22 +
          typeNeed * 6 +
          keywordSynergy * 8 +
          traitSynergy * 10 +
          (currentCopies > 0 ? 14 : 0) +
          (card.faction == faction ? 4 : 0);
      if (bestCard == null ||
          score > bestScore! ||
          (score == bestScore &&
              (card.cost < bestCard.cost ||
                  (card.cost == bestCard.cost &&
                      card.id.compareTo(bestCard.id) < 0)))) {
        bestCard = card;
        bestScore = score;
      }
    }
    if (bestCard == null) break;
    completed.add(bestCard.id);
    addedCardIds.add(bestCard.id);
    counts[bestCard.id] = (counts[bestCard.id] ?? 0) + 1;
    registerCard(bestCard);
  }

  return DeckCompletionResult(
    cardIds: completed,
    addedCardIds: addedCardIds,
    faction: faction,
  );
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

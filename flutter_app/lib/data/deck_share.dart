import '../models/card_definition.dart';
import 'deck_code.dart';
import 'formats.dart';

String formatDeckShareText({
  required RankedFormat format,
  required String name,
  required List<String> cardIds,
  required Iterable<CardDefinition> catalog,
}) {
  final code = encodeDeckCode(format: format, name: name, cardIds: cardIds);
  final normalized = decodeDeckCode(code);
  final cardsById = {for (final card in catalog) card.id: card};
  final counts = <String, int>{};
  for (final cardId in normalized.cardIds) {
    counts[cardId] = (counts[cardId] ?? 0) + 1;
  }
  final cards = counts.entries.toList()
    ..sort((a, b) {
      final aCard = cardsById[a.key];
      final bCard = cardsById[b.key];
      final costDifference =
          (aCard?.cost ?? 0x3fffffff) - (bCard?.cost ?? 0x3fffffff);
      return costDifference != 0 ? costDifference : a.key.compareTo(b.key);
    });

  return [
    '# 余烬协议牌组：${normalized.name}',
    '# 模式：${normalized.format?.fullLabel ?? format.fullLabel}',
    '# ${normalized.cardIds.length} 张卡牌 · ${cards.length} 种',
    '',
    ...cards.map((entry) {
      final card = cardsById[entry.key];
      return '${entry.value}x (${card?.cost ?? '?'}) ${card?.name ?? entry.key}';
    }),
    '',
    '# 卡组代码',
    code,
    '',
    '# 复制完整牌表或仅复制上方代码，均可在余烬协议中导入。',
  ].join('\n');
}

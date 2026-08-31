import '../data/formats.dart';

const int maxSavedDecks = 27;

class LocalSavedDeck {
  const LocalSavedDeck({
    required this.id,
    required this.name,
    required this.format,
    required this.cardIds,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final RankedFormat format;
  final List<String> cardIds;
  final String updatedAt;

  LocalSavedDeck copyWith({
    String? id,
    String? name,
    RankedFormat? format,
    List<String>? cardIds,
    String? updatedAt,
  }) => LocalSavedDeck(
    id: id ?? this.id,
    name: name ?? this.name,
    format: format ?? this.format,
    cardIds: List<String>.from(cardIds ?? this.cardIds),
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'format': format.wireValue,
    'cardIds': cardIds,
    'updatedAt': updatedAt,
  };

  static LocalSavedDeck? tryParse(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final id = json['id']?.toString().trim() ?? '';
    final rawName = json['name']?.toString().trim() ?? '';
    final rawCardIds = json['cardIds'];
    if (id.isEmpty || rawCardIds is! List) return null;
    final name = rawName.isEmpty
        ? '未命名卡组'
        : rawName.length <= 32
        ? rawName
        : rawName.substring(0, 32);
    final cardIds = rawCardIds
        .whereType<String>()
        .where((cardId) => cardId.trim().isNotEmpty)
        .toList(growable: false);
    return LocalSavedDeck(
      id: id,
      name: name,
      format: rankedFormatFromWire(json['format']?.toString()),
      cardIds: cardIds,
      updatedAt:
          json['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }
}

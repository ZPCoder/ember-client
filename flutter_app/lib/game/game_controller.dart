import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalog.dart';
import '../data/deck_code.dart';
import '../data/deck_recipes.dart';
import '../data/deck_share.dart';
import '../data/deck_replacements.dart';
import '../data/formats.dart';
import '../models/card_definition.dart';
import '../models/local_saved_deck.dart';

const int maxBattleActionWindows = 89;

class _QueuedDeath {
  const _QueuedDeath({
    required this.unit,
    required this.side,
    required this.enemy,
  });

  final BattleUnit unit;
  final BattleSide side;
  final BattleSide enemy;
}

class GameController extends ChangeNotifier {
  GameController({String? startingPlayer, Random? startingPlayerRandom})
    : assert(
        startingPlayer == null ||
            startingPlayer == 'player' ||
            startingPlayer == 'ai',
      ),
      _forcedStartingPlayer = startingPlayer,
      _startingPlayerRandom = startingPlayerRandom ?? Random();

  List<CardDefinition> catalog = const [];
  final Map<String, int> collection = <String, int>{};
  final List<String> deckIds = <String>[];
  final List<LocalSavedDeck> savedDecks = <LocalSavedDeck>[];
  String? activeDeckId;
  String deckName = '曜光先锋';
  RankedFormat deckFormat = RankedFormat.standard;
  String recipeFaction = '曜光';
  BattleState? battle;
  bool isLoading = true;
  String? errorMessage;
  String commanderName = '旅者 071';
  int gold = 1280;
  int dust = 360;
  int packs = 1;
  int wins = 0;
  int losses = 0;
  int matchesPlayed = 0;
  bool isResolvingTurn = false;

  final Random _random = Random(20260809);
  final String? _forcedStartingPlayer;
  final Random _startingPlayerRandom;
  bool _resolvingDeaths = false;
  int _effectResolutionDepth = 0;
  SharedPreferences? _prefs;
  Timer? _turnTimer;
  int _deckIdSequence = 0;
  String? _declinedClipboardDeckCode;
  Future<void> _deckPersistQueue = Future<void>.value();

  Map<String, CardDefinition> get cardsById => {
    for (final card in catalog) card.id: card,
  };

  Future<void> initialize() async {
    try {
      catalog = await loadCatalog();
      _prefs = await SharedPreferences.getInstance();
      _restoreState();
      if (savedDecks.isEmpty) {
        if (deckIds.isEmpty) _seedStarterDeck();
        _createInitialSavedDeck();
        await _queueDeckPersistence();
      }
      if (collection.isEmpty) {
        for (final card in catalog) {
          collection[card.id] =
              card.id.startsWith('sun-') || card.id.startsWith('neutral-')
              ? 2
              : 0;
        }
        _persistCollection();
      }
    } catch (error) {
      errorMessage = '卡牌档案加载失败：$error';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void _restoreState() {
    deckFormat = rankedFormatFromWire(_prefs?.getString('deck_format'));
    final storedDecks = _prefs?.getString('saved_decks');
    if (storedDecks != null) {
      try {
        final decoded = jsonDecode(storedDecks);
        if (decoded is List) {
          final seenIds = <String>{};
          for (final raw in decoded) {
            final deck = LocalSavedDeck.tryParse(raw);
            if (deck != null &&
                seenIds.add(deck.id) &&
                savedDecks.length < maxSavedDecks) {
              savedDecks.add(deck);
            }
          }
        }
      } catch (_) {
        savedDecks.clear();
      }
    }
    if (savedDecks.isNotEmpty) {
      final storedActiveDeckId = _prefs?.getString('active_deck_id');
      final selected = savedDecks.firstWhere(
        (deck) => deck.id == storedActiveDeckId,
        orElse: () => savedDecks.first,
      );
      _loadDeck(selected);
    } else {
      final storedDeck = _prefs?.getStringList('deck_ids');
      if (storedDeck != null) deckIds.addAll(storedDeck);
      deckName = '迁移牌组';
    }
    final storedCollection = _prefs?.getString('collection');
    if (storedCollection != null) {
      final decoded = jsonDecode(storedCollection);
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.value is num) {
            collection[entry.key.toString()] = (entry.value as num).toInt();
          }
        }
      }
    }
    commanderName = _prefs?.getString('commander_name') ?? commanderName;
    gold = _prefs?.getInt('gold') ?? gold;
    dust = _prefs?.getInt('dust') ?? dust;
    packs = _prefs?.getInt('packs') ?? packs;
    wins = _prefs?.getInt('wins') ?? wins;
    losses = _prefs?.getInt('losses') ?? losses;
    matchesPlayed = _prefs?.getInt('matches') ?? matchesPlayed;
  }

  void _seedStarterDeck() {
    deckIds.clear();
    final starter = catalog
        .where(
          (card) =>
              cardAvailableInRankedFormat(card, RankedFormat.standard) &&
              (card.faction == '曜光' || card.id.startsWith('neutral-')),
        )
        .take(15);
    for (final card in starter) {
      deckIds.add(card.id);
      deckIds.add(card.id);
    }
  }

  void _createInitialSavedDeck() {
    final deck = LocalSavedDeck(
      id: 'mobile-starter',
      name: deckName,
      format: deckFormat,
      cardIds: List<String>.from(deckIds),
      updatedAt: DateTime.now().toIso8601String(),
    );
    savedDecks.add(deck);
    activeDeckId = deck.id;
  }

  void _loadDeck(LocalSavedDeck deck) {
    activeDeckId = deck.id;
    deckName = deck.name;
    deckFormat = deck.format;
    deckIds
      ..clear()
      ..addAll(deck.cardIds);
  }

  CardDefinition? card(String id) => cardsById[id];

  List<CardDefinition> get cardsAvailableForDeck => catalog
      .where((card) => cardAvailableInRankedFormat(card, deckFormat))
      .toList(growable: false);

  bool cardAllowedInDeck(CardDefinition card) =>
      cardAvailableInRankedFormat(card, deckFormat);

  bool get canCreateDeck => savedDecks.length < maxSavedDecks;

  LocalSavedDeck? get activeSavedDeck {
    final id = activeDeckId;
    if (id == null) return null;
    for (final deck in savedDecks) {
      if (deck.id == id) return deck;
    }
    return null;
  }

  void setDeckFormat(RankedFormat format) {
    if (deckFormat == format) return;
    deckFormat = format;
    _stageActiveDeck();
    unawaited(_queueDeckPersistence());
    notifyListeners();
  }

  void setDeckName(String value) {
    deckName = value;
    notifyListeners();
  }

  int owned(String id) => collection[id] ?? 0;

  bool addToDeck(CardDefinition card) {
    final copies = deckIds.where((id) => id == card.id).length;
    if (deckIds.length >= 30 ||
        !cardAllowedInDeck(card) ||
        copies >= _copyLimit(card) ||
        owned(card.id) <= copies) {
      return false;
    }
    final faction = _deckFaction;
    if (card.faction != '中立' && faction != null && faction != card.faction) {
      return false;
    }
    deckIds.add(card.id);
    _stageActiveDeck();
    unawaited(_queueDeckPersistence());
    notifyListeners();
    return true;
  }

  void removeFromDeck(String id) {
    final index = deckIds.lastIndexOf(id);
    if (index >= 0) {
      deckIds.removeAt(index);
      _stageActiveDeck();
      unawaited(_queueDeckPersistence());
      notifyListeners();
    }
  }

  int autoCompleteDeck() {
    if (deckIds.length >= 30 || missingDeckCards.isNotEmpty) return 0;
    final completion = completeDeckFromCollection(
      cardIds: List<String>.from(deckIds),
      collection: Map<String, int>.from(collection),
      format: deckFormat,
      catalog: catalog,
    );
    if (completion.addedCardIds.isEmpty) return 0;
    deckIds
      ..clear()
      ..addAll(completion.cardIds);
    _stageActiveDeck();
    unawaited(_queueDeckPersistence());
    notifyListeners();
    return completion.addedCardIds.length;
  }

  List<DeckRecipe> get deckRecipes =>
      deckRecipesForFaction(recipeFaction, catalog);

  void setRecipeFaction(String faction) {
    if (faction == '中立' || faction == recipeFaction) return;
    recipeFaction = faction;
    notifyListeners();
  }

  int applyDeckRecipe(DeckRecipe recipe) {
    if (!canCreateDeck) return -1;
    _stageActiveDeck();
    activeDeckId = null;
    deckFormat = recipe.format;
    deckName = _normalizeDeckName(recipe.name);
    deckIds
      ..clear()
      ..addAll(recipe.cardIds);
    _declinedClipboardDeckCode = null;
    unawaited(_queueDeckPersistence());
    notifyListeners();
    return missingDeckCount;
  }

  String? get _deckFaction {
    for (final id in deckIds) {
      final faction = card(id)?.faction;
      if (faction != null && faction != '中立') return faction;
    }
    return null;
  }

  String? _validateDeck(List<String> ids, RankedFormat format) {
    if (ids.length < 30) return '还差 ${30 - ids.length} 张卡牌';
    if (ids.length > 30) return '卡组最多 30 张卡牌';
    if (ids.any((id) => card(id) == null)) return '卡组包含未知卡牌';
    final factions = <String>{};
    for (final id in ids) {
      final definition = card(id)!;
      if (!cardAvailableInRankedFormat(definition, format)) {
        return '${format.fullLabel}不能使用「${definition.name}」'
            '（${cardSetDefinition(definition.setId).label}）';
      }
      if (definition.faction != '中立') factions.add(definition.faction);
    }
    if (factions.length > 1) return '不能混合两个非中立阵营';

    final copies = <String, int>{};
    for (final id in ids) {
      copies[id] = (copies[id] ?? 0) + 1;
    }
    for (final entry in copies.entries) {
      final definition = card(entry.key)!;
      if (entry.value > _copyLimit(definition)) {
        return definition.rarity == '传说'
            ? '传说卡「${definition.name}」最多 1 张'
            : '「${definition.name}」最多 2 张';
      }
    }
    return null;
  }

  String? get _deckValidationError => _validateDeck(deckIds, deckFormat);

  bool get deckValid => _deckValidationError == null;

  List<MissingDeckCard> get missingDeckCards => collection.isEmpty
      ? const []
      : findMissingDeckCards(
          List<String>.from(deckIds),
          Map<String, int>.from(collection),
        );

  int get missingDeckCount =>
      missingDeckCards.fold(0, (total, card) => total + card.missingCount);

  bool get deckPlayable => deckValid && missingDeckCards.isEmpty;

  String get deckStatus {
    final validation = _deckValidationError;
    if (validation != null) return validation;
    final missing = missingDeckCount;
    return missing > 0
        ? '缺少 $missing 张卡牌，可使用替换建议'
        : '${deckFormat.fullLabel}卡组协议有效';
  }

  Future<bool> saveDeck() async {
    deckName = _normalizeDeckName(deckName);
    final active = activeSavedDeck;
    if (active == null) {
      if (!canCreateDeck) return false;
      final deck = _currentDeckSnapshot(id: _newDeckId());
      savedDecks.add(deck);
      activeDeckId = deck.id;
    } else {
      _stageActiveDeck();
    }
    await _queueDeckPersistence();
    notifyListeners();
    return true;
  }

  Future<bool> selectDeck(String deckId) async {
    _stageActiveDeck();
    LocalSavedDeck? selected;
    for (final deck in savedDecks) {
      if (deck.id == deckId) {
        selected = deck;
        break;
      }
    }
    if (selected == null) return false;
    _loadDeck(selected);
    await _queueDeckPersistence();
    notifyListeners();
    return true;
  }

  Future<bool> createNewDeck() async {
    if (!canCreateDeck) return false;
    _stageActiveDeck();
    deckFormat = RankedFormat.standard;
    deckName = '新建战术卡组 ${savedDecks.length + 1}';
    _seedStarterDeck();
    final deck = _currentDeckSnapshot(id: _newDeckId());
    savedDecks.add(deck);
    activeDeckId = deck.id;
    await _queueDeckPersistence();
    notifyListeners();
    return true;
  }

  Future<bool> duplicateActiveDeck() async {
    if (!canCreateDeck || activeSavedDeck == null) return false;
    _stageActiveDeck();
    deckName = _normalizeDeckName('${_normalizeDeckName(deckName)} 副本');
    final deck = _currentDeckSnapshot(id: _newDeckId());
    savedDecks.add(deck);
    activeDeckId = deck.id;
    await _queueDeckPersistence();
    notifyListeners();
    return true;
  }

  String exportActiveDeckCode() => encodeDeckCode(
    format: deckFormat,
    name: _normalizeDeckName(deckName),
    cardIds: List<String>.from(deckIds),
  );

  String exportActiveDeckShareText() => formatDeckShareText(
    format: deckFormat,
    name: _normalizeDeckName(deckName),
    cardIds: List<String>.from(deckIds),
    catalog: catalog,
  );

  DeckCodePreview? previewClipboardDeckCode(String value) {
    final code = value.trim();
    if (code.isEmpty || code == _declinedClipboardDeckCode) return null;
    DecodedDeckCode decoded;
    try {
      decoded = decodeDeckCode(code);
    } on FormatException {
      return null;
    }
    final format = decoded.format ?? deckFormat;
    if (_validateDeck(decoded.cardIds, format) != null) return null;
    final missing = collection.isEmpty
        ? 0
        : findMissingDeckCards(
            List<String>.from(decoded.cardIds),
            Map<String, int>.from(collection),
          ).fold(0, (total, card) => total + card.missingCount);
    return DeckCodePreview(
      code: code,
      version: decoded.version,
      format: format,
      name: decoded.name ?? '导入牌组',
      missingCount: missing,
    );
  }

  void declineClipboardDeckCode(String code) {
    _declinedClipboardDeckCode = code.trim();
  }

  Future<DeckCodeImportResult> importDeckCode(String value) async {
    if (!canCreateDeck) {
      return const DeckCodeImportResult(
        success: false,
        message: '27 个牌组栏位已全部使用，请先删除一个牌组',
      );
    }
    DecodedDeckCode decoded;
    try {
      decoded = decodeDeckCode(value);
    } on FormatException catch (error) {
      return DeckCodeImportResult(
        success: false,
        message: error.message.toString(),
      );
    }
    final format = decoded.format ?? deckFormat;
    final validationError = _validateDeck(decoded.cardIds, format);
    if (validationError != null) {
      return DeckCodeImportResult(success: false, message: validationError);
    }
    _stageActiveDeck();
    activeDeckId = null;
    deckFormat = format;
    deckName = _normalizeDeckName(decoded.name ?? '导入牌组');
    deckIds
      ..clear()
      ..addAll(decoded.cardIds);
    _declinedClipboardDeckCode = null;
    notifyListeners();
    final missing = missingDeckCount;
    return DeckCodeImportResult(
      success: true,
      message: missing > 0
          ? '已导入「$deckName」草稿；缺少 $missing 张卡牌，可按建议替换'
          : '已导入「$deckName」为新的${format.label}牌组草稿',
    );
  }

  List<CardDefinition> replacementSuggestions(String missingCardId) =>
      suggestDeckReplacements(
        cardIds: List<String>.from(deckIds),
        missingCardId: missingCardId,
        collection: Map<String, int>.from(collection),
        format: deckFormat,
        catalog: catalog,
      );

  bool replaceMissingDeckCard(String missingCardId, String replacementCardId) {
    final allowed = replacementSuggestions(
      missingCardId,
    ).any((candidate) => candidate.id == replacementCardId);
    final index = deckIds.lastIndexOf(missingCardId);
    if (!allowed || index < 0) return false;
    deckIds[index] = replacementCardId;
    _stageActiveDeck();
    unawaited(_queueDeckPersistence());
    notifyListeners();
    return true;
  }

  Future<bool> deleteDeck(String deckId) async {
    final index = savedDecks.indexWhere((deck) => deck.id == deckId);
    if (index < 0) return false;
    _stageActiveDeck();
    savedDecks.removeAt(index);
    if (savedDecks.isEmpty) {
      deckFormat = RankedFormat.standard;
      deckName = '新建战术卡组';
      _seedStarterDeck();
      final replacement = _currentDeckSnapshot(id: _newDeckId());
      savedDecks.add(replacement);
      activeDeckId = replacement.id;
    } else if (activeDeckId == deckId || activeSavedDeck == null) {
      final nextIndex = index >= savedDecks.length
          ? savedDecks.length - 1
          : index;
      _loadDeck(savedDecks[nextIndex]);
    }
    await _queueDeckPersistence();
    notifyListeners();
    return true;
  }

  LocalSavedDeck _currentDeckSnapshot({required String id}) => LocalSavedDeck(
    id: id,
    name: _normalizeDeckName(deckName),
    format: deckFormat,
    cardIds: List<String>.from(deckIds),
    updatedAt: DateTime.now().toIso8601String(),
  );

  String _normalizeDeckName(String value) {
    final trimmed = value.trim();
    final normalized = trimmed.isEmpty ? '未命名卡组' : trimmed;
    return normalized.length <= 32 ? normalized : normalized.substring(0, 32);
  }

  void _stageActiveDeck() {
    final index = savedDecks.indexWhere((deck) => deck.id == activeDeckId);
    if (index < 0) return;
    savedDecks[index] = _currentDeckSnapshot(id: savedDecks[index].id);
  }

  String _newDeckId() {
    String candidate;
    do {
      candidate =
          'mobile-deck-${DateTime.now().microsecondsSinceEpoch}-${_deckIdSequence++}';
    } while (savedDecks.any((deck) => deck.id == candidate));
    return candidate;
  }

  Future<void> _queueDeckPersistence() {
    _deckPersistQueue = _deckPersistQueue
        .catchError((Object _) {})
        .then((_) => _persistDecks());
    return _deckPersistQueue;
  }

  Future<void> _persistDecks() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(
      'saved_decks',
      jsonEncode(savedDecks.map((deck) => deck.toJson()).toList()),
    );
    if (activeDeckId != null) {
      await prefs.setString('active_deck_id', activeDeckId!);
    } else {
      await prefs.remove('active_deck_id');
    }
    await prefs.setStringList('deck_ids', deckIds);
    await prefs.setString('deck_format', deckFormat.wireValue);
    await prefs.setString('commander_name', commanderName);
  }

  void openPack() {
    if (packs <= 0 || catalog.isEmpty) return;
    packs--;
    final eligible = catalog
        .where((card) => (collection[card.id] ?? 0) < _copyLimit(card))
        .toList();
    final normalPool = eligible.isNotEmpty ? eligible : catalog;
    final rarePool = normalPool.where((card) => card.rarity != '普通').toList();
    final guaranteedRarePool = rarePool.isNotEmpty
        ? rarePool
        : catalog.where((card) => card.rarity != '普通').toList();
    final drawn = <String, int>{};
    for (var i = 0; i < 5; i++) {
      final available = normalPool
          .where(
            (card) =>
                (collection[card.id] ?? 0) + (drawn[card.id] ?? 0) <
                _copyLimit(card),
          )
          .toList();
      final pool = i == 0
          ? guaranteedRarePool
          : (available.isNotEmpty ? available : normalPool);
      final picked = pool[_random.nextInt(pool.length)];
      drawn[picked.id] = (drawn[picked.id] ?? 0) + 1;
      collection[picked.id] = (collection[picked.id] ?? 0) + 1;
    }
    gold += 50;
    _prefs?.setInt('packs', packs);
    _prefs?.setInt('gold', gold);
    _persistCollection();
    notifyListeners();
  }

  int _copyLimit(CardDefinition card) => card.rarity == '传说' ? 1 : 2;

  HeroPowerDefinition _heroPowerForFaction(String faction) {
    switch (faction) {
      case '曜光':
        return const HeroPowerDefinition(
          id: 'radiance-mend',
          faction: '曜光',
          name: '日耀修复',
          description: '为一个友方角色恢复 2 点生命。',
          cost: 2,
          target: 'friendly-character',
          effect: {'kind': 'heal-friendly-character', 'amount': 2},
        );
      case '幽潮':
        return const HeroPowerDefinition(
          id: 'tide-pulse',
          faction: '幽潮',
          name: '潮汐脉冲',
          description: '对敌方核心造成 1 点伤害。',
          cost: 2,
          effect: {'kind': 'damage-enemy-hero', 'amount': 1},
        );
      case '烬火':
        return const HeroPowerDefinition(
          id: 'ember-scorch',
          faction: '烬火',
          name: '熔火灼痕',
          description: '对一个敌方单位造成 2 点伤害。',
          cost: 2,
          target: 'enemy-unit',
          effect: {'kind': 'damage-enemy-unit', 'amount': 2},
        );
      case '星穹':
        return const HeroPowerDefinition(
          id: 'astral-insight',
          faction: '星穹',
          name: '星穹洞见',
          description: '抽一张牌。',
          cost: 2,
          effect: {'kind': 'draw', 'count': 1},
        );
      case '苍林':
        return const HeroPowerDefinition(
          id: 'verdant-growth',
          faction: '苍林',
          name: '苍林生长',
          description: '召唤一个 1/2 的苔径奔行兽。',
          cost: 2,
          effect: {
            'kind': 'summon',
            'cardId': 'neutral-moss-runner',
            'count': 1,
          },
        );
      case '雷铸':
        return const HeroPowerDefinition(
          id: 'storm-plating',
          faction: '雷铸',
          name: '雷铸装甲',
          description: '为你的核心获得 2 点护甲。',
          cost: 2,
          effect: {'kind': 'armor', 'amount': 2},
        );
      default:
        return const HeroPowerDefinition(
          id: 'core-pulse',
          faction: '中立',
          name: '核心脉冲',
          description: '对敌方核心造成 1 点伤害。',
          cost: 2,
          effect: {'kind': 'damage-enemy-hero', 'amount': 1},
        );
    }
  }

  String _factionForCards(List<CardDefinition> cards) => cards
      .map((item) => item.faction)
      .firstWhere((faction) => faction != '中立', orElse: () => '中立');

  List<String> _fallbackDeckIds() {
    final knownDeckCards = deckIds.map(card).whereType<CardDefinition>();
    final preferredFaction = knownDeckCards
        .map((definition) => definition.faction)
        .firstWhere(
          (faction) => faction != '中立',
          orElse: () => catalog
              .map((definition) => definition.faction)
              .firstWhere((faction) => faction != '中立', orElse: () => '中立'),
        );
    var pool = cardsAvailableForDeck
        .where(
          (definition) =>
              definition.faction == preferredFaction ||
              definition.faction == '中立',
        )
        .toList();
    if (pool.isEmpty) pool = [...cardsAvailableForDeck];
    if (pool.isEmpty) return const [];

    final fallback = <String>[];
    for (final definition in pool) {
      for (
        var copy = 0;
        copy < _copyLimit(definition) && fallback.length < 30;
        copy++
      ) {
        fallback.add(definition.id);
      }
      if (fallback.length == 30) return fallback;
    }

    // Tiny fixture catalogs cannot form a legal constructed deck. Cycling a
    // known card still gives callers a safe, non-crashing practice battle;
    // production's complete catalog always fills the copy-limited path above.
    final practicePool = pool
        .where((definition) => definition.rarity != '传说')
        .toList();
    final cycle = practicePool.isEmpty ? pool : practicePool;
    var index = 0;
    while (fallback.length < 30) {
      fallback.add(cycle[index % cycle.length].id);
      index++;
    }
    return fallback;
  }

  void _persistCollection() {
    _prefs?.setString('collection', jsonEncode(collection));
  }

  void startBattle() {
    if (catalog.isEmpty || isResolvingTurn) return;
    if (deckValid && missingDeckCards.isNotEmpty) return;
    _turnTimer?.cancel();
    final deck = deckValid ? [...deckIds] : _fallbackDeckIds();
    if (deck.isEmpty) return;
    final playerDeck = deck.map((id) => card(id)!).toList()..shuffle(_random);
    final playerFaction = _factionForCards(playerDeck);
    final availableAiFactions = cardsAvailableForDeck
        .map((card) => card.faction)
        .where((faction) => faction != '中立')
        .toSet()
        .toList();
    final aiFaction = availableAiFactions.isEmpty
        ? '幽潮'
        : availableAiFactions[_random.nextInt(availableAiFactions.length)];
    final aiCandidates =
        cardsAvailableForDeck
            .where((card) => card.faction == aiFaction || card.faction == '中立')
            .toList()
          ..sort((left, right) => left.cost.compareTo(right.cost));
    final aiSingles = aiCandidates.take(15).toList();
    final aiDeck = aiSingles.expand((card) => [card, card]).toList()
      ..shuffle(_random);
    final startingPlayer =
        _forcedStartingPlayer ??
        (_startingPlayerRandom.nextBool() ? 'player' : 'ai');
    final playerIsSecond = startingPlayer == 'ai';
    final aiIsSecond = startingPlayer == 'player';
    final player = BattleSide(
      heroHealth: 30,
      maxHeroHealth: 30,
      mana: 1,
      maxMana: 1,
      deck: playerDeck,
      hand: [],
      board: [],
      coinAvailable: playerIsSecond,
    );
    final ai = BattleSide(
      heroHealth: 30,
      maxHeroHealth: 30,
      mana: 1,
      maxMana: 1,
      deck: aiDeck,
      hand: [],
      board: [],
      coinAvailable: aiIsSecond,
    );
    battle = BattleState(
      player: player,
      ai: ai,
      playerHeroPower: _heroPowerForFaction(playerFaction),
      aiHeroPower: _heroPowerForFaction(aiFaction),
      turn: 1,
      activePlayer: startingPlayer,
      phase: 'mulligan',
      aiFaction: aiFaction,
      logs: [
        startingPlayer == 'player'
            ? '对局开始：你获得先手，请选择要替换的起手牌。'
            : '对局开始：敌方获得先手，你获得幸运币。',
      ],
    );
    for (var i = 0; i < 3; i++) {
      _draw(player);
      _draw(ai);
    }
    // The actual second player receives both the fourth mulligan card and Coin.
    _draw(playerIsSecond ? player : ai);
    _autoMulligan(ai);
    _emitFx(
      'start',
      '战斗开始',
      '抽取起始手牌，准备部署你的第一支部队。',
      Icons.sports_kabaddi,
      0xFF69CFC3,
    );
    notifyListeners();
  }

  void toggleMulligan(int index) {
    final state = battle;
    if (state == null || state.phase != 'mulligan' || state.mulliganDone) {
      return;
    }
    if (index < 0 || index >= state.player.hand.length) return;
    if (!state.mulliganSelected.add(index)) {
      state.mulliganSelected.remove(index);
    }
    notifyListeners();
  }

  Future<void> confirmMulligan() async {
    final state = battle;
    if (state == null || state.phase != 'mulligan' || state.mulliganDone) {
      return;
    }
    final selected = state.mulliganSelected.toList()..sort();
    final returned = <CardDefinition>[];
    _syncHandCostReductions(state.player);
    for (final index in selected.reversed) {
      if (index >= 0 && index < state.player.hand.length) {
        returned.add(state.player.hand.removeAt(index));
        state.player.handCostReductions.removeAt(index);
      }
    }
    for (var i = 0; i < returned.length; i++) {
      _draw(state.player);
    }
    if (returned.isNotEmpty) {
      state.player.deck.addAll(returned);
      state.player.deck.shuffle(_random);
    }
    state.mulliganSelected.clear();
    state.mulliganDone = true;
    state.logs.insert(
      0,
      returned.isEmpty ? '起手牌已确认。' : '起手换牌完成，替换 ${returned.length} 张牌。',
    );

    if (state.activePlayer == 'ai') {
      isResolvingTurn = true;
      state.phase = 'end';
      state.logs.insert(0, '敌方演算体获得先手，开始第一回合。');
      _emitFx('turn', '敌方先手', '演算体正在执行第一回合', Icons.hourglass_top, 0xFFA692D1);
      notifyListeners();
      _beginSideTurn(state, owner: 'ai');
      await _aiTurn(state);
      if (!state.finished) {
        if (_advanceActionWindow(state, 'player')) {
          _beginSideTurn(state, owner: 'player');
          state.logs.insert(0, '你的第 1 回合开始，法力恢复至 ${state.player.mana}。');
          _emitFx(
            'turn',
            '第 1 回合',
            '你的法力已恢复，轮到你行动',
            Icons.hourglass_top,
            0xFF69CFC3,
          );
          _startTurnTimer();
        }
      }
      isResolvingTurn = false;
      notifyListeners();
      return;
    }

    _beginSideTurn(state, owner: 'player');
    _emitFx(
      'turn',
      '第一回合开始',
      '获得 1 点法力，部署你的战术。',
      Icons.hourglass_top,
      0xFF69CFC3,
    );
    _startTurnTimer();
    notifyListeners();
  }

  void _autoMulligan(BattleSide side) {
    final indexed = side.hand.asMap().entries.toList()
      ..sort((left, right) => left.value.cost.compareTo(right.value.cost));
    final keep = <int>{};
    final keptIds = <String>{};
    for (final entry in indexed) {
      if (keep.length >= 2 ||
          entry.value.cost > 2 ||
          !keptIds.add(entry.value.id)) {
        continue;
      }
      keep.add(entry.key);
    }
    if (keep.isEmpty && indexed.isNotEmpty) keep.add(indexed.first.key);
    final returned = <CardDefinition>[];
    _syncHandCostReductions(side);
    for (final index
        in side.hand
            .asMap()
            .keys
            .where((index) => !keep.contains(index))
            .toList()
            .reversed) {
      returned.add(side.hand.removeAt(index));
      side.handCostReductions.removeAt(index);
    }
    for (var i = 0; i < returned.length; i++) {
      if (side.deck.isNotEmpty) {
        side.hand.add(side.deck.removeLast());
        side.handCostReductions.add(0);
      }
    }
    side.deck.addAll(returned);
    side.deck.shuffle(_random);
  }

  void _beginSideTurn(BattleState state, {required String owner}) {
    final isPlayer = owner == 'player';
    final side = isPlayer ? state.player : state.ai;
    final turnsStarted = isPlayer
        ? state.playerTurnsStarted
        : state.aiTurnsStarted;
    state.activePlayer = owner;
    state.phase = 'main';
    if (turnsStarted == 0) {
      side.mana = side.maxMana;
    } else {
      _refillMana(side);
    }
    if (isPlayer) {
      state.playerTurnsStarted++;
      state.turn = state.playerTurnsStarted;
      state.heroPowerUsed = false;
    } else {
      state.aiTurnsStarted++;
      state.aiHeroPowerUsed = false;
    }
    _refreshSideForTurn(side);
    _resolveTurnTriggers(side, start: true);
    _processDeaths();
    _checkFinished();
    if (!state.finished) {
      _draw(side);
      _checkFinished();
    }
  }

  void _startTurnTimer() {
    _turnTimer?.cancel();
    final state = battle;
    if (state == null || state.finished || state.activePlayer != 'player') {
      return;
    }
    state.turnSecondsLeft = 75;
    _turnTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = battle;
      if (current == null ||
          current.finished ||
          current.activePlayer != 'player') {
        _turnTimer?.cancel();
        return;
      }
      current.turnSecondsLeft--;
      if (current.turnSecondsLeft <= 0 && !isResolvingTurn) {
        _turnTimer?.cancel();
        endTurn();
      }
      notifyListeners();
    });
  }

  void _draw(BattleSide side) {
    if (side.deck.isNotEmpty) {
      final drawn = side.deck.removeLast();
      if (_occupiedHandSlots(side) < 10) {
        side.hand.add(drawn);
        _syncHandCostReductions(side);
        return;
      }
      stateLog(
        _ownerOf(side) == 'player' ? '手牌已满' : '敌方手牌已满',
        ' ${drawn.name} 被燃毁。',
      );
      _emitFx(
        'burn',
        '手牌燃毁',
        '${drawn.name} 因手牌已满被销毁',
        Icons.local_fire_department,
        0xFFE46D3F,
        sourceId: drawn.id,
      );
      return;
    }
    if (side.deck.isEmpty) {
      side.fatigue++;
      _damageHero(side, side.fatigue);
      stateLog(
        _ownerOf(side) == 'player' ? '疲劳伤害' : '敌方疲劳伤害',
        '受到 ${side.fatigue} 点疲劳伤害。',
      );
      _emitFx(
        'fatigue',
        '疲劳伤害',
        '牌库为空，受到 ${side.fatigue} 点伤害',
        Icons.hourglass_disabled,
        0xFFE46D3F,
        amount: side.fatigue,
      );
    }
  }

  bool playCard(
    CardDefinition card, {
    int? handIndex,
    BattleUnit? target,
    bool targetHero = false,
  }) {
    final state = battle;
    final resolvedHandIndex = state == null
        ? -1
        : _resolveHandIndex(state.player, card, handIndex);
    final effectiveCost = state == null || resolvedHandIndex < 0
        ? card.cost
        : _effectiveHandCost(state.player, resolvedHandIndex);
    if (state == null ||
        state.finished ||
        state.activePlayer != 'player' ||
        state.phase != 'main' ||
        state.player.mana < effectiveCost) {
      return false;
    }
    if (resolvedHandIndex < 0 ||
        (card.isUnit && state.player.board.length >= 7) ||
        (state.player.board.length >= 7 &&
            _isPureSummonSpell(card, state.player)) ||
        !_validTarget(card, state.player, state.ai, target)) {
      return false;
    }
    _playCardForSide(
      card,
      source: state.player,
      enemy: state.ai,
      owner: 'player',
      handIndex: resolvedHandIndex,
      target: target,
      targetHero: targetHero,
    );
    _checkFinished();
    notifyListeners();
    return true;
  }

  bool tradeCard(CardDefinition card, {int? handIndex}) {
    final state = battle;
    if (state == null ||
        state.finished ||
        state.activePlayer != 'player' ||
        state.phase != 'main' ||
        !card.tradeable ||
        state.player.deck.isEmpty ||
        state.player.mana < 1) {
      return false;
    }
    final index = _resolveHandIndex(state.player, card, handIndex);
    if (index < 0) return false;
    state.player.hand.removeAt(index);
    state.player.handCostReductions.removeAt(index);
    state.player.mana--;
    // Tradeable draws from the original deck before the physical card is
    // inserted, so a trade can never immediately redraw itself. Preserve the
    // remaining deck order and choose only the insertion position at random.
    _draw(state.player);
    state.player.deck.insert(
      _random.nextInt(state.player.deck.length + 1),
      card,
    );
    state.logs.insert(0, '${card.name} 已交易，抽取一张替代档案。');
    _emitFx(
      'trade',
      '可交易',
      '${card.name} 回到牌库并抽取替代牌',
      Icons.swap_horiz,
      0xFF65CDDA,
      sourceId: card.id,
    );
    notifyListeners();
    return true;
  }

  bool prepareCard(CardDefinition card, {int? handIndex}) {
    final state = battle;
    if (state == null ||
        state.finished ||
        state.activePlayer != 'player' ||
        state.phase != 'main' ||
        !card.preparable ||
        state.player.mana < 1) {
      return false;
    }
    final index = _resolveHandIndex(state.player, card, handIndex);
    if (index < 0 || state.player.handCostReductions[index] > 0) return false;
    final manaSpent = state.player.mana;
    final reduction = manaSpent + 1;
    state.player.mana = 0;
    state.player.handCostReductions[index] = reduction;
    state.logs.insert(0, '${card.name} 完成预备，费用永久降低 $reduction 点。');
    _emitFx(
      'prepare',
      '预备完成',
      '${card.name} 降低 $reduction 点费用',
      Icons.keyboard_double_arrow_down,
      0xFF79B980,
      sourceId: card.id,
      amount: reduction,
    );
    notifyListeners();
    return true;
  }

  int playerHandCost(int handIndex) {
    final side = battle?.player;
    if (side == null || handIndex < 0 || handIndex >= side.hand.length) {
      return 0;
    }
    return _effectiveHandCost(side, handIndex);
  }

  int playerHandCostReduction(int handIndex) {
    final side = battle?.player;
    if (side == null || handIndex < 0 || handIndex >= side.hand.length) {
      return 0;
    }
    _syncHandCostReductions(side);
    return side.handCostReductions[handIndex];
  }

  bool heroAttack({BattleUnit? target, bool targetHero = false}) {
    final state = battle;
    final weapon = state?.player.weapon;
    if (state == null ||
        state.finished ||
        state.phase != 'main' ||
        state.activePlayer != 'player' ||
        weapon == null ||
        weapon.durability <= 0 ||
        state.player.heroHasAttacked) {
      return false;
    }
    final taunts = state.ai.board
        .where((unit) => unit.hasTaunt && !unit.stealthActive)
        .toList();
    if (taunts.isNotEmpty && (target == null || !target.hasTaunt)) return false;
    if (target != null && !state.ai.board.contains(target)) return false;
    if (target?.stealthActive ?? false) return false;
    if (target == null) {
      _triggerSecrets(
        state.ai,
        'opponent-attacks-hero',
        triggeringSide: state.player,
      );
      if (state.player.heroHealth <= 0) {
        _processDeaths();
        _checkFinished();
        notifyListeners();
        return false;
      }
    }
    // Combat damage is simultaneous. Snapshot the defender's attack and
    // Lifesteal before the weapon hit can mark that unit as dead.
    final defenderAttack = target?.attack ?? 0;
    final defenderHasLifesteal = target?.hasLifesteal ?? false;
    final dealt = target == null
        ? _damageHero(state.ai, weapon.attack)
        : _damageUnit(target, weapon.attack, combat: true);
    if (target != null) {
      final reflected = _damageHero(state.player, defenderAttack);
      if (defenderHasLifesteal && reflected > 0) {
        _healHero(state.ai, reflected);
      }
    }
    state.player.heroHasAttacked = true;
    weapon.durability--;
    state.logs.insert(
      0,
      target == null
          ? '英雄使用 ${weapon.card.name} 攻击敌方核心，造成 $dealt 点伤害。'
          : '英雄使用 ${weapon.card.name} 攻击 ${target.card.name}。',
    );
    _emitFx(
      'attack',
      '英雄发起攻击',
      target == null ? '对敌方核心造成 $dealt 点伤害' : '与 ${target.card.name} 交战',
      Icons.flash_on,
      0xFFE46D3F,
      sourceId: 'player-hero',
      targetId: target?.instanceId ?? 'ai-hero',
      amount: dealt,
    );
    if (weapon.durability <= 0) {
      state.logs.insert(0, '${weapon.card.name} 耐久耗尽。');
      state.player.weapon = null;
      _emitFx(
        'death',
        '${weapon.card.name} 损毁',
        '武器耐久耗尽，已离开装备区',
        Icons.broken_image_outlined,
        0xFF9D7567,
      );
    }
    _processDeaths();
    _checkFinished();
    notifyListeners();
    return true;
  }

  bool useHeroPower({BattleUnit? target, bool targetHero = false}) {
    final state = battle;
    if (state == null ||
        state.finished ||
        state.activePlayer != 'player' ||
        state.phase != 'main' ||
        state.heroPowerUsed ||
        !_canResolveHeroPower(
          state.playerHeroPower,
          source: state.player,
          enemy: state.ai,
          target: target,
          targetHero: targetHero,
        )) {
      return false;
    }
    final resolved = _resolveHeroPower(
      state.playerHeroPower,
      source: state.player,
      enemy: state.ai,
      owner: 'player',
      target: target,
      targetHero: targetHero,
    );
    if (!resolved) return false;
    _checkFinished();
    notifyListeners();
    return true;
  }

  bool _canResolveHeroPower(
    HeroPowerDefinition power, {
    required BattleSide source,
    required BattleSide enemy,
    BattleUnit? target,
    required bool targetHero,
  }) {
    if (source.mana < power.cost) return false;
    if (power.effect['kind'] == 'summon' && source.board.length >= 7) {
      return false;
    }
    final targetType = power.target ?? 'none';
    if (targetType == 'enemy-unit') {
      return target != null &&
          enemy.board.contains(target) &&
          !target.stealthActive;
    }
    if (targetType == 'friendly-unit') {
      return target != null && source.board.contains(target);
    }
    if (targetType == 'friendly-character') {
      return targetHero || (target != null && source.board.contains(target));
    }
    return true;
  }

  bool _resolveHeroPower(
    HeroPowerDefinition power, {
    required BattleSide source,
    required BattleSide enemy,
    required String owner,
    BattleUnit? target,
    required bool targetHero,
  }) {
    final state = battle;
    if (state == null ||
        !_canResolveHeroPower(
          power,
          source: source,
          enemy: enemy,
          target: target,
          targetHero: targetHero,
        )) {
      return false;
    }
    source.mana -= power.cost;
    if (owner == 'player') {
      state.heroPowerUsed = true;
    } else {
      state.aiHeroPowerUsed = true;
    }
    final effect = power.effect;
    final kind = effect['kind']?.toString();
    final amount = (effect['amount'] as num?)?.toInt() ?? 0;
    final sourceId = owner == 'player' ? 'player-hero-power' : 'ai-hero-power';
    switch (kind) {
      case 'damage-enemy-hero':
        final dealt = _damageHero(enemy, amount);
        stateLog(power.name, '对敌方核心造成 $dealt 点伤害。');
        _emitFx(
          'hero-power',
          power.name,
          '英雄技能造成 $dealt 点核心伤害',
          Icons.bolt,
          0xFF65CDDA,
          sourceId: sourceId,
          targetId: owner == 'player' ? 'ai-hero' : 'player-hero',
          amount: dealt,
        );
        break;
      case 'damage-enemy-unit':
        if (target == null || !enemy.board.contains(target)) return false;
        final dealt = _damageUnit(target, amount);
        stateLog(power.name, '对 ${target.card.name} 造成 $dealt 点伤害。');
        _emitFx(
          'hero-power',
          power.name,
          '英雄技能命中 ${target.card.name}',
          Icons.bolt,
          0xFFE46D3F,
          sourceId: sourceId,
          targetId: target.instanceId,
          amount: dealt,
        );
        break;
      case 'heal-friendly-character':
        var effectiveHealing = amount;
        if (targetHero) {
          effectiveHealing = _healHero(source, amount);
          if (effectiveHealing > 0) {
            stateLog(power.name, '核心恢复 $effectiveHealing 点生命。');
          }
        } else if (target != null && source.board.contains(target)) {
          final before = target.health;
          target.health = min(target.maxHealth, target.health + amount);
          effectiveHealing = target.health - before;
          if (effectiveHealing > 0) {
            stateLog(
              power.name,
              '${target.card.name} 恢复 $effectiveHealing 点生命。',
            );
          }
        } else {
          return false;
        }
        _emitFx(
          'hero-power',
          power.name,
          power.description,
          Icons.favorite,
          0xFF79B980,
          sourceId: sourceId,
          targetId: targetHero ? '$owner-hero' : target?.instanceId,
          amount: effectiveHealing,
        );
        break;
      case 'heal-friendly-unit':
        if (target == null || !source.board.contains(target)) return false;
        target.health = min(target.maxHealth, target.health + amount);
        stateLog(power.name, '${target.card.name} 恢复 $amount 点生命。');
        break;
      case 'draw':
        final count = (effect['count'] as num?)?.toInt() ?? 1;
        for (var i = 0; i < count; i++) {
          _draw(source);
        }
        stateLog(power.name, '抽取 $count 张牌。');
        break;
      case 'summon':
        final cardId = effect['cardId']?.toString();
        final summonCard = cardId == null ? null : card(cardId);
        final count = (effect['count'] as num?)?.toInt() ?? 1;
        if (summonCard == null || !summonCard.isUnit) return false;
        for (var i = 0; i < count && source.board.length < 7; i++) {
          final unit = _summonUnit(summonCard, owner: owner);
          source.board.add(unit);
          _emitFx(
            'summon',
            '${power.name} · ${summonCard.name}',
            '英雄技能召唤一个新的战场单位',
            Icons.auto_awesome,
            factionColors[summonCard.faction] ?? 0xFF69CFC3,
            sourceId: sourceId,
          );
        }
        break;
      case 'armor':
        source.armor += amount;
        stateLog(power.name, '核心获得 $amount 点护甲。');
        _emitFx(
          'armor',
          power.name,
          '核心获得 $amount 点护甲',
          Icons.shield,
          0xFFE7BD7A,
          sourceId: sourceId,
          amount: amount,
        );
        break;
      default:
        return false;
    }
    _processDeaths();
    return true;
  }

  bool useCoin() {
    final state = battle;
    if (state == null ||
        state.finished ||
        state.phase != 'main' ||
        state.activePlayer != 'player' ||
        !state.player.coinAvailable) {
      return false;
    }
    _playCoinForSide(source: state.player, enemy: state.ai, owner: 'player');
    notifyListeners();
    return true;
  }

  bool _playCoinForSide({
    required BattleSide source,
    required BattleSide enemy,
    required String owner,
  }) {
    if (!source.coinAvailable) return false;
    source.coinAvailable = false;
    // The Coin is a real 0-cost spell: it counts as the previous card for
    // Combo even when Counterspell prevents its mana effect.
    source.cardsPlayedThisTurn++;
    final countered = _triggerSecrets(
      enemy,
      'opponent-plays-spell',
      triggeringSide: source,
    );
    if (countered) {
      stateLog(owner == 'player' ? '幸运币被反制。' : '敌方的幸运币被反制。');
      _processDeaths();
      _checkFinished();
      return true;
    }

    final absorbsOverloadDebt = source.overloadLocked > source.maxMana;
    if (absorbsOverloadDebt) {
      source.overloadLocked -= 1;
      stateLog(owner == 'player' ? '你使用幸运币' : '敌方演算体使用幸运币', '抵消 1 点过载锁定。');
    } else {
      source.mana += 1;
      stateLog(owner == 'player' ? '你使用幸运币' : '敌方演算体使用幸运币', '获得 1 点临时法力。');
    }
    _emitFx(
      'coin',
      owner == 'player' ? '幸运币' : '敌方使用幸运币',
      absorbsOverloadDebt ? '抵消 1 点过载锁定' : '获得 1 点临时法力',
      Icons.monetization_on,
      0xFFE7BD7A,
      amount: 1,
    );
    if (battle?.phase == 'main') {
      _resolveSpellTriggers(source: source, enemy: enemy);
    }
    _processDeaths();
    _checkFinished();
    return true;
  }

  BattleUnit _summonUnit(
    CardDefinition card, {
    required String owner,
    int? healthOverride,
    bool reborn = false,
  }) {
    final rush = card.keywords.contains('rush');
    final charge = card.keywords.contains('charge');
    return BattleUnit(
      instanceId:
          '$owner-${DateTime.now().microsecondsSinceEpoch}-${card.id}-${_random.nextInt(9999)}',
      card: card,
      owner: owner,
      attack: card.attack ?? 0,
      health: healthOverride ?? card.health ?? 1,
      maxHealth: card.health ?? 1,
      hasAttacked: !charge && !rush,
      divineShield: card.keywords.contains('shield') && !reborn,
      summoningSick: !charge && !rush,
      rushOnly: rush,
      stealthActive: card.keywords.contains('stealth'),
      rebornUsed: reborn,
    );
  }

  void _playCardForSide(
    CardDefinition card, {
    required BattleSide source,
    required BattleSide enemy,
    required String owner,
    int? handIndex,
    BattleUnit? target,
    bool targetHero = false,
  }) {
    final resolvedHandIndex = _resolveHandIndex(source, card, handIndex);
    if (resolvedHandIndex < 0) return;
    final effectiveCost = _effectiveHandCost(source, resolvedHandIndex);
    source.hand.removeAt(resolvedHandIndex);
    source.handCostReductions.removeAt(resolvedHandIndex);
    source.mana -= effectiveCost;
    final comboActive = source.cardsPlayedThisTurn > 0;
    source.cardsPlayedThisTurn++;
    if (card.type == 'spell' &&
        _triggerSecrets(
          enemy,
          'opponent-plays-spell',
          triggeringSide: source,
        )) {
      stateLog(
        owner == 'player' ? '${card.name} 被奥秘反制。' : '敌方的 ${card.name} 被奥秘反制。',
      );
      _processDeaths();
      return;
    }
    source.overloadLocked += card.overload;
    if (card.type == 'weapon') {
      final maxDurability = max(1, card.durability ?? card.health ?? 1);
      source.weapon = BattleWeapon(
        card: card,
        attack: card.attack ?? 0,
        durability: maxDurability,
        maxDurability: maxDurability,
      );
      source.heroHasAttacked = false;
      stateLog(owner == 'player' ? '${card.name} 已装备。' : '敌方装备 ${card.name}。');
      _emitFx(
        'weapon',
        '${card.name} 装备',
        '${card.attack ?? 0} 攻击 · $maxDurability 耐久',
        Icons.shield_moon,
        factionColors[card.faction] ?? 0xFFE7BD7A,
        sourceId: card.id,
      );
    } else if (card.isUnit) {
      final unit = _summonUnit(card, owner: owner);
      source.board.add(unit);
      _triggerSecrets(enemy, 'opponent-summons-unit', triggeringSide: source);
      source.board.length == 1 && owner == 'player'
          ? _emitFx(
              'summon',
              '${card.name} 登场',
              card.description,
              Icons.auto_awesome,
              factionColors[card.faction] ?? 0xFF69CFC3,
              sourceId: unit.instanceId,
            )
          : _emitFx(
              'summon',
              owner == 'player' ? '${card.name} 登场' : '敌方部署 ${card.name}',
              card.description,
              Icons.auto_awesome,
              factionColors[card.faction] ?? 0xFF69CFC3,
              sourceId: unit.instanceId,
            );
      stateLog(owner == 'player' ? '${card.name} 登场。' : '敌方部署 ${card.name}。');
      _resolveEffects(
        card.onPlay,
        source: source,
        enemy: enemy,
        target: target ?? (card.target == null ? unit : null),
        targetHero: targetHero,
        sourceName: card.name,
        sourceCard: card,
      );
      if (comboActive && card.combo.isNotEmpty && battle?.phase == 'main') {
        _resolveEffects(
          card.combo,
          source: source,
          enemy: enemy,
          target: target,
          targetHero: targetHero,
          sourceName: '${card.name} · 连击',
          sourceCard: card,
        );
      }
    } else {
      _emitFx(
        'spell',
        '${card.name} 释放',
        card.description,
        Icons.auto_awesome,
        factionColors[card.faction] ?? 0xFFA692D1,
        sourceId: card.id,
        amount: _cardEffectAmount(card),
      );
      _resolveEffects(
        card.effect,
        source: source,
        enemy: enemy,
        target: target,
        targetHero: targetHero,
        sourceName: card.name,
        sourceCard: card,
      );
      if (comboActive && card.combo.isNotEmpty && battle?.phase == 'main') {
        _resolveEffects(
          card.combo,
          source: source,
          enemy: enemy,
          target: target,
          targetHero: targetHero,
          sourceName: '${card.name} · 连击',
          sourceCard: card,
        );
      }
      if (battle?.phase == 'main') {
        _resolveSpellTriggers(source: source, enemy: enemy);
      }
      stateLog(card.name, card.description);
    }
    _processDeaths();
  }

  void _syncHandCostReductions(BattleSide side) {
    while (side.handCostReductions.length > side.hand.length) {
      side.handCostReductions.removeLast();
    }
    while (side.handCostReductions.length < side.hand.length) {
      side.handCostReductions.add(0);
    }
  }

  int _resolveHandIndex(
    BattleSide side,
    CardDefinition card,
    int? preferredIndex,
  ) {
    _syncHandCostReductions(side);
    if (preferredIndex != null &&
        preferredIndex >= 0 &&
        preferredIndex < side.hand.length &&
        side.hand[preferredIndex].id == card.id) {
      return preferredIndex;
    }
    return side.hand.indexWhere((item) => item.id == card.id);
  }

  int _effectiveHandCost(BattleSide side, int handIndex) {
    _syncHandCostReductions(side);
    if (handIndex < 0 || handIndex >= side.hand.length) return 0;
    return max(
      0,
      side.hand[handIndex].cost - side.handCostReductions[handIndex],
    );
  }

  int _occupiedHandSlots(BattleSide side) =>
      side.hand.length + (side.coinAvailable ? 1 : 0);

  bool _isPureSummonSpell(CardDefinition card, BattleSide source) {
    if (card.type != 'spell') return false;
    final resolvedEffects = <Map<String, dynamic>>[
      ...card.effect,
      if (source.cardsPlayedThisTurn > 0) ...card.combo,
    ];
    return resolvedEffects.isNotEmpty &&
        resolvedEffects.every((effect) => effect['kind'] == 'summon');
  }

  bool _validTarget(
    CardDefinition card,
    BattleSide source,
    BattleSide enemy,
    BattleUnit? target,
  ) {
    final targetType = card.target ?? '';
    if (!targetType.contains('unit')) return true;
    if (target == null) {
      return false;
    }
    if (target.stealthActive) return false;
    final friendly = targetType.startsWith('friendly');
    return friendly
        ? source.board.contains(target)
        : enemy.board.contains(target);
  }

  int _spellDamageBonus(BattleSide side) => side.board
      .where((unit) => !unit.silenced)
      .fold(0, (total, unit) => total + unit.card.spellDamage);

  void _resolveSpellTriggers({
    required BattleSide source,
    required BattleSide enemy,
  }) {
    for (final unit in [...source.board]) {
      if (!source.board.contains(unit) ||
          unit.silenced ||
          unit.card.onSpellPlayed.isEmpty) {
        continue;
      }
      _resolveEffects(
        unit.card.onSpellPlayed,
        source: source,
        enemy: enemy,
        target: unit,
        sourceName: '${unit.card.name} · 法术触发',
      );
    }
  }

  void _resolveEffects(
    List<Map<String, dynamic>> effects, {
    required BattleSide source,
    required BattleSide enemy,
    BattleUnit? target,
    bool targetHero = false,
    required String sourceName,
    CardDefinition? sourceCard,
  }) {
    _effectResolutionDepth++;
    try {
      for (final effect in effects) {
        final kind = effect['kind']?.toString();
        final amount = (effect['amount'] as num?)?.toInt() ?? 0;
        final spellBonus = sourceCard?.type == 'spell'
            ? _spellDamageBonus(source)
            : 0;
        final damageAmount = amount + spellBonus;
        switch (kind) {
          case 'secret':
            final secretId = effect['secretId']?.toString();
            final trigger = effect['trigger']?.toString();
            final secretEffect = effect['effect'];
            if (secretId != null &&
                trigger != null &&
                secretEffect is Map &&
                source.secrets.length < 5 &&
                !source.secrets.any((secret) => secret.secretId == secretId)) {
              source.secrets.add(
                BattleSecret(
                  card:
                      sourceCard ??
                      catalog.firstWhere(
                        (item) => sourceName.startsWith(item.name),
                        orElse: () => catalog.first,
                      ),
                  secretId: secretId,
                  trigger: trigger,
                  effect: Map<String, dynamic>.from(secretEffect),
                ),
              );
              stateLog(sourceName, '已暗置奥秘。');
            }
            break;
          case 'discover':
            final choices = effect['choices'];
            final state = battle;
            if (state != null && choices is List) {
              final validChoices = choices
                  .map((item) => item.toString())
                  .where((id) => card(id) != null)
                  .toList();
              if (validChoices.isNotEmpty) {
                state.phase = 'discover';
                state.discoverChoices = validChoices;
                state.discoverSource = sourceCard?.id ?? sourceName;
                state.discoverOwner = _ownerOf(source);
                stateLog(sourceName, '从候选档案中发现一张卡牌。');
                _emitFx(
                  'discover',
                  '发现选择',
                  '从 ${validChoices.length} 张候选卡牌中选择一张',
                  Icons.travel_explore,
                  0xFFA692D1,
                );
                return;
              }
            }
            break;
          case 'damage':
            if (target != null && enemy.board.contains(target)) {
              _damageUnit(target, damageAmount);
            } else {
              final dealt = _damageHero(enemy, damageAmount);
              stateLog('$sourceName：', '对敌方核心造成 $dealt 点伤害');
            }
            break;
          case 'damage-all-enemies':
            final dealt = _damageHero(enemy, damageAmount);
            for (final unit in [...enemy.board]) {
              _damageUnit(unit, damageAmount);
            }
            stateLog(
              sourceName,
              '对敌方核心和战场造成 $damageAmount 点范围伤害（核心实际 $dealt）。',
            );
            break;
          case 'freeze':
            if (target != null && enemy.board.contains(target)) {
              target.frozenTurns = max(target.frozenTurns, max(1, amount));
              stateLog(sourceName, '${target.card.name} 被冻结。');
            }
            break;
          case 'random-enemy-freeze':
            final candidates = enemy.board
                // Hearthstone random effects may hit Stealth units. Stealth
                // only prevents explicit targeting and attacks.
                .where((unit) => unit.health > 0)
                .toList();
            if (candidates.isNotEmpty) {
              final frozen = candidates[_random.nextInt(candidates.length)];
              frozen.frozenTurns = max(frozen.frozenTurns, max(1, amount));
              stateLog(sourceName, '${frozen.card.name} 被冻结。');
            }
            break;
          case 'random-enemy-damage':
            final candidates = [...enemy.board];
            if (candidates.isEmpty) {
              _damageHero(enemy, damageAmount);
            } else {
              final targets = <Object>[enemy, ...candidates];
              final picked = targets[_random.nextInt(targets.length)];
              if (picked is BattleSide) {
                _damageHero(picked, damageAmount);
              } else {
                _damageUnit(picked as BattleUnit, damageAmount);
              }
            }
            break;
          case 'heal':
            if (target != null && source.board.contains(target)) {
              target.health = min(target.maxHealth, target.health + amount);
            } else {
              final healed = _healHero(source, amount);
              if (healed > 0) {
                stateLog('$sourceName：', '恢复 $healed 点核心生命');
              }
            }
            break;
          case 'draw':
            final count = (effect['count'] as num?)?.toInt() ?? 1;
            for (var i = 0; i < count; i++) {
              _draw(source);
            }
            break;
          case 'buff':
            final unit = target != null && source.board.contains(target)
                ? target
                : source.board.isEmpty
                ? null
                : source.board.last;
            if (unit != null) {
              final attack = (effect['attack'] as num?)?.toInt() ?? 0;
              final health = (effect['health'] as num?)?.toInt() ?? 0;
              unit.attack += attack;
              unit.maxHealth += health;
              unit.health += health;
              unit.permanentAttackBonus += attack;
              unit.permanentHealthBonus += health;
              stateLog(
                '$sourceName：',
                '${unit.card.name} 获得 +$attack/+$health',
              );
            }
            break;
          case 'buff-all-friendly':
            final attack = (effect['attack'] as num?)?.toInt() ?? 0;
            final health = (effect['health'] as num?)?.toInt() ?? 0;
            for (final unit in [...source.board]) {
              unit.attack += attack;
              unit.maxHealth += health;
              unit.health += health;
              unit.permanentAttackBonus += attack;
              unit.permanentHealthBonus += health;
            }
            stateLog(sourceName, '友方全体获得 +$attack/+$health。');
            break;
          case 'temporary-buff':
            final unit = target != null && source.board.contains(target)
                ? target
                : source.board.isEmpty
                ? null
                : source.board.last;
            if (unit != null) {
              final attack = (effect['attack'] as num?)?.toInt() ?? 0;
              final health = (effect['health'] as num?)?.toInt() ?? 0;
              unit.attack += attack;
              unit.maxHealth += health;
              unit.health += health;
              unit.temporaryAttackBonus += attack;
              unit.temporaryHealthBonus += health;
              stateLog(sourceName, '${unit.card.name} 获得临时 +$attack/+$health。');
            }
            break;
          case 'silence':
            if (target == null) break;
            final targetSide = source.board.contains(target)
                ? source
                : enemy.board.contains(target)
                ? enemy
                : null;
            if (targetSide == null) break;
            target.attack = target.card.attack ?? 0;
            target.maxHealth = target.card.health ?? 1;
            target.health = min(target.health, target.maxHealth);
            target.permanentAttackBonus = 0;
            target.permanentHealthBonus = 0;
            target.temporaryAttackBonus = 0;
            target.temporaryHealthBonus = 0;
            target.silenced = true;
            target.divineShield = false;
            target.stealthActive = false;
            target.frozenTurns = 0;
            target.freezeBlocked = false;
            target.rushOnly = false;
            target.rebornUsed = true;
            stateLog(sourceName, '${target.card.name} 被沉默。');
            break;
          case 'transform':
            if (target == null) break;
            final cardId = effect['cardId']?.toString();
            final transformed = cardId == null ? null : card(cardId);
            if (transformed == null || !transformed.isUnit) break;
            final targetSide = source.board.contains(target)
                ? source
                : enemy.board.contains(target)
                ? enemy
                : null;
            if (targetSide == null) break;
            final index = targetSide.board.indexOf(target);
            if (index < 0) break;
            final replacement = _summonUnit(transformed, owner: target.owner);
            targetSide.board[index] = replacement;
            stateLog(
              sourceName,
              '${target.card.name} 变形为 ${transformed.name}。',
            );
            break;
          case 'choose-one':
            final options = effect['options'];
            final state = battle;
            if (state != null && options is List && options.length >= 2) {
              state.phase = 'choose-one';
              state.chooseOneOptions = options
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList();
              state.chooseOneSource = sourceName;
              state.chooseOneOwner = _ownerOf(source);
              state.chooseOneTarget = target;
              stateLog(sourceName, '请选择一个战术分支。');
              _emitFx(
                'choose-one',
                '抉择分支',
                '从多个效果中选择一个',
                Icons.alt_route,
                0xFFA692D1,
              );
              return;
            }
            break;
          case 'armor':
            source.armor += amount;
            break;
          case 'summon':
            final cardId = effect['cardId']?.toString();
            final summonCard = cardId == null ? null : card(cardId);
            final count = (effect['count'] as num?)?.toInt() ?? 1;
            if (summonCard != null && summonCard.isUnit) {
              for (var i = 0; i < count && source.board.length < 7; i++) {
                final unit = _summonUnit(summonCard, owner: _ownerOf(source));
                source.board.add(unit);
                _emitFx(
                  'summon',
                  '${summonCard.name} 被召唤',
                  '效果生成一个新的战场单位',
                  Icons.auto_awesome,
                  factionColors[summonCard.faction] ?? 0xFF69CFC3,
                  sourceId: unit.instanceId,
                );
              }
            }
            break;
        }
        _processDeaths();
      }
    } finally {
      _effectResolutionDepth--;
      if (_effectResolutionDepth == 0 && !_resolvingDeaths) {
        _processDeaths();
      }
    }
  }

  bool _triggerSecrets(
    BattleSide owner,
    String trigger, {
    required BattleSide triggeringSide,
    BattleUnit? attackingUnit,
  }) {
    final pending = owner.secrets
        .where((secret) => secret.trigger == trigger)
        .toList();
    if (pending.isEmpty) return false;
    var countered = false;
    for (final secret in pending) {
      owner.secrets.remove(secret);
      final kind = secret.effect['kind']?.toString();
      final amount = (secret.effect['amount'] as num?)?.toInt() ?? 0;
      switch (kind) {
        case 'counterspell':
          countered = true;
          stateLog('奥秘触发', '${secret.card.name} 反制了这张战术。');
          break;
        case 'damage-enemy-hero':
          final dealt = _damageHero(triggeringSide, amount);
          stateLog('奥秘触发', '${secret.card.name} 造成 $dealt 点核心伤害。');
          _emitFx(
            'secret',
            '${secret.card.name} 触发',
            '对敌方核心造成 $dealt 点伤害',
            Icons.auto_awesome,
            0xFFE46D3F,
            amount: dealt,
          );
          break;
        case 'damage-attacker':
          if (attackingUnit != null) {
            final dealt = _damageUnit(attackingUnit, amount);
            stateLog('奥秘触发', '${secret.card.name} 对攻击者造成 $dealt 点伤害。');
          } else {
            final dealt = _damageHero(triggeringSide, amount);
            stateLog('奥秘触发', '${secret.card.name} 对英雄造成 $dealt 点伤害。');
          }
          break;
        case 'armor':
          owner.armor += amount;
          stateLog('奥秘触发', '${secret.card.name} 让核心获得 $amount 点护甲。');
          break;
        case 'draw':
          final count = (secret.effect['count'] as num?)?.toInt() ?? 1;
          for (var i = 0; i < count; i++) {
            _draw(owner);
          }
          break;
      }
    }
    return countered;
  }

  bool chooseDiscover(String cardId) {
    final state = battle;
    if (state == null ||
        state.phase != 'discover' ||
        !state.discoverChoices.contains(cardId)) {
      return false;
    }
    final discovered = card(cardId);
    if (discovered == null) return false;
    final owner = state.discoverOwner == 'ai' ? state.ai : state.player;
    final enemy = identical(owner, state.player) ? state.ai : state.player;
    if (_occupiedHandSlots(owner) < 10) {
      owner.hand.add(discovered);
      _syncHandCostReductions(owner);
    } else {
      stateLog('发现失败', '${discovered.name} 因手牌已满被燃毁。');
    }
    state.phase = 'main';
    state.discoverChoices = <String>[];
    state.discoverSource = null;
    state.discoverOwner = 'player';
    stateLog('发现完成', '${discovered.name} 已加入手牌。');
    _resolveSpellTriggers(source: owner, enemy: enemy);
    _emitFx(
      'discover',
      '发现完成',
      '${discovered.name} 已加入手牌',
      Icons.check_circle_outline,
      0xFFA692D1,
    );
    notifyListeners();
    return true;
  }

  bool chooseOne(int optionIndex) {
    final state = battle;
    if (state == null ||
        state.phase != 'choose-one' ||
        optionIndex < 0 ||
        optionIndex >= state.chooseOneOptions.length) {
      return false;
    }
    final option = state.chooseOneOptions[optionIndex];
    final effects = option['effects'];
    if (effects is! List) return false;
    final source = state.chooseOneOwner == 'ai' ? state.ai : state.player;
    final enemy = identical(source, state.player) ? state.ai : state.player;
    final parsed = effects
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final sourceName = state.chooseOneSource ?? '抉择';
    final target = state.chooseOneTarget;
    state.phase = 'main';
    state.chooseOneOptions = <Map<String, dynamic>>[];
    state.chooseOneSource = null;
    state.chooseOneOwner = 'player';
    state.chooseOneTarget = null;
    _resolveEffects(
      parsed,
      source: source,
      enemy: enemy,
      target: target,
      sourceName: '$sourceName · ${option['label'] ?? '分支'}',
    );
    if (state.phase == 'main') {
      _resolveSpellTriggers(source: source, enemy: enemy);
    }
    stateLog('抉择完成', '已选择 ${option['label'] ?? '一个分支'}。');
    _processDeaths();
    _checkFinished();
    notifyListeners();
    return true;
  }

  bool attack(BattleUnit attacker, {BattleUnit? target}) {
    final state = battle;
    if (state == null ||
        state.finished ||
        state.activePlayer != 'player' ||
        state.phase != 'main' ||
        !attacker.canAttack ||
        !state.player.board.contains(attacker)) {
      return false;
    }
    final taunts = state.ai.board
        .where((unit) => unit.hasTaunt && !unit.stealthActive)
        .toList();
    if (taunts.isNotEmpty && (target == null || !target.hasTaunt)) {
      return false;
    }
    if (target != null && !state.ai.board.contains(target)) return false;
    if (target?.stealthActive ?? false) return false;
    if (target == null && attacker.rushOnly) return false;
    _performAttack(attacker, state.ai, target);
    _checkFinished();
    notifyListeners();
    return true;
  }

  void _performAttack(
    BattleUnit attacker,
    BattleSide defender,
    BattleUnit? target,
  ) {
    if (target == null) {
      _triggerSecrets(
        defender,
        'opponent-attacks-hero',
        triggeringSide: _sideFor(attacker),
        attackingUnit: attacker,
      );
      if (attacker.health <= 0 ||
          !_sideFor(attacker).board.contains(attacker)) {
        _processDeaths();
        return;
      }
    }
    attacker.stealthActive = false;
    attacker.attacksMade++;
    attacker.hasAttacked = true;
    final defenderName = target?.card.name ?? '敌方核心';
    // Both combatants deal their snapshotted attack at the same time. In
    // particular, a defender still retaliates when the incoming hit is lethal.
    final defenderAttack = target?.attack ?? 0;
    final defenderHasLifesteal = target?.hasLifesteal ?? false;
    final outgoing = target == null
        ? _damageHero(defender, attacker.attack)
        : _damageUnit(target, attacker.attack, source: attacker, combat: true);
    final reflected = target == null
        ? 0
        : _damageUnit(attacker, defenderAttack, source: target, combat: true);
    if (attacker.hasLifesteal && outgoing > 0) {
      final side = _sideFor(attacker);
      final healed = _healHero(side, outgoing);
      if (healed > 0) {
        stateLog('${attacker.card.name}：', '汲取 $healed 点生命');
        _emitFx(
          'heal',
          '生命汲取',
          '${attacker.card.name} 恢复自身核心',
          Icons.favorite,
          0xFF79B980,
        );
      }
    }
    if (target != null && defenderHasLifesteal && reflected > 0) {
      final side = _sideFor(target);
      _healHero(side, reflected);
    }
    _emitFx(
      'attack',
      '${attacker.card.name} 发起攻击',
      target == null ? '对敌方核心造成 $outgoing 点伤害' : '与 $defenderName 发生交战',
      Icons.flash_on,
      0xFFE46D3F,
      sourceId: attacker.instanceId,
      targetId: target?.instanceId ?? 'ai-hero',
      amount: outgoing,
    );
    stateLog(
      attacker.card.name,
      target == null ? '对敌方核心造成 $outgoing 点伤害。' : '与 $defenderName 交战。',
    );
    _processDeaths();
  }

  int _damageHero(BattleSide side, int amount) {
    if (amount <= 0) return 0;
    final absorbed = min(side.armor, amount);
    side.armor -= absorbed;
    final healthDamage = amount - absorbed;
    side.heroHealth = max(0, side.heroHealth - healthDamage);
    return healthDamage;
  }

  bool _heroIsMarkedForDeath(BattleSide side) {
    final state = battle;
    if (state == null) return false;
    return identical(side, state.player)
        ? state.playerHeroMarkedForDeath
        : state.aiHeroMarkedForDeath;
  }

  int _healHero(BattleSide side, int amount) {
    if (amount <= 0 || _heroIsMarkedForDeath(side)) return 0;
    final before = side.heroHealth;
    side.heroHealth = min(side.maxHeroHealth, side.heroHealth + amount);
    return side.heroHealth - before;
  }

  int _damageUnit(
    BattleUnit unit,
    int amount, {
    BattleUnit? source,
    bool combat = false,
  }) {
    if (amount <= 0 || unit.health <= 0) return 0;
    if (unit.divineShield) {
      unit.divineShield = false;
      _emitFx(
        'shield',
        '护盾破碎',
        '${unit.card.name} 的护盾抵消了伤害',
        Icons.shield,
        0xFFE7BD7A,
        sourceId: unit.instanceId,
        targetId: unit.instanceId,
      );
      return 0;
    }
    final applied = min(unit.health, amount);
    unit.health = max(0, unit.health - amount);
    if (source?.hasPoisonous == true && applied > 0 && unit.health > 0) {
      unit.health = 0;
      stateLog('${source!.card.name}：', '${unit.card.name} 受到剧毒。');
      _emitFx(
        'poison',
        '剧毒生效',
        '${unit.card.name} 被剧毒摧毁',
        Icons.coronavirus,
        0xFF79B980,
        sourceId: source.instanceId,
        targetId: unit.instanceId,
      );
    }
    if (combat && unit.hasFury && !unit.furyTriggered && unit.health > 0) {
      unit.furyTriggered = true;
      unit.attack += 1;
      stateLog('${unit.card.name}：', '激昂触发，攻击力 +1');
      _emitFx(
        'fury',
        '激昂触发',
        '${unit.card.name} 获得 +1 攻击',
        Icons.whatshot,
        0xFFE46D3F,
        sourceId: unit.instanceId,
        targetId: unit.instanceId,
      );
    }
    return applied;
  }

  BattleSide _sideFor(BattleUnit unit) {
    final state = battle!;
    return unit.owner == 'player' ? state.player : state.ai;
  }

  String _ownerOf(BattleSide side) {
    final state = battle!;
    return identical(side, state.player) ? 'player' : 'ai';
  }

  void _markHeroesForDeath(BattleState state) {
    if (state.player.heroHealth <= 0) {
      state.playerHeroMarkedForDeath = true;
    }
    if (state.ai.heroHealth <= 0) {
      state.aiHeroMarkedForDeath = true;
    }
  }

  void _processDeaths() {
    final state = battle;
    if (state == null || _resolvingDeaths || _effectResolutionDepth > 0) {
      return;
    }
    final deathQueue = <_QueuedDeath>[];
    final rebornQueue = <_QueuedDeath>[];

    void enqueueDeadUnits() {
      for (final side in [state.player, state.ai]) {
        final enemy = identical(side, state.player) ? state.ai : state.player;
        final dead = side.board.where((unit) => unit.health <= 0).toList();
        if (dead.isEmpty) continue;
        // Lock the complete simultaneous death wave before any Deathrattle can
        // inspect or refill those battlefield slots.
        side.board.removeWhere((unit) => unit.health <= 0);
        deathQueue.addAll(
          dead.map(
            (unit) => _QueuedDeath(unit: unit, side: side, enemy: enemy),
          ),
        );
      }
    }

    _resolvingDeaths = true;
    try {
      // Death creation is irreversible for heroes. Healing later in this
      // death window may change the displayed health, but cannot clear a loss.
      _markHeroesForDeath(state);
      enqueueDeadUnits();
      var deathIndex = 0;
      var rebornIndex = 0;
      while (deathIndex < deathQueue.length ||
          rebornIndex < rebornQueue.length) {
        // All Deathrattles, including later waves created by earlier
        // Deathrattles, resolve before the first queued Reborn.
        while (deathIndex < deathQueue.length) {
          final entry = deathQueue[deathIndex++];
          final unit = entry.unit;
          stateLog('亡语回响', '${unit.card.name} 离开战场。');
          _emitFx(
            'death',
            '${unit.card.name} 被摧毁',
            '战场位置已释放',
            Icons.blur_on,
            0xFF9D7567,
            sourceId: unit.instanceId,
            targetId: unit.instanceId,
          );
          if (unit.card.hasDeathrattle && !unit.silenced) {
            _resolveEffects(
              unit.card.onDeath,
              source: entry.side,
              enemy: entry.enemy,
              sourceName: '${unit.card.name} 的亡语',
              sourceCard: unit.card,
            );
          }
          _markHeroesForDeath(state);
          if (unit.hasReborn && !unit.rebornUsed) {
            rebornQueue.add(entry);
          }
          enqueueDeadUnits();
        }

        if (rebornIndex >= rebornQueue.length) break;
        final entry = rebornQueue[rebornIndex++];
        if (entry.side.board.length >= 7) continue;
        final unit = entry.unit;
        final reborn = _summonUnit(
          unit.card,
          owner: unit.owner,
          healthOverride: 1,
          reborn: true,
        );
        entry.side.board.add(reborn);
        stateLog('复生回响', '${unit.card.name} 以 1 点生命回到战场。');
        _emitFx(
          'reborn',
          '${unit.card.name} 复生',
          '以 1 点生命重新回到战场',
          Icons.autorenew,
          0xFFA692D1,
          sourceId: reborn.instanceId,
        );
        // Reborn is a summon for secret/trigger purposes.
        _triggerSecrets(
          entry.enemy,
          'opponent-summons-unit',
          triggeringSide: entry.side,
        );
        _markHeroesForDeath(state);
        enqueueDeadUnits();
      }
    } finally {
      _resolvingDeaths = false;
    }
  }

  Future<void> endTurn() async {
    final state = battle;
    if (state == null ||
        state.finished ||
        state.phase != 'main' ||
        state.activePlayer != 'player') {
      return;
    }
    if (isResolvingTurn) return;
    isResolvingTurn = true;
    _turnTimer?.cancel();
    _resolveTurnTriggers(state.player, start: false);
    _clearTemporaryBuffs(state.player);
    _settleFreezeAtEndOfTurn(state.player);
    _processDeaths();
    _checkFinished();
    if (state.finished) {
      isResolvingTurn = false;
      notifyListeners();
      return;
    }
    state.phase = 'end';
    if (!_advanceActionWindow(state, 'ai')) {
      isResolvingTurn = false;
      notifyListeners();
      return;
    }
    state.logs.insert(0, '你结束回合，敌方演算体获得行动权。');
    _emitFx('turn', '回合交接', '敌方演算体开始行动', Icons.swap_vert, 0xFFA692D1);
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 700));
    _beginSideTurn(state, owner: 'ai');
    if (!state.finished) await _aiTurn(state);
    if (!state.finished) {
      if (_advanceActionWindow(state, 'player')) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
        _beginSideTurn(state, owner: 'player');
        state.logs.insert(
          0,
          '第 ${state.turn} 回合开始，法力恢复至 ${state.player.mana}。',
        );
        _emitFx(
          'turn',
          '第 ${state.turn} 回合',
          '你的法力已恢复，轮到你行动',
          Icons.hourglass_top,
          0xFF69CFC3,
        );
        _startTurnTimer();
      }
    }
    isResolvingTurn = false;
    notifyListeners();
  }

  Future<void> _aiTurn(BattleState state) async {
    if (state.finished) return;
    if (state.ai.coinAvailable &&
        state.ai.hand.any(
          (card) => card.cost > state.ai.mana && card.cost <= state.ai.mana + 1,
        )) {
      _playCoinForSide(source: state.ai, enemy: state.player, owner: 'ai');
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (state.finished) return;
    }
    state.aiHeroPowerUsed = false;
    final aiPowerTarget = _aiHeroPowerTarget(state);
    final aiPowerTargetsHero =
        aiPowerTarget == null &&
        state.aiHeroPower.target == 'friendly-character' &&
        state.ai.heroHealth < state.ai.maxHeroHealth;
    if (!state.aiHeroPowerUsed &&
        _canResolveHeroPower(
          state.aiHeroPower,
          source: state.ai,
          enemy: state.player,
          target: aiPowerTarget,
          targetHero: aiPowerTargetsHero,
        ) &&
        _resolveHeroPower(
          state.aiHeroPower,
          source: state.ai,
          enemy: state.player,
          owner: 'ai',
          target: aiPowerTarget,
          targetHero: aiPowerTargetsHero,
        )) {
      _checkFinished();
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 1050));
    }
    while (!state.finished) {
      _syncHandCostReductions(state.ai);
      final candidates =
          List<int>.generate(state.ai.hand.length, (index) => index)..sort(
            (left, right) => _effectiveHandCost(
              state.ai,
              left,
            ).compareTo(_effectiveHandCost(state.ai, right)),
          );
      int? handIndex;
      CardDefinition? card;
      BattleUnit? target;
      for (final candidateIndex in candidates) {
        final candidate = state.ai.hand[candidateIndex];
        if (_effectiveHandCost(state.ai, candidateIndex) > state.ai.mana ||
            (candidate.isUnit && state.ai.board.length >= 7) ||
            (state.ai.board.length >= 7 &&
                _isPureSummonSpell(candidate, state.ai))) {
          continue;
        }
        final candidateTarget = _aiTarget(candidate, state);
        if (!_validTarget(candidate, state.ai, state.player, candidateTarget)) {
          continue;
        }
        handIndex = candidateIndex;
        card = candidate;
        target = candidateTarget;
        break;
      }
      if (handIndex == null || card == null) break;
      _playCardForSide(
        card,
        source: state.ai,
        enemy: state.player,
        owner: 'ai',
        handIndex: handIndex,
        target: target,
      );
      if (state.phase == 'discover' &&
          state.discoverOwner == 'ai' &&
          state.discoverChoices.isNotEmpty) {
        chooseDiscover(state.discoverChoices.first);
      }
      if (state.phase == 'choose-one' &&
          state.chooseOneOwner == 'ai' &&
          state.chooseOneOptions.isNotEmpty) {
        chooseOne(0);
      }
      _checkFinished();
      notifyListeners();
      // Leave enough room for the client-side cast, card flight and impact
      // beats to finish before the next AI action starts.
      await Future<void>.delayed(const Duration(milliseconds: 1280));
    }
    if (state.finished) return;
    _syncHandCostReductions(state.ai);
    if (state.ai.mana > 0) {
      final candidates =
          state.ai.hand
              .asMap()
              .entries
              .where(
                (entry) =>
                    entry.value.preparable &&
                    state.ai.handCostReductions[entry.key] == 0,
              )
              .toList()
            ..sort(
              (left, right) => right.value.cost.compareTo(left.value.cost),
            );
      if (candidates.isNotEmpty) {
        final prepared = candidates.first;
        final manaSpent = state.ai.mana;
        final reduction = manaSpent + 1;
        state.ai.mana = 0;
        state.ai.handCostReductions[prepared.key] = reduction;
        state.logs.insert(0, '敌方完成预备，一张手牌降低 $reduction 点费用。');
        _emitFx(
          'prepare',
          '敌方完成预备',
          '一张手牌降低 $reduction 点费用',
          Icons.keyboard_double_arrow_down,
          0xFFA692D1,
          amount: reduction,
        );
        notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
    final attackers = [...state.ai.board];
    final taunts = state.player.board
        .where((unit) => unit.hasTaunt && !unit.stealthActive)
        .toList();
    for (final unit in attackers) {
      if (state.finished || !unit.canAttack || !state.ai.board.contains(unit)) {
        continue;
      }
      final visibleUnits = state.player.board
          .where((candidate) => !candidate.stealthActive)
          .toList();
      if (unit.rushOnly && visibleUnits.isEmpty) continue;
      final targetPool = taunts.isNotEmpty ? taunts : visibleUnits;
      final target = unit.rushOnly || taunts.isNotEmpty
          ? (targetPool.isEmpty
                ? null
                : targetPool[_random.nextInt(targetPool.length)])
          : null;
      _performAttack(unit, state.player, target);
      _checkFinished();
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 1380));
    }
    if (!state.finished &&
        state.ai.weapon != null &&
        !state.ai.heroHasAttacked &&
        state.ai.weapon!.durability > 0) {
      final taunts = state.player.board
          .where((unit) => unit.hasTaunt && !unit.stealthActive)
          .toList();
      final visible = state.player.board
          .where((unit) => !unit.stealthActive)
          .toList();
      final targetPool = taunts.isNotEmpty ? taunts : visible;
      final target = targetPool.isEmpty
          ? null
          : targetPool[_random.nextInt(targetPool.length)];
      _aiHeroAttack(state, target);
      _checkFinished();
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 1380));
    }
    _resolveTurnTriggers(state.ai, start: false);
    _clearTemporaryBuffs(state.ai);
    _settleFreezeAtEndOfTurn(state.ai);
    _processDeaths();
    _checkFinished();
  }

  void _aiHeroAttack(BattleState state, BattleUnit? target) {
    final weapon = state.ai.weapon;
    if (weapon == null || weapon.durability <= 0) return;
    if (target == null) {
      _triggerSecrets(
        state.player,
        'opponent-attacks-hero',
        triggeringSide: state.ai,
      );
      if (state.ai.heroHealth <= 0) {
        _processDeaths();
        _checkFinished();
        return;
      }
    }
    final defenderAttack = target?.attack ?? 0;
    final defenderHasLifesteal = target?.hasLifesteal ?? false;
    final dealt = target == null
        ? _damageHero(state.player, weapon.attack)
        : _damageUnit(target, weapon.attack, combat: true);
    if (target != null) {
      final reflected = _damageHero(state.ai, defenderAttack);
      if (defenderHasLifesteal && reflected > 0) {
        _healHero(state.player, reflected);
      }
    }
    state.ai.heroHasAttacked = true;
    weapon.durability--;
    state.logs.insert(
      0,
      target == null
          ? '敌方英雄使用 ${weapon.card.name} 攻击核心，造成 $dealt 点伤害。'
          : '敌方英雄使用 ${weapon.card.name} 攻击 ${target.card.name}。',
    );
    _emitFx(
      'attack',
      '敌方英雄攻击',
      target == null ? '你的核心受到 $dealt 点伤害' : '英雄与 ${target.card.name} 交战',
      Icons.flash_on,
      0xFFE46D3F,
      sourceId: 'ai-hero',
      targetId: target?.instanceId ?? 'player-hero',
      amount: dealt,
    );
    if (weapon.durability <= 0) state.ai.weapon = null;
    _processDeaths();
  }

  void _refreshSideForTurn(BattleSide side) {
    side.heroHasAttacked = false;
    side.cardsPlayedThisTurn = 0;
    for (final unit in side.board) {
      unit.attacksMade = 0;
      if (unit.frozenTurns > 0) {
        unit.attacksMade = unit.attackLimit;
        unit.hasAttacked = true;
        unit.summoningSick = false;
        unit.freezeBlocked = true;
      } else {
        unit.hasAttacked = false;
        unit.summoningSick = false;
        unit.rushOnly = false;
        unit.freezeBlocked = false;
      }
    }
  }

  /// Consume Freeze after the character has actually lost its next attack.
  /// A character frozen after attacking carries the lock into its next turn;
  /// a character frozen before it could attack thaws at this turn's end.
  void _settleFreezeAtEndOfTurn(BattleSide side) {
    for (final unit in side.board) {
      if (unit.frozenTurns <= 0) {
        unit.freezeBlocked = false;
        continue;
      }
      final missedCurrentTurnAttack =
          !unit.summoningSick &&
          unit.attack > 0 &&
          unit.attacksMade < unit.attackLimit;
      if (unit.freezeBlocked || missedCurrentTurnAttack) {
        unit.frozenTurns = max(0, unit.frozenTurns - 1);
        unit.freezeBlocked = false;
      }
    }
  }

  void _resolveTurnTriggers(BattleSide side, {required bool start}) {
    final state = battle;
    if (state == null) return;
    final enemy = identical(side, state.player) ? state.ai : state.player;
    for (final unit in [...side.board]) {
      if (!side.board.contains(unit) || unit.silenced) continue;
      final effects = start ? unit.card.onTurnStart : unit.card.onTurnEnd;
      if (effects.isEmpty) continue;
      _resolveEffects(
        effects,
        source: side,
        enemy: enemy,
        target: unit,
        sourceName: '${unit.card.name} · ${start ? '回合开始' : '回合结束'}',
        sourceCard: unit.card,
      );
      if (state.finished) break;
    }
  }

  void _clearTemporaryBuffs(BattleSide side) {
    for (final unit in side.board) {
      if (unit.temporaryAttackBonus != 0) {
        unit.attack -= unit.temporaryAttackBonus;
        unit.temporaryAttackBonus = 0;
      }
      if (unit.temporaryHealthBonus != 0) {
        unit.maxHealth -= unit.temporaryHealthBonus;
        unit.health = min(unit.health, unit.maxHealth);
        unit.temporaryHealthBonus = 0;
      }
    }
  }

  void _refillMana(BattleSide side) {
    side.maxMana = min(10, side.maxMana + 1);
    final locked = min(side.maxMana, side.overloadLocked);
    side.overloadLocked = 0;
    side.mana = side.maxMana - locked;
    if (locked > 0) {
      stateLog(
        identical(battle?.player, side) ? '过载' : '敌方过载',
        '下回合锁定 $locked 个法力水晶。',
      );
      _emitFx(
        'overload',
        '过载锁定',
        '本回合可用法力减少 $locked',
        Icons.lock_clock,
        0xFFE46D3F,
        amount: locked,
      );
    }
  }

  BattleUnit? _aiTarget(CardDefinition card, BattleState state) {
    final type = card.target ?? '';
    if (type.startsWith('friendly')) {
      if (type.contains('unit')) {
        return state.ai.board.isEmpty ? null : state.ai.board.first;
      }
      return null;
    }
    if (type.startsWith('enemy') && type.contains('unit')) {
      return state.player.board.isEmpty ? null : state.player.board.first;
    }
    return null;
  }

  BattleUnit? _aiHeroPowerTarget(BattleState state) {
    switch (state.aiHeroPower.target) {
      case 'enemy-unit':
        final visible =
            state.player.board
                .where((unit) => !unit.stealthActive && unit.health > 0)
                .toList()
              ..sort((left, right) => left.health.compareTo(right.health));
        return visible.isEmpty ? null : visible.first;
      case 'friendly-unit':
      case 'friendly-character':
        final damaged =
            state.ai.board
                .where(
                  (unit) => unit.health > 0 && unit.health < unit.maxHealth,
                )
                .toList()
              ..sort(
                (left, right) => (left.maxHealth - left.health).compareTo(
                  right.maxHealth - right.health,
                ),
              );
        return damaged.isEmpty ? null : damaged.first;
      default:
        return null;
    }
  }

  bool _advanceActionWindow(BattleState state, String nextPlayer) {
    state.activePlayer = nextPlayer;
    state.actionWindow++;
    if (state.actionWindow > maxBattleActionWindows) {
      _finishBattle(winner: null, reason: 'draw');
      return false;
    }
    return true;
  }

  void _finishBattle({required String? winner, required String reason}) {
    final state = battle;
    if (state == null || state.finished) return;
    state.finished = true;
    state.phase = 'game-over';
    state.winner = winner;
    state.endReason = reason;
    _turnTimer?.cancel();

    var reward = 0;
    if (winner == 'player') {
      wins++;
      reward = 60;
    } else if (winner == 'ai') {
      losses++;
      reward = 20;
    }
    gold += reward;
    matchesPlayed++;
    _prefs?.setInt('wins', wins);
    _prefs?.setInt('losses', losses);
    _prefs?.setInt('matches', matchesPlayed);
    _prefs?.setInt('gold', gold);

    if (winner == null) {
      final reachedTurnLimit = state.actionWindow > maxBattleActionWindows;
      state.logs.insert(
        0,
        reachedTurnLimit ? '已结算 89 个行动窗口，第 90 个窗口不会开启，对局平局。' : '双方核心同时失效，对局平局。',
      );
      _emitFx('draw', '演算平局', '本局不计入胜负', Icons.balance, 0xFFE7BD7A);
      return;
    }

    final victory = winner == 'player';
    state.logs.insert(0, victory ? '演算胜利，获得 60 金币。' : '演算结束，获得 20 金币。');
    _emitFx(
      victory ? 'victory' : 'defeat',
      victory ? '演算胜利' : '演算结束',
      victory ? '战报已归档，获得 60 金币' : '保留战术日志，获得 20 金币',
      victory ? Icons.emoji_events : Icons.close,
      victory ? 0xFFE7BD7A : 0xFFE46D3F,
    );
  }

  void _checkFinished() {
    final state = battle;
    if (state == null || state.finished) return;
    final playerDead =
        state.playerHeroMarkedForDeath || state.player.heroHealth <= 0;
    final aiDead = state.aiHeroMarkedForDeath || state.ai.heroHealth <= 0;
    if (!playerDead && !aiDead) return;
    if (playerDead && aiDead) {
      _finishBattle(winner: null, reason: 'draw');
    } else {
      _finishBattle(
        winner: playerDead ? 'ai' : 'player',
        reason: 'hero-defeated',
      );
    }
  }

  void stateLog(String title, [String? description]) {
    final state = battle;
    if (state == null) return;
    state.logs.insert(0, description == null ? title : '$title$description');
    if (state.logs.length > 20) state.logs.removeLast();
  }

  void _emitFx(
    String kind,
    String title,
    String subtitle,
    IconData icon,
    int color, {
    String? sourceId,
    String? targetId,
    int? amount,
  }) {
    final state = battle;
    if (state == null) return;
    state.fxSequence++;
    state.fx = BattleFxEvent(
      kind: kind,
      title: title,
      subtitle: subtitle,
      icon: icon.codePoint,
      color: color,
      sequence: state.fxSequence,
      sourceId: sourceId,
      targetId: targetId,
      amount: amount,
    );
  }

  int? _cardEffectAmount(CardDefinition card) {
    for (final effect in [...card.effect, ...card.onPlay]) {
      final value = effect['amount'];
      if (value is num && value > 0) return value.toInt();
    }
    return null;
  }

  @override
  void dispose() {
    _turnTimer?.cancel();
    super.dispose();
  }
}

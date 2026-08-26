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

  @override
  void notifyListeners() {
    final state = battle;
    if (state != null && state.phase != 'mulligan') {
      _syncCoinMirror(state.player);
      _syncCoinMirror(state.ai);
    }
    super.notifyListeners();
  }

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
  int _shatterGroupSequence = 0;
  int _discardSequence = 0;
  int _cardEntitySequence = 0;

  String _nextCardEntityId() => 'mobile-card-${_cardEntitySequence++}';
  String? _declinedClipboardDeckCode;
  Future<void> _deckPersistQueue = Future<void>.value();

  Map<String, CardDefinition> get cardsById => {
    for (final card in catalog) card.id: card,
    for (final card in generatedBattleCards) card.id: card,
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
      faction: playerFaction,
      heroHealth: 30,
      maxHeroHealth: 30,
      mana: 1,
      maxMana: 1,
      deck: playerDeck,
      deckCostOverrides: List<int?>.filled(playerDeck.length, null),
      deckEntityIds: List<String>.generate(
        playerDeck.length,
        (_) => _nextCardEntityId(),
      ),
      hand: [],
      board: [],
      coinAvailable: playerIsSecond,
      coinEntityId: playerIsSecond ? _nextCardEntityId() : null,
    );
    final ai = BattleSide(
      faction: aiFaction,
      heroHealth: 30,
      maxHeroHealth: 30,
      mana: 1,
      maxMana: 1,
      deck: aiDeck,
      deckCostOverrides: List<int?>.filled(aiDeck.length, null),
      deckEntityIds: List<String>.generate(
        aiDeck.length,
        (_) => _nextCardEntityId(),
      ),
      hand: [],
      board: [],
      coinAvailable: aiIsSecond,
      coinEntityId: aiIsSecond ? _nextCardEntityId() : null,
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
    _syncHandCostReductions(state.player);
    final groupId = state.player.handFragments[index]?.groupId;
    final linkedIndexes = groupId == null
        ? <int>[index]
        : state.player.handFragments
              .asMap()
              .entries
              .where((entry) => entry.value?.groupId == groupId)
              .map((entry) => entry.key)
              .toList();
    final shouldSelect = !linkedIndexes.every(state.mulliganSelected.contains);
    for (final linkedIndex in linkedIndexes) {
      if (shouldSelect) {
        state.mulliganSelected.add(linkedIndex);
      } else {
        state.mulliganSelected.remove(linkedIndex);
      }
    }
    notifyListeners();
  }

  Future<void> confirmMulligan() async {
    final state = battle;
    if (state == null || state.phase != 'mulligan' || state.mulliganDone) {
      return;
    }
    final selected = _expandedMulliganIndexes(
      state.player,
      state.mulliganSelected,
    );
    final returned =
        <({CardDefinition card, bool startedInDeck, String entityId})>[];
    final returnedGroups = <String>{};
    _syncHandCostReductions(state.player);
    for (final index in selected.reversed) {
      if (index >= 0 && index < state.player.hand.length) {
        final fragment = state.player.handFragments[index];
        final startedInDeck = state.player.handStartedInDeck[index];
        final entityId = state.player.handEntityIds[index];
        final removed = state.player.hand.removeAt(index);
        if (fragment == null || returnedGroups.add(fragment.groupId)) {
          returned.add((
            card: card(removed.id) ?? removed,
            startedInDeck: startedInDeck,
            entityId: entityId,
          ));
        }
        state.player.handCostReductions.removeAt(index);
        state.player.handFragments.removeAt(index);
        state.player.handStartedInDeck.removeAt(index);
        state.player.handEnteredTurns.removeAt(index);
        state.player.handEntityIds.removeAt(index);
      }
    }
    for (var i = 0; i < returned.length; i++) {
      if (state.player.deck.isNotEmpty) _draw(state.player);
    }
    if (returned.isNotEmpty) {
      state.player.deck.addAll(returned.map((entry) => entry.card));
      state.player.deckCostOverrides.addAll(
        List<int?>.filled(returned.length, null),
      );
      state.player.deckStartedInDeck.addAll(
        returned.map((entry) => entry.startedInDeck),
      );
      state.player.deckEntityIds.addAll(
        returned.map((entry) => entry.entityId),
      );
      _shuffleDeck(state.player);
    }
    state.mulliganSelected.clear();
    state.mulliganDone = true;
    state.logs.insert(
      0,
      returned.isEmpty ? '起手牌已确认。' : '起手换牌完成，替换 ${returned.length} 张牌。',
    );

    _ensureCoinInHand(state.player);
    _ensureCoinInHand(state.ai);

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
    final returned =
        <({CardDefinition card, bool startedInDeck, String entityId})>[];
    _syncHandCostReductions(side);
    final returnIndexes = _expandedMulliganIndexes(
      side,
      side.hand.asMap().keys.where((index) => !keep.contains(index)),
    );
    final returnedGroups = <String>{};
    for (final index in returnIndexes.reversed) {
      final fragment = side.handFragments[index];
      final startedInDeck = side.handStartedInDeck[index];
      final entityId = side.handEntityIds[index];
      final removed = side.hand.removeAt(index);
      if (fragment == null || returnedGroups.add(fragment.groupId)) {
        returned.add((
          card: card(removed.id) ?? removed,
          startedInDeck: startedInDeck,
          entityId: entityId,
        ));
      }
      side.handCostReductions.removeAt(index);
      side.handFragments.removeAt(index);
      side.handStartedInDeck.removeAt(index);
      side.handEnteredTurns.removeAt(index);
      side.handEntityIds.removeAt(index);
    }
    for (var i = 0; i < returned.length; i++) {
      if (side.deck.isNotEmpty) _draw(side);
    }
    side.deck.addAll(returned.map((entry) => entry.card));
    side.deckCostOverrides.addAll(List<int?>.filled(returned.length, null));
    side.deckStartedInDeck.addAll(returned.map((entry) => entry.startedInDeck));
    side.deckEntityIds.addAll(returned.map((entry) => entry.entityId));
    _shuffleDeck(side);
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
      _syncDeckCostOverrides(side);
      final drawn = side.deck.removeLast();
      final costOverride = side.deckCostOverrides.removeLast();
      final startedInDeck = side.deckStartedInDeck.removeLast();
      final entityId = side.deckEntityIds.removeLast();
      if (_resolveDrawnCard(
        side,
        drawn,
        costOverride: costOverride,
        startedInDeck: startedInDeck,
        entityId: entityId,
      )) {
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

  bool _resolveDrawnCard(
    BattleSide side,
    CardDefinition drawn, {
    int? costOverride,
    bool startedInDeck = false,
    required String entityId,
  }) {
    if (!drawn.castsWhenDrawn) {
      return _addCardToHand(
        side,
        drawn,
        costOverride: costOverride,
        startedInDeck: startedInDeck,
        entityId: entityId,
        sourceZone: 'deck',
      );
    }
    final state = battle;
    if (state == null) return true;
    final enemy = identical(side, state.player) ? state.ai : state.player;
    stateLog(drawn.name, '抽到时自动施放，然后抽取替代牌。');
    _emitFx(
      'spell',
      '${drawn.name} · 抽到时施放',
      drawn.description,
      Icons.bolt,
      factionColors[drawn.faction] ?? 0xFFE46D3F,
      sourceId: drawn.id,
      amount: _cardEffectAmount(drawn),
    );
    if (drawn.school != null) {
      side.spellSchoolsPlayedThisTurn.add(drawn.school!);
    }
    _resolveEffects(
      drawn.effect,
      source: side,
      enemy: enemy,
      sourceName: drawn.name,
      sourceCard: drawn,
    );
    _resolveSpellTriggers(source: side, enemy: enemy);
    _sendCardToGraveyard(
      side,
      drawn,
      entityId,
      fromZone: 'deck',
      reason: 'cast-when-drawn',
    );
    _draw(side);
    return true;
  }

  bool _drawMinionType(BattleSide side, String minionType) {
    _syncDeckCostOverrides(side);
    final matchIndex = side.deck.lastIndexWhere(
      (candidate) => candidate.isUnit && hasMinionType(candidate, minionType),
    );
    // A failed search is not an empty-deck draw and therefore never creates
    // Fatigue or substitutes an unrelated card.
    if (matchIndex < 0) return false;
    final drawn = side.deck.removeAt(matchIndex);
    final costOverride = side.deckCostOverrides.removeAt(matchIndex);
    final startedInDeck = side.deckStartedInDeck.removeAt(matchIndex);
    final entityId = side.deckEntityIds.removeAt(matchIndex);
    if (_resolveDrawnCard(
      side,
      drawn,
      costOverride: costOverride,
      startedInDeck: startedInDeck,
      entityId: entityId,
    )) {
      return true;
    }
    stateLog(
      _ownerOf(side) == 'player' ? '手牌已满' : '敌方手牌已满',
      ' ${drawn.name} 被燃毁。',
    );
    return true;
  }

  bool _drawSpellSchool(BattleSide side, String school) {
    _syncDeckCostOverrides(side);
    final matchIndex = side.deck.lastIndexWhere(
      (candidate) => candidate.type == 'spell' && candidate.school == school,
    );
    if (matchIndex < 0) return false;
    final drawn = side.deck.removeAt(matchIndex);
    final costOverride = side.deckCostOverrides.removeAt(matchIndex);
    final startedInDeck = side.deckStartedInDeck.removeAt(matchIndex);
    final entityId = side.deckEntityIds.removeAt(matchIndex);
    if (_resolveDrawnCard(
      side,
      drawn,
      costOverride: costOverride,
      startedInDeck: startedInDeck,
      entityId: entityId,
    )) {
      return true;
    }
    stateLog(
      _ownerOf(side) == 'player' ? '手牌已满' : '敌方手牌已满',
      ' ${drawn.name} 被燃毁。',
    );
    return true;
  }

  bool _spellSchoolPayoffActive(BattleSide side, Map<String, dynamic> effect) {
    final history = effect['window'] == 'last-turn'
        ? side.spellSchoolsPlayedLastTurn
        : side.spellSchoolsPlayedThisTurn;
    final distinct = history.toSet();
    final requiredSchool = effect['requiredSchool']?.toString();
    final minimumDistinct = max(
      1,
      (effect['minimumDistinct'] as num?)?.toInt() ?? 1,
    );
    return (requiredSchool == null || distinct.contains(requiredSchool)) &&
        distinct.length >= minimumDistinct;
  }

  bool _addCardToHand(
    BattleSide side,
    CardDefinition drawn, {
    int? costOverride,
    int? costReduction,
    String? fragment,
    bool startedInDeck = false,
    String? entityId,
    String sourceZone = 'generated',
  }) {
    final resolvedEntityId = entityId ?? _nextCardEntityId();
    final available = 10 - _occupiedHandSlots(side);
    if (available <= 0) {
      if (!drawn.isUnit) {
        _sendCardToGraveyard(
          side,
          drawn,
          resolvedEntityId,
          fromZone: sourceZone,
          reason: 'burned',
        );
      }
      return false;
    }
    _syncHandCostReductions(side);
    final enteredTurn = battle?.phase == 'mulligan' ? 0 : battle?.turn ?? 0;
    final retainedReduction = costReduction == null
        ? (costOverride == null
              ? 0
              : max(0, drawn.cost - max(0, costOverride)).toInt())
        : max(0, costReduction).toInt();
    if (!drawn.hasShatter) {
      side.hand.add(drawn);
      side.handCostReductions.add(retainedReduction);
      side.handFragments.add(null);
      side.handStartedInDeck.add(startedInDeck);
      side.handEnteredTurns.add(enteredTurn);
      side.handEntityIds.add(resolvedEntityId);
      return true;
    }
    final groupId = 'm${_shatterGroupSequence++}';
    if (fragment == 'left' || fragment == 'right') {
      side.hand.add(_shatterFragmentCard(drawn, fragment!));
      side.handCostReductions.add(retainedReduction);
      side.handFragments.add(HandFragment(groupId: groupId, piece: fragment));
      side.handStartedInDeck.add(startedInDeck);
      side.handEnteredTurns.add(enteredTurn);
      side.handEntityIds.add(resolvedEntityId);
      return true;
    }
    side.hand.insert(0, _shatterFragmentCard(drawn, 'left'));
    side.handCostReductions.insert(0, retainedReduction);
    side.handFragments.insert(0, HandFragment(groupId: groupId, piece: 'left'));
    side.handStartedInDeck.insert(0, startedInDeck);
    side.handEnteredTurns.insert(0, enteredTurn);
    side.handEntityIds.insert(0, resolvedEntityId);
    var fragmentCount = 1;
    if (available >= 2) {
      side.hand.add(_shatterFragmentCard(drawn, 'right'));
      side.handCostReductions.add(retainedReduction);
      side.handFragments.add(HandFragment(groupId: groupId, piece: 'right'));
      side.handStartedInDeck.add(startedInDeck);
      side.handEnteredTurns.add(enteredTurn);
      side.handEntityIds.add(_nextCardEntityId());
      fragmentCount = 2;
    } else {
      stateLog('破碎片燃毁', '${drawn.name} 的右片因手牌空间不足被销毁。');
    }
    stateLog('破碎', '${drawn.name} 裂成 $fragmentCount 片并移向手牌两端。');
    _emitFx(
      'buff',
      '破碎',
      '${drawn.name} 裂至手牌两端',
      Icons.call_split,
      0xFF65CDDA,
      sourceId: drawn.id,
    );
    return true;
  }

  void _discardRandomCards({
    required BattleSide source,
    required BattleSide enemy,
    required int count,
    required String sourceName,
  }) {
    for (
      var discarded = 0;
      discarded < count && source.hand.isNotEmpty;
      discarded++
    ) {
      _syncHandCostReductions(source);
      final index = _random.nextInt(source.hand.length);
      final removed = source.hand.removeAt(index);
      source.handCostReductions.removeAt(index);
      final fragment = source.handFragments.removeAt(index);
      source.handStartedInDeck.removeAt(index);
      source.handEnteredTurns.removeAt(index);
      final entityId = source.handEntityIds.removeAt(index);
      final state = battle!;
      final discardId = 'discard-${_discardSequence++}';
      source.discardHistory.add(
        BattleDiscardRecord(
          discardId: discardId,
          cardId: removed.id,
          name: removed.name,
          player: identical(source, state.player) ? 0 : 1,
          discardedTurn: state.turn,
          discardOrder:
              state.player.discardHistory.length +
              state.ai.discardHistory.length +
              1,
          fragment: fragment?.piece,
        ),
      );
      if (!removed.isUnit) {
        _sendCardToGraveyard(
          source,
          removed,
          entityId,
          fromZone: 'hand',
          reason: 'discarded',
        );
      }
      stateLog(
        sourceName,
        '弃掉 ${removed.name}${fragment == null ? '' : '·${fragment.isLeft ? '左片' : '右片'}'}。',
      );
      _emitFx(
        'burn',
        '${removed.name} 被弃掉',
        '已写入本局弃牌历史',
        Icons.delete_sweep_outlined,
        0xFFE7BD7A,
        sourceId: removed.id,
      );
      if (removed.onDiscard.isNotEmpty) {
        _resolveEffects(
          removed.onDiscard,
          source: source,
          enemy: enemy,
          sourceName: '${removed.name} · 弃牌触发',
        );
      }
    }
  }

  void _recoverDiscardedCards({
    required BattleSide source,
    required int count,
    required String sourceName,
  }) {
    final pool = List<BattleDiscardRecord>.from(source.discardHistory);
    for (var recovered = 0; recovered < count && pool.isNotEmpty; recovered++) {
      final index = _random.nextInt(pool.length);
      final record = pool.removeAt(index);
      final recoveredCard = card(record.cardId);
      if (recoveredCard == null) continue;
      if (_addCardToHand(source, recoveredCard)) {
        stateLog(sourceName, '找回 ${recoveredCard.name} 的印刷复制。');
        _emitFx(
          'draw',
          '${recoveredCard.name} 被找回',
          '弃牌历史不会被消耗',
          Icons.restore_from_trash_outlined,
          factionColors[recoveredCard.faction] ?? 0xFFE7BD7A,
          sourceId: recoveredCard.id,
        );
      } else {
        stateLog(sourceName, '${recoveredCard.name} 因手牌已满而燃毁。');
      }
    }
  }

  bool playCard(
    CardDefinition card, {
    int? handIndex,
    BattleUnit? target,
    bool targetHero = false,
    String placement = 'friendly',
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
    if (placement != 'friendly' &&
        (placement != 'enemy' || !card.isUnit || !card.disguised)) {
      return false;
    }
    if (card.id == 'the-coin') {
      final played = _playCoinForSide(
        source: state.player,
        enemy: state.ai,
        owner: 'player',
        handIndex: resolvedHandIndex,
      );
      if (!played) return false;
      notifyListeners();
      return true;
    }
    final recipient = placement == 'enemy' ? state.ai : state.player;
    if (resolvedHandIndex < 0 ||
        (card.isUnit &&
            _battlefieldSize(recipient) >= 7 &&
            _findUpgradeTarget(recipient, card) == null) ||
        (card.isLocation && _battlefieldSize(state.player) >= 7) ||
        (_battlefieldSize(state.player) >= 7 &&
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
      placement: placement,
    );
    _checkFinished();
    notifyListeners();
    return true;
  }

  int _battlefieldSize(BattleSide side) =>
      side.board.length + side.locations.length;

  bool activateLocation(BattleLocation location) {
    final state = battle;
    if (state == null ||
        state.finished ||
        state.phase != 'main' ||
        state.activePlayer != 'player' ||
        !state.player.locations.contains(location) ||
        state.actionWindow < location.readyOnTurn) {
      return false;
    }
    location.durability--;
    location.readyOnTurn = state.actionWindow + 4;
    stateLog(location.card.name, '地点能力激活，消耗 1 点耐久。');
    _emitFx(
      'location',
      '${location.card.name} 激活',
      '剩余 ${location.durability} 点耐久',
      Icons.location_city,
      factionColors[location.card.faction] ?? 0xFF69CFC3,
      sourceId: location.entityId,
    );
    _resolveEffects(
      location.card.effect,
      source: state.player,
      enemy: state.ai,
      sourceName: location.card.name,
    );
    if (location.durability <= 0) {
      state.player.locations.remove(location);
      _sendCardToGraveyard(
        state.player,
        location.card,
        location.entityId,
        fromZone: 'location',
        reason: 'durability',
      );
      stateLog(location.card.name, '耐久耗尽，地点离开战场。');
    }
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
    _syncHandCostReductions(state.player);
    final startedInDeck = state.player.handStartedInDeck[index];
    final handEntityId = state.player.handEntityIds[index];
    state.player.hand.removeAt(index);
    state.player.handCostReductions.removeAt(index);
    state.player.handFragments.removeAt(index);
    state.player.handStartedInDeck.removeAt(index);
    state.player.handEnteredTurns.removeAt(index);
    state.player.handEntityIds.removeAt(index);
    state.player.mana--;
    // Tradeable draws from the original deck before the physical card is
    // inserted, so a trade can never immediately redraw itself. Preserve the
    // remaining deck order and choose only the insertion position at random.
    _draw(state.player);
    final insertionIndex = _random.nextInt(state.player.deck.length + 1);
    _syncDeckCostOverrides(state.player);
    state.player.deck.insert(insertionIndex, this.card(card.id) ?? card);
    state.player.deckCostOverrides.insert(insertionIndex, null);
    state.player.deckStartedInDeck.insert(insertionIndex, startedInDeck);
    state.player.deckEntityIds.insert(insertionIndex, handEntityId);
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

  HandFragment? playerHandFragment(int handIndex) {
    final side = battle?.player;
    if (side == null || handIndex < 0 || handIndex >= side.hand.length) {
      return null;
    }
    _syncHandCostReductions(side);
    return side.handFragments[handIndex];
  }

  bool heroAttack({BattleUnit? target, bool targetHero = false}) {
    final state = battle;
    final weapon = state?.player.weapon;
    final attack = (weapon?.attack ?? 0) + (state?.player.heroAttackBonus ?? 0);
    if (state == null ||
        state.finished ||
        state.phase != 'main' ||
        state.activePlayer != 'player' ||
        attack <= 0 ||
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
        ? _damageHero(state.ai, attack)
        : _damageUnit(target, attack, combat: true);
    if (target != null) {
      final reflected = _damageHero(state.player, defenderAttack);
      if (defenderHasLifesteal && reflected > 0) {
        _healHero(state.ai, reflected);
      }
    }
    state.player.heroHasAttacked = true;
    if (weapon != null) weapon.durability--;
    final attackSource = weapon?.card.name ?? state.player.heroName;
    state.logs.insert(
      0,
      target == null
          ? '英雄使用 $attackSource 攻击敌方核心，造成 $dealt 点伤害。'
          : '英雄使用 $attackSource 攻击 ${target.card.name}。',
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
    if (weapon != null && weapon.durability <= 0) {
      state.logs.insert(0, '${weapon.card.name} 耐久耗尽。');
      _sendCardToGraveyard(
        state.player,
        weapon.card,
        weapon.entityId,
        fromZone: 'weapon',
        reason: 'durability',
      );
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
    if (power.effect['kind'] == 'summon' && _battlefieldSize(source) >= 7) {
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
        for (var i = 0; i < count && _battlefieldSize(source) < 7; i++) {
          final unit = _summonUnit(summonCard, owner: owner, side: source);
          source.board.add(unit);
          _summonColossalParts(
            card: summonCard,
            source: source,
            enemy: enemy,
            owner: owner,
          );
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
      case 'gain-attack':
        source.heroAttackBonus += amount;
        stateLog(power.name, '英雄本回合获得 +$amount 攻击。');
        _emitFx(
          'hero-power',
          power.name,
          '英雄本回合获得 +$amount 攻击',
          Icons.flash_on,
          0xFFE46D3F,
          sourceId: sourceId,
          targetId: '$owner-hero',
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
        state.activePlayer != 'player') {
      return false;
    }
    if (!_playCoinForSide(
      source: state.player,
      enemy: state.ai,
      owner: 'player',
    )) {
      return false;
    }
    notifyListeners();
    return true;
  }

  bool _playCoinForSide({
    required BattleSide source,
    required BattleSide enemy,
    required String owner,
    int? handIndex,
  }) {
    _ensureCoinInHand(source);
    final coin = card('the-coin');
    if (coin == null) return false;
    final resolvedHandIndex = _resolveHandIndex(source, coin, handIndex);
    if (resolvedHandIndex < 0) return false;
    _syncHandCostReductions(source);
    final coinEntityId = source.handEntityIds[resolvedHandIndex];
    source.hand.removeAt(resolvedHandIndex);
    source.handCostReductions.removeAt(resolvedHandIndex);
    source.handFragments.removeAt(resolvedHandIndex);
    source.handStartedInDeck.removeAt(resolvedHandIndex);
    source.handEnteredTurns.removeAt(resolvedHandIndex);
    source.handEntityIds.removeAt(resolvedHandIndex);
    _syncCoinMirror(source);
    // The Coin is a real 0-cost spell: it counts as the previous card for
    // Combo even when Counterspell prevents its mana effect.
    source.cardsPlayedThisTurn++;
    final countered = _triggerSecrets(
      enemy,
      'opponent-plays-spell',
      triggeringSide: source,
    );
    if (countered) {
      _sendCardToGraveyard(
        source,
        coin,
        coinEntityId,
        fromZone: 'hand',
        reason: 'countered',
      );
      stateLog(owner == 'player' ? '幸运币被反制。' : '敌方的幸运币被反制。');
      _processDeaths();
      _checkFinished();
      return true;
    }

    while (source.spellsPlayedEntityIds.length <
        source.spellsPlayedThisGame.length) {
      source.spellsPlayedEntityIds.add(
        'legacy-spell-${source.spellsPlayedEntityIds.length}-${source.spellsPlayedThisGame[source.spellsPlayedEntityIds.length]}',
      );
    }
    while (source.spellsPlayedFromStartingDeck.length <
        source.spellsPlayedThisGame.length) {
      source.spellsPlayedFromStartingDeck.add(true);
    }
    source.spellsPlayedThisGame.add(coin.id);
    source.spellsPlayedEntityIds.add(coinEntityId);
    source.spellsPlayedFromStartingDeck.add(false);
    _sendCardToGraveyard(
      source,
      coin,
      coinEntityId,
      fromZone: 'hand',
      reason: 'resolved',
    );

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
    BattleSide? side,
    int? healthOverride,
    bool reborn = false,
    String? instanceId,
  }) {
    final rush = card.keywords.contains('rush');
    final charge = card.keywords.contains('charge');
    final multiplier = card.hasColossal && side != null
        ? _heraldMultiplier(side)
        : 1;
    final printedHealth = (card.health ?? 1) * multiplier;
    return BattleUnit(
      instanceId:
          instanceId ??
          '$owner-${DateTime.now().microsecondsSinceEpoch}-${card.id}-${_random.nextInt(9999)}',
      card: card,
      owner: owner,
      attack: (card.attack ?? 0) * multiplier,
      health: healthOverride ?? printedHealth,
      maxHealth: printedHealth,
      hasAttacked: !charge && !rush,
      divineShield: card.keywords.contains('shield') && !reborn,
      summoningSick: !charge && !rush,
      rushOnly: rush,
      stealthActive: card.keywords.contains('stealth'),
      rebornUsed: reborn,
    );
  }

  BattleUnit _copyUnitForBattlefield(
    BattleUnit original, {
    required String owner,
    String? instanceId,
  }) {
    final hasCharge =
        !original.silenced && original.card.keywords.contains('charge');
    final hasRush =
        !original.silenced && original.card.keywords.contains('rush');
    return BattleUnit(
      instanceId:
          instanceId ??
          '$owner-${DateTime.now().microsecondsSinceEpoch}-${original.card.id}-${_random.nextInt(9999)}',
      card: original.card,
      owner: owner,
      attack: original.attack,
      health: original.health,
      maxHealth: original.maxHealth,
      hasAttacked: false,
      stars: original.stars,
      divineShield: original.divineShield,
      furyTriggered: original.furyTriggered,
      attacksMade: 0,
      summoningSick: !hasCharge && !hasRush,
      rushOnly: !hasCharge && hasRush,
      stealthActive: original.stealthActive,
      frozenTurns: original.frozenTurns,
      freezeBlocked: original.frozenTurns > 0,
      rebornUsed: original.rebornUsed,
      permanentAttackBonus: original.permanentAttackBonus,
      permanentHealthBonus: original.permanentHealthBonus,
      temporaryAttackBonus: original.temporaryAttackBonus,
      temporaryHealthBonus: original.temporaryHealthBonus,
      silenced: original.silenced,
    );
  }

  int _heraldMultiplier(BattleSide side) {
    if (side.heraldCount >= 4) return 4;
    if (side.heraldCount >= 2) return 2;
    return 1;
  }

  List<Map<String, dynamic>> _colossalParts(CardDefinition card) {
    final raw = card.colossal?['parts'];
    return raw is List
        ? raw
              .whereType<Map>()
              .map((part) => Map<String, dynamic>.from(part))
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _scaledEffects(Object? raw, int multiplier) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((entry) {
          final effect = Map<String, dynamic>.from(entry);
          final kind = effect['kind']?.toString();
          if ({
            'damage',
            'heal',
            'damage-friendly-hero',
            'random-enemy-damage',
            'damage-all-enemies',
            'armor',
            'random-enemy-freeze',
          }.contains(kind)) {
            effect['amount'] =
                ((effect['amount'] as num?)?.toInt() ?? 1) * multiplier;
          } else if ({
            'draw',
            'draw-opponent',
            'draw-minion-type',
            'draw-spell-school',
            'resurrect-friendly-unit',
            'discard-random',
            'recover-discarded',
            'copy-random-opponent-deck',
            'summon',
          }.contains(kind)) {
            effect['count'] =
                ((effect['count'] as num?)?.toInt() ?? 1) * multiplier;
          } else if ({
            'buff',
            'buff-all-friendly',
            'buff-friendly-minion-type',
            'temporary-buff',
          }.contains(kind)) {
            effect['attack'] =
                ((effect['attack'] as num?)?.toInt() ?? 0) * multiplier;
            effect['health'] =
                ((effect['health'] as num?)?.toInt() ?? 0) * multiplier;
          } else if (kind == 'spell-school-payoff') {
            effect['effects'] = _scaledEffects(effect['effects'], multiplier);
          }
          return effect;
        })
        .toList(growable: false);
  }

  CardDefinition _colossalTokenCard(
    CardDefinition colossal,
    Map<String, dynamic> part, {
    required bool soldier,
  }) {
    final partId = part['id']?.toString() ?? '${colossal.id}-appendage';
    final partName = part['name']?.toString() ?? '${colossal.name}附肢';
    final generatedId = soldier ? '$partId-soldier' : partId;
    final registered = card(generatedId);
    if (registered != null) return registered;
    final keywords = part['keywords'] is List
        ? (part['keywords'] as List)
              .map((item) => item.toString())
              .toList(growable: false)
        : const <String>[];
    return CardDefinition(
      id: generatedId,
      name: soldier ? '$partName士兵' : partName,
      description: soldier ? '先驱召唤的巨型附肢士兵。' : '巨型组装的附肢。',
      faction: colossal.faction,
      type: 'unit',
      cost: 0,
      rarity: '衍生',
      setId: colossal.setId,
      attack: (part['attack'] as num?)?.toInt() ?? 0,
      health: (part['health'] as num?)?.toInt() ?? 1,
      keywords: keywords,
      traits: colossal.traits,
      minionTypes: part['minionTypes'] is List
          ? (part['minionTypes'] as List)
                .map((item) => item.toString())
                .toList(growable: false)
          : colossal.minionTypes,
      onPlay: part['effect'] is List
          ? (part['effect'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(growable: false)
          : const <Map<String, dynamic>>[],
    );
  }

  BattleUnit? _summonColossalToken({
    required CardDefinition colossal,
    required Map<String, dynamic> part,
    required BattleSide source,
    required BattleSide enemy,
    required String owner,
    required int multiplier,
    required bool soldier,
  }) {
    if (_battlefieldSize(source) >= 7) return null;
    final tokenCard = _colossalTokenCard(colossal, part, soldier: soldier);
    final unit = _summonUnit(tokenCard, owner: owner);
    unit.attack *= multiplier;
    unit.health *= multiplier;
    unit.maxHealth *= multiplier;
    source.board.add(unit);
    _emitFx(
      'summon',
      '${tokenCard.name} 被召唤',
      soldier ? '先驱士兵强度 ×$multiplier' : '巨型附肢强度 ×$multiplier',
      Icons.auto_awesome,
      factionColors[colossal.faction] ?? 0xFF69CFC3,
      sourceId: unit.instanceId,
      amount: multiplier,
    );
    _triggerSecrets(enemy, 'opponent-summons-unit', triggeringSide: source);
    _resolveEffects(
      _scaledEffects(part['effect'], multiplier),
      source: source,
      enemy: enemy,
      sourceName: tokenCard.name,
      sourceCard: tokenCard,
    );
    return unit;
  }

  void _summonColossalParts({
    required CardDefinition card,
    required BattleSide source,
    required BattleSide enemy,
    required String owner,
  }) {
    if (!card.hasColossal) return;
    final multiplier = _heraldMultiplier(source);
    var summoned = 0;
    for (final part in _colossalParts(card)) {
      final unit = _summonColossalToken(
        colossal: card,
        part: part,
        source: source,
        enemy: enemy,
        owner: owner,
        multiplier: multiplier,
        soldier: false,
      );
      if (unit != null) summoned++;
    }
    stateLog(card.name, '以 ×$multiplier 强度组装，召唤 $summoned 个附肢。');
  }

  void _resolveHeraldPlay({
    required CardDefinition card,
    required BattleSide source,
    required BattleSide enemy,
    required String owner,
  }) {
    if (!card.hasHerald) return;
    source.heraldCount++;
    final multiplier = _heraldMultiplier(source);
    final colossalId = card.herald?['colossalCardId']?.toString();
    final colossal = colossalId == null ? null : this.card(colossalId);
    final parts = colossal == null
        ? const <Map<String, dynamic>>[]
        : _colossalParts(colossal);
    if (colossal != null && parts.isNotEmpty) {
      _summonColossalToken(
        colossal: colossal,
        part: parts.first,
        source: source,
        enemy: enemy,
        owner: owner,
        multiplier: multiplier,
        soldier: true,
      );
    }
    stateLog(card.name, '先驱进度 ${source.heraldCount}，巨型强度 ×$multiplier。');
  }

  BattleUnit? _findUpgradeTarget(BattleSide side, CardDefinition card) {
    for (final unit in side.board) {
      if (unit.card.id == card.id && unit.stars == 1) return unit;
    }
    return null;
  }

  int _activeTraitTier(BattleSide side, String trait) {
    final distinctCards = side.board
        .where((unit) => unit.card.traits.contains(trait))
        .map((unit) => unit.card.id)
        .toSet()
        .length;
    if (distinctCards >= 4) return 2;
    if (distinctCards >= 2) return 1;
    return 0;
  }

  void _upgradeUnit(BattleSide side, BattleUnit unit, CardDefinition card) {
    final craftBonus = card.traits.contains('craft')
        ? _activeTraitTier(side, 'craft')
        : 0;
    final attackBonus = ((card.attack ?? 0) / 2).ceil() + craftBonus;
    final healthBonus = ((card.health ?? 1) / 2).ceil() + craftBonus;
    unit.attack += attackBonus;
    unit.maxHealth += healthBonus;
    unit.health += healthBonus;
    unit.permanentAttackBonus += attackBonus;
    unit.permanentHealthBonus += healthBonus;
    unit.stars = 2;
    stateLog('${card.name} 升阶', '同名档案共鸣，升至二星并获得 +$attackBonus/+$healthBonus。');
    _emitFx(
      'buff',
      '${card.name} 升至二星',
      '+$attackBonus/+$healthBonus',
      Icons.upgrade,
      factionColors[card.faction] ?? 0xFFE7BD7A,
      sourceId: unit.instanceId,
    );
  }

  HeroPowerDefinition? _heroPowerFromMap(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final effect = map['effect'];
    if (effect is! Map) return null;
    return HeroPowerDefinition(
      id: map['id']?.toString() ?? 'generated-hero-power',
      faction: map['faction']?.toString() ?? '中立',
      name: map['name']?.toString() ?? '英雄技能',
      description: map['description']?.toString() ?? '',
      cost: (map['cost'] as num?)?.toInt() ?? 2,
      target: map['target']?.toString(),
      effect: Map<String, dynamic>.from(effect),
    );
  }

  void _playHeroCard({
    required CardDefinition card,
    required String handEntityId,
    required BattleSide source,
    required BattleSide enemy,
    required String owner,
  }) {
    final state = battle;
    final definition = card.heroCard;
    if (state == null || definition == null) return;
    final heroPower = _heroPowerFromMap(definition['heroPower']);
    final rawOptions = definition['options'];
    if (heroPower == null || rawOptions is! List) return;
    final options = rawOptions
        .whereType<Map>()
        .map((option) => Map<String, dynamic>.from(option))
        .toList(growable: false);
    if (options.length < 2) return;

    source.heroId = definition['heroId']?.toString() ?? card.id;
    source.heroName = definition['heroName']?.toString() ?? card.name;
    source.heroCardEntityId = handEntityId;
    _sendCardToGraveyard(
      source,
      card,
      handEntityId,
      fromZone: 'hand',
      reason: 'transformed',
    );
    final armor = (definition['armor'] as num?)?.toInt() ?? 0;
    source.armor += max(0, armor);
    if (owner == 'player') {
      state.playerHeroPower = heroPower;
      state.heroPowerUsed = false;
    } else {
      state.aiHeroPower = heroPower;
      state.aiHeroPowerUsed = false;
    }
    stateLog(card.name, '化身为 ${source.heroName}，获得 $armor 点护甲。');
    _emitFx(
      'hero-transform',
      source.heroName,
      '获得 $armor 点护甲并替换英雄技能',
      Icons.whatshot,
      0xFFE46D3F,
      sourceId: handEntityId,
      amount: armor,
    );

    final choiceCount = definition['scalesWithHerald'] == true
        ? source.heraldCount >= 4
              ? 4
              : source.heraldCount >= 2
              ? 2
              : 1
        : 1;
    if (choiceCount >= options.length) {
      for (final option in options) {
        final effects = option['effects'];
        if (effects is! List) continue;
        final parsed = effects
            .whereType<Map>()
            .map((effect) => Map<String, dynamic>.from(effect))
            .toList(growable: false);
        final label = option['label']?.toString() ?? '灭世灾变';
        stateLog('灭世灾变', label);
        _resolveEffects(
          parsed,
          source: source,
          enemy: enemy,
          sourceName: label,
        );
        if (state.finished) break;
      }
      return;
    }

    state.phase = 'choose-one';
    state.chooseOneOptions = List<Map<String, dynamic>>.from(options);
    state.chooseOneSource = card.name;
    state.chooseOneSourceEntityId = handEntityId;
    state.chooseOneOwner = owner;
    state.chooseOneTarget = null;
    state.chooseOneRemaining = choiceCount;
    state.chooseOneSourceKind = 'hero-card';
    state.chooseOneChosenLabels.clear();
    stateLog(card.name, '从 ${options.length} 个灭世灾变中选择 $choiceCount 个。');
  }

  void _playCardForSide(
    CardDefinition card, {
    required BattleSide source,
    required BattleSide enemy,
    required String owner,
    int? handIndex,
    BattleUnit? target,
    bool targetHero = false,
    String placement = 'friendly',
  }) {
    final resolvedHandIndex = _resolveHandIndex(source, card, handIndex);
    if (resolvedHandIndex < 0) return;
    _syncHandCostReductions(source);
    final startedInDeck = source.handStartedInDeck[resolvedHandIndex];
    final enteredTurn = source.handEnteredTurns[resolvedHandIndex];
    final handEntityId = source.handEntityIds[resolvedHandIndex];
    final quickdrawActive =
        card.quickdraw.isNotEmpty &&
        battle?.phase == 'main' &&
        enteredTurn == battle?.turn;
    final effectiveCost = _effectiveHandCost(source, resolvedHandIndex);
    source.hand.removeAt(resolvedHandIndex);
    source.handCostReductions.removeAt(resolvedHandIndex);
    source.handFragments.removeAt(resolvedHandIndex);
    source.handStartedInDeck.removeAt(resolvedHandIndex);
    source.handEnteredTurns.removeAt(resolvedHandIndex);
    source.handEntityIds.removeAt(resolvedHandIndex);
    _reassembleAdjacentFragments(source);
    source.mana -= effectiveCost;
    final comboActive = source.cardsPlayedThisTurn > 0;
    source.cardsPlayedThisTurn++;
    if (card.type == 'spell' &&
        _triggerSecrets(
          enemy,
          'opponent-plays-spell',
          triggeringSide: source,
        )) {
      _sendCardToGraveyard(
        source,
        card,
        handEntityId,
        fromZone: 'hand',
        reason: 'countered',
      );
      stateLog(
        owner == 'player' ? '${card.name} 被奥秘反制。' : '敌方的 ${card.name} 被奥秘反制。',
      );
      _processDeaths();
      return;
    }
    if (card.type == 'spell') {
      while (source.spellsPlayedFromStartingDeck.length <
          source.spellsPlayedThisGame.length) {
        source.spellsPlayedFromStartingDeck.add(true);
      }
      while (source.spellsPlayedEntityIds.length <
          source.spellsPlayedThisGame.length) {
        source.spellsPlayedEntityIds.add(
          'legacy-spell-${source.spellsPlayedEntityIds.length}-${source.spellsPlayedThisGame[source.spellsPlayedEntityIds.length]}',
        );
      }
      source.spellsPlayedThisGame.add(card.id);
      source.spellsPlayedEntityIds.add(handEntityId);
      source.spellsPlayedFromStartingDeck.add(startedInDeck);
      final armsSecret = card.effect.any(
        (effect) => effect['kind']?.toString() == 'secret',
      );
      if (!armsSecret) {
        _sendCardToGraveyard(
          source,
          card,
          handEntityId,
          fromZone: 'hand',
          reason: 'resolved',
        );
      }
      if (card.school != null) {
        source.spellSchoolsPlayedThisTurn.add(card.school!);
      }
    }
    source.overloadLocked += card.overload;
    if (card.isHero) {
      _playHeroCard(
        card: card,
        handEntityId: handEntityId,
        source: source,
        enemy: enemy,
        owner: owner,
      );
    } else if (card.isLocation) {
      final maxDurability = max(1, card.durability ?? 1);
      source.locations.add(
        BattleLocation(
          entityId: handEntityId,
          card: card,
          owner: owner,
          durability: maxDurability,
          maxDurability: maxDurability,
          readyOnTurn: (battle?.actionWindow ?? 0) + 2,
        ),
      );
      stateLog(owner == 'player' ? '${card.name} 已部署。' : '敌方部署 ${card.name}。');
      _emitFx(
        'location',
        '${card.name} 部署',
        '$maxDurability 耐久 · 下个己方回合可激活',
        Icons.location_city,
        factionColors[card.faction] ?? 0xFF69CFC3,
        sourceId: handEntityId,
      );
    } else if (card.type == 'weapon') {
      final previousWeapon = source.weapon;
      if (previousWeapon != null) {
        _sendCardToGraveyard(
          source,
          previousWeapon.card,
          previousWeapon.entityId,
          fromZone: 'weapon',
          reason: 'replaced',
        );
      }
      final maxDurability = max(1, card.durability ?? card.health ?? 1);
      source.weapon = BattleWeapon(
        entityId: handEntityId,
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
        sourceId: handEntityId,
      );
    } else if (card.isUnit) {
      final recipient = placement == 'enemy' ? enemy : source;
      final recipientOwner = placement == 'enemy'
          ? (owner == 'player' ? 'ai' : 'player')
          : owner;
      final upgradeTarget = _findUpgradeTarget(recipient, card);
      final unit =
          upgradeTarget ??
          _summonUnit(
            card,
            owner: recipientOwner,
            side: recipient,
            instanceId: handEntityId,
          );
      if (upgradeTarget == null) {
        recipient.board.add(unit);
        _summonColossalParts(
          card: card,
          source: recipient,
          enemy: placement == 'enemy' ? source : enemy,
          owner: recipientOwner,
        );
      } else {
        _upgradeUnit(recipient, upgradeTarget, card);
      }
      recipient.board.length == 1 && recipientOwner == 'player'
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
              placement == 'enemy'
                  ? '${card.name} 伪装渗透'
                  : owner == 'player'
                  ? '${card.name} 登场'
                  : '敌方部署 ${card.name}',
              card.description,
              Icons.auto_awesome,
              factionColors[card.faction] ?? 0xFF69CFC3,
              sourceId: unit.instanceId,
            );
      stateLog(
        placement == 'enemy'
            ? '${card.name} 伪装部署到对方战场。'
            : owner == 'player'
            ? '${card.name} 登场。'
            : '敌方部署 ${card.name}。',
      );
      _resolveEffects(
        card.onPlay,
        source: source,
        enemy: enemy,
        target: target ?? (card.target == null ? unit : null),
        targetHero: targetHero,
        targetFriendlyHero:
            targetHero && (card.target ?? '').startsWith('friendly'),
        sourceName: card.name,
        sourceCard: card,
        sourceUnit: unit,
      );
      if (comboActive && card.combo.isNotEmpty && battle?.phase == 'main') {
        _resolveEffects(
          card.combo,
          source: source,
          enemy: enemy,
          target: target,
          targetHero: targetHero,
          targetFriendlyHero:
              targetHero && (card.target ?? '').startsWith('friendly'),
          sourceName: '${card.name} · 连击',
          sourceCard: card,
        );
      }
      if (upgradeTarget == null &&
          recipient.board.any(
            (entry) => entry.instanceId == unit.instanceId && entry.health > 0,
          )) {
        // Hearthstone's after-play Secret window opens after Battlecries.
        // A self-transforming copy is therefore observed in its final form,
        // while a unit that died during its Battlecry no longer triggers it.
        _triggerSecrets(enemy, 'opponent-summons-unit', triggeringSide: source);
      }
      _resolveHeraldPlay(
        card: card,
        source: source,
        enemy: enemy,
        owner: owner,
      );
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
        targetFriendlyHero:
            targetHero && (card.target ?? '').startsWith('friendly'),
        sourceName: card.name,
        sourceCard: card,
        sourceEntityId: handEntityId,
      );
      if (comboActive && card.combo.isNotEmpty && battle?.phase == 'main') {
        _resolveEffects(
          card.combo,
          source: source,
          enemy: enemy,
          target: target,
          targetHero: targetHero,
          targetFriendlyHero:
              targetHero && (card.target ?? '').startsWith('friendly'),
          sourceName: '${card.name} · 连击',
          sourceCard: card,
        );
      }
      if (quickdrawActive) {
        _resolveQuickdraw(
          card: card,
          source: source,
          enemy: enemy,
          target: target,
          targetHero: targetHero,
        );
      }
      if (battle?.phase == 'main') {
        _resolveSpellTriggers(source: source, enemy: enemy);
      }
      stateLog(card.name, card.description);
    }
    if (quickdrawActive && card.type != 'spell') {
      _resolveQuickdraw(
        card: card,
        source: source,
        enemy: enemy,
        target: target,
        targetHero: targetHero,
      );
    }
    _processDeaths();
  }

  void _resolveQuickdraw({
    required CardDefinition card,
    required BattleSide source,
    required BattleSide enemy,
    BattleUnit? target,
    bool targetHero = false,
  }) {
    if (card.quickdraw.isEmpty) return;
    stateLog(card.name, '快枪触发。');
    _emitFx(
      'buff',
      '${card.name} · 快枪',
      '这张牌在进入手牌的同一回合被使用',
      Icons.flash_on,
      0xFFFFC857,
      sourceId: card.id,
    );
    _resolveEffects(
      card.quickdraw,
      source: source,
      enemy: enemy,
      target: target,
      targetHero: targetHero,
      targetFriendlyHero:
          targetHero && (card.target ?? '').startsWith('friendly'),
      sourceName: '${card.name} · 快枪',
      sourceCard: card,
    );
  }

  void _syncHandCostReductions(BattleSide side) {
    while (side.handCostReductions.length > side.hand.length) {
      side.handCostReductions.removeLast();
    }
    while (side.handCostReductions.length < side.hand.length) {
      side.handCostReductions.add(0);
    }
    while (side.handFragments.length > side.hand.length) {
      side.handFragments.removeLast();
    }
    while (side.handFragments.length < side.hand.length) {
      side.handFragments.add(null);
    }
    while (side.handStartedInDeck.length > side.hand.length) {
      side.handStartedInDeck.removeLast();
    }
    while (side.handStartedInDeck.length < side.hand.length) {
      side.handStartedInDeck.add(true);
    }
    while (side.handEnteredTurns.length > side.hand.length) {
      side.handEnteredTurns.removeLast();
    }
    while (side.handEnteredTurns.length < side.hand.length) {
      side.handEnteredTurns.add(0);
    }
    while (side.handEntityIds.length > side.hand.length) {
      side.handEntityIds.removeLast();
    }
    final seenEntityIds = <String>{
      ...side.deckEntityIds.take(side.deck.length),
      ...side.board.map((unit) => unit.instanceId),
    };
    for (var index = 0; index < side.handEntityIds.length; index++) {
      final entityId = side.handEntityIds[index];
      if (entityId.isEmpty || !seenEntityIds.add(entityId)) {
        var replacement = _nextCardEntityId();
        while (seenEntityIds.contains(replacement)) {
          replacement = _nextCardEntityId();
        }
        side.handEntityIds[index] = replacement;
        seenEntityIds.add(replacement);
      }
    }
    while (side.handEntityIds.length < side.hand.length) {
      var entityId = _nextCardEntityId();
      while (seenEntityIds.contains(entityId)) {
        entityId = _nextCardEntityId();
      }
      side.handEntityIds.add(entityId);
      seenEntityIds.add(entityId);
    }
  }

  void _syncCoinMirror(BattleSide side) {
    _syncHandCostReductions(side);
    final coinIndex = side.hand.indexWhere((item) => item.id == 'the-coin');
    side.coinAvailable = coinIndex >= 0;
    side.coinEntityId = coinIndex >= 0 ? side.handEntityIds[coinIndex] : null;
  }

  void _ensureCoinInHand(BattleSide side) {
    final existingIndex = side.hand.indexWhere((item) => item.id == 'the-coin');
    if (existingIndex >= 0) {
      _syncCoinMirror(side);
      return;
    }
    if (!side.coinAvailable || side.hand.length >= 10) {
      _syncCoinMirror(side);
      return;
    }
    final coin = card('the-coin');
    if (coin == null) return;
    final reservedEntityId = side.coinEntityId ?? _nextCardEntityId();
    _syncHandCostReductions(side);
    side.hand.add(coin);
    side.handCostReductions.add(0);
    side.handFragments.add(null);
    side.handStartedInDeck.add(false);
    side.handEnteredTurns.add(0);
    side.handEntityIds.add(reservedEntityId);
    _syncCoinMirror(side);
  }

  List<({String cardId, int costReduction, String? fragment})>
  _opponentHandCopyChoices(BattleSide side) {
    _syncHandCostReductions(side);
    final seen = <String>{};
    final choices = <({String cardId, int costReduction, String? fragment})>[];
    for (var index = 0; index < side.hand.length; index++) {
      final cardId = side.hand[index].id;
      final costReduction = side.handCostReductions[index];
      final fragment = side.handFragments[index]?.piece;
      final signature =
          '$cardId\u0000$costReduction\u0000${fragment ?? 'full'}';
      if (seen.add(signature)) {
        choices.add((
          cardId: cardId,
          costReduction: costReduction,
          fragment: fragment,
        ));
      }
    }
    return choices;
  }

  void _syncDeckCostOverrides(BattleSide side) {
    while (side.deckCostOverrides.length > side.deck.length) {
      side.deckCostOverrides.removeLast();
    }
    while (side.deckCostOverrides.length < side.deck.length) {
      side.deckCostOverrides.add(null);
    }
    while (side.deckStartedInDeck.length > side.deck.length) {
      side.deckStartedInDeck.removeLast();
    }
    while (side.deckStartedInDeck.length < side.deck.length) {
      side.deckStartedInDeck.add(true);
    }
    while (side.deckEntityIds.length > side.deck.length) {
      side.deckEntityIds.removeLast();
    }
    final seenEntityIds = <String>{
      ...side.handEntityIds,
      ...side.board.map((unit) => unit.instanceId),
    };
    for (var index = 0; index < side.deckEntityIds.length; index++) {
      final entityId = side.deckEntityIds[index];
      if (entityId.isEmpty || !seenEntityIds.add(entityId)) {
        var replacement = _nextCardEntityId();
        while (seenEntityIds.contains(replacement)) {
          replacement = _nextCardEntityId();
        }
        side.deckEntityIds[index] = replacement;
        seenEntityIds.add(replacement);
      }
    }
    while (side.deckEntityIds.length < side.deck.length) {
      var entityId = _nextCardEntityId();
      while (seenEntityIds.contains(entityId)) {
        entityId = _nextCardEntityId();
      }
      side.deckEntityIds.add(entityId);
      seenEntityIds.add(entityId);
    }
  }

  void _shuffleDeck(BattleSide side) {
    _syncDeckCostOverrides(side);
    final entries = List.generate(
      side.deck.length,
      (index) => (
        card: side.deck[index],
        cost: side.deckCostOverrides[index],
        startedInDeck: side.deckStartedInDeck[index],
        entityId: side.deckEntityIds[index],
      ),
    )..shuffle(_random);
    side.deck
      ..clear()
      ..addAll(entries.map((entry) => entry.card));
    side.deckCostOverrides
      ..clear()
      ..addAll(entries.map((entry) => entry.cost));
    side.deckStartedInDeck
      ..clear()
      ..addAll(entries.map((entry) => entry.startedInDeck));
    side.deckEntityIds
      ..clear()
      ..addAll(entries.map((entry) => entry.entityId));
  }

  List<int> _expandedMulliganIndexes(BattleSide side, Iterable<int> requested) {
    _syncHandCostReductions(side);
    final valid = requested
        .where((index) => index >= 0 && index < side.hand.length)
        .toSet();
    final groups = valid
        .map((index) => side.handFragments[index]?.groupId)
        .whereType<String>()
        .toSet();
    final expanded =
        side.hand
            .asMap()
            .keys
            .where(
              (index) =>
                  valid.contains(index) ||
                  groups.contains(side.handFragments[index]?.groupId),
            )
            .toList()
          ..sort();
    return expanded;
  }

  CardDefinition _shatterFragmentCard(CardDefinition full, String piece) {
    final rawEffects = full.shatter?[piece];
    final effects = rawEffects is List
        ? rawEffects
              .whereType<Map>()
              .map((effect) => Map<String, dynamic>.from(effect))
              .toList(growable: false)
        : <Map<String, dynamic>>[];
    final target =
        full.shatter?['${piece}Target']?.toString() ?? full.target ?? 'none';
    final label = piece == 'left' ? '左片' : '右片';
    return full.copyWith(
      name: '${full.name} · $label',
      description: '破碎$label：单独使用时只结算这一半效果；与同组另一片相邻后自动重组。${full.description}',
      target: target,
      effect: effects,
    );
  }

  void _reassembleAdjacentFragments(BattleSide side) {
    _syncHandCostReductions(side);
    for (var index = 0; index < side.hand.length - 1; index++) {
      final left = side.handFragments[index];
      final right = side.handFragments[index + 1];
      if (left == null ||
          right == null ||
          !left.isLeft ||
          right.piece != 'right' ||
          left.groupId != right.groupId ||
          side.hand[index].id != side.hand[index + 1].id) {
        continue;
      }
      final restored = card(side.hand[index].id) ?? side.hand[index];
      side.hand[index] = restored;
      side.hand.removeAt(index + 1);
      side.handCostReductions[index] = max(
        side.handCostReductions[index],
        side.handCostReductions[index + 1],
      );
      side.handCostReductions.removeAt(index + 1);
      side.handFragments[index] = null;
      side.handFragments.removeAt(index + 1);
      side.handStartedInDeck[index] =
          side.handStartedInDeck[index] && side.handStartedInDeck[index + 1];
      side.handStartedInDeck.removeAt(index + 1);
      side.handEnteredTurns[index] = max(
        side.handEnteredTurns[index],
        side.handEnteredTurns[index + 1],
      );
      side.handEnteredTurns.removeAt(index + 1);
      side.handEntityIds.removeAt(index + 1);
      stateLog('破碎重组', '${restored.name} 的两片重新相接。');
      _emitFx(
        'buff',
        '破碎重组',
        '${restored.name} 恢复为完整卡牌',
        Icons.join_inner,
        0xFFE7BD7A,
        sourceId: restored.id,
      );
      break;
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

  int _occupiedHandSlots(BattleSide side) => side.hand.length;

  bool _isPureSummonSpell(CardDefinition card, BattleSide source) {
    if (card.type != 'spell') return false;
    final resolvedEffects = <Map<String, dynamic>>[
      ...card.effect,
      if (source.cardsPlayedThisTurn > 0) ...card.combo,
    ];
    return resolvedEffects.isNotEmpty &&
        resolvedEffects.every(
          (effect) =>
              effect['kind'] == 'summon' ||
              effect['kind'] == 'summon-copy-of-unit',
        );
  }

  bool _validTarget(
    CardDefinition card,
    BattleSide source,
    BattleSide enemy,
    BattleUnit? target,
  ) {
    final transfersTarget = [
      ...card.effect,
      ...card.onPlay,
      ...card.combo,
    ].any((effect) => effect['kind'] == 'take-control');
    final reservedSlots = card.isUnit ? 1 : 0;
    if (transfersTarget && source.board.length + reservedSlots >= 7) {
      return false;
    }
    final targetType = card.target ?? '';
    if (!targetType.contains('unit')) return true;
    if (target == null) {
      return false;
    }
    if (targetType == 'any-unit') {
      return source.board.contains(target) ||
          (enemy.board.contains(target) && !target.stealthActive);
    }
    final friendly = targetType.startsWith('friendly');
    return friendly
        ? source.board.contains(target)
        : enemy.board.contains(target) && !target.stealthActive;
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

  ({BattleUnit? target, bool targetHero, bool targetFriendlyHero})?
  _randomRecastTarget(
    CardDefinition card, {
    required BattleSide source,
    required BattleSide enemy,
  }) {
    final rule = card.target ?? 'none';
    if (rule == 'none') {
      return (target: null, targetHero: false, targetFriendlyHero: false);
    }
    final friendlyUnits = source.board
        .where((unit) => unit.health > 0)
        .toList();
    final enemyUnits = enemy.board.where((unit) => unit.health > 0).toList();
    switch (rule) {
      case 'enemy-unit':
        if (enemyUnits.isEmpty) return null;
        return (
          target: enemyUnits[_random.nextInt(enemyUnits.length)],
          targetHero: false,
          targetFriendlyHero: false,
        );
      case 'friendly-unit':
        if (friendlyUnits.isEmpty) return null;
        return (
          target: friendlyUnits[_random.nextInt(friendlyUnits.length)],
          targetHero: false,
          targetFriendlyHero: false,
        );
      case 'any-unit':
        final candidates = <BattleUnit>[...friendlyUnits, ...enemyUnits];
        if (candidates.isEmpty) return null;
        return (
          target: candidates[_random.nextInt(candidates.length)],
          targetHero: false,
          targetFriendlyHero: false,
        );
      case 'enemy-character':
        final index = _random.nextInt(enemyUnits.length + 1);
        return index == 0
            ? (target: null, targetHero: true, targetFriendlyHero: false)
            : (
                target: enemyUnits[index - 1],
                targetHero: false,
                targetFriendlyHero: false,
              );
      case 'friendly-character':
        final index = _random.nextInt(friendlyUnits.length + 1);
        return index == 0
            ? (target: null, targetHero: true, targetFriendlyHero: true)
            : (
                target: friendlyUnits[index - 1],
                targetHero: false,
                targetFriendlyHero: false,
              );
      case 'any-character':
        final candidates = <Object>[
          source,
          ...friendlyUnits,
          enemy,
          ...enemyUnits,
        ];
        final chosen = candidates[_random.nextInt(candidates.length)];
        if (chosen is BattleUnit) {
          return (target: chosen, targetHero: false, targetFriendlyHero: false);
        }
        return (
          target: null,
          targetHero: true,
          targetFriendlyHero: identical(chosen, source),
        );
      default:
        return null;
    }
  }

  List<String> _discoverPoolForEffect(
    Map<String, dynamic> effect,
    BattleSide source,
    String? sourceCardId,
  ) {
    final dynamicPool = effect['pool'];
    Iterable<String> candidates;
    if (dynamicPool is Map) {
      final factionRule = dynamicPool['faction']?.toString();
      final includeNeutral = dynamicPool['includeNeutral'] == true;
      final cardType = dynamicPool['cardType']?.toString();
      candidates = catalog
          .where((candidate) {
            if (candidate.id == sourceCardId) return false;
            if (!candidate.collectible ||
                !cardAvailableInRankedFormat(candidate, deckFormat)) {
              return false;
            }
            if (cardType != null && candidate.type != cardType) return false;
            if (factionRule == 'neutral') return candidate.faction == '中立';
            return candidate.faction == source.faction ||
                (includeNeutral && candidate.faction == '中立');
          })
          .map((candidate) => candidate.id);
    } else {
      final choices = effect['choices'];
      candidates = choices is List
          ? choices.map((candidate) => candidate.toString())
          : const Iterable<String>.empty();
    }
    return candidates
        .where(
          (candidateId) =>
              candidateId != sourceCardId && card(candidateId) != null,
        )
        .toSet()
        .toList(growable: false);
  }

  void _recastLastOpponentSpell({
    required BattleSide source,
    required BattleSide enemy,
    required String sourceName,
  }) {
    final state = battle;
    if (state == null || enemy.spellsPlayedThisGame.isEmpty) {
      stateLog(sourceName, '没有可重施放的敌方战术。');
      return;
    }
    final copiedSpell = card(enemy.spellsPlayedThisGame.last);
    if (copiedSpell == null || copiedSpell.type != 'spell') {
      stateLog(sourceName, '没有可重施放的敌方战术。');
      return;
    }
    _recastSpellCopy(
      copiedSpell,
      source: source,
      enemy: enemy,
      sourceName: sourceName,
    );
  }

  void _recastSpellCopy(
    CardDefinition copiedSpell, {
    required BattleSide source,
    required BattleSide enemy,
    required String sourceName,
  }) {
    final selection = _randomRecastTarget(
      copiedSpell,
      source: source,
      enemy: enemy,
    );
    if (selection == null) {
      stateLog(sourceName, '${copiedSpell.name} 没有合法的随机目标。');
      return;
    }
    stateLog(sourceName, '重施放 ${copiedSpell.name}，目标由时砂随机选择。');
    _emitFx(
      'spell',
      '${copiedSpell.name} 重施放',
      '复制对手上一张使用的战术',
      Icons.replay,
      0xFFA692D1,
      sourceId: copiedSpell.id,
    );
    if (_triggerSecrets(
      enemy,
      'opponent-plays-spell',
      triggeringSide: source,
    )) {
      stateLog(sourceName, '${copiedSpell.name} 的复制被奥秘反制。');
      return;
    }
    if (copiedSpell.school != null) {
      source.spellSchoolsPlayedThisTurn.add(copiedSpell.school!);
    }
    source.overloadLocked += copiedSpell.overload;

    final discover = copiedSpell.effect.where(
      (effect) =>
          effect['kind'] == 'discover' ||
          effect['kind'] == 'discover-copy-opponent-hand',
    );
    final chooseOne = copiedSpell.effect.where(
      (effect) => effect['kind'] == 'choose-one',
    );
    if (discover.isNotEmpty) {
      final effect = discover.first;
      if (effect['kind'] == 'discover-copy-opponent-hand') {
        final choices = _opponentHandCopyChoices(enemy);
        if (choices.isNotEmpty) {
          final snapshot = choices[_random.nextInt(choices.length)];
          final chosen = card(snapshot.cardId);
          if (chosen != null &&
              !_addCardToHand(
                source,
                chosen,
                costReduction: snapshot.costReduction,
                fragment: snapshot.fragment,
              )) {
            stateLog('重施放燃毁', '${chosen.name} 因手牌已满被销毁。');
          }
        }
      } else {
        final choices = _discoverPoolForEffect(effect, source, copiedSpell.id)
            .where((candidateId) => card(candidateId) != null)
            .toSet()
            .toList(growable: false);
        if (choices.isNotEmpty) {
          final chosen = card(choices[_random.nextInt(choices.length)]);
          if (chosen != null && !_addCardToHand(source, chosen)) {
            stateLog('重施放燃毁', '${chosen.name} 因手牌已满被销毁。');
          }
        }
      }
    } else if (chooseOne.isNotEmpty) {
      final options = chooseOne.first['options'];
      if (options is List && options.isNotEmpty) {
        final option = options[_random.nextInt(options.length)];
        if (option is Map && option['effects'] is List) {
          _resolveEffects(
            (option['effects'] as List)
                .whereType<Map>()
                .map((effect) => Map<String, dynamic>.from(effect))
                .toList(growable: false),
            source: source,
            enemy: enemy,
            target: selection.target,
            targetHero: selection.targetHero,
            targetFriendlyHero: selection.targetFriendlyHero,
            sourceName: '${copiedSpell.name} · 随机抉择',
            sourceCard: copiedSpell,
          );
        }
      }
    } else {
      _resolveEffects(
        copiedSpell.effect,
        source: source,
        enemy: enemy,
        target: selection.target,
        targetHero: selection.targetHero,
        targetFriendlyHero: selection.targetFriendlyHero,
        sourceName: '${copiedSpell.name} · 重施放',
        sourceCard: copiedSpell,
      );
    }
    _resolveSpellTriggers(source: source, enemy: enemy);
  }

  void _recastNonDeckSpellsOnce({
    required BattleSide source,
    required BattleSide enemy,
    required String sourceName,
  }) {
    if (source.nonDeckSpellRecastUsed) {
      stateLog(sourceName, '本局已经释放过非起始牌组战术回响。');
      return;
    }
    source.nonDeckSpellRecastUsed = true;
    while (source.spellsPlayedFromStartingDeck.length <
        source.spellsPlayedThisGame.length) {
      source.spellsPlayedFromStartingDeck.add(true);
    }
    final cardIds = <String>[];
    for (var index = 0; index < source.spellsPlayedThisGame.length; index++) {
      if (!source.spellsPlayedFromStartingDeck[index]) {
        cardIds.add(source.spellsPlayedThisGame[index]);
      }
    }
    if (cardIds.isEmpty) {
      stateLog(sourceName, '没有未始于起始牌组的战术可重施放。');
      return;
    }
    for (final cardId in cardIds) {
      final copiedSpell = card(cardId);
      if (copiedSpell == null || copiedSpell.type != 'spell') continue;
      _recastSpellCopy(
        copiedSpell,
        source: source,
        enemy: enemy,
        sourceName: sourceName,
      );
    }
  }

  void _resolveEffects(
    List<Map<String, dynamic>> effects, {
    required BattleSide source,
    required BattleSide enemy,
    BattleUnit? target,
    bool targetHero = false,
    bool targetFriendlyHero = false,
    required String sourceName,
    CardDefinition? sourceCard,
    BattleUnit? sourceUnit,
    String? sourceEntityId,
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
          case 'gain-temporary-mana':
            source.mana += max(0, amount);
            stateLog(sourceName, '获得 ${max(0, amount)} 点临时法力。');
            break;
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
                  entityId: sourceEntityId ?? _nextCardEntityId(),
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
            final state = battle;
            if (state != null) {
              final pool = _discoverPoolForEffect(
                effect,
                source,
                sourceCard?.id,
              );
              if (pool.length > 3) pool.shuffle(_random);
              final validChoices = pool.take(3).toList(growable: false);
              if (validChoices.isNotEmpty) {
                state.phase = 'discover';
                state.discoverChoices = validChoices;
                state.discoverCostReductions = List<int>.filled(
                  validChoices.length,
                  0,
                );
                state.discoverFragments = List<String?>.filled(
                  validChoices.length,
                  null,
                );
                state.discoverSource = sourceCard?.id ?? sourceName;
                state.discoverOwner = _ownerOf(source);
                state.discoverCopiedFrom = null;
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
          case 'discover-copy-opponent-hand':
            final state = battle;
            if (state != null) {
              final pool = _opponentHandCopyChoices(enemy);
              if (pool.length > 3) pool.shuffle(_random);
              final choices = pool.take(3).toList(growable: false);
              if (choices.isNotEmpty) {
                state.phase = 'discover';
                state.discoverChoices = choices
                    .map((choice) => choice.cardId)
                    .toList(growable: false);
                state.discoverCostReductions = choices
                    .map((choice) => choice.costReduction)
                    .toList(growable: false);
                state.discoverFragments = choices
                    .map((choice) => choice.fragment)
                    .toList(growable: false);
                state.discoverSource = sourceCard?.id ?? sourceName;
                state.discoverOwner = _ownerOf(source);
                state.discoverCopiedFrom = 'opponent-hand';
                stateLog(sourceName, '从对手手牌中发现一张复制。');
                _emitFx(
                  'discover',
                  '窥视手牌',
                  '从 ${choices.length} 张敌方手牌中选择复制',
                  Icons.visibility,
                  0xFFA692D1,
                );
                return;
              }
            }
            break;
          case 'copy-random-opponent-deck':
            _syncDeckCostOverrides(enemy);
            final pool = List.generate(
              enemy.deck.length,
              (index) => (
                card: enemy.deck[index],
                costOverride: enemy.deckCostOverrides[index],
              ),
            );
            final count = (effect['count'] as num?)?.toInt() ?? 1;
            var copied = 0;
            for (var index = 0; index < count && pool.isNotEmpty; index++) {
              final chosenIndex = _random.nextInt(pool.length);
              final copiedEntry = pool.removeAt(chosenIndex);
              final copiedCard = copiedEntry.card;
              if (_addCardToHand(
                source,
                copiedCard,
                costOverride: copiedEntry.costOverride,
              )) {
                copied++;
              } else {
                stateLog('复制燃毁', '${copiedCard.name} 因手牌已满被销毁。');
              }
            }
            stateLog(sourceName, '从对手牌库复制了 $copied 张牌；原牌库保持不变。');
            if (copied > 0) {
              _emitFx(
                'draw',
                '牌库复制',
                '获得 $copied 张保留当前费用的复制',
                Icons.content_copy,
                0xFFA692D1,
                amount: copied,
              );
            }
            break;
          case 'recast-last-opponent-spell':
            _recastLastOpponentSpell(
              source: source,
              enemy: enemy,
              sourceName: sourceName,
            );
            break;
          case 'recast-nondeck-spells-once':
            _recastNonDeckSpellsOnce(
              source: source,
              enemy: enemy,
              sourceName: sourceName,
            );
            break;
          case 'become-copy-of-unit':
            if (sourceUnit == null ||
                target == null ||
                identical(sourceUnit, target)) {
              break;
            }
            final sourceBoard = source.board.contains(sourceUnit)
                ? source
                : enemy.board.contains(sourceUnit)
                ? enemy
                : null;
            if (sourceBoard == null || target.health <= 0) break;
            final sourceIndex = sourceBoard.board.indexOf(sourceUnit);
            if (sourceIndex < 0) break;
            final replacement = _copyUnitForBattlefield(
              target,
              owner: sourceUnit.owner,
              instanceId: sourceUnit.instanceId,
            );
            sourceBoard.board[sourceIndex] = replacement;
            stateLog(sourceName, '变形成为 ${target.card.name} 的完整复制。');
            _emitFx(
              'transform',
              '${sourceUnit.card.name} 完整复制',
              '继承 ${target.card.name} 的当前状态与增益',
              Icons.copy_all,
              factionColors[target.card.faction] ?? 0xFFA692D1,
              sourceId: replacement.instanceId,
              targetId: target.instanceId,
            );
            break;
          case 'summon-copy-of-unit':
            if (target == null ||
                target.health <= 0 ||
                _battlefieldSize(source) >= 7) {
              break;
            }
            final copiedUnit = _copyUnitForBattlefield(
              target,
              owner: _ownerOf(source),
            );
            source.board.add(copiedUnit);
            stateLog(sourceName, '召唤 ${target.card.name} 的完整复制。');
            _emitFx(
              'summon',
              '${target.card.name} 完整复制',
              '保留当前状态与增益，不触发战吼',
              Icons.copy_all,
              factionColors[target.card.faction] ?? 0xFFA692D1,
              sourceId: copiedUnit.instanceId,
              targetId: target.instanceId,
            );
            _triggerSecrets(
              enemy,
              'opponent-summons-unit',
              triggeringSide: source,
            );
            break;
          case 'copy-unit-to-hand':
            if (target == null || target.health <= 0) break;
            if (_addCardToHand(source, target.card)) {
              stateLog(sourceName, '将 ${target.card.name} 的印刷复制置入手牌。');
              _emitFx(
                'draw',
                '${target.card.name} 已复制',
                '战场增益不随逆向区域复制保留',
                Icons.content_copy,
                factionColors[target.card.faction] ?? 0xFFA692D1,
                sourceId: target.instanceId,
              );
            } else {
              stateLog(sourceName, '${target.card.name} 的复制因手牌已满而燃毁。');
            }
            break;
          case 'damage':
            if (target != null &&
                (enemy.board.contains(target) ||
                    source.board.contains(target))) {
              _damageUnit(target, damageAmount);
            } else {
              final hero = targetHero && targetFriendlyHero ? source : enemy;
              final dealt = _damageHero(hero, damageAmount);
              stateLog(
                '$sourceName：',
                '${identical(hero, source) ? '对友方' : '对敌方'}核心造成 $dealt 点伤害',
              );
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
          case 'damage-all-enemy-units':
            for (final unit in [...enemy.board]) {
              _damageUnit(unit, damageAmount);
            }
            stateLog(sourceName, '对所有敌方单位造成 $damageAmount 点伤害。');
            break;
          case 'destroy-highest-health-enemy':
            final candidates =
                enemy.board.where((unit) => unit.health > 0).toList()
                  ..sort((left, right) => right.health.compareTo(left.health));
            if (candidates.isNotEmpty) {
              final destroyed = candidates.first;
              destroyed.health = 0;
              stateLog(sourceName, '摧毁 ${destroyed.card.name}。');
            }
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
            if (target != null &&
                (source.board.contains(target) ||
                    enemy.board.contains(target))) {
              target.health = min(target.maxHealth, target.health + amount);
            } else {
              final hero = targetHero && !targetFriendlyHero ? enemy : source;
              final healed = _healHero(hero, amount);
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
          case 'draw-minion-type':
            final count = (effect['count'] as num?)?.toInt() ?? 1;
            final minionType = effect['minionType']?.toString() ?? '';
            for (var i = 0; i < count; i++) {
              if (!_drawMinionType(source, minionType)) break;
            }
            break;
          case 'draw-spell-school':
            final count = (effect['count'] as num?)?.toInt() ?? 1;
            final school = effect['school']?.toString() ?? '';
            for (var i = 0; i < count; i++) {
              if (!_drawSpellSchool(source, school)) break;
            }
            break;
          case 'resurrect-friendly-unit':
            final count = (effect['count'] as num?)?.toInt() ?? 1;
            final minionType = effect['minionType']?.toString();
            final eligible = source.deathHistory.reversed
                .where((record) {
                  final definition = card(record.cardId);
                  if (definition == null || !definition.isUnit) return false;
                  return minionType == null ||
                      minionType.isEmpty ||
                      hasMinionType(definition, minionType);
                })
                .take(count)
                .toList(growable: false);
            var resurrected = 0;
            for (final record in eligible) {
              if (_battlefieldSize(source) >= 7) break;
              final definition = card(record.cardId);
              if (definition == null || !definition.isUnit) continue;
              final unit = _summonUnit(
                definition,
                owner: _ownerOf(source),
                side: source,
              );
              source.board.add(unit);
              resurrected++;
              stateLog(sourceName, '${definition.name} 以印刷状态复活。');
              _emitFx(
                'summon',
                '${definition.name} 复活',
                '不保留原有增益',
                Icons.restore,
                factionColors[definition.faction] ?? 0xFFA692D1,
                sourceId: unit.instanceId,
              );
              _triggerSecrets(
                enemy,
                'opponent-summons-unit',
                triggeringSide: source,
              );
              _summonColossalParts(
                card: definition,
                source: source,
                enemy: enemy,
                owner: _ownerOf(source),
              );
            }
            if (resurrected == 0) {
              stateLog(sourceName, '没有可复活的友方单位。');
            }
            break;
          case 'spell-school-payoff':
            final nested = effect['effects'];
            if (_spellSchoolPayoffActive(source, effect) && nested is List) {
              _resolveEffects(
                nested
                    .whereType<Map>()
                    .map((item) => Map<String, dynamic>.from(item))
                    .toList(growable: false),
                source: source,
                enemy: enemy,
                target: target,
                targetHero: targetHero,
                targetFriendlyHero: targetFriendlyHero,
                sourceName: '$sourceName · 派系共鸣',
                sourceCard: sourceCard,
                sourceUnit: sourceUnit,
              );
            }
            break;
          case 'shuffle-random-into-deck':
            final ids = effect['cardIds'];
            final pool = ids is List
                ? ids
                      .map((id) => card(id.toString()))
                      .whereType<CardDefinition>()
                      .toList()
                : <CardDefinition>[];
            final count = (effect['count'] as num?)?.toInt() ?? 1;
            final fixedCost = (effect['cost'] as num?)?.toInt();
            final recipient = effect['player'] == 'opponent' ? enemy : source;
            for (var i = 0; i < count && pool.isNotEmpty; i++) {
              final generated = pool[_random.nextInt(pool.length)];
              _syncDeckCostOverrides(recipient);
              final insertionIndex = _random.nextInt(recipient.deck.length + 1);
              recipient.deck.insert(insertionIndex, generated);
              recipient.deckCostOverrides.insert(insertionIndex, fixedCost);
              recipient.deckStartedInDeck.insert(insertionIndex, false);
              recipient.deckEntityIds.insert(
                insertionIndex,
                _nextCardEntityId(),
              );
            }
            stateLog(
              sourceName,
              effect['player'] == 'opponent'
                  ? '将 $count 张牌洗入对手牌库。'
                  : '将 $count 张牌洗入牌库。',
            );
            break;
          case 'draw-opponent':
            final count = (effect['count'] as num?)?.toInt() ?? 1;
            for (var i = 0; i < count; i++) {
              _draw(enemy);
            }
            stateLog(sourceName, '贿赂收益：对手抽取 $count 张牌。');
            break;
          case 'damage-friendly-hero':
            final dealt = _damageHero(source, amount);
            stateLog(sourceName, '对其控制者的核心造成 $dealt 点伤害。');
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
          case 'buff-friendly-minion-type':
            final attack = (effect['attack'] as num?)?.toInt() ?? 0;
            final health = (effect['health'] as num?)?.toInt() ?? 0;
            final minionType = effect['minionType']?.toString() ?? '';
            final excludeSource = effect['excludeSource'] == true;
            var affected = 0;
            for (final unit in [...source.board]) {
              if (excludeSource && identical(unit, sourceUnit)) continue;
              if (!hasMinionType(unit.card, minionType)) continue;
              unit.attack += attack;
              unit.maxHealth += health;
              unit.health += health;
              unit.permanentAttackBonus += attack;
              unit.permanentHealthBonus += health;
              affected++;
            }
            stateLog(
              sourceName,
              '${minionTypeLabels[minionType] ?? minionType}单位 $affected 个获得 +$attack/+$health。',
            );
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
            final replacement = _summonUnit(
              transformed,
              owner: target.owner,
              side: targetSide,
            );
            targetSide.board[index] = replacement;
            stateLog(
              sourceName,
              '${target.card.name} 变形为 ${transformed.name}。',
            );
            break;
          case 'return-unit-to-hand':
            if (target == null) break;
            final targetSide = source.board.contains(target)
                ? source
                : enemy.board.contains(target)
                ? enemy
                : null;
            if (targetSide == null) break;
            targetSide.board.remove(target);
            _syncHandCostReductions(targetSide);
            if (_occupiedHandSlots(targetSide) < 10) {
              targetSide.hand.add(target.card);
              targetSide.handCostReductions.add(0);
              targetSide.handFragments.add(null);
              targetSide.handStartedInDeck.add(false);
              targetSide.handEnteredTurns.add(battle!.turn);
              targetSide.handEntityIds.add(target.instanceId);
              stateLog(sourceName, '${target.card.name} 返回其控制者的手牌并移除全部增益。');
              _emitFx(
                'draw',
                '${target.card.name} 返回手牌',
                '战场增益已移除',
                Icons.keyboard_return,
                factionColors[target.card.faction] ?? 0xFFA692D1,
                sourceId: target.instanceId,
              );
            } else {
              stateLog(sourceName, '${target.card.name} 因控制者手牌已满而燃毁。');
              _emitFx(
                'burn',
                '回手燃毁',
                '${target.card.name} 因手牌已满被销毁',
                Icons.local_fire_department,
                0xFFE46D3F,
                sourceId: target.instanceId,
              );
            }
            break;
          case 'take-control':
            if (target != null) {
              _takeControlOfUnit(
                source: source,
                enemy: enemy,
                unit: target,
                sourceName: sourceName,
              );
            }
            break;
          case 'take-control-random-enemy':
            if (_battlefieldSize(source) >= 7) break;
            final candidates = enemy.board
                .where((unit) => unit.health > 0)
                .toList(growable: false);
            if (candidates.isEmpty) break;
            _takeControlOfUnit(
              source: source,
              enemy: enemy,
              unit: candidates[_random.nextInt(candidates.length)],
              sourceName: sourceName,
            );
            break;
          case 'discard-random':
            _discardRandomCards(
              source: source,
              enemy: enemy,
              count: (effect['count'] as num?)?.toInt() ?? 1,
              sourceName: sourceName,
            );
            break;
          case 'recover-discarded':
            _recoverDiscardedCards(
              source: source,
              count: (effect['count'] as num?)?.toInt() ?? 1,
              sourceName: sourceName,
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
              state.chooseOneSourceEntityId = sourceEntityId;
              state.chooseOneOwner = _ownerOf(source);
              state.chooseOneTarget = target;
              state.chooseOneRemaining = 1;
              state.chooseOneSourceKind = 'spell';
              state.chooseOneChosenLabels.clear();
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
              for (var i = 0; i < count && _battlefieldSize(source) < 7; i++) {
                final unit = _summonUnit(
                  summonCard,
                  owner: _ownerOf(source),
                  side: source,
                );
                source.board.add(unit);
                _emitFx(
                  'summon',
                  '${summonCard.name} 被召唤',
                  '效果生成一个新的战场单位',
                  Icons.auto_awesome,
                  factionColors[summonCard.faction] ?? 0xFF69CFC3,
                  sourceId: unit.instanceId,
                );
                _triggerSecrets(
                  enemy,
                  'opponent-summons-unit',
                  triggeringSide: source,
                );
                _summonColossalParts(
                  card: summonCard,
                  source: source,
                  enemy: enemy,
                  owner: _ownerOf(source),
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
      _sendCardToGraveyard(
        owner,
        secret.card,
        secret.entityId,
        fromZone: 'secret',
        reason: 'triggered',
      );
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

  bool chooseDiscover(String cardId, {int? choiceIndex}) {
    final state = battle;
    final resolvedIndex =
        choiceIndex ?? state?.discoverChoices.indexOf(cardId) ?? -1;
    if (state == null ||
        state.phase != 'discover' ||
        resolvedIndex < 0 ||
        resolvedIndex >= state.discoverChoices.length ||
        state.discoverChoices[resolvedIndex] != cardId) {
      return false;
    }
    final discovered = card(cardId);
    if (discovered == null) return false;
    final owner = state.discoverOwner == 'ai' ? state.ai : state.player;
    final enemy = identical(owner, state.player) ? state.ai : state.player;
    final copiedFrom = state.discoverCopiedFrom;
    final retainedReduction =
        resolvedIndex < state.discoverCostReductions.length
        ? state.discoverCostReductions[resolvedIndex]
        : 0;
    final fragment = resolvedIndex < state.discoverFragments.length
        ? state.discoverFragments[resolvedIndex]
        : null;
    if (!_addCardToHand(
      owner,
      discovered,
      costReduction: retainedReduction,
      fragment: fragment,
    )) {
      stateLog('发现失败', '${discovered.name} 因手牌已满被燃毁。');
    }
    state.phase = 'main';
    state.discoverChoices = <String>[];
    state.discoverCostReductions = <int>[];
    state.discoverFragments = <String?>[];
    state.discoverSource = null;
    state.discoverOwner = 'player';
    state.discoverCopiedFrom = null;
    stateLog(copiedFrom == null ? '发现完成' : '复制完成', '${discovered.name} 已加入手牌。');
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
    final sourceEntityId = state.chooseOneSourceEntityId;
    final target = state.chooseOneTarget;
    final sourceKind = state.chooseOneSourceKind;
    final label = option['label']?.toString() ?? '一个分支';

    if (sourceKind == 'hero-card') {
      state.chooseOneChosenLabels.add(label);
      state.chooseOneOptions.removeAt(optionIndex);
      state.chooseOneRemaining = max(0, state.chooseOneRemaining - 1);
      _resolveEffects(
        parsed,
        source: source,
        enemy: enemy,
        target: target,
        sourceName: '$sourceName · $label',
      );
      stateLog('灭世灾变', '已释放 $label。');
      if (state.finished || state.chooseOneRemaining <= 0) {
        state.chooseOneOptions = <Map<String, dynamic>>[];
        state.chooseOneSource = null;
        state.chooseOneSourceEntityId = null;
        state.chooseOneOwner = 'player';
        state.chooseOneTarget = null;
        state.chooseOneRemaining = 1;
        state.chooseOneSourceKind = 'spell';
        state.chooseOneChosenLabels.clear();
        if (!state.finished) state.phase = 'main';
      } else {
        state.phase = 'choose-one';
      }
      _processDeaths();
      _checkFinished();
      notifyListeners();
      return true;
    }

    state.phase = 'main';
    state.chooseOneOptions = <Map<String, dynamic>>[];
    state.chooseOneSource = null;
    state.chooseOneSourceEntityId = null;
    state.chooseOneOwner = 'player';
    state.chooseOneTarget = null;
    state.chooseOneRemaining = 1;
    state.chooseOneSourceKind = 'spell';
    state.chooseOneChosenLabels.clear();
    _resolveEffects(
      parsed,
      source: source,
      enemy: enemy,
      target: target,
      sourceName: '$sourceName · $label',
      sourceEntityId: sourceEntityId,
    );
    if (state.phase == 'main') {
      _resolveSpellTriggers(source: source, enemy: enemy);
    }
    stateLog('抉择完成', '已选择 $label。');
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

  bool _takeControlOfUnit({
    required BattleSide source,
    required BattleSide enemy,
    required BattleUnit unit,
    required String sourceName,
  }) {
    if (_battlefieldSize(source) >= 7 ||
        unit.health <= 0 ||
        !enemy.board.contains(unit)) {
      return false;
    }
    enemy.board.remove(unit);
    unit.owner = _ownerOf(source);
    unit.attacksMade = 0;
    unit.hasAttacked = false;
    unit.summoningSick = !unit.hasCharge && !unit.hasRush;
    unit.rushOnly = !unit.hasCharge && unit.hasRush;
    unit.freezeBlocked = unit.frozenTurns > 0;
    source.board.add(unit);
    stateLog(sourceName, '获得 ${unit.card.name} 的控制权。');
    _emitFx(
      'summon',
      '控制权转移',
      '${unit.card.name} 加入新的战场',
      Icons.swap_horiz,
      0xFFA692D1,
      sourceId: unit.instanceId,
      targetId: unit.instanceId,
    );
    return true;
  }

  String _ownerOf(BattleSide side) {
    final state = battle!;
    return identical(side, state.player) ? 'player' : 'ai';
  }

  void _sendCardToGraveyard(
    BattleSide side,
    CardDefinition card,
    String entityId, {
    required String fromZone,
    required String reason,
  }) {
    if (card.isUnit ||
        side.cardGraveyard.any((entry) => entry.entityId == entityId)) {
      return;
    }
    side.cardGraveyard.add(
      BattleGraveyardRecord(
        entityId: entityId,
        card: card,
        fromZone: fromZone,
        reason: reason,
        turn: battle?.turn ?? 0,
        order: side.cardGraveyard.length + 1,
      ),
    );
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
          entry.side.deathHistory.add(
            BattleDeathRecord(
              entityId: unit.instanceId,
              cardId: unit.card.id,
              name: unit.card.name,
              controller: identical(entry.side, state.player) ? 0 : 1,
              diedTurn: state.turn,
              deathOrder:
                  state.player.deathHistory.length +
                  state.ai.deathHistory.length +
                  1,
              minionTypes: List<String>.from(unit.card.minionTypes),
            ),
          );
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
        if (_battlefieldSize(entry.side) >= 7) continue;
        final unit = entry.unit;
        final reborn = _summonUnit(
          unit.card,
          owner: unit.owner,
          side: entry.side,
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
        _summonColossalParts(
          card: unit.card,
          source: entry.side,
          enemy: entry.enemy,
          owner: unit.owner,
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
    state.player.heroAttackBonus = 0;
    _archiveSpellSchoolTurn(state.player);
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
    for (final location in List<BattleLocation>.from(state.ai.locations)) {
      if (state.actionWindow < location.readyOnTurn) continue;
      location.durability--;
      location.readyOnTurn = state.actionWindow + 4;
      stateLog(location.card.name, '敌方激活地点，剩余 ${location.durability} 点耐久。');
      _resolveEffects(
        location.card.effect,
        source: state.ai,
        enemy: state.player,
        sourceName: location.card.name,
      );
      if (location.durability <= 0) {
        state.ai.locations.remove(location);
        _sendCardToGraveyard(
          state.ai,
          location.card,
          location.entityId,
          fromZone: 'location',
          reason: 'durability',
        );
      }
      if (state.finished) return;
    }
    if (state.ai.hand.any((card) => card.id == 'the-coin') &&
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
          List<int>.generate(state.ai.hand.length, (index) => index)
            ..sort((left, right) {
              final heraldOrder = (_isHeraldSetup(state.ai, left) ? 0 : 1)
                  .compareTo(_isHeraldSetup(state.ai, right) ? 0 : 1);
              if (heraldOrder != 0) return heraldOrder;
              final bridgeOrder = (_isShatterBridge(state.ai, left) ? 0 : 1)
                  .compareTo(_isShatterBridge(state.ai, right) ? 0 : 1);
              if (bridgeOrder != 0) return bridgeOrder;
              return _effectiveHandCost(
                state.ai,
                left,
              ).compareTo(_effectiveHandCost(state.ai, right));
            });
      int? handIndex;
      CardDefinition? card;
      BattleUnit? target;
      var placement = 'friendly';
      for (final candidateIndex in candidates) {
        final candidate = state.ai.hand[candidateIndex];
        if (candidate.id == 'the-coin') continue;
        final candidatePlacement = _chooseAiCardPlacement(state, candidate);
        final recipient = candidatePlacement == 'enemy'
            ? state.player
            : state.ai;
        if (_effectiveHandCost(state.ai, candidateIndex) > state.ai.mana ||
            (candidate.isUnit &&
                _battlefieldSize(recipient) >= 7 &&
                _findUpgradeTarget(recipient, candidate) == null) ||
            (candidate.isLocation && _battlefieldSize(state.ai) >= 7) ||
            (_battlefieldSize(state.ai) >= 7 &&
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
        placement = candidatePlacement;
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
        placement: placement,
      );
      if (state.phase == 'discover' &&
          state.discoverOwner == 'ai' &&
          state.discoverChoices.isNotEmpty) {
        chooseDiscover(state.discoverChoices.first, choiceIndex: 0);
      }
      while (state.phase == 'choose-one' &&
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
        ((state.ai.weapon?.attack ?? 0) + state.ai.heroAttackBonus) > 0 &&
        !state.ai.heroHasAttacked &&
        (state.ai.weapon == null || state.ai.weapon!.durability > 0)) {
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
    state.ai.heroAttackBonus = 0;
    _archiveSpellSchoolTurn(state.ai);
    _settleFreezeAtEndOfTurn(state.ai);
    _processDeaths();
    _checkFinished();
  }

  String _chooseAiCardPlacement(BattleState state, CardDefinition card) {
    if (!card.isUnit || !card.disguised) return 'friendly';
    final canPlaceFriendly =
        _battlefieldSize(state.ai) < 7 ||
        _findUpgradeTarget(state.ai, card) != null;
    final canPlaceEnemy =
        _battlefieldSize(state.player) < 7 ||
        _findUpgradeTarget(state.player, card) != null;
    if (!canPlaceFriendly && canPlaceEnemy) return 'enemy';
    if (!canPlaceEnemy) return 'friendly';
    if (state.player.heroHealth <= 2 || state.player.board.length >= 6) {
      return 'enemy';
    }
    return 'friendly';
  }

  bool _isShatterBridge(BattleSide side, int handIndex) {
    _syncHandCostReductions(side);
    if (handIndex < 0 ||
        handIndex >= side.hand.length ||
        side.handFragments[handIndex] != null) {
      return false;
    }
    for (var leftIndex = 0; leftIndex < handIndex; leftIndex++) {
      final left = side.handFragments[leftIndex];
      if (left == null || !left.isLeft) continue;
      for (
        var rightIndex = handIndex + 1;
        rightIndex < side.hand.length;
        rightIndex++
      ) {
        final right = side.handFragments[rightIndex];
        if (right != null &&
            right.piece == 'right' &&
            right.groupId == left.groupId &&
            side.hand[leftIndex].id == side.hand[rightIndex].id) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isHeraldSetup(BattleSide side, int handIndex) {
    if (handIndex < 0 || handIndex >= side.hand.length) return false;
    final colossalId = side.hand[handIndex].herald?['colossalCardId']
        ?.toString();
    return colossalId != null &&
        side.hand.any((candidate) => candidate.id == colossalId);
  }

  void _aiHeroAttack(BattleState state, BattleUnit? target) {
    final weapon = state.ai.weapon;
    final attack = (weapon?.attack ?? 0) + state.ai.heroAttackBonus;
    if (attack <= 0) return;
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
        ? _damageHero(state.player, attack)
        : _damageUnit(target, attack, combat: true);
    if (target != null) {
      final reflected = _damageHero(state.ai, defenderAttack);
      if (defenderHasLifesteal && reflected > 0) {
        _healHero(state.player, reflected);
      }
    }
    state.ai.heroHasAttacked = true;
    if (weapon != null) weapon.durability--;
    final attackSource = weapon?.card.name ?? state.ai.heroName;
    state.logs.insert(
      0,
      target == null
          ? '敌方英雄使用 $attackSource 攻击核心，造成 $dealt 点伤害。'
          : '敌方英雄使用 $attackSource 攻击 ${target.card.name}。',
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
    if (weapon != null && weapon.durability <= 0) {
      _sendCardToGraveyard(
        state.ai,
        weapon.card,
        weapon.entityId,
        fromZone: 'weapon',
        reason: 'durability',
      );
      state.ai.weapon = null;
    }
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

  void _archiveSpellSchoolTurn(BattleSide side) {
    side.spellSchoolsPlayedLastTurn
      ..clear()
      ..addAll(side.spellSchoolsPlayedThisTurn);
    side.spellSchoolsPlayedThisTurn.clear();
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
    if (type == 'any-unit') {
      final candidates =
          <BattleUnit>[
            ...state.ai.board.where((unit) => unit.health > 0),
            ...state.player.board.where(
              (unit) => unit.health > 0 && !unit.stealthActive,
            ),
          ]..sort(
            (left, right) => (right.attack + right.health).compareTo(
              left.attack + left.health,
            ),
          );
      return candidates.isEmpty ? null : candidates.first;
    }
    if (type.startsWith('friendly')) {
      if (type.contains('unit')) {
        return state.ai.board.isEmpty ? null : state.ai.board.first;
      }
      return null;
    }
    if (type.startsWith('enemy') && type.contains('unit')) {
      final visible = state.player.board
          .where((unit) => !unit.stealthActive && unit.health > 0)
          .toList();
      if (visible.isEmpty) return null;
      final takesControl = [
        ...card.effect,
        ...card.onPlay,
        ...card.combo,
      ].any((effect) => effect['kind'] == 'take-control');
      if (takesControl) {
        visible.sort(
          (left, right) => (right.attack + right.health).compareTo(
            left.attack + left.health,
          ),
        );
      }
      return visible.first;
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

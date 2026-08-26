import 'dart:convert';

import 'formats.dart';

const _deckCodeVersion = 'ASTRA2';
const _legacyDeckCodeVersion = 'ASTRA1';
const _maxEncodedLength = 12000;
final _cardIdPattern = RegExp(r'^[a-z0-9][a-z0-9-]*$');

class DecodedDeckCode {
  const DecodedDeckCode({
    required this.version,
    required this.format,
    required this.name,
    required this.cardIds,
  });

  final int version;
  final RankedFormat? format;
  final String? name;
  final List<String> cardIds;
}

class DeckCodeImportResult {
  const DeckCodeImportResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class DeckCodePreview {
  const DeckCodePreview({
    required this.code,
    required this.version,
    required this.format,
    required this.name,
    required this.missingCount,
  });

  final String code;
  final int version;
  final RankedFormat format;
  final String name;
  final int missingCount;
}

String _normalizeDeckName(String value) {
  final trimmed = value.trim();
  final normalized = trimmed.isEmpty ? '未命名卡组' : trimmed;
  return normalized.length <= 32 ? normalized : normalized.substring(0, 32);
}

String _encodeDeckName(String value) =>
    Uri.encodeComponent(_normalizeDeckName(value)).replaceAllMapped(
      RegExp(r"[!'()*]"),
      (match) =>
          '%${match.group(0)!.codeUnitAt(0).toRadixString(16).toUpperCase()}',
    );

List<String> _parseCardIds(String value) {
  final ids = value.split(',');
  if (ids.isEmpty || ids.any((id) => !_cardIdPattern.hasMatch(id))) {
    throw const FormatException('卡组代码包含无效卡牌编号。');
  }
  return ids;
}

DecodedDeckCode _decodeRawDeckCode(String raw) {
  if (raw.startsWith('$_deckCodeVersion|')) {
    final parts = raw.split('|');
    if (parts.length != 4) {
      throw const FormatException('ASTRA2 卡组代码字段不完整。');
    }
    final format = switch (parts[1]) {
      'standard' => RankedFormat.standard,
      'wild' => RankedFormat.wild,
      _ => throw const FormatException('卡组代码包含未知模式。'),
    };
    String name;
    try {
      name = Uri.decodeComponent(parts[2]);
    } on FormatException {
      throw const FormatException('卡组代码名称无效。');
    }
    return DecodedDeckCode(
      version: 2,
      format: format,
      name: _normalizeDeckName(name),
      cardIds: _parseCardIds(parts[3]),
    );
  }

  if (raw.startsWith('$_legacyDeckCodeVersion|')) {
    return DecodedDeckCode(
      version: 1,
      format: null,
      name: null,
      cardIds: _parseCardIds(raw.substring(_legacyDeckCodeVersion.length + 1)),
    );
  }

  if (raw.contains(',') && !raw.contains('|')) {
    return DecodedDeckCode(
      version: 1,
      format: null,
      name: null,
      cardIds: _parseCardIds(raw),
    );
  }

  throw const FormatException('不支持的卡组代码版本。');
}

String encodeDeckCode({
  required RankedFormat format,
  required String name,
  required List<String> cardIds,
}) {
  final parsedIds = _parseCardIds(cardIds.join(','));
  final raw = [
    _deckCodeVersion,
    format.wireValue,
    _encodeDeckName(name),
    parsedIds.join(','),
  ].join('|');
  return base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
}

DecodedDeckCode decodeDeckCode(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > _maxEncodedLength) {
    throw const FormatException('卡组代码为空或过长。');
  }
  if (trimmed.startsWith('$_deckCodeVersion|') ||
      trimmed.startsWith('$_legacyDeckCodeVersion|') ||
      (trimmed.contains(',') && !trimmed.contains('|'))) {
    return _decodeRawDeckCode(trimmed);
  }
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(trimmed) ||
      trimmed.length % 4 == 1) {
    throw const FormatException('卡组代码格式无效。');
  }
  final normalized = trimmed.replaceAll('-', '+').replaceAll('_', '/');
  final padded = normalized.padRight(
    normalized.length + ((4 - normalized.length % 4) % 4),
    '=',
  );
  try {
    return _decodeRawDeckCode(utf8.decode(base64.decode(padded)));
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('卡组代码格式无效。');
  }
}

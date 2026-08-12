import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/card_definition.dart';
import 'rule_overrides.dart';

const factionOrder = <String>['曜光', '幽潮', '中立', '烬火', '星穹', '苍林', '雷铸'];

const factionDoctrine = <String, String>{
  '曜光': '护盾 · 增益',
  '幽潮': '汲取 · 手牌',
  '中立': '通用 · 巧铸',
  '烬火': '冲锋 · 直伤',
  '星穹': '秘契 · 护盾',
  '苍林': '治疗 · 猎痕',
  '雷铸': '巧铸 · 激昂',
};

const factionSigil = <String, String>{
  '曜光': '☼',
  '幽潮': '◒',
  '中立': '◇',
  '烬火': '△',
  '星穹': '✦',
  '苍林': '♧',
  '雷铸': 'ϟ',
};

const factionColors = <String, int>{
  '曜光': 0xFFE9CC78,
  '幽潮': 0xFF68A9D8,
  '中立': 0xFFB6A17E,
  '烬火': 0xFFE46D3F,
  '星穹': 0xFFA692D1,
  '苍林': 0xFF79B980,
  '雷铸': 0xFF65CDDA,
};

const rarityColors = <String, int>{
  '普通': 0xFF87958D,
  '稀有': 0xFF62CFC5,
  '史诗': 0xFFA692D1,
  '传说': 0xFFE46D3F,
};

const keywordLabels = <String, String>{
  'battlecry': '战吼',
  'deathrattle': '亡语',
  'charge': '冲锋',
  'rush': '突袭',
  'taunt': '嘲讽',
  'shield': '护盾',
  'lifesteal': '汲取',
  'fury': '激昂',
  'windfury': '风怒',
  'poisonous': '剧毒',
  'stealth': '潜行',
  'reborn': '复生',
  'freeze': '冻结',
  'overload': '过载',
  'tradeable': '可交易',
  'spell-damage': '法术伤害',
  'secret': '奥秘',
  'discover': '发现',
  'combo': '连击',
  'silence': '沉默',
  'choose-one': '抉择',
  'transform': '变形',
  'temporary': '临时',
  'end-of-turn': '回合结束',
  'start-of-turn': '回合开始',
  'spell-trigger': '法术触发',
};

const traitLabels = <String, String>{
  'swift': '迅锋',
  'bulwark': '坚阵',
  'arcane': '秘契',
  'hunt': '猎痕',
  'craft': '巧铸',
};

Future<List<CardDefinition>> loadCatalog() async {
  final raw = await rootBundle.loadString('assets/cards.json');
  final decoded = jsonDecode(raw) as List<dynamic>;
  return decoded
      .whereType<Map>()
      .map((item) => CardDefinition.fromJson(Map<String, dynamic>.from(item)))
      .map(enrichCardRules)
      .toList(growable: false);
}

import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/card_definition.dart';

const factionOrder = <String>[
  '曜光',
  '幽潮',
  '中立',
  '烬火',
  '星穹',
  '苍林',
  '雷铸',
  '霜境',
  '砂海',
  '赤月',
  '灵脉',
  '暮影',
  '云瀑',
  '磁风',
  '晶核',
  '梦境',
  '裂星',
  '时砂',
  '幽森',
  '天穹',
];

const factionDoctrine = <String, String>{
  '曜光': '护盾 · 增益',
  '幽潮': '汲取 · 手牌',
  '中立': '通用 · 巧铸',
  '烬火': '冲锋 · 直伤',
  '星穹': '秘契 · 护盾',
  '苍林': '治疗 · 猎痕',
  '雷铸': '巧铸 · 激昂',
  '霜境': '冻结 · 冰甲',
  '砂海': '沙暴 · 资源',
  '赤月': '献祭 · 吸血',
  '灵脉': '法术 · 共鸣',
  '暮影': '潜伏 · 反制',
  '云瀑': '风行 · 回旋',
  '磁风': '磁场 · 装配',
  '晶核': '护晶 · 变形',
  '梦境': '幻术 · 发现',
  '裂星': '撕裂 · 直伤',
  '时砂': '延时 · 复写',
  '幽森': '亡语 · 毒荆',
  '天穹': '巨像 · 终局',
};

const factionSigil = <String, String>{
  '曜光': '☼',
  '幽潮': '◒',
  '中立': '◇',
  '烬火': '△',
  '星穹': '✦',
  '苍林': '♧',
  '雷铸': 'ϟ',
  '霜境': '❄',
  '砂海': '⌁',
  '赤月': '☾',
  '灵脉': '⌬',
  '暮影': '◐',
  '云瀑': '≋',
  '磁风': '⊕',
  '晶核': '◈',
  '梦境': '✧',
  '裂星': '✺',
  '时砂': '⌛',
  '幽森': '♠',
  '天穹': '⬡',
};

const factionColors = <String, int>{
  '曜光': 0xFFE9CC78,
  '幽潮': 0xFF68A9D8,
  '中立': 0xFFB6A17E,
  '烬火': 0xFFE46D3F,
  '星穹': 0xFFA692D1,
  '苍林': 0xFF79B980,
  '雷铸': 0xFF65CDDA,
  '霜境': 0xFF79DCFF,
  '砂海': 0xFFE2B45D,
  '赤月': 0xFFE24D62,
  '灵脉': 0xFF67E8D4,
  '暮影': 0xFF7359A8,
  '云瀑': 0xFF8BD7EC,
  '磁风': 0xFFE08E55,
  '晶核': 0xFFDCECFF,
  '梦境': 0xFFF0A9E6,
  '裂星': 0xFFF36B52,
  '时砂': 0xFFE5C779,
  '幽森': 0xFF7BBF76,
  '天穹': 0xFFFFE3A2,
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
  'prepare': '预备',
  'bribe': '贿赂',
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
      .toList(growable: false);
}

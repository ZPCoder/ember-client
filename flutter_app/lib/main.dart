import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, HapticFeedback, SystemSound, SystemSoundType;
import 'data/catalog.dart';
import 'game/game_controller.dart';
import 'models/card_definition.dart';
import 'network/multiplayer_client.dart';
import 'network/online_battle_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = GameController();
  await controller.initialize();
  runApp(AstraProtocolApp(controller: controller));
}

class AstraProtocolApp extends StatelessWidget {
  const AstraProtocolApp({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    const paper = Color(0xFFF1E6C8);
    const ink = Color(0xFF06110F);
    return MaterialApp(
      title: '星骇协议 · ASTRA PROTOCOL',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ink,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF69CFC3),
          brightness: Brightness.dark,
          surface: const Color(0xFF10211D),
          onSurface: paper,
        ),
        fontFamily: 'AstraCJK',
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Color(0xFFB9C2B9), height: 1.35),
          titleLarge: TextStyle(color: paper, fontWeight: FontWeight.w700),
          headlineMedium: TextStyle(color: paper, fontWeight: FontWeight.w700),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF081713),
          foregroundColor: paper,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0D1D19),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFF29403A)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFF29403A)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Color(0xFF69CFC3)),
          ),
          labelStyle: TextStyle(color: Color(0xFF84938A)),
          hintStyle: TextStyle(color: Color(0xFF65746D)),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF10221D),
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            side: BorderSide(color: Color(0xFF29403A)),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF081713),
          indicatorColor: Color(0xFF1F514B),
          labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11)),
        ),
      ),
      home: AppShell(controller: controller),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final GameController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selectedIndex = 0;

  static const labels = ['总览', '收藏', '卡组', '对战', '联机', '运营'];
  static const icons = [
    Icons.radar_outlined,
    Icons.grid_view_rounded,
    Icons.layers_outlined,
    Icons.sports_kabaddi_outlined,
    Icons.public,
    Icons.insights_outlined,
  ];

  Widget _page() {
    switch (selectedIndex) {
      case 1:
        return CollectionPage(controller: widget.controller);
      case 2:
        return DeckPage(controller: widget.controller);
      case 3:
        return BattlePage(controller: widget.controller);
      case 4:
        return MultiplayerPage(controller: widget.controller);
      case 5:
        return OperationsPage(controller: widget.controller);
      default:
        return OverviewPage(
          controller: widget.controller,
          onNavigate: (index) => setState(() => selectedIndex = index),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        if (widget.controller.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (widget.controller.errorMessage != null) {
          return Scaffold(
            body: Center(child: Text(widget.controller.errorMessage!)),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 850;
            final content = Scaffold(
              appBar: AppBar(
                title: Row(
                  children: [
                    const Text(
                      'ASTRA PROTOCOL',
                      style: TextStyle(letterSpacing: 2, fontSize: 15),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: Color(0xFF69CFC3),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                actions: [
                  _CurrencyChip(
                    icon: Icons.circle,
                    label: '${widget.controller.gold}',
                    color: const Color(0xFFE8C46F),
                  ),
                  _CurrencyChip(
                    icon: Icons.auto_awesome,
                    label: '${widget.controller.dust}',
                    color: const Color(0xFFA692D1),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              body: _page(),
              bottomNavigationBar: wide
                  ? null
                  : NavigationBar(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: (index) =>
                          setState(() => selectedIndex = index),
                      destinations: [
                        for (var i = 0; i < labels.length; i++)
                          NavigationDestination(
                            icon: Icon(icons[i]),
                            label: labels[i],
                          ),
                      ],
                    ),
            );
            if (!wide) return content;
            return Scaffold(
              body: Row(
                children: [
                  _DesktopRail(
                    selectedIndex: selectedIndex,
                    labels: labels,
                    icons: icons,
                    onSelected: (index) =>
                        setState(() => selectedIndex = index),
                  ),
                  Expanded(child: content),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.selectedIndex,
    required this.labels,
    required this.icons,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<String> labels;
  final List<IconData> icons;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      color: const Color(0xFF081713),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 16, 32),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE46D3F)),
                    ),
                    child: const Icon(
                      Icons.brightness_7,
                      color: Color(0xFFE46D3F),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Text(
                      '星骇协议\nASTRA',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '战略终端',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  color: Color(0xFF64766D),
                ),
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < labels.length; i++)
              _RailItem(
                icon: icons[i],
                label: labels[i],
                selected: selectedIndex == i,
                onTap: () => onSelected(i),
              ),
            const Spacer(),
            const Divider(color: Color(0xFF22362F), height: 1),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                '云端节点在线\n版本 0.2.0 · Flutter',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF708078),
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? const Color(0xFF2D2820) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected
                      ? const Color(0xFFE46D3F)
                      : const Color(0xFF8C9B92),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFFF1E6C8)
                        : const Color(0xFF9AA9A0),
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrencyChip extends StatelessWidget {
  const _CurrencyChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF29403A)),
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFF0D1D19),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(24, 24, 24, 32),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) =>
      SingleChildScrollView(padding: padding, child: child);
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    this.action,
  });

  final String eyebrow;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFE46D3F),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 30,
                    color: Color(0xFFF1E6C8),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF84938A),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class OverviewPage extends StatelessWidget {
  const OverviewPage({
    super.key,
    required this.controller,
    required this.onNavigate,
  });

  final GameController controller;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            eyebrow: 'COMMAND / ASTRA PROTOCOL',
            title: '战情总览',
            description: '构筑你的回合，改写整片星图的战局。',
            action: FilledButton.icon(
              onPressed: () => onNavigate(3),
              icon: const Icon(Icons.sports_kabaddi_outlined),
              label: const Text('开始演算'),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 850
                  ? 4
                  : constraints.maxWidth > 520
                  ? 2
                  : 1;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.2,
                children: [
                  _MetricCard(
                    icon: Icons.grid_view_rounded,
                    label: '已收藏卡牌',
                    value:
                        '${controller.collection.values.where((value) => value > 0).length}',
                    sub: '/ 210 档案',
                  ),
                  _MetricCard(
                    icon: Icons.sports_kabaddi_outlined,
                    label: '完成对局',
                    value: '${controller.matchesPlayed}',
                    sub: '累计演算',
                  ),
                  _MetricCard(
                    icon: Icons.emoji_events_outlined,
                    label: '胜率',
                    value: controller.matchesPlayed == 0
                        ? '—'
                        : '${(controller.wins / controller.matchesPlayed * 100).round()}%',
                    sub: '${controller.wins} 胜',
                  ),
                  _MetricCard(
                    icon: Icons.inventory_2_outlined,
                    label: '可用卡包',
                    value: '${controller.packs}',
                    sub: '点击开包',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '七大阵营协议',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  '每个阵营包含 20 张单位与 10 张战术，围绕 2 / 4 档特质构筑牌组。',
                  style: TextStyle(color: Color(0xFF84938A), fontSize: 12),
                ),
                const SizedBox(height: 15),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    for (final faction in factionOrder)
                      _FactionPill(
                        faction: faction,
                        count: controller.catalog
                            .where((card) => card.faction == faction)
                            .length,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 720;
              final actions = [
                _QuickAction(
                  icon: Icons.grid_view_rounded,
                  title: '浏览卡牌收藏',
                  description: '检索 210 张原创档案',
                  onTap: () => onNavigate(1),
                ),
                _QuickAction(
                  icon: Icons.layers_outlined,
                  title: '编辑战术卡组',
                  description: '编排 30 张出战牌组',
                  onTap: () => onNavigate(2),
                ),
                _QuickAction(
                  icon: Icons.inventory_2_outlined,
                  title: '打开档案包',
                  description: '随机解锁 5 张卡牌',
                  onTap: controller.openPack,
                ),
              ];
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: actions
                          .map(
                            (action) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: action,
                              ),
                            ),
                          )
                          .toList(),
                    )
                  : Column(children: actions);
            },
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
  });

  final IconData icon;
  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) => GlassPanel(
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF173C36),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: const Color(0xFF69CFC3), size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xFF84938A), fontSize: 11),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 23,
                      color: Color(0xFFF1E6C8),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    sub,
                    style: const TextStyle(
                      color: Color(0xFF71827A),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFE46D3F)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFF84938A),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 13,
              color: Color(0xFF64766D),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FactionPill extends StatelessWidget {
  const _FactionPill({required this.faction, required this.count});

  final String faction;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Color(factionColors[faction]!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            factionSigil[faction]!,
            style: TextStyle(color: color, fontSize: 17),
          ),
          const SizedBox(width: 7),
          Text(
            faction,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$count 张',
            style: const TextStyle(color: Color(0xFF84938A), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key, required this.controller});

  final GameController controller;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  String query = '';
  String faction = '全部';
  String type = '全部';
  int visible = 30;

  List<CardDefinition> get filtered {
    final needle = query.trim().toLowerCase();
    final result = widget.controller.catalog.where((card) {
      final textMatch =
          needle.isEmpty ||
          '${card.name} ${card.description}'.toLowerCase().contains(needle);
      return textMatch &&
          (faction == '全部' || card.faction == faction) &&
          (type == '全部' || card.type == type);
    }).toList();
    if (faction != '全部') return result;
    final buckets = [
      for (final item in factionOrder)
        result.where((card) => card.faction == item).toList(),
    ];
    final maxLength = buckets.fold<int>(
      0,
      (max, item) => item.length > max ? item.length : max,
    );
    final mixed = <CardDefinition>[];
    for (var index = 0; index < maxLength; index++) {
      for (final bucket in buckets) {
        if (index < bucket.length) mixed.add(bucket[index]);
      }
    }
    return mixed;
  }

  @override
  Widget build(BuildContext context) {
    final cards = filtered;
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            eyebrow: 'TACTICAL ARCHIVE / COLLECTION',
            title: '卡牌收藏',
            description: '七大阵营共 210 张档案，按阵营、类型和关键词检索。',
            action: FilledButton.icon(
              onPressed: () => _showPackMessage(),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('开档案包'),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in ['全部', ...factionOrder])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(item),
                      selected: faction == item,
                      onSelected: (_) => setState(() {
                        faction = item;
                        visible = 30;
                      }),
                      selectedColor: Color(
                        factionColors[item] ?? 0xFF1F514B,
                      ).withValues(alpha: .3),
                      labelStyle: TextStyle(
                        color: faction == item
                            ? const Color(0xFFF1E6C8)
                            : const Color(0xFF9AA9A0),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '搜索名称或描述',
                      ),
                      onChanged: (value) => setState(() {
                        query = value;
                        visible = 30;
                      }),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 125,
                    child: DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: '类型'),
                      items: const [
                        DropdownMenuItem(value: '全部', child: Text('全部')),
                        DropdownMenuItem(value: 'unit', child: Text('单位')),
                        DropdownMenuItem(value: 'spell', child: Text('战术')),
                        DropdownMenuItem(value: 'weapon', child: Text('武器')),
                      ],
                      onChanged: (value) => setState(() {
                        type = value ?? '全部';
                        visible = 30;
                      }),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '显示 ${cards.take(visible).length} / ${cards.length} 张档案',
                style: const TextStyle(color: Color(0xFF84938A), fontSize: 11),
              ),
              const Spacer(),
              const Text(
                '点击卡牌加入当前卡组',
                style: TextStyle(color: Color(0xFF65746D), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1250
                  ? 5
                  : constraints.maxWidth >= 900
                  ? 4
                  : constraints.maxWidth >= 600
                  ? 3
                  : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cards.take(visible).length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: .66,
                ),
                itemBuilder: (context, index) => CardTile(
                  card: cards[index],
                  owned: widget.controller.owned(cards[index].id),
                  onTap: () => _addCard(cards[index]),
                ),
              );
            },
          ),
          if (visible < cards.length)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => visible += 30),
                  icon: const Icon(Icons.expand_more),
                  label: Text('再加载 ${min(30, cards.length - visible)} 张'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _addCard(CardDefinition card) {
    final added = widget.controller.addToDeck(card);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(added ? '${card.name} 已加入卡组' : '当前卡组无法加入这张卡（阵营、数量或卡组已满）'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  void _showPackMessage() {
    widget.controller.openPack();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('档案包已解密，新增 5 张卡牌')));
  }
}

class CardTile extends StatelessWidget {
  const CardTile({
    super.key,
    required this.card,
    this.owned,
    this.onTap,
    this.onLongPress,
    this.compact = false,
  });

  final CardDefinition card;
  final int? owned;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = Color(factionColors[card.faction] ?? 0xFF86AAA3);
    final rarity = Color(rarityColors[card.rarity] ?? 0xFF87958D);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(15),
                ),
                child: Image.asset(
                  'assets/cards/${card.id}.webp',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: const Color(0xFF152722),
                    child: Icon(
                      card.isUnit ? Icons.shield_outlined : Icons.auto_awesome,
                      color: color,
                      size: 42,
                    ),
                  ),
                ),
              ),
              Container(
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xD906110F)],
                  ),
                ),
              ),
              Positioned(
                left: 9,
                top: 9,
                child: Container(
                  width: 29,
                  height: 29,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF164E49),
                    shape: BoxShape.circle,
                    border: Border.all(color: color.withValues(alpha: .7)),
                  ),
                  child: Text(
                    '${card.cost}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              Positioned(
                right: 10,
                top: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: rarity,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: rarity.withValues(alpha: .7),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),
              if (owned != null)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xC906110F),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '持有 $owned',
                      style: const TextStyle(
                        fontSize: 8,
                        color: Color(0xFFF1E6C8),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      card.faction,
                      style: TextStyle(color: color, fontSize: 9),
                    ),
                  ),
                  Text(
                    card.isUnit
                        ? '单位'
                        : card.type == 'weapon'
                        ? '武器'
                        : '战术',
                    style: const TextStyle(
                      color: Color(0xFF84938A),
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                card.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF1E6C8),
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 5),
                Text(
                  card.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF84938A),
                    height: 1.2,
                  ),
                ),
              ],
              const SizedBox(height: 7),
              Row(
                children: [
                  for (final trait in card.traits.take(2))
                    _TinyTag(
                      label: traitLabels[trait] ?? trait,
                      color: const Color(0xFF69CFC3),
                    ),
                  for (final keyword in card.keywords.take(3))
                    _TinyTag(
                      label: keywordLabels[keyword] ?? keyword,
                      color: const Color(0xFFE7BD7A),
                    ),
                  if (card.isUnit || card.type == 'weapon') ...[
                    const Spacer(),
                    Text(
                      card.type == 'weapon'
                          ? '${card.attack ?? 0} / ${card.durability ?? card.health ?? 0}'
                          : '${card.attack} / ${card.health}',
                      style: const TextStyle(
                        color: Color(0xFFE7BD7A),
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, onLongPress: onLongPress, child: content),
    );
  }
}

class _TinyTag extends StatelessWidget {
  const _TinyTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 3),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 8)),
  );
}

class DeckPage extends StatelessWidget {
  const DeckPage({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final id in controller.deckIds) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PageHeader(
            eyebrow: 'ARSENAL / DECK FORGE',
            title: '卡组工坊',
            description: '编排 30 张战术档案，同名双份用于对局内二星共鸣。',
            action: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: controller.saveDeck,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('保存'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: controller.deckValid
                      ? () {
                          controller.startBattle();
                        }
                      : null,
                  icon: const Icon(Icons.sports_kabaddi_outlined),
                  label: const Text('投入演算'),
                ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final manifest = GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '当前牌组',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '${controller.deckIds.length} / 30 张 · ${controller.deckStatus}',
                      style: TextStyle(
                        color: controller.deckValid
                            ? const Color(0xFF79B980)
                            : const Color(0xFFE7BD7A),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 15),
                    LinearProgressIndicator(
                      value: controller.deckIds.length / 30,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(6),
                      backgroundColor: const Color(0xFF1C322B),
                      color: controller.deckValid
                          ? const Color(0xFF69CFC3)
                          : const Color(0xFFE7BD7A),
                    ),
                    const SizedBox(height: 15),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final entry in counts.entries)
                            _DeckEntry(
                              card: controller.card(entry.key)!,
                              count: entry.value,
                              onRemove: () =>
                                  controller.removeFromDeck(entry.key),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
              final picker = GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '可用卡牌',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 11),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, inner) {
                          final columns = inner.maxWidth > 550 ? 4 : 2;
                          return GridView.builder(
                            itemCount: controller.catalog.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 9,
                                  mainAxisSpacing: 9,
                                  childAspectRatio: .68,
                                ),
                            itemBuilder: (_, index) => CardTile(
                              card: controller.catalog[index],
                              owned: controller.owned(
                                controller.catalog[index].id,
                              ),
                              compact: true,
                              onTap: () {
                                final added = controller.addToDeck(
                                  controller.catalog[index],
                                );
                                if (!added) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('这张卡无法加入当前牌组'),
                                    ),
                                  );
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
              if (wide) {
                return SizedBox(
                  height: 650,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 270, child: manifest),
                      const SizedBox(width: 14),
                      Expanded(child: picker),
                    ],
                  ),
                );
              }
              return Column(
                children: [
                  SizedBox(height: 380, child: manifest),
                  const SizedBox(height: 14),
                  SizedBox(height: 600, child: picker),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DeckEntry extends StatelessWidget {
  const _DeckEntry({
    required this.card,
    required this.count,
    required this.onRemove,
  });

  final CardDefinition card;
  final int count;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              image: DecorationImage(
                image: AssetImage('assets/cards/${card.id}.webp'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              card.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11),
            ),
          ),
          Text(
            '×$count',
            style: const TextStyle(color: Color(0xFFE7BD7A), fontSize: 11),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline, size: 17),
            color: const Color(0xFFE46D3F),
            tooltip: '移除',
          ),
        ],
      ),
    );
  }
}

class BattlePage extends StatelessWidget {
  const BattlePage({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.battle;
    if (state == null) {
      return PageFrame(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: GlassPanel(
              child: Column(
                children: [
                  const Icon(
                    Icons.sports_kabaddi_outlined,
                    size: 64,
                    color: Color(0xFFE46D3F),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '战术对战',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '与镜像演算体 K-7 进行一场本地 AI 对局。卡牌部署、攻击与回合节奏都将在 Flutter 客户端内即时反馈。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF84938A)),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: controller.startBattle,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始对战'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return BattleBoard(controller: controller, state: state);
  }
}

class BattleBoard extends StatefulWidget {
  const BattleBoard({super.key, required this.controller, required this.state});

  final GameController controller;
  final BattleState state;

  @override
  State<BattleBoard> createState() => _BattleBoardState();
}

class _BattleBoardState extends State<BattleBoard> {
  GameController get controller => widget.controller;
  BattleState get state => widget.state;
  int _lastFxSequence = -1;

  @override
  void didUpdateWidget(covariant BattleBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final event = widget.state.fx;
    if (event != null && event.sequence != _lastFxSequence) {
      _lastFxSequence = event.sequence;
      _playBattleCue(event.kind);
    }
  }

  Future<void> _playCard(BuildContext context, CardDefinition card) async {
    final targetType = card.target ?? '';
    _BattleTargetChoice? choice;
    if (targetType.contains('unit') || targetType.contains('character')) {
      final targetUnits =
          (targetType.startsWith('friendly')
                  ? state.player.board
                  : state.ai.board)
              .where(
                (unit) =>
                    !targetType.startsWith('enemy') || !unit.stealthActive,
              )
              .toList();
      choice = await _pickBattleTarget(
        context,
        card,
        targetUnits,
        allowHero: targetType.contains('character'),
        enemy: targetType.startsWith('enemy'),
      );
      if (!context.mounted || choice == null) return;
    }
    final played = controller.playCard(
      card,
      target: choice?.unit,
      targetHero: choice?.isHero ?? false,
    );
    if (!played && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前法力、目标或战场位置不满足这张卡的使用条件'),
          duration: Duration(milliseconds: 850),
        ),
      );
    }
  }

  Future<void> _attack(BuildContext context, BattleUnit attacker) async {
    final taunts = state.ai.board
        .where((unit) => unit.hasTaunt && !unit.stealthActive)
        .toList();
    final visibleUnits = state.ai.board
        .where((unit) => !unit.stealthActive)
        .toList();
    final choice = await _pickBattleTarget(
      context,
      null,
      taunts.isNotEmpty ? taunts : visibleUnits,
      allowHero: taunts.isEmpty && !attacker.rushOnly,
      enemy: true,
    );
    if (!context.mounted || choice == null) return;
    final attacked = controller.attack(attacker, target: choice.unit);
    if (!attacked && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(taunts.isNotEmpty ? '必须先处理敌方嘲讽单位' : '该单位还不能攻击或已经行动过'),
          duration: const Duration(milliseconds: 850),
        ),
      );
    }
  }

  Future<void> _heroAttack(BuildContext context) async {
    final weapon = state.player.weapon;
    if (weapon == null) return;
    final taunts = state.ai.board
        .where((unit) => unit.hasTaunt && !unit.stealthActive)
        .toList();
    final visibleUnits = state.ai.board
        .where((unit) => !unit.stealthActive)
        .toList();
    final choice = await _pickBattleTarget(
      context,
      null,
      taunts.isNotEmpty ? taunts : visibleUnits,
      allowHero: taunts.isEmpty,
      enemy: true,
    );
    if (!context.mounted || choice == null) return;
    final attacked = controller.heroAttack(
      target: choice.unit,
      targetHero: choice.isHero,
    );
    if (!attacked && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(taunts.isNotEmpty ? '必须先处理敌方嘲讽单位' : '英雄本回合已经攻击过'),
          duration: const Duration(milliseconds: 850),
        ),
      );
    }
  }

  Future<_BattleTargetChoice?> _pickBattleTarget(
    BuildContext context,
    CardDefinition? card,
    List<BattleUnit> units, {
    required bool allowHero,
    required bool enemy,
  }) {
    final title = card == null ? '选择攻击目标' : '选择「${card.name}」的目标';
    return showModalBottomSheet<_BattleTargetChoice>(
      context: context,
      backgroundColor: const Color(0xFF10211D),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (allowHero)
                _TargetTile(
                  icon: enemy ? Icons.crisis_alert : Icons.person,
                  title: enemy ? '敌方指挥核心' : '你的指挥核心',
                  subtitle: enemy
                      ? '${state.ai.heroHealth} 生命 · ${state.ai.armor} 护甲'
                      : '${state.player.heroHealth} 生命 · ${state.player.armor} 护甲',
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(const _BattleTargetChoice.hero()),
                ),
              for (final unit in units)
                _TargetTile(
                  icon: unit.hasTaunt ? Icons.shield : Icons.blur_on,
                  title: unit.card.name,
                  subtitle:
                      '${unit.attack} 攻击 · ${unit.health}/${unit.maxHealth} 生命${unit.divineShield ? ' · 护盾' : ''}',
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_BattleTargetChoice.unit(unit)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'TACTICAL BATTLE / LIVE SIMULATION',
                  style: TextStyle(
                    color: Color(0xFFE46D3F),
                    letterSpacing: 1.6,
                    fontSize: 10,
                  ),
                ),
              ),
              Text(
                '第 ${state.turn} 回合',
                style: const TextStyle(color: Color(0xFF84938A), fontSize: 12),
              ),
              const SizedBox(width: 10),
              if (state.phase == 'mulligan')
                const _BattlePhasePill(icon: Icons.swap_horiz, label: '起手换牌')
              else
                _TurnTimer(seconds: state.turnSecondsLeft),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: controller.startBattle,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('重开'),
              ),
            ],
          ),
          if (state.phase == 'mulligan') ...[
            const SizedBox(height: 12),
            GlassPanel(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.style_outlined,
                    color: Color(0xFFE7BD7A),
                    size: 19,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      '起手换牌：点击不想保留的卡牌，确认后会从牌库抽取替换牌。',
                      style: TextStyle(color: Color(0xFFB9C2B9), fontSize: 11),
                    ),
                  ),
                  FilledButton(
                    onPressed: controller.confirmMulligan,
                    child: Text(
                      state.mulliganSelected.isEmpty
                          ? '保留全部'
                          : '替换 ${state.mulliganSelected.length} 张',
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (state.phase == 'discover' && state.discoverOwner == 'player') ...[
            const SizedBox(height: 12),
            GlassPanel(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.travel_explore,
                        color: Color(0xFFA692D1),
                        size: 19,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '发现：从候选档案中选择一张加入手牌',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        '${state.discoverChoices.length} 选 1',
                        style: const TextStyle(
                          color: Color(0xFFA692D1),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 205,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: state.discoverChoices.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 9),
                      itemBuilder: (_, index) {
                        final discovered = controller.card(
                          state.discoverChoices[index],
                        );
                        if (discovered == null) return const SizedBox.shrink();
                        return SizedBox(
                          width: 145,
                          child: CardTile(
                            card: discovered,
                            compact: true,
                            onTap: () =>
                                controller.chooseDiscover(discovered.id),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Stack(
            children: [
              _BattleImpactFrame(
                event: state.fx,
                child: GlassPanel(
                  child: Column(
                    children: [
                      if (state.fx != null) ...[
                        _BattleFxBanner(event: state.fx!),
                        const SizedBox(height: 12),
                      ],
                      _HeroBar(
                        name: '镜像演算体 K-7 · ${state.aiFaction}',
                        health: state.ai.heroHealth,
                        maxHealth: state.ai.maxHeroHealth,
                        mana: state.ai.mana,
                        armor: state.ai.armor,
                        coinAvailable: state.ai.coinAvailable,
                        weapon: state.ai.weapon,
                        overloadLocked: state.ai.overloadLocked,
                        secretCount: state.ai.secrets.length,
                        ai: true,
                      ),
                      const SizedBox(height: 13),
                      _BoardRow(
                        units: state.ai.board,
                        enemy: true,
                        onAttack: null,
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14),
                        child: Divider(color: Color(0xFF29403A)),
                      ),
                      _BoardRow(
                        units: state.player.board,
                        enemy: false,
                        onAttack: state.phase == 'main'
                            ? (unit) => _attack(context, unit)
                            : null,
                      ),
                      const SizedBox(height: 13),
                      _HeroBar(
                        name: '你的指挥核心',
                        health: state.player.heroHealth,
                        maxHealth: state.player.maxHeroHealth,
                        mana: state.player.mana,
                        armor: state.player.armor,
                        coinAvailable: state.player.coinAvailable,
                        weapon: state.player.weapon,
                        overloadLocked: state.player.overloadLocked,
                        secretCount: state.player.secrets.length,
                        ai: false,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(
                            Icons.auto_awesome,
                            size: 16,
                            color: Color(0xFF65CDDA),
                          ),
                          const SizedBox(width: 7),
                          const Expanded(
                            child: Text(
                              '星骇脉冲 · 2 法力 · 对敌方核心造成 2 点伤害',
                              style: TextStyle(
                                color: Color(0xFF84938A),
                                fontSize: 10,
                              ),
                            ),
                          ),
                          if (state.player.coinAvailable) ...[
                            OutlinedButton.icon(
                              onPressed: controller.useCoin,
                              icon: const Icon(Icons.monetization_on, size: 15),
                              label: const Text('幸运币'),
                            ),
                            const SizedBox(width: 7),
                          ],
                          if (state.player.weapon != null) ...[
                            OutlinedButton.icon(
                              onPressed:
                                  state.player.heroHasAttacked ||
                                      state.activePlayer != 'player' ||
                                      state.finished ||
                                      state.phase != 'main'
                                  ? null
                                  : () => _heroAttack(context),
                              icon: const Icon(Icons.gavel, size: 15),
                              label: Text(
                                state.player.heroHasAttacked ? '已攻击' : '英雄攻击',
                              ),
                            ),
                            const SizedBox(width: 7),
                          ],
                          OutlinedButton(
                            onPressed:
                                state.heroPowerUsed ||
                                    state.player.mana < 2 ||
                                    state.activePlayer != 'player' ||
                                    state.finished
                                ? null
                                : () {
                                    controller.useHeroPower();
                                  },
                            child: Text(state.heroPowerUsed ? '已使用' : '使用'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (state.fx != null)
                Positioned.fill(child: _BattleFxLayer(event: state.fx!)),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              const Text('你的手牌', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text(
                '${state.player.hand.length} 张',
                style: const TextStyle(color: Color(0xFF84938A), fontSize: 11),
              ),
              const Spacer(),
              if (state.phase == 'main' &&
                  state.activePlayer == 'player' &&
                  !state.finished)
                FilledButton.icon(
                  onPressed: controller.isResolvingTurn
                      ? null
                      : () {
                          controller.endTurn();
                        },
                  icon: const Icon(Icons.skip_next, size: 17),
                  label: Text(controller.isResolvingTurn ? '敌方演算中…' : '结束回合'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 220,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: state.player.hand.length,
              separatorBuilder: (_, _) => const SizedBox(width: 9),
              itemBuilder: (_, index) {
                final handCard = state.player.hand[index];
                final selected = state.mulliganSelected.contains(index);
                return SizedBox(
                  width: 145,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(17),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFFE46D3F)
                            : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: selected
                          ? const [
                              BoxShadow(
                                color: Color(0x66E46D3F),
                                blurRadius: 14,
                              ),
                            ]
                          : const [],
                    ),
                    child: CardTile(
                      card: handCard,
                      compact: true,
                      onTap: state.phase == 'mulligan'
                          ? () => controller.toggleMulligan(index)
                          : state.activePlayer != 'player' ||
                                state.player.mana < handCard.cost
                          ? null
                          : () => _playCard(context, handCard),
                      onLongPress: state.phase == 'main' && handCard.tradeable
                          ? () {
                              final traded = controller.tradeCard(handCard);
                              if (traded && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('已交易：消耗 1 法力并抽取替代牌'),
                                    duration: Duration(milliseconds: 750),
                                  ),
                                );
                              }
                            }
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 13),
          GlassPanel(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '战术日志',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 8),
                for (final log in state.logs.take(7))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      '› $log',
                      style: const TextStyle(
                        color: Color(0xFF84938A),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (state.finished)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: GlassPanel(
                child: Column(
                  children: [
                    Text(
                      state.winner == 'player' ? '演算胜利' : '演算结束',
                      style: TextStyle(
                        fontSize: 24,
                        color: state.winner == 'player'
                            ? const Color(0xFF79B980)
                            : const Color(0xFFE46D3F),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      state.winner == 'player'
                          ? '战报已归档，获得 60 金币。'
                          : '保留战术日志，获得 20 金币。',
                      style: const TextStyle(color: Color(0xFF84938A)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BattleTargetChoice {
  const _BattleTargetChoice.unit(this.unit) : isHero = false;
  const _BattleTargetChoice.hero() : unit = null, isHero = true;

  final BattleUnit? unit;
  final bool isHero;
}

class _TargetTile extends StatelessWidget {
  const _TargetTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF162A24),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF29403A)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF69CFC3), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF84938A),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF65746D)),
          ],
        ),
      ),
    ),
  );
}

class _TurnTimer extends StatelessWidget {
  const _TurnTimer({required this.seconds});

  final int seconds;

  @override
  Widget build(BuildContext context) {
    final urgent = seconds <= 15;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: urgent ? const Color(0xFF4A251D) : const Color(0xFF173C36),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: urgent ? const Color(0xFFE46D3F) : const Color(0xFF29403A),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 14,
            color: urgent ? const Color(0xFFE46D3F) : const Color(0xFF69CFC3),
          ),
          const SizedBox(width: 4),
          Text(
            '${seconds}s',
            style: TextStyle(
              color: urgent ? const Color(0xFFFFB19A) : const Color(0xFFB9C2B9),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BattlePhasePill extends StatelessWidget {
  const _BattlePhasePill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFF4A3020),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: const Color(0xFFE7BD7A)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFFE7BD7A)),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFF1E6C8),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _BattleImpactFrame extends StatelessWidget {
  const _BattleImpactFrame({required this.event, required this.child});

  final BattleFxEvent? event;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (event == null) return child;
    final shake =
        event!.kind == 'attack' ||
        event!.kind == 'spell' ||
        event!.kind == 'hero-power' ||
        event!.kind == 'death';
    return TweenAnimationBuilder<double>(
      key: ValueKey('impact-${event!.sequence}'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 760),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        final wobble = shake
            ? math.sin(progress * math.pi * 10) * (1 - progress) * 5
            : 0.0;
        return Transform.translate(offset: Offset(wobble, 0), child: child);
      },
    );
  }
}

class _BattleFxLayer extends StatelessWidget {
  const _BattleFxLayer({required this.event});

  final BattleFxEvent event;

  @override
  Widget build(BuildContext context) {
    final accent = Color(event.color);
    final combatEvent =
        event.kind == 'attack' ||
        event.kind == 'spell' ||
        event.kind == 'hero-power';
    return TweenAnimationBuilder<double>(
      key: ValueKey('fx-layer-${event.sequence}'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: combatEvent ? 1420 : 1120),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) {
        final opacity = progress < .14
            ? progress / .14
            : progress > .76
            ? (1 - progress) / .24
            : 1.0;
        return IgnorePointer(
          child: Opacity(
            opacity: opacity.clamp(0, 1),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (event.kind == 'attack')
                  CustomPaint(painter: _BattleSlashPainter(progress, accent)),
                if (event.kind == 'spell' || event.kind == 'hero-power')
                  Center(
                    child: _BattlePulse(progress: progress, color: accent),
                  ),
                if (event.kind == 'summon')
                  Center(
                    child: _SummonRings(progress: progress, color: accent),
                  ),
                if (event.kind == 'shield')
                  Center(
                    child: _ShieldBurst(progress: progress, color: accent),
                  ),
                if (event.kind == 'reborn')
                  Center(
                    child: _SummonRings(progress: progress, color: accent),
                  ),
                if (event.kind == 'poison')
                  Center(
                    child: _BattlePulse(progress: progress, color: accent),
                  ),
                if (event.kind == 'death')
                  CustomPaint(painter: _DeathBurstPainter(progress, accent)),
                if (event.kind == 'attack')
                  _AttackTrail(progress: progress, color: accent),
                if (event.kind == 'summon' || event.kind == 'spell')
                  _FlyingFxCard(
                    progress: progress,
                    color: accent,
                    title: event.title,
                    subtitle: event.kind == 'spell'
                        ? 'SPELL CAST'
                        : 'UNIT DEPLOYED',
                  ),
                if (event.amount != null && event.amount! > 0 && combatEvent)
                  _FloatingCombatValue(
                    progress: progress,
                    value: event.amount!,
                    color: event.kind == 'spell' || event.kind == 'hero-power'
                        ? accent
                        : const Color(0xFFFFB19A),
                    positive: false,
                  ),
                if (event.kind == 'victory' || event.kind == 'defeat')
                  _BattleOutcome(event: event, progress: progress),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BattlePulse extends StatelessWidget {
  const _BattlePulse({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scale = .35 + progress * 1.55;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 94,
        height: 94,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: .12 * (1 - progress)),
          border: Border.all(color: color.withValues(alpha: .82), width: 2),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .55), blurRadius: 30),
          ],
        ),
        child: Icon(Icons.bolt, color: color, size: 38),
      ),
    );
  }
}

class _SummonRings extends StatelessWidget {
  const _SummonRings({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: .35 + progress * 1.8,
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: .72), width: 2),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: .44), blurRadius: 22),
          ],
        ),
        child: Icon(Icons.auto_awesome, color: color, size: 30),
      ),
    );
  }
}

class _ShieldBurst extends StatelessWidget {
  const _ShieldBurst({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: .55 + progress * .9,
      child: Icon(
        Icons.shield,
        color: color.withValues(alpha: 1 - progress),
        size: 66,
        shadows: [Shadow(color: color, blurRadius: 22)],
      ),
    );
  }
}

class _AttackTrail extends StatelessWidget {
  const _AttackTrail({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Transform.translate(
        offset: Offset(0, 102 - progress * 190),
        child: Transform.rotate(
          angle: -.18,
          child: Icon(
            Icons.flash_on,
            color: color.withValues(alpha: .92),
            size: 36,
            shadows: [Shadow(color: color, blurRadius: 18)],
          ),
        ),
      ),
    );
  }
}

class _FlyingFxCard extends StatelessWidget {
  const _FlyingFxCard({
    required this.progress,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final double progress;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final opacity = progress < .2
        ? progress / .2
        : (1 - progress).clamp(0, 1).toDouble();
    return Align(
      alignment: Alignment.bottomCenter,
      child: Transform.translate(
        offset: Offset(0, 80 - progress * 160),
        child: Opacity(
          opacity: opacity,
          child: Container(
            width: 166,
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1E1A).withValues(alpha: .94),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: .9)),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: .4), blurRadius: 18),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF84938A),
                    fontSize: 8,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FloatingCombatValue extends StatelessWidget {
  const _FloatingCombatValue({
    required this.progress,
    required this.value,
    required this.color,
    required this.positive,
  });

  final double progress;
  final int value;
  final Color color;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Transform.translate(
        offset: Offset(0, 40 - progress * 92),
        child: Transform.scale(
          scale: .7 + progress * .45,
          child: Text(
            '${positive ? '+' : '-'}$value',
            style: TextStyle(
              color: color,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              shadows: [
                Shadow(color: color.withValues(alpha: .55), blurRadius: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BattleOutcome extends StatelessWidget {
  const _BattleOutcome({required this.event, required this.progress});

  final BattleFxEvent event;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final color = Color(event.color);
    return Center(
      child: Transform.scale(
        scale: .7 + progress * .35,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
          decoration: BoxDecoration(
            color: const Color(0xFF081713).withValues(alpha: .92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color, width: 1.5),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: .4), blurRadius: 28),
            ],
          ),
          child: Text(
            event.title,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _BattleSlashPainter extends CustomPainter {
  _BattleSlashPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: (1 - progress).clamp(.15, 1))
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final center = Offset(size.width / 2, size.height / 2);
    final span = size.width * (.12 + progress * .28);
    final lift = size.height * (.12 + progress * .18);
    canvas.drawLine(
      center + Offset(-span, lift),
      center + Offset(span, -lift),
      paint,
    );
    paint.strokeWidth = 1.4;
    canvas.drawLine(
      center + Offset(-span * .65, lift * 1.4),
      center + Offset(span * .65, -lift * 1.4),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _BattleSlashPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _DeathBurstPainter extends CustomPainter {
  _DeathBurstPainter(this.progress, this.color);

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: (1 - progress).clamp(.08, .75))
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    for (var i = 0; i < 12; i++) {
      final angle = i * math.pi / 6;
      final inner = 12 + progress * 18;
      final outer = inner + progress * 64;
      final from =
          center + Offset(math.cos(angle) * inner, math.sin(angle) * inner);
      final to =
          center + Offset(math.cos(angle) * outer, math.sin(angle) * outer);
      canvas.drawLine(from, to, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DeathBurstPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _BattleFxBanner extends StatelessWidget {
  const _BattleFxBanner({required this.event});

  final BattleFxEvent event;

  @override
  Widget build(BuildContext context) {
    final color = Color(event.color);
    return TweenAnimationBuilder<double>(
      key: ValueKey(event.sequence),
      tween: Tween(begin: .78, end: 1),
      duration: const Duration(milliseconds: 440),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: color.withValues(alpha: .7)),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: .24), blurRadius: 20),
            ],
          ),
          child: Row(
            children: [
              Icon(_fxIcon(event.kind), color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      event.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB9C2B9),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.graphic_eq,
                color: color.withValues(alpha: .8),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _fxIcon(String kind) {
  switch (kind) {
    case 'start':
      return Icons.sports_kabaddi;
    case 'summon':
    case 'spell':
      return Icons.auto_awesome;
    case 'attack':
      return Icons.flash_on;
    case 'shield':
      return Icons.shield;
    case 'fury':
      return Icons.whatshot;
    case 'poison':
      return Icons.coronavirus;
    case 'reborn':
      return Icons.autorenew;
    case 'heal':
      return Icons.favorite;
    case 'death':
      return Icons.blur_on;
    case 'hero-power':
      return Icons.bolt;
    case 'victory':
      return Icons.emoji_events;
    case 'defeat':
      return Icons.close;
    default:
      return Icons.graphic_eq;
  }
}

void _playBattleCue(String kind) {
  if (kIsWeb) return;
  if (kind == 'attack' || kind == 'spell' || kind == 'hero-power') {
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.mediumImpact();
  } else if (kind == 'summon') {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.selectionClick();
  } else {
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
  }
}

class _HeroBar extends StatelessWidget {
  const _HeroBar({
    required this.name,
    required this.health,
    required this.maxHealth,
    required this.mana,
    required this.armor,
    required this.coinAvailable,
    required this.weapon,
    required this.overloadLocked,
    required this.secretCount,
    required this.ai,
  });

  final String name;
  final int health;
  final int maxHealth;
  final int mana;
  final int armor;
  final bool coinAvailable;
  final BattleWeapon? weapon;
  final int overloadLocked;
  final int secretCount;
  final bool ai;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 43,
        height: 43,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ai ? const Color(0xFF35221C) : const Color(0xFF173C36),
          border: Border.all(
            color: ai ? const Color(0xFFE46D3F) : const Color(0xFF69CFC3),
          ),
        ),
        child: Icon(
          ai ? Icons.smart_toy_outlined : Icons.person_outline,
          color: ai ? const Color(0xFFE46D3F) : const Color(0xFF69CFC3),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: health / maxHealth),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) => LinearProgressIndicator(
                  value: value,
                  minHeight: 7,
                  backgroundColor: const Color(0xFF263C34),
                  color: ai ? const Color(0xFFE46D3F) : const Color(0xFF69CFC3),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$health',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          if (armor > 0)
            Text(
              '◆ $armor',
              style: const TextStyle(color: Color(0xFFE7BD7A), fontSize: 10),
            ),
          if (weapon != null)
            Text(
              '⚔ ${weapon!.card.name} · ${weapon!.attack}/${weapon!.durability}',
              style: const TextStyle(color: Color(0xFFE7BD7A), fontSize: 9),
            ),
          if (secretCount > 0)
            Text(
              ai ? '◇ 敌方奥秘 ×$secretCount' : '◇ 奥秘 ×$secretCount',
              style: const TextStyle(color: Color(0xFFA692D1), fontSize: 9),
            ),
          if (overloadLocked > 0)
            Text(
              '🔒 过载 $overloadLocked',
              style: const TextStyle(color: Color(0xFFE46D3F), fontSize: 9),
            ),
        ],
      ),
      const SizedBox(width: 12),
      Row(
        children: [
          for (var i = 0; i < mana; i++)
            const Padding(
              padding: EdgeInsets.only(left: 3),
              child: Icon(Icons.circle, size: 9, color: Color(0xFF69CFC3)),
            ),
          if (coinAvailable) ...[
            const SizedBox(width: 6),
            const Icon(
              Icons.monetization_on,
              size: 14,
              color: Color(0xFFE7BD7A),
            ),
          ],
        ],
      ),
    ],
  );
}

class _BoardRow extends StatelessWidget {
  const _BoardRow({
    required this.units,
    required this.enemy,
    required this.onAttack,
  });

  final List<BattleUnit> units;
  final bool enemy;
  final ValueChanged<BattleUnit>? onAttack;

  @override
  Widget build(BuildContext context) {
    if (units.isEmpty) {
      return SizedBox(
        height: 78,
        child: Center(
          child: Text(
            enemy ? '敌方战场空置' : '点击手牌部署单位',
            style: const TextStyle(color: Color(0xFF65746D), fontSize: 11),
          ),
        ),
      );
    }
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: units.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final unit = units[index];
          return GestureDetector(
            onTap: onAttack == null || !unit.canAttack
                ? null
                : () => onAttack!(unit),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: 142,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFF162A24),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: unit.hasAttacked
                      ? const Color(0xFF29403A)
                      : Color(factionColors[unit.card.faction] ?? 0xFF69CFC3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.asset(
                          'assets/cards/${unit.card.id}.webp',
                          width: 38,
                          height: 36,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 38,
                            height: 36,
                            color: const Color(0xFF203A32),
                            child: const Icon(
                              Icons.auto_awesome,
                              size: 16,
                              color: Color(0xFF69CFC3),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          unit.card.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (unit.stars > 1)
                        const Text(
                          '★★',
                          style: TextStyle(
                            color: Color(0xFFE7BD7A),
                            fontSize: 9,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    children: [
                      if (unit.hasTaunt)
                        const _UnitBadge(label: '嘲讽', color: Color(0xFFE7BD7A)),
                      if (unit.divineShield)
                        const _UnitBadge(label: '护盾', color: Color(0xFF69CFC3)),
                      if (unit.hasLifesteal)
                        const _UnitBadge(label: '汲取', color: Color(0xFF79B980)),
                      if (unit.hasRush)
                        const _UnitBadge(label: '突袭', color: Color(0xFFE46D3F)),
                      if (unit.hasWindfury)
                        const _UnitBadge(label: '风怒', color: Color(0xFFA692D1)),
                      if (unit.hasPoisonous)
                        const _UnitBadge(label: '剧毒', color: Color(0xFF79B980)),
                      if (unit.hasStealth && unit.stealthActive)
                        const _UnitBadge(label: '潜行', color: Color(0xFF65CDDA)),
                      if (unit.hasReborn)
                        const _UnitBadge(label: '复生', color: Color(0xFFA692D1)),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    unit.isFrozen
                        ? '冻结中'
                        : unit.summoningSick
                        ? '等待下回合'
                        : unit.hasWindfury && unit.attacksMade == 1
                        ? '风怒 · 还可攻击'
                        : unit.hasAttacked
                        ? '已行动'
                        : enemy
                        ? '敌方单位'
                        : '点击攻击',
                    style: TextStyle(
                      color:
                          unit.isFrozen ||
                              unit.summoningSick ||
                              unit.hasAttacked
                          ? const Color(0xFF65746D)
                          : const Color(0xFF69CFC3),
                      fontSize: 9,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${unit.attack} ⚔   ${unit.health}/${unit.maxHealth} ◆',
                    style: const TextStyle(
                      color: Color(0xFFE7BD7A),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _UnitBadge extends StatelessWidget {
  const _UnitBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: color.withValues(alpha: .55)),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 8)),
  );
}

class MultiplayerPage extends StatefulWidget {
  const MultiplayerPage({super.key, required this.controller});

  final GameController controller;

  @override
  State<MultiplayerPage> createState() => _MultiplayerPageState();
}

class _MultiplayerPageState extends State<MultiplayerPage> {
  final MultiplayerClient client = MultiplayerClient();
  OnlineBattleController? onlineBattle;
  final endpointController = TextEditingController(text: 'ws://127.0.0.1:8787');
  final playerController = TextEditingController(text: '旅者 071');
  final roomController = TextEditingController();

  @override
  void initState() {
    super.initState();
    client.addListener(_handleClientState);
  }

  void _handleClientState() {
    if (!mounted || client.peerName != null || onlineBattle == null) return;
    onlineBattle?.dispose();
    setState(() => onlineBattle = null);
  }

  @override
  void dispose() {
    client.removeListener(_handleClientState);
    endpointController.dispose();
    playerController.dispose();
    roomController.dispose();
    onlineBattle?.dispose();
    client.dispose();
    super.dispose();
  }

  void _openOnlineBattle() {
    if (!client.hasRoom || client.peerName == null) return;
    setState(() {
      onlineBattle ??= OnlineBattleController(
        catalog: widget.controller.catalog,
        client: client,
      );
    });
  }

  Future<void> _connect() =>
      client.connect(endpointController.text, name: playerController.text);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: client,
      builder: (context, _) {
        final connected = client.isConnected;
        final waiting = connected && client.hasRoom && client.peerName == null;
        return PageFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                eyebrow: 'MULTIPLAYER / ROOM RELAY',
                title: '联机大厅',
                description: '创建或加入 1v1 房间，客户端通过 WebSocket 同步对战动作。',
                action: _ConnectionPill(
                  status: client.status,
                  connected: connected,
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 880;
                  final connection = GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '服务器连接',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '本地测试可运行 dart run server/multiplayer_server.dart 8787；部署后填入 wss:// 地址。',
                          style: TextStyle(
                            color: Color(0xFF84938A),
                            fontSize: 11,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 14),
                        if (wide)
                          Row(
                            children: [
                              Expanded(child: _endpointField()),
                              const SizedBox(width: 10),
                              SizedBox(width: 150, child: _playerField()),
                            ],
                          )
                        else ...[
                          _endpointField(),
                          const SizedBox(height: 10),
                          _playerField(),
                        ],
                        const SizedBox(height: 13),
                        Row(
                          children: [
                            FilledButton.icon(
                              onPressed: connected ? null : _connect,
                              icon: const Icon(Icons.link, size: 17),
                              label: const Text('连接服务器'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: connected ? client.disconnect : null,
                              icon: const Icon(Icons.link_off, size: 17),
                              label: const Text('断开'),
                            ),
                          ],
                        ),
                        if (client.errorMessage != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            client.errorMessage!,
                            style: const TextStyle(
                              color: Color(0xFFE46D3F),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                  final room = GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '房间操作',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          connected
                              ? (client.hasRoom
                                    ? '房间 ${client.roomCode} · ${client.status}'
                                    : '连接已建立，选择创建或加入房间')
                              : '连接服务器后才能进入房间',
                          style: const TextStyle(
                            color: Color(0xFF84938A),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 15),
                        if (!client.hasRoom) ...[
                          FilledButton.icon(
                            onPressed: connected ? client.createRoom : null,
                            icon: const Icon(Icons.add_home_outlined),
                            label: const Text('创建新房间'),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: roomController,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  decoration: const InputDecoration(
                                    labelText: '房间码',
                                    hintText: '例如 A7KQ',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: connected
                                    ? () => client.joinRoom(roomController.text)
                                    : null,
                                child: const Text('加入'),
                              ),
                            ],
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 13,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF173C36),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF69CFC3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.vpn_key_outlined,
                                  color: Color(0xFF69CFC3),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    client.roomCode ?? '----',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      letterSpacing: 4,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFF1E6C8),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '复制房间码',
                                  onPressed: client.roomCode == null
                                      ? null
                                      : () => Clipboard.setData(
                                          ClipboardData(text: client.roomCode!),
                                        ),
                                  icon: const Icon(Icons.copy_outlined),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 15),
                          Row(
                            children: [
                              Icon(
                                waiting
                                    ? Icons.hourglass_top_outlined
                                    : Icons.person_pin_circle_outlined,
                                color: waiting
                                    ? const Color(0xFFE7BD7A)
                                    : const Color(0xFF79B980),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  waiting
                                      ? '房间已创建，等待对手加入…'
                                      : '对手：${client.peerName ?? '未命名指挥官'}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: client.disconnect,
                            icon: const Icon(Icons.exit_to_app, size: 17),
                            label: const Text('离开房间'),
                          ),
                          if (client.peerName != null) ...[
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _openOnlineBattle,
                              icon: const Icon(Icons.sports_kabaddi_outlined),
                              label: Text(
                                onlineBattle == null ? '进入联机战场' : '联机战场已打开',
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  );
                  final activity = GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '联机事件',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (client.hasRoom)
                              OutlinedButton.icon(
                                onPressed: () {
                                  _openOnlineBattle();
                                  onlineBattle?.ready();
                                },
                                icon: const Icon(Icons.bolt, size: 16),
                                label: const Text('发送准备信号'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (client.events.isEmpty)
                          const Text(
                            '连接、房间和对战动作会显示在这里。',
                            style: TextStyle(
                              color: Color(0xFF65746D),
                              fontSize: 11,
                            ),
                          )
                        else
                          for (final event in client.events.take(8))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '›',
                                    style: TextStyle(color: Color(0xFFE46D3F)),
                                  ),
                                  const SizedBox(width: 7),
                                  Expanded(
                                    child: Text(
                                      event.message ?? event.type,
                                      style: const TextStyle(
                                        color: Color(0xFFB9C2B9),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  );
                  final arena = onlineBattle == null
                      ? null
                      : OnlineBattlePanel(controller: onlineBattle!);
                  if (wide) {
                    return Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: connection),
                            const SizedBox(width: 14),
                            Expanded(child: room),
                          ],
                        ),
                        if (arena != null) ...[
                          const SizedBox(height: 14),
                          arena,
                        ],
                        const SizedBox(height: 14),
                        activity,
                      ],
                    );
                  }
                  return Column(
                    children: [
                      connection,
                      const SizedBox(height: 14),
                      room,
                      const SizedBox(height: 14),
                      if (arena != null) ...[arena, const SizedBox(height: 14)],
                      activity,
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _endpointField() => TextField(
    controller: endpointController,
    keyboardType: TextInputType.url,
    decoration: const InputDecoration(
      labelText: 'WebSocket 地址',
      hintText: 'ws://127.0.0.1:8787',
      prefixIcon: Icon(Icons.dns_outlined),
    ),
  );

  Widget _playerField() => TextField(
    controller: playerController,
    decoration: const InputDecoration(
      labelText: '指挥官名',
      prefixIcon: Icon(Icons.badge_outlined),
    ),
  );
}

class OnlineBattlePanel extends StatelessWidget {
  const OnlineBattlePanel({super.key, required this.controller});

  final OnlineBattleController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '联机战场 / LIVE DUEL',
                    style: TextStyle(
                      color: Color(0xFFE46D3F),
                      letterSpacing: 1.5,
                      fontSize: 10,
                    ),
                  ),
                ),
                Text(
                  '第 ${controller.turn} 回合',
                  style: const TextStyle(
                    color: Color(0xFF84938A),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _OnlineHealth(
                    label: '你的指挥核心',
                    value: controller.localHealth,
                    color: const Color(0xFF69CFC3),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OnlineHealth(
                    label: controller.client.peerName ?? '对手核心',
                    value: controller.remoteHealth,
                    color: const Color(0xFFE46D3F),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (!controller.started)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1D19),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.localReady
                            ? (controller.remoteReady
                                  ? '双方已准备，正在同步战场…'
                                  : '你已准备，等待对手确认…')
                            : '双方确认后开始同步牌局。',
                        style: const TextStyle(
                          color: Color(0xFFB9C2B9),
                          fontSize: 11,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: controller.localReady
                          ? null
                          : controller.ready,
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: Text(controller.localReady ? '已准备' : '准备'),
                    ),
                  ],
                ),
              )
            else ...[
              _OnlineBoardRow(
                title: '对手战场',
                units: controller.remoteBoard,
                enemy: true,
              ),
              const SizedBox(height: 8),
              _OnlineBoardRow(
                title: '你的战场',
                units: controller.localBoard,
                onAttack: controller.attack,
              ),
              const SizedBox(height: 13),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '你的手牌',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.finished ? null : controller.endTurn,
                    icon: const Icon(Icons.skip_next, size: 16),
                    label: const Text('结束回合'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 206,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: controller.hand.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 9),
                  itemBuilder: (context, index) => SizedBox(
                    width: 142,
                    child: CardTile(
                      card: controller.hand[index],
                      compact: true,
                      onTap: controller.finished
                          ? null
                          : () => controller.playCard(controller.hand[index]),
                    ),
                  ),
                ),
              ),
            ],
            if (controller.finished)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  controller.winner == 'player' ? '联机胜利' : '联机演算结束',
                  style: TextStyle(
                    color: controller.winner == 'player'
                        ? const Color(0xFF79B980)
                        : const Color(0xFFE46D3F),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (controller.logs.isNotEmpty) ...[
              const SizedBox(height: 13),
              const Text(
                '联机战报',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 7),
              for (final log in controller.logs.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '› $log',
                    style: const TextStyle(
                      color: Color(0xFF84938A),
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OnlineHealth extends StatelessWidget {
  const _OnlineHealth({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: value / 30),
          duration: const Duration(milliseconds: 350),
          builder: (context, progress, child) => LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            backgroundColor: const Color(0xFF263C34),
            color: color,
          ),
        ),
      ),
    ],
  );
}

class _OnlineBoardRow extends StatelessWidget {
  const _OnlineBoardRow({
    required this.title,
    required this.units,
    this.enemy = false,
    this.onAttack,
  });

  final String title;
  final List<OnlineUnit> units;
  final bool enemy;
  final ValueChanged<OnlineUnit>? onAttack;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(color: Color(0xFF84938A), fontSize: 10),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 68,
        child: units.isEmpty
            ? Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1D19),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  enemy ? '对手尚未部署单位' : '点击手牌部署单位',
                  style: const TextStyle(
                    color: Color(0xFF65746D),
                    fontSize: 10,
                  ),
                ),
              )
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: units.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final unit = units[index];
                  return GestureDetector(
                    onTap: onAttack == null ? null : () => onAttack!(unit),
                    child: Container(
                      width: 136,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF162A24),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: unit.hasAttacked
                              ? const Color(0xFF29403A)
                              : const Color(0xFF69CFC3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            unit.card.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${unit.attack} ⚔   ${unit.health} ◆',
                            style: const TextStyle(
                              color: Color(0xFFE7BD7A),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    ],
  );
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.status, required this.connected});

  final String status;
  final bool connected;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: connected ? const Color(0xFF173C36) : const Color(0xFF1C2924),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: connected ? const Color(0xFF69CFC3) : const Color(0xFF29403A),
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          connected ? Icons.wifi : Icons.wifi_off,
          size: 14,
          color: connected ? const Color(0xFF69CFC3) : const Color(0xFF84938A),
        ),
        const SizedBox(width: 6),
        Text(status, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}

class OperationsPage extends StatelessWidget {
  const OperationsPage({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            eyebrow: 'OPERATIONS / TELEMETRY',
            title: '运营台',
            description: '七大阵营、对局表现与本地档案运行状态。',
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 850
                  ? 4
                  : constraints.maxWidth > 520
                  ? 2
                  : 1;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 2.2,
                children: [
                  _MetricCard(
                    icon: Icons.sports_kabaddi_outlined,
                    label: '对局',
                    value: '${controller.matchesPlayed}',
                    sub: '已归档',
                  ),
                  _MetricCard(
                    icon: Icons.emoji_events_outlined,
                    label: '胜利',
                    value: '${controller.wins}',
                    sub: '核心演算',
                  ),
                  _MetricCard(
                    icon: Icons.close,
                    label: '失败',
                    value: '${controller.losses}',
                    sub: '保留日志',
                  ),
                  _MetricCard(
                    icon: Icons.account_balance_wallet_outlined,
                    label: '金币',
                    value: '${controller.gold}',
                    sub: '可用资源',
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '阵营胜率',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                for (final item in <String, double>{
                  '曜光': .506,
                  '幽潮': .502,
                  '中立': .489,
                  '烬火': .511,
                  '星穹': .518,
                  '苍林': .498,
                  '雷铸': .494,
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: Text(
                            item.key,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF84938A),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: item.value,
                              minHeight: 6,
                              backgroundColor: const Color(0xFF22352E),
                              color: Color(factionColors[item.key]!),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 38,
                          child: Text(
                            '${(item.value * 100).toStringAsFixed(1)}%',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFFF1E6C8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '核心卡牌表现',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 13),
                for (final card in controller.catalog.where(
                  (card) =>
                      ['棱镜守卫', '焰脊先锋', '世界根母', '天铸雷王'].contains(card.name),
                ))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Color(factionColors[card.faction]!),
                      backgroundImage: AssetImage(
                        'assets/cards/${card.id}.webp',
                      ),
                    ),
                    title: Text(
                      card.name,
                      style: const TextStyle(fontSize: 12),
                    ),
                    subtitle: Text(
                      '${card.faction} · ${card.type == 'unit' ? '单位' : '战术'}',
                      style: const TextStyle(
                        color: Color(0xFF84938A),
                        fontSize: 10,
                      ),
                    ),
                    trailing: const Text(
                      '稳定',
                      style: TextStyle(color: Color(0xFF79B980), fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

int min(int a, int b) => a < b ? a : b;

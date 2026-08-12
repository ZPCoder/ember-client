# ASTRA PROTOCOL Flutter 全端口客户端

这是“星骇协议”卡牌对战客户端的 Flutter 版本，复用主项目的 7 个阵营、210 张卡牌定义和对应封面资源。

## 已实现

- macOS / Windows / Linux / iOS / Android / Web 的 Flutter 工程入口
- 7 个阵营卡牌收藏：每个阵营 30 张，共 210 张
- 搜索、阵营筛选、类型筛选和卡牌封面展示
- 30 张卡组编排、同名卡数量限制、非中立阵营校验、本地保存
- 本地 AI 对战：1～10 点递增法力、7 格战场、75 秒回合计时、英雄技能、目标选择、单位互殴、疲劳与胜负结算
- 炉石式卡牌属性：战吼、亡语、嘲讽、护盾、冲锋、突袭、风怒、剧毒、潜行、复生、冻结、汲取、激昂、武器、奥秘、发现、抉择、连击、过载、可交易、法术伤害、沉默、变形和临时增益；支持亡语召唤、复生回场、护盾抵伤、剧毒击杀、冻结跳过攻击、风怒双攻击、英雄武器攻击与回合触发
- 战斗表现层：出牌/攻击/护盾破碎/治疗/死亡/胜负横幅、生命条缓动、回合倒计时、目标选择面板、iOS/Android/macOS 系统音效与触感反馈
- WebSocket 联机大厅与联机战场：创建/加入 1v1 房间、准备同步、出牌、部署单位、攻击、回合和生命值同步
- SharedPreferences 本地保存卡组、资源、战绩和卡包
- 桌面端 NavigationRail、窄屏端 NavigationBar，自适应布局

## 对战设计依据

对战节奏采用数字卡牌游戏常见的“递增法力 + 受限战场 + 明确关键词 + 可读反馈”结构：炉石的设计资料强调法力曲线、嘲讽、战吼、亡语、秘密和关键词提示；《符文之地传说》强调回合攻击权和法术速度；Magic 的官方规则将战斗拆成攻击者、阻挡者、伤害和结束步骤。项目使用原创“星骇协议”名称、视觉、卡牌和系统音效，不复用竞品素材。

- https://hearthstone.blizzard.com/en-us/news/23014810/developer-insights-class-identity-hall-of-fame-and-new-cards
- https://hearthstone.blizzard.com/en-us/news/22552047
- https://hearthstone.blizzard.com/en-us/news/24244450/welcome-back-to-hearthstone-a-returning-player-s-guide
- https://wiki.leagueoflegends.com/en-us/LoR%3AHome
- https://magic.wizards.com/en/how-to-play

## 启动

```bash
cd flutter_app
flutter pub get
flutter run -d chrome       # Web
flutter run -d macos        # macOS
flutter run                 # 连接 Android / iOS 设备后运行
```

## 启动联机房间服务器

仓库根目录提供了一个无额外依赖的 Dart WebSocket 房间服务器。先启动服务器，再在 App 的“联机”页填入地址：

```bash
dart run server/multiplayer_server.dart 8787
```

本机地址使用 `ws://127.0.0.1:8787`；局域网设备请填写运行服务器电脑的局域网 IP，例如 `ws://192.168.1.20:8787`。生产环境应使用反向代理提供 `wss://` 地址。

启动服务器后，可用两个 Node 客户端运行协议烟测：

```bash
node server/multiplayer_smoke_test.mjs ws://127.0.0.1:8787
```

房间服务器负责房间、玩家状态和动作转发；当前联机战场由双方客户端根据同一套卡牌定义演算并实时同步状态。正式运营时建议在服务器侧增加签名校验、回合锁和权威结算。

## 构建

```bash
flutter build web --release
flutter build web --release --no-web-resources-cdn
flutter build macos --release
flutter build apk --release
flutter build ios --release --no-codesign
```

Windows 和 Linux 需要在对应操作系统上安装 Flutter Desktop toolchain 后执行：

```bash
flutter build windows --release
flutter build linux --release
```

Web 发布默认使用本地 CanvasKit 与本地 Noto Sans SC 字体，不依赖运行时 CDN；在受限网络环境中请使用带 `--no-web-resources-cdn` 的构建命令。Android 已声明网络权限，macOS 已开启网络客户端权限，iOS 已声明局域网访问用途；生产联机地址请使用 `wss://`。

`assets/fonts/NotoSansSC-Regular.ttf` 来自 Google Noto Sans SC，按 SIL Open Font License 1.1 分发，许可说明见字体目录中的 `NOTICE.md`。

## 更新卡牌资源

主项目的卡牌数据发生变化时，在仓库根目录执行：

```bash
node scripts/export-flutter-catalog.mjs
cp public/cards/*.webp flutter_app/assets/cards/
```

然后重新运行 `flutter pub get` 或对应平台构建命令即可。

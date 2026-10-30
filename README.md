# 影幕 Kagemaku

macOS 悬浮遮挡条，两种用法：

- 练听力：整条挡住字幕先听，听不出来再偷看一眼。
- 学外语：看双语字幕时，只用一条透明毛玻璃糊掉中文那一行，外文照常看。

## 装

直接用：从 [Releases](https://github.com/Shinkou777/kagemaku/releases) 下载 `Kagemaku.dmg`，把 Kagemaku.app 拖进「应用程序」。
这个包没有经过 Apple 公证，第一次打开要在访达里右键 App → 打开。
自动对齐字幕（学外语默认开着）要在「系统设置 → 隐私与安全性 → 屏幕录制」里给它授权。

从源码装：

```bash
./scripts/install.sh
```

编译、装 App、装 `kagemaku` 命令到 `~/.local/bin`、挂 launchd 登录自启，一步到位。

菜单栏出现一个条状图标，屏幕下方三分之一处出现一条毛玻璃。没有 Dock 图标（LSUIElement）。

需要 Swift 6 工具链（Command Line Tools 即可，不用完整 Xcode）。部署目标 macOS 14。

## 管

launchd 托管，崩了自动拉起；从菜单正常退出就不再拉。日常操作都在 `kagemaku` 这一个命令里。

```
kagemaku up              启动并挂到登录自启
kagemaku down            停掉并撤销自启
kagemaku restart         重启
kagemaku status          进程、版本、遮挡条、部件、设置一次看完
kagemaku settings [页]   打开设置窗，页：masks learn skins widgets keys tracking about
kagemaku logs [-f]       看日志
kagemaku build           只重新编译
kagemaku reload          重新编译并重启（改完代码用这个）
kagemaku doctor          自检：工具链、签名、路径、授权
kagemaku uninstall       卸载，加 --purge 连数据一起删
```

`status` 的输出长这样：

```
SERVICE      STATE      PID      AUTO     VERSION
kagemaku     running    2161     on       0.2.0

  遮挡条 2 条
    遮挡条          938x104  @ 287,108　听力　手动　不透明 95%
    遮挡条 2        900x58   @ 306,140　学外语　自动对齐　不透明 95%
  浮在全屏之上 是　贴边吸附 是　动效 开
```

日志在 `~/Library/Logs/Kagemaku/`，LaunchAgent 是 `~/Library/LaunchAgents/com.shinkouniv.kagemaku.plist`。

## 用

- 拖条身移动，拖四边四角缩放
- 鼠标停上去出工具条：锁定 / 学外语 / 追踪 / 皮肤 / 设置 / 隐藏；停在按钮上，左上角会写这个按钮做什么
- 右键条身出完整菜单，退出影幕也在里面
- 锁定后鼠标穿透，播放器的进度条照点；解锁靠快捷键或菜单栏
- 移除一条要先确认，删完能在菜单栏「撤销移除」放回最近一条

### 学外语

右键条身选「学外语：只盖中文」，或者点工具条上的书本按钮。

- 玻璃换成透明的一款：只留模糊，不压暗、不加灰、不描边，左右两端羽化，盖着的地方还看得出画面
- 自动对齐跟着打开：影幕认出中文那一行，把玻璃的上下边对过去，下沿停在外文字的外面
- 有汉字、没有假名的行才算中文，中日双语时日文那行不会被盖
- 字幕变成两行时玻璃马上变高；变回一行，过三秒才缩回去，句子换得快时不露字
- 看不懂了按住 ⌥⌘E 偷看中文
- 模糊强度在设置的「学外语」页调；没授权屏幕录制时，玻璃照样能用，自己拖到中文那一行上

第一次认字要加载系统的识别模型，新装或更新后可能要等二十秒左右，之后每次一百毫秒上下。

### 快捷键（可在设置里改）

| 组合 | 作用 |
|---|---|
| ⌥⌘E | 按住偷看（松开复原，也可改成按一下切换） |
| ⌥⌘M | 全部收起 / 放出 |
| ⌥⌘L | 全部锁定 / 解锁 |
| ⌥⌘N | 新建一条 |
| ⌥⌘K | 换下一个皮肤 |

### 三种追踪

1. **自动对齐字幕**：在玻璃附近开一条搜索带，每秒拍两次，用系统的 Vision 认字，找到字幕所在的行，把玻璃的上下边对过去。听力模式盖整块字幕，学外语只盖中文那行。**需要屏幕录制权限**，画面只在本机认，不存、不上传。
2. **手动摆放**：拖到哪就在哪，零权限。
3. **跟随播放器窗口**：选一个窗口，条按相对比例锚在里面，窗口移动缩放全跟着走。用 CGWindowList 轮询 bounds，不要任何权限；拿不到窗口标题时只显示 App 名。

### 皮肤

练听力的遮挡条用皮肤。内置七套：霧硝子 Frosted / 曇硝子 Milk / 深夜霓虹 Neon Noir / 曉光 Aurora / 墨 Sumi / 走査線 CRT / モザイク Mosaic。

内置的只读，复制一份就能改：材质、明暗、只留模糊、模糊半径、饱和度、两端羽化、上下端底色、渐变角度、圆角、描边粗细与起止色、外发光半径与颜色、顶部高光，以及动效（流光 / 扫描线 / 极光 / 呼吸 / 颗粒 / 霜面）。

不透明度每条独立可调，5%–100%。

### 显示部件

练听力时条身空着，可以叠文字装置。开箱什么都不放，盖在画面上一直跳动的字会分心；要的话在设置「显示部件」里添加，或者一键摆上一组示例。学外语的玻璃上不显示部件。

样式：辉光管 Nixie、翻页牌 Split-flap（换字带翻转动画）、点阵 LED、七段数码管、霓虹、简约。

内容与数据源：

| 部件 | 来源 | 说明 |
|---|---|---|
| 时间 / 日期 | 本地 | 格式串自己写，如 `HH:mm:ss`、`MM月dd日(EEE)` |
| 行情 | Yahoo Finance 公开接口 | 代码填 `^N225` `AAPL` `BTC-USD` `USDJPY=X` `GC=F`，60 秒刷新，可带涨跌幅 |
| 天气 | Open-Meteo | 填城市名，先地理编码再取当前气温和天气码，10 分钟刷新 |
| 新闻 | 任意 RSS | 示例是 NHK 主要ニュース，取标题配跑马灯滚动，10 分钟刷新 |
| 自定义文字 | 自己填 | 想写什么写什么 |

## 实现上的几个坑

- **毛玻璃必须留在 AppKit。** SwiftUI 的 `.opacity()` / `compositingGroup()` 会把 `NSVisualEffectView` 推进离屏图层，behind-window 的背景模糊直接失效：看着像糊了，其实只是压暗，底下的字一个不少。现在玻璃是 `MaskRootView` 的子视图 `GlassView`，SwiftUI 只画着色、描边和部件。
- **系统材质在模糊上面还叠了三层。** `NSVisualEffectView` 里有一个 `backdrop`（`CABackdropLayer`，带 gaussianBlur 和 colorSaturate 两个滤镜），上面盖着 `fill`（40% 灰）、`tone`（提亮）、`desktop tint`。学外语的透明玻璃把后三层藏掉、饱和度还原，半径自己定。AppKit 换材质、换外观时会重建这些图层，所以 `GlassView` 每次 layout 都重新套一遍。
- **`maskImage` 只认硬边。** 两端羽化要把渐变遮罩挂在玻璃图层的 `mask` 上。
- **外发光只画在条身外面。** 阴影直接挂在半透明着色层上的话，条身里面也透出一层阴影，整条玻璃被压暗。现在 `GlowLayer` 用 even-odd 裁掉条身再画阴影。
- **条身四周留 48pt 透明边**（`maskPad`）给外发光，发光半径夹在 28 以内，高斯阴影淡到看不见要 1.5 倍半径左右，留少了会裁出一圈硬边灰框。`config.frame` 存的是条身，面板比它四周各大 48pt。
- **透明边会吃点击。** 外发光那圈像素带一点不透明度，窗口会把点击收下。鼠标不在条身上时整块面板设成 `ignoresMouseEvents`，30Hz 轮询鼠标位置。
- **弹出菜单和对话框要让路。** 面板在 `.screenSaver` 层，比弹出菜单、`NSAlert` 都高。右键菜单从鼠标位置弹出，上面几项正好压在条身底下，隔着毛玻璃看就是灰的、点不到。弹出期间先把面板降到 `.floating`，关掉再升回去。
- **相邻两行的识别框是贴着的。** Vision 给的框上下比字迹松，中文行和外文行的框经常挨在一起，实际字迹之间只有八九点空隙。所以在框附近按行算横向梯度，找出字迹真正的上下沿，玻璃下沿停在外文字顶上方 1.5 点。
- **圆角两层必须同一种曲线。** 玻璃层的 `maskImage` 用 `NSBezierPath` 画正圆弧，SwiftUI 那边就得用 `style: .circular`；混用 `.continuous` squircle 会在四个角上错开。半径还要按条身尺寸夹住（`Skin.clampRadius`）。
- **部件文字全部 `lineLimit(1).fixedSize()`。** 跑马灯容器有宽度约束，不锁单行的话长文本会折成好几行堆成方块。
- **空格不要画成字符。** 七段把空格画成全暗的 8、翻页牌画成一块空牌，数字前面就挂个鬼影。
- **交互全走 AppKit。** 拖动、缩放、hover、工具条命中都在 `MaskRootView` 里算，`NSHostingView` 的 `hitTest` 返回 nil。
- 面板 level 用 `.screenSaver` + `canJoinAllSpaces` + `fullScreenAuxiliary`，才能浮在别的 App 的全屏视频上。设置里可以降回 `.floating`。

## 排位逻辑单独测

认字和排位的计算在 `src/SubtitleLayout.swift`，不碰窗口，能拿截图直接跑：

```bash
cp tools/layout-test.swift /tmp/main.swift
swiftc -O src/MaskMode.swift src/SubtitleLayout.swift src/SubtitleDetector.swift /tmp/main.swift -o /tmp/layout-test
/tmp/layout-test /tmp 截图1.png 截图2.png
```

每张图出一份标了框、模拟了玻璃的结果图，并检查中文是否落在玻璃实心区内、外文有没有被盖。

开一份不碰正在用的数据的测试实例：`KAGEMAKU_DATA_DIR=/tmp/kgm-test /Applications/Kagemaku.app/Contents/MacOS/Kagemaku`。

## 数据落在哪

```
~/Library/Application Support/Kagemaku/skins.json    自定义皮肤
~/Library/Application Support/Kagemaku/state.json    遮挡条位置、用途、部件、全局设置
```

存档缺字段会用默认值补齐，以后加设置项不会把旧存档读废。

## 还没做

- 屏幕录制权限认的是 ad-hoc 签名，每次从源码重新编译后可能要重新授权
- 只有汉字、没有假名的日文行（比如一行全是地名）会被当成中文盖住

## ShinkoUniv 的其他工具

影幕由 [ShinkoUniv](https://shinkouniv.com) 出品。ShinkoUniv 是 Isen 的实验室，Isen 在日本、中国从事 AI 教育、技术培训与咨询。制作记录在 [note](https://note.com/heishinkou) 和 [小红书 @先進元素](https://www.xiaohongshu.com/user/profile/5e493a3900000000010079b6)。

| 工具 | 做什么 |
|---|---|
| [幻灯 GENTO](https://github.com/Shinkou777/gento) | Claude Code skill：给一段素材，用代码做出带配乐的动画短片 |
| [文房 BUNBO](https://github.com/Shinkou777/bunbo-skill) | Claude Code skill：素材做成小红书长图和 Ins 日英卡片 |
| [浮子 UKI](https://github.com/Shinkou777/uki) | macOS 桌面小浮窗，显示 Claude 的用量限额 |

## 许可

MIT，见 [LICENSE](LICENSE)。

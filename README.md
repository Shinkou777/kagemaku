# 影幕 Kagemaku

挡住动漫字幕先听，听不出来再偷看一眼。macOS 悬浮遮挡条。

## 装

```bash
./scripts/build-app.sh          # 编译 + 生成图标 + 组装到 /Applications/Kagemaku.app
open /Applications/Kagemaku.app
```

菜单栏出现一个条状图标，屏幕下方三分之一处出现一条毛玻璃。没有 Dock 图标（LSUIElement）。

需要 Swift 6 工具链（Command Line Tools 即可，不用完整 Xcode）。部署目标 macOS 14。

## 用

- 拖条身移动，拖四边四角缩放
- 鼠标停上去出工具条：锁定 / 追踪 / 皮肤 / 设置 / 移除
- 右键条身出完整菜单
- 锁定后鼠标穿透，播放器的进度条照点；解锁靠快捷键或菜单栏

### 快捷键（可在设置里改）

| 组合 | 作用 |
|---|---|
| ⌥⌘E | 按住偷看（松开复原，也可改成按一下切换） |
| ⌥⌘M | 全部收起 / 放出 |
| ⌥⌘L | 全部锁定 / 解锁 |
| ⌥⌘N | 新建一条（双语字幕各遮各的） |
| ⌥⌘K | 换下一个皮肤 |

### 三种追踪

1. **手动摆放** —— 拖到哪就在哪，零权限。
2. **跟随播放器窗口** —— 选一个窗口，条按相对比例锚在里面，窗口移动缩放全跟着走。用 CGWindowList 轮询 bounds，不要任何权限；拿不到窗口标题时只显示 App 名。
3. **自动吸附字幕行** —— 在条身附近开一条搜索带，ScreenCaptureKit 定时采样，用横向梯度找成行的文字，把条对过去。**需要屏幕录制权限**，第一次开会弹授权提示。灵敏度、搜索带高度、采样频率都在设置里。

### 皮肤

内置七套：霧硝子 Frosted / 深夜霓虹 Neon Noir / 曉光 Aurora / 墨 Sumi / 走査線 CRT / 曇硝子 Milk / モザイク Mosaic。

内置的只读，复制一份就能改：材质、明暗、饱和度、上下端底色、渐变角度、圆角、描边粗细与起止色、外发光半径与颜色、顶部高光，以及动效（流光 / 扫描线 / 极光 / 呼吸 / 颗粒 / 霜面）。

不透明度每条独立可调，5%–100%。

### 显示部件

条身上可以叠文字装置，位置分靠左 / 居中 / 靠右，每个部件独立选样式、字号、颜色。

样式：辉光管 Nixie、翻页牌 Split-flap（换字带翻转动画）、点阵 LED、七段数码管、霓虹、简约。

内容与数据源：

| 部件 | 来源 | 说明 |
|---|---|---|
| 时间 / 日期 | 本地 | 格式串自己写，如 `HH:mm:ss`、`MM月dd日(EEE)` |
| 行情 | Yahoo Finance 公开接口 | 代码填 `^N225` `AAPL` `BTC-USD` `USDJPY=X` `GC=F`，60 秒刷新，可带涨跌幅 |
| 天气 | Open-Meteo | 填城市名，先地理编码再取当前气温和天气码，10 分钟刷新 |
| 新闻 | 任意 RSS | 填订阅源地址，取标题，配跑马灯滚动，10 分钟刷新 |
| 自定义文字 | 自己填 | 想写什么写什么 |

## 实现上的几个坑

- **毛玻璃必须留在 AppKit。** SwiftUI 的 `.opacity()` / `compositingGroup()` 会把 `NSVisualEffectView` 推进离屏图层，behind-window 的背景模糊直接失效——看着像糊了，其实只是压暗，底下的字一个不少。现在玻璃是 `MaskRootView` 的子视图，SwiftUI 只画着色、描边和部件。
- **动效层不能跟玻璃做混合。** `blendMode(.plusLighter)` 叠在玻璃上会糊出硬边暗矩形。动效层单独 `compositingGroup()`，不用混合模式。
- **交互全走 AppKit。** 拖动、缩放、hover、工具条命中都在 `MaskRootView` 里算，`NSHostingView` 的 `hitTest` 返回 nil。浮动面板在非激活状态下这样最稳。
- **条身四周留 24pt 透明边**（`maskPad`）给外发光和阴影，否则窗口正好等于条身，阴影全被裁掉。`config.frame` 存的是条身，面板比它四周各大 24pt。
- 面板 level 用 `.screenSaver` + `canJoinAllSpaces` + `fullScreenAuxiliary`，才能浮在别的 App 的全屏视频上。设置里可以降回 `.floating`。

## 数据落在哪

```
~/Library/Application Support/Kagemaku/skins.json    自定义皮肤
~/Library/Application Support/Kagemaku/state.json    遮挡条位置、部件、全局设置
```

存档缺字段会用默认值补齐，以后加设置项不会把旧存档读废。

## 还没做

- 屏幕录制权限是 ad-hoc 签名认的身份，每次重新编译后可能要重新授权
- 自动吸附字幕靠横向梯度，画面纹理复杂时会被骗走，灵敏度需要手调

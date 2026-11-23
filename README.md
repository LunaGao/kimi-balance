# Kimi Balance

一款原生 macOS 菜单栏应用，用于展示 Kimi 订阅的总使用量和 5 小时用量，并在后台自动刷新数据。

- 当前版本：1.2 (3)
- GitHub：[LunaGao/kimi-balance](https://github.com/LunaGao/kimi-balance)
- 下载：[Releases](https://github.com/LunaGao/kimi-balance/releases)

## 界面预览

![Kimi Balance 菜单栏用量展示](docs/images/menu-bar.png)

## 功能

- 菜单栏实时显示总使用量和 5 小时用量。
- 点击菜单栏图标可查看两项用量及各自的重置时间。
- 每 60 秒自动刷新，也可以点击“立即刷新”手动更新。
- 主窗口关闭后，后台仍会持续刷新数据。
- 启动时只显示菜单栏，不自动打开主窗口。
- 主窗口采用单窗口模式；再次打开时会复用并置前显示已有窗口。
- 仅主窗口显示时展示 Dock 图标，关闭主窗口后自动隐藏。
- 设置页提供英文操作指南、版本号、构建号、GitHub 仓库和数据来源入口。
- 使用 Sparkle 检查应用更新。

## 使用说明

### 1. 启动应用

从 [Releases](https://github.com/LunaGao/kimi-balance/releases) 下载并打开 Kimi Balance，或按照下方“构建与运行”章节自行构建。

启动后，应用图标和用量信息会出现在 macOS 菜单栏中，不会自动打开主窗口。

### 2. 登录 Kimi

首次使用或登录状态失效时，菜单栏会显示“请完成登录”：

1. 点击菜单栏中的 Kimi Balance。
2. 选择“显示主窗口”。
3. 在主窗口打开的 `kimi.com` 页面中完成登录。
4. 点击“登录完成，查看用量”。

只要登录 Cookie 仍然有效，后续启动会直接复用登录状态，无需重复登录。

### 3. 查看用量

登录成功后，菜单栏会直接显示总使用量和 5 小时用量。点击菜单栏区域可查看：

- 总使用量及其重置时间。
- 5 小时用量及其重置时间。
- 刷新、主窗口、设置、检查更新和退出等操作。

### 4. 刷新数据

应用每 60 秒自动刷新一次。需要立即获取最新数据时，可通过以下任一方式刷新：

- 点击菜单栏中的“立即刷新”。
- 在主窗口中点击“立即刷新”。

关闭主窗口不会退出应用，也不会停止后台刷新。

### 5. 打开设置与检查更新

点击菜单栏中的“设置…”，可以查看：

- 英文版操作流程（How to Use）。
- 应用版本号和构建号。
- GitHub 仓库与 Kimi 订阅数据来源链接。
- 登录 Cookie 和用量数据的简要说明。

选择“检查更新…”可通过 Sparkle 检查新版本。选择“退出 Kimi Balance”可完全退出应用并停止后台刷新。

## 登录与数据

应用使用 `WKWebView` 的持久化数据存储保存登录 Cookie，不会读取 Chrome、Safari 或其他浏览器的 Cookie。Cookie 仅保存在应用本地的 WebView 数据存储中。

登录有效时，应用通过不展示的后台 WebView 访问以下页面并提取用量数据：

```text
https://www.kimi.com/settings/subscription
```

应用不会修改订阅数据。用量信息和重置时间以 Kimi 订阅页面显示的内容为准。

## 常见问题

### 菜单栏一直显示“请完成登录”

重新打开主窗口，确认已在当前应用内置页面完成 Kimi 登录，然后点击“登录完成，查看用量”。仅在独立浏览器中登录不会同步到应用。

### 用量显示为 `--`

这通常表示登录已失效、订阅页面尚未加载完成，或页面内容暂时无法读取。请先确认登录状态，再点击“立即刷新”；如果仍无法恢复，请重新登录。

### 主窗口关闭后找不到应用

应用仍在菜单栏运行。点击菜单栏中的用量信息，选择“显示主窗口”即可重新打开；如需完全退出，请选择“退出 Kimi Balance”。

## 构建与运行

要求：

- macOS 26.6.2 或更高版本
- Xcode 27 或兼容版本

打开项目并运行：

```bash
open kimi-balance.xcodeproj
```

也可以使用命令行构建：

```bash
xcodebuild -project kimi-balance.xcodeproj \
  -scheme kimi-balance \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

应用启用了 App Sandbox，仅包含网络客户端权限。Sparkle 依赖由 Xcode Swift Package Manager 自动解析。

## 主要代码

- `kimi-balance/MyApp.swift`：应用启动、设置场景、主窗口复用和 Dock 图标管理。
- `kimi-balance/StatusBarController.swift`：原生菜单栏图标、文字及下拉菜单。
- `kimi-balance/ContentView.swift`：登录页面、用量展示、后台刷新与数据提取。
- `kimi-balance/SettingsView.swift`：英文操作流程、版本信息及项目链接。

<p align="center">
  <img src="Assets/AppIcon-1024.png" width="128" alt="DockUnstick icon">
</p>

<h1 align="center">DockUnstick</h1>

<p align="center">
  修复 macOS 切换全屏空间后，Dock 卡在悬停状态、不自动收回的问题。
</p>

<p align="center">
  <b>简体中文</b> | <a href="README.md">English</a>
</p>

---

## 为什么写这个项目

升级到 macOS 27.2 之后，Dock 出现了一个能稳定复现的问题:

1. 在一个全屏应用里，把鼠标停在 Dock 的某个图标上；
2. 通过触控板左右滑动，或点击 Dock 图标，切换到另一个全屏应用；
3. 在切换动画进行时，把鼠标快速移到屏幕中间。

结果 Dock **一直显示着不收回**，那个图标的名称提示也一直挂着，就像鼠标还停在上面一样。只有把鼠标移回 Dock 再移开，或者执行 `killall Dock`，Dock 才会恢复，而且下次切换又会出现。社区里也有不少人报告了同样的问题，目前除了关闭放大效果，没有其他办法。

在 Apple 修复之前，DockUnstick 会在后台自动处理这个问题，不用你动手。

## 原因

通过监听窗口服务器发给 Dock 进程的事件，可以看到问题出在一个**被丢掉的"鼠标离开"事件**上。

### 两个角色

- **窗口服务器：** 系统里负责盯着鼠标的部分。鼠标进入 Dock 时，它通知 Dock"进来了"(事件 8)；离开时，通知"走了"(事件 9)。
- **Dock：** 收到"进来了"就显示悬停效果并保持显示；收到"走了"就取消悬停、收回。它不会自己去看鼠标在哪，完全依赖这两个通知。

### 关键：切换一开始，"走了"就提前发出了

不管鼠标是否真的离开，切换 Space 一开始，窗口服务器就会给 Dock 发一个"走了"，即使鼠标还停在图标上。而此时 Dock 正忙着执行切换动画，会忽略这个通知。

所以每次切换，Dock 实际上都漏掉了一个"走了"。能不能恢复，就看切换结束时鼠标在哪。

下面两个例子来自实际抓到的事件，切换是通过点击 Dock 图标触发的；用触控板滑动切换时过程完全一样，只是没有点击这一步。

**正常：切换结束时，鼠标还在 Dock 上**

| 时间 | 发生了什么 | Dock 的状态 |
|---|---|---|
| 31.06–31.19 | 点击 WebStorm 图标，开始切换 | 悬停中 |
| 31.23 | 提前发出"走了"，被 Dock 忽略 | 仍然悬停 |
| 31.49 | 切换结束，鼠标还在 Dock 上，窗口服务器补发一次"进来了" | 悬停，和实际一致 |
| 31.57 | 鼠标移开，窗口服务器发出"走了"，Dock 正常处理 | 退出悬停，收回 ✅ |

**卡住：切换还没结束，鼠标就已经离开**

| 时间 | 发生了什么 | Dock 的状态 |
|---|---|---|
| 36.54–36.66 | 点击 WebStorm 图标，开始切换 | 悬停中 |
| 36.70 | 提前发出"走了"，被 Dock 忽略 | 仍然悬停 |
| 切换过程中 | 鼠标快速移到屏幕中间 | 仍然悬停 |
| 36.97 | 切换结束，鼠标已经在 Dock 外面 | 仍然悬停 ❌ |

这时窗口服务器认为"走了"已经通知过、鼠标也确实在外面，不会再发任何事件；Dock 没收到"走了"，以为鼠标还在图标上，也不会自己去确认。于是就一直卡着。

### 一个比喻

门卫(窗口服务器)看到客人起身，就打电话通知店主(Dock)"客人走了"。可店主正在搬货，没接到电话。

- **客人没走、回到店里：** 门卫会再通知一次"客人来了"，店主就知道了，之后客人真的离开时也能接到电话。
- **客人趁着搬货直接离开了：** 门卫觉得已经通知过了，不会再打电话；店主却一直以为客人还在店里。

DockUnstick 做的，就是在发现店主还在等客人时，把门卫那通电话**再打一遍**。

## 它做了什么

- **记录:** 用只监听的事件监听(`CGEvent.tapCreateForPid`)挂在 Dock 进程上，只订阅"进入/离开"两种事件，保存最近一次"鼠标离开"事件。
- **检测:** 每次切换 Space 后立即检查一次；如果鼠标还在 Dock 上，或者修复没有生效，就按设定的间隔再检查，默认最多再检查 3 次、每次间隔 0.5 秒。如果鼠标已经不在 Dock 上，但 Dock 仍有图标处于悬停状态，或者本该自动隐藏却仍然显示，就判定为卡住。
- **修复:** 把保存的"鼠标离开"事件复制一份，更新为当前时间和鼠标位置，投递给 Dock 进程(`CGEvent.postToPid`)。Dock 收到它漏掉的事件后，正常退出悬停并收回。

整个过程**不移动鼠标指针、不重启 Dock、不读取屏幕内容、不联网**。平时不轮询，只在切换 Space 后检查几次。所用接口都是公开 API。

在作者的机器上实测：卡住的情况 8/8 被修复，从切换 Space 到 Dock 收回大约 1 秒。

## 安装

需要 macOS 13 或更高版本，支持 Apple 芯片和 Intel 芯片。

### 方式一：下载编译好的版本

1. 在 [Releases](https://github.com/LLP2333/dockUnstick/releases) 页面下载最新的 `DockUnstick-x.y.z.zip`，解压后把 `DockUnstick.app` 拖到"应用程序"文件夹；
2. 第一次打开时，macOS 会提示"无法验证开发者"并拒绝打开。这是因为本项目没有使用付费的 Apple 开发者证书签名和公证。请到 **系统设置 → 隐私与安全性**，在页面下方点「仍要打开」。

也可以在终端里去掉下载标记，之后就能直接打开:

```bash
xattr -dr com.apple.quarantine /Applications/DockUnstick.app
```

### 方式二：从源码编译

需要 Xcode 或 Xcode Command Line Tools(提供 `swiftc`)。

```bash
git clone https://github.com/LLP2333/dockUnstick.git
cd dockUnstick
./build.sh
```

建议先把编译出来的 `DockUnstick.app` 移到"应用程序"文件夹，再打开:

```bash
mv DockUnstick.app /Applications/
open /Applications/DockUnstick.app
```

### 授权辅助功能

首次打开时，点击菜单栏里的 DockUnstick 图标，在面板中点「授权…」，然后在 **隐私与安全性 → 辅助功能** 里打开 DockUnstick 的开关。面板会自动检测到授权；后续不会再重复弹出授权引导窗口。

> 程序是本机临时签名(ad-hoc)的，**每次重新编译后，macOS 都会把它当成新程序**，旧的授权会失效。这时开关看起来是打开的，但其实没有生效。请用 **−** 删除 DockUnstick，再用 **+** 重新添加。
>
> 开发调试时，如果本机已有 Developer ID 证书，可以用 `CODESIGN_IDENTITY="Developer ID Application: 名称 (TEAMID)" ./build.sh` 使用稳定签名，避免每次重建后重新授权。

## 使用

DockUnstick 在后台运行，不出现在 Dock 里。点击菜单栏图标会直接展开轻量面板；在它运行时再次打开 app 也会显示这个面板，不会创建独立窗口:

- **状态:** 是否正在运行；缺少辅助功能权限时，可以从这里直达系统授权设置；
- **救援仪表盘:** 以今日救援次数为核心，加入救援等级、连续天数、累计修复、成功率、上次修复时间和最近七天趋势；
- **设置:**
  - 「登录时自动启动」：使用系统的登录项，首次可能需要在 系统设置 → 通用 → 登录项 中允许。登录时自动启动不会展开面板，只在后台安静运行；
  - 「语言」：跟随系统、中文或 English。默认跟随系统：系统首选语言是中文时显示中文，其他语言一律显示英文；
  - 「菜单栏图标」：「dockUnstick（默认）」保留项目原版图标，另有 23 个样式，包括云朵、街机、人物头像、小动物和彩色 Emoji，选择后立即生效；
  - 「记录日志」：**默认关闭**。打开后才写入诊断日志；`--dump` 和 `--tap` 诊断模式仍会临时记录；
  - 「修复节奏」：可调整检查次数和间隔。切换 Space 后会立即检查一次；如果没能确认 Dock 正常(鼠标还在 Dock 上，或者修复没有生效)，就按间隔再检查。次数 0–5，**默认 3 次**；间隔 0.1–1 秒，**默认 0.5 秒**。拖动后从下一次切换 Space 开始生效；
- 打开日志、打开项目主页、重置统计或退出。

## 设置

可以用 `defaults` 调整。除了 `language`、`menuBarIcon`、`loggingEnabled`、`retryCount` 和 `retryInterval` 以外，修改后都要重启 DockUnstick 才生效:

| 键 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `language` | 字符串 | `system` | 界面语言：`system`(跟随系统)、`zh` 或 `en`，也可以在面板里切换，立即生效 |
| `menuBarIcon` | 字符串 | `original` | 菜单栏图标。可选 `original`、`rocket`、`protection`、`diagnostics`、`cat`、`game`、`puzzle`、`lightning`、`cloud`、`cloudSun`、`arcade`、`bobAvatar`、`tuftAvatar`、`twinTailAvatar`、`bird`、`fish`、`alien`、`panda`、`fox`、`frog`、`bubbleTea`、`sushi`、`ghost` 或 `robot` |
| `loggingEnabled` | bool | `false` | 是否写入日志。也可以在面板里切换 |
| `trace` | bool | `true` | 开启日志时，每次检查都把 Dock 状态写入日志 |
| `retryCount` | 整数 | `3` | 第一次检查没能确认 Dock 正常时，最多再检查几次(0–5)。也可以在面板里调整 |
| `retryInterval` | 数字 | `0.5` | 每次再检查之间间隔几秒(0.1–1)。也可以在面板里调整 |

```bash
defaults write local.dockunstick trace -bool false
defaults write local.dockunstick retryCount -int 5
defaults write local.dockunstick retryInterval -float 0.2
```

日志默认关闭。开启后写入 `~/Library/Logs/DockUnstick.log`；超过 1 MB 时会改名为 `DockUnstick.log.1`(覆盖上一份)，然后重新开始写，所以两个文件加起来最多约 2 MB。

## 诊断模式

如果系统更新后修复失效了，下面两个模式能帮助定位原因:

```bash
# 60 秒内记录窗口服务器发给 Dock 的所有事件(鼠标移动事件只计数)
open DockUnstick.app --args --tap 60

# 8 秒后导出 Dock 的辅助功能信息(各图标的位置、悬停状态等)
open DockUnstick.app --args --dump 8
```

结果都写入上面的日志文件。运行前请先退出正在运行的 DockUnstick。

## 局限

- 这是绕过问题的办法，不是根治。根治需要 Apple 在 Dock 切换动画结束后重新检查鼠标位置。如果你也遇到了，欢迎通过「反馈助理」向 Apple 报告。
- 修复依赖 Dock 的事件格式（类型 9"鼠标离开"）。如果未来系统改了格式，修复可能失效，日志中会出现 `fix: replayexit did not help`。
- 判断 Dock 是否收回时，目前只考虑放在主显示器底部的 Dock。

## 卸载

1. 打开 DockUnstick，关闭「登录时自动启动」，然后点「退出 DockUnstick」；
2. 删除 `DockUnstick.app`；
3. 在 系统设置 → 隐私与安全性 → 辅助功能 中删除 DockUnstick；
4. 可选：清理设置、统计和日志:

```bash
defaults delete local.dockunstick
rm -f ~/Library/Logs/DockUnstick.log ~/Library/Logs/DockUnstick.log.1
```

## 许可证

[MIT](LICENSE)

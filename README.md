# tiny11builder

**用于制作精简版 Windows 11 镜像的脚本 —— 现已改用 PowerShell！**

## 简介

tiny11 builder 已经完成全面重构。
历经一年多未更新（对此我深表歉意），tiny11 builder 如今已是一套更完整、灵活的解决方案，**一个脚本适配全部场景**。同时，这也是后续开发更完善版本的铺垫。

现在该工具可以适配**任意 Windows 11 正式版本**（不再局限于特定内部版本），同时支持任意语言与处理器架构。
这得益于 PowerShell 相比旧版批处理脚本大幅提升的脚本处理能力。

该脚本用于自动构建一套精简的 Windows 11 镜像，效果类似 tiny10。
脚本现已使用 DISM 的恢复压缩功能，最终 ISO 文件体积大幅缩小，且不依赖任何第三方外部工具。唯一附带的可执行文件是 **oscdimg.exe**，该程序来自 Windows ADK，用于生成可启动的 ISO 镜像。

包内还包含一份无人值守应答文件，可以在系统初始化界面（OOBE）绕过微软账户登录，并且以 `/compact` 压缩模式部署系统。

本项目开源，**欢迎自行增删修改功能！** 也非常欢迎反馈意见。

本次首次推出 **tiny11 core builder**！一套功能更强的脚本，专为快速简易的开发测试环境打造。仅保留最基础组件，剔除所有冗余内容。

该脚本会生成一个极致精简的 Windows 11 镜像。但**不适合日常使用**：它丧失系统维护能力——镜像制作完成后，无法追加语言包、安装系统更新、添加系统功能。tiny11 Core 不能作为完整 Windows 11 的替代品，它主要用于快速测试或者开发场景，虚拟机环境下尤为实用。

---

## ⚠️ 脚本版本说明

- **tiny11maker.ps1**：常规版本脚本。移除大量预装臃肿应用，但保留系统维护能力。制作完成后仍可以安装语言包、系统更新、添加系统组件。**推荐普通用户使用。**
- ⚠️ **tiny11coremaker.ps1**：核心精简版脚本。删除更多组件，但同时破坏镜像的系统维护能力。制作完成后无法添加语言、更新系统、开启新功能。适合快速测试、开发调试。

## 使用步骤

1. 从[微软官网](https://www.microsoft.com/software-download/windows11)或 Rufus 项目下载 Windows 11 原版镜像
2. 使用资源管理器挂载下载好的 ISO 文件
3. 以管理员身份打开 **PowerShell 5.1**
4. 修改脚本执行策略：

```
Set-ExecutionPolicy Bypass -Scope Process
```

> 
> 使用 `-Scope Process` 参数只会对当前 PowerShell 会话生效，不会改动系统原有执行策略。

5. **（可选）** 运行图形界面（GUI）自由勾选要保留/删除的组件，然后点击“保存并启动构建”即可：

```
C:/你的脚本路径/gui.ps1
```

> 
> GUI 会把你的选择写入 `config.json`，构建脚本会自动读取同一份配置。
> 也可以直接手动编辑 `config.json`（默认值均为 `true`，即默认执行所有精简项）。

6. 也可以直接命令行运行脚本：

```
C:/你的脚本路径/script.ps1 -ISO 挂载盘盘符 -SCRATCH 临时盘盘符
```

> 
> 执行 `get‑help` 命令查看脚本完整帮助文档。

7. 选择镜像挂载的驱动器盘符（**只输入字母，不要带冒号 :**）
8. 选择想要制作的系统版本（SKU）
9. 静静等待构建完成 :)
10. 构建结束后，`tiny11.iso` 会生成在脚本解压目录下。

---

## 组件移除清单

| tiny11maker（常规版） | tiny11coremaker（核心精简版） |
| --- | --- |
| - Clipchamp（视频编辑器）   - 新闻   - 天气   - Xbox   - 帮助   - 入门   - Office Hub   - 纸牌游戏   - 人脉   - PowerAutomate   - ToDo 待办   - 闹钟   - 邮件和日历   - 反馈中心   - 地图   - 录音机   - 你的手机   - 媒体播放器   - 快速助手   - Internet Explorer   - 平板电脑数学组件   - Edge浏览器   - OneDrive | 包含常规 tiny11 的全部删除项，额外移除：   - Windows 组件存储库（WinSxS）   - Windows Defender（仅禁用，可手动重新开启）   - Windows 更新（缺少 WinSxS 导致更新无法工作，强行开启会造成系统故障）   - Windows 恢复环境 WinRE |

**移除预装应用（`apps` 开关）具体包含**（通过 DISM 按包前缀匹配移除）：

- **办公**：Office Hub（Office 中心）、OneNote、Outlook for Windows、Power Automate、Dev Home、Copilot
- **沟通/媒体**：Teams、微软商店版 Teams、Skype、Xbox 全家桶（TCUI/App/GameOverlay/GamingOverlay/IdentityProvider/SpeechToText）、Zune 音乐/视频、Clipchamp（视频编辑器）、3D 查看器、画图
- **生活工具**：闹钟、相机、地图、录音机、便签（StickyNotes）、待办（Todos）、钱包（Wallet）、人脉
- **资讯/辅助**：Bing 新闻/搜索/天气、获取帮助（GetHelp）、入门（GetStarted）、反馈中心（Feedback Hub）、跨设备（CrossDevice）
- **系统相关**：Windows 邮件与应用（communicationsapps）、Windows Terminal、MSPaint 等

### config.json 配置项说明

| 键 | 说明 | 适用脚本 |
| --- | --- | --- |
| `apps` | 移除预装应用（见上方清单） | 两个版本 |
| `edge` | 移除 Edge 及残留 | 两个版本 |
| `onedrive` | 移除 OneDrive 及禁用备份 | 两个版本 |
| `systemPackages` | 移除系统包（含 Windows Defender，仅禁用、可手动重开；含 Internet Explorer、媒体播放器、写字板等） | 仅核心版 |
| `winre` | 移除恢复环境 WinRE | 仅核心版 |
| `trimWinSxS` | 精简 WinSxS 组件库 | 仅核心版 |
| `disableUpdates` | 禁用 Windows 更新 | 仅核心版 |
| `bypassRequirements` | 绕过硬件系统要求 | 两个版本 |
| `disableSponsoredApps` | 禁用推广应用 | 两个版本 |
| `disableTelemetry` | 禁用遥测 | 两个版本 |
| `localAccount` | 启用 OOBE 本地账户（绕过微软登录） | 两个版本 |
| `disableReserves` | 禁用保留空间 | 两个版本 |
| `disableBitLocker` | 禁用 BitLocker 设备加密 | 两个版本 |
| `disableChat` | 禁用任务栏聊天图标 | 两个版本 |
| `disableCopilot` | 禁用 Copilot | 两个版本 |
| `blockWebApps` | 阻止 Teams/Outlook/DevHome 自动重装 | 两个版本 |
| `deleteTelemetryTasks` | 删除遥测相关计划任务 | 两个版本 |

> 
> 所有键默认值为 `true`（执行全部精简项）。设为 `false` 可保留相应组件。
> 核心版（core）独有 4 项（`systemPackages`/`winre`/`trimWinSxS`/`disableUpdates`），常规版运行时会被忽略。

> 
> 注意：**tiny11 core 制作完成后无法恢复被删除的系统功能！**
> 构建镜像过程中会询问你是否开启 .NET 3.5 支持。

---

## 已知问题

1. 虽然 Edge 浏览器已被删除，但设置界面仍会残留部分相关条目，程序本体已经被移除。
2. 使用微软商店安装应用前，可能需要手动更新 Winget。
3. Outlook 和 Dev Home 有时会自动重新安装，项目组正在处理该问题；最新版脚本已经加强限制来缓解该现象。
4. ~~在 ARM64 平台运行脚本时，会短暂弹出报错。原因是 ARM64 原版镜像的 System32 目录不存在 OneDriveSetup.exe。~~（已于 2026-08-21 版本修复：加入文件存在性判断，缺失时跳过。）

## 待实现功能

- ~~关闭遥测~~（已于2024‑04‑29版本完成）
- ~~增强广告拦截~~（2025‑09‑06 版本已部分实现）
- ~~优化语言、处理器架构识别逻辑~~（已于 2026-08-21 版本完成）
- ~~支持自定义配置，自由选择保留/删除组件~~（已于 2026-08-21 版本完成，通过 `config.json` 或 `gui.ps1` 图形界面操作）
- ~~未来可能开发图形界面（GUI)~~（已于 2026-08-21 版本完成，内置 `gui.ps1` 图形界面）

以上就是目前全部内容！

## ❤️ 支持本项目

如果这个项目对你有帮助，欢迎给予支持。小额捐助可以让作者投入更多时间开发这类工具。

感谢！
[Patreon](http://patreon.com/ntdev) | [PayPal](http://paypal.me/ntdev2) | [Ko‑fi](http://ko%E2%80%91fi.com/ntdev)

感谢体验，欢迎反馈你的使用感受！
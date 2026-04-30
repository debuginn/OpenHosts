![OpenHosts](https://webp.debuginn.com/20260430HADx6Z.jpeg)

# OpenHosts

一款原生 macOS 菜单栏应用，用于管理 `/etc/hosts`。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-26.0%2B-000000.svg)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-FA7343.svg)](https://swift.org/)

[English](README.md)

## 功能特性

- **菜单栏应用** — 常驻 macOS 菜单栏，一键可达
- **Hosts 编辑器** — 完整的文本编辑器，支持语法高亮（IP 蓝色、注释灰色、无效行红色下划线）
- **配置管理** — 将 hosts 条目组织为独立的配置项，可单独开关
- **分组支持** — 将多个配置项组合为分组，批量切换
- **快速切换** — 在菜单栏弹窗中直接开关配置和分组
- **快照历史** — 自动保存配置变更快照，一键恢复
- **特权助手** — 通过 XPC 安全写入 `/etc/hosts`，验证调用方身份
- **桌面小组件** — WidgetKit 扩展，在桌面快速切换
- **格式校验** — 实时验证 hosts 格式，阻止无效配置生效

![Widget](https://webp.debuginn.com/202604309qf4Vs.jpeg)

## 系统要求

- macOS 26.0+
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## 安装

从 [GitHub Releases](https://github.com/debuginn/OpenHosts/releases) 下载最新版本，解压后将 `OpenHosts.app` 移动到 `/Applications` 目录。

## 从源码构建

```bash
# 安装 XcodeGen（如尚未安装）
brew install xcodegen

# 克隆仓库
git clone https://github.com/debuginn/OpenHosts.git
cd OpenHosts

# 生成 Xcode 工程
xcodegen generate

# 构建
xcodebuild build -scheme OpenHosts -configuration Release

# 运行测试
xcodebuild test -scheme SharedKitTests -destination 'platform=macOS'
```

也可以打开 `OpenHosts.xcodeproj` 在 Xcode 中直接构建。

## 使用方法

1. 启动 OpenHosts — 应用出现在菜单栏
2. 点击菜单栏图标打开弹窗
3. 点击 **OpenHosts** 打开编辑器窗口
4. 使用 **+** 按钮创建配置项，编写 hosts 条目
5. 开关配置项 — 变更会自动应用到 `/etc/hosts`
6. 使用分组来组织和批量切换相关配置

特权助手需要在 **系统设置 > 通用 > 登录项与扩展** 中一次性授权。

## 架构

```
OpenHosts（主应用）
├── 菜单栏弹窗 — 快速切换 UI
├── 编辑器窗口 — 完整的 hosts 编辑器，支持语法高亮
├── 设置窗口 — 偏好设置（通用 + 关于）
└── AppViewModel — 集中状态管理

OpenHostsHelper（特权守护进程）
└── XPC 服务 — 原子写入 /etc/hosts，通过 proc_pidpath() 验证调用方

OpenHostsWidget（WidgetKit 扩展）
└── 桌面小组件快速切换配置

SharedKit（SPM 包）
├── HostsComposer — 组装 /etc/hosts 内容，管理区段边界
├── HostsGroup — 分组数据模型
└── HostsParser — 文本解析工具
```

应用在 `/etc/hosts` 中管理 `# --- OPENHOSTS_START ---` 和 `# --- OPENHOSTS_END ---` 标记之间的区段，保留标记外的所有内容。

## 参与贡献

欢迎提交 Issue 或 Pull Request！

## 许可证

[MIT](LICENSE)

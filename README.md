![OpenHosts](https://webp.debuginn.com/20260430HADx6Z.jpeg)

# OpenHosts

A native macOS menu bar app for managing `/etc/hosts`.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-26.0%2B-000000.svg)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-FA7343.svg)](https://swift.org/)

[中文](README_CN.md)

## Features

- **Menu Bar App** — Lives in the macOS menu bar, always one click away
- **Hosts Editor** — Full text editor with syntax highlighting (IPs in blue, comments in gray, invalid lines underlined in red)
- **Config Management** — Organize entries into named configs, toggle them on/off independently
- **Group Support** — Bundle multiple configs into groups for batch toggling
- **Quick Toggle** — Enable/disable configs and groups directly from the menu bar popover
- **Snapshot History** — Automatic snapshots of config changes with one-click restore
- **Privileged Helper** — Secure write to `/etc/hosts` via XPC with caller verification
- **Widget** — WidgetKit extension for quick toggles from the desktop
- **Validation** — Real-time hosts format validation before applying changes

![Widget](https://webp.debuginn.com/202604309qf4Vs.jpeg)

## Requirements

- macOS 26.0+
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Installation

Download the latest release from [GitHub Releases](https://github.com/debuginn/OpenHosts/releases), unzip, and move `OpenHosts.app` to `/Applications`.

## Build from Source

```bash
# Install XcodeGen if needed
brew install xcodegen

# Clone the repository
git clone https://github.com/debuginn/OpenHosts.git
cd OpenHosts

# Generate Xcode project
xcodegen generate

# Build
xcodebuild build -scheme OpenHosts -configuration Release

# Run tests
xcodebuild test -scheme SharedKitTests -destination 'platform=macOS'
```

Or open `OpenHosts.xcodeproj` in Xcode and build from there.

## Usage

1. Launch OpenHosts — it appears in the menu bar
2. Click the menu bar icon to open the popover
3. Click **OpenHosts** to open the editor window
4. Create configs with the **+** button, write your hosts entries
5. Toggle configs on/off — changes are applied to `/etc/hosts` automatically
6. Use groups to organize and batch-toggle related configs

The privileged helper requires one-time approval in **System Settings > General > Login Items & Extensions**.

## Architecture

```
OpenHosts (Main App)
├── Menu Bar Popover — quick toggle UI
├── Editor Window — full hosts editor with syntax highlighting
├── Settings Window — preferences (General + About tabs)
└── AppViewModel — central state management

OpenHostsHelper (Privileged Daemon)
└── XPC Service — writes /etc/hosts atomically, validates caller via proc_pidpath()

OpenHostsWidget (WidgetKit Extension)
└── Toggle configs from desktop widgets

SharedKit (SPM Package)
├── HostsComposer — assembles /etc/hosts content with managed section boundaries
├── HostsGroup — group data model
└── HostsParser — text parsing utilities
```

The app manages a section in `/etc/hosts` between `# --- OPENHOSTS_START ---` and `# --- OPENHOSTS_END ---` markers, preserving all content outside those boundaries.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

[MIT](LICENSE)

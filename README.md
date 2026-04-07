**MacBackroom**

[简体中文](./README.zh-CN.md)

MacBackroom is a macOS menu bar utility for efficiency-focused system controls. The current build focuses on fast Space switching with a private gesture path, and the longer-term goal is to grow into a broader toolkit for practical macOS tweaks and hidden settings.

## 一、Overview

MacBackroom is built for local macOS workflows where speed matters more than platform portability. Right now the app ships as a menu bar extra with global shortcuts, live Space snapshots, and safeguards for repeated rapid switching.

## 二、Current Features

### 1. Switching

- Fast left and right Space switching from the menu bar popup
- Global hotkeys: `⌃⌥⌘←` and `⌃⌥⌘→`
- Edge-overshoot prevention for rapid repeated input

### 2. Runtime Status

- Accessibility permission detection and relaunch flow
- Per-display managed Space snapshot display
- Manual snapshot refresh from the popup window

## 三、Technical Notes

### 1. Platform

- macOS only
- SwiftUI menu bar app

### 2. Implementation

- Uses private `SkyLight` APIs and synthetic gesture events
- Requires Accessibility permission to post the switching gesture
- Intended for local experimentation and personal productivity workflows

### 3. Distribution

- Not suitable for App Store distribution in its current form
- Future compatibility may change across macOS releases because private APIs are involved

## 四、Build And Run

### 1. Open In Xcode

- Open [MacBackroom.xcodeproj](./MacBackroom.xcodeproj)
- Select the `MacBackroom` scheme
- Build and run on your Mac

### 2. Build From Terminal

```bash
xcodebuild -project MacBackroom.xcodeproj -scheme MacBackroom -derivedDataPath .DerivedData build
```

### 3. Grant Permissions

- On first launch, grant Accessibility permission in System Settings
- After permission is granted, the app relaunches and reinitializes the switching path

## 五、Project Layout

- `MacBackroom/`: Swift source for the app
- `MacBackroom/AppModel.swift`: permission flow, state, and top-level app actions
- `MacBackroom/SkyLightBridge.swift`: low-level Space snapshot and gesture driver
- `MacBackroom/ContentView.swift`: popup UI
- `MacBackroom.xcodeproj/`: Xcode project

## 六、Roadmap

- Expand beyond Space switching into more efficiency-oriented macOS controls
- Add more user-facing toggles for practical hidden settings
- Keep the UI lightweight enough for fast menu bar workflows

## 七、License

- Licensed under the [MIT License](./LICENSE)

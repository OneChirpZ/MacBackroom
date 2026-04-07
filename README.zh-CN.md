**MacBackroom**

[English](./README.md)

MacBackroom 是一个面向效率场景的 macOS 菜单栏工具。当前版本重点解决快速切换 Space 的体验问题，后续会逐步扩展为一个更通用的 macOS 效率优化与隐藏设置工具箱。

## 一、项目概述

MacBackroom 当前以本地个人使用为主要目标，优先考虑操作响应速度和系统级能力，而不是跨平台能力。现在的版本已经具备菜单栏入口、全局快捷键、Space 快照展示，以及连续快速切换时的边界保护。

## 二、当前功能

### 1. 空间切换

- 从菜单栏弹窗快速向左或向右切换 Space
- 支持全局快捷键：`⌃⌥⌘←` 与 `⌃⌥⌘→`
- 支持快速连续触发时的边界过冲拦截

### 2. 运行状态

- 自动检测 Accessibility 权限并在授权后重启初始化
- 按显示器展示当前受管 Space 快照
- 可在弹窗中手动刷新快照

## 三、技术说明

### 1. 平台范围

- 仅支持 macOS
- 基于 SwiftUI 的菜单栏应用

### 2. 实现方式

- 使用私有 `SkyLight` API 与合成手势事件
- 发送切换手势前需要系统 Accessibility 权限
- 当前定位是本地实验和个人效率工作流

### 3. 分发限制

- 目前不适合上架 App Store
- 由于依赖私有 API，不同 macOS 版本上的兼容性可能变化

## 四、构建与运行

### 1. 通过 Xcode

- 打开 [MacBackroom.xcodeproj](./MacBackroom.xcodeproj)
- 选择 `MacBackroom` scheme
- 在本机构建并运行

### 2. 通过终端

```bash
xcodebuild -project MacBackroom.xcodeproj -scheme MacBackroom -derivedDataPath .DerivedData build
```

### 3. 权限要求

- 首次运行时需要在系统设置中授予 Accessibility 权限
- 授权完成后，应用会重启并重新初始化切换路径

## 五、目录结构

- `MacBackroom/`: 应用 Swift 源码
- `MacBackroom/AppModel.swift`: 权限流程、状态管理与高层行为
- `MacBackroom/SkyLightBridge.swift`: Space 快照与底层切换驱动
- `MacBackroom/ContentView.swift`: 弹窗界面
- `MacBackroom.xcodeproj/`: Xcode 工程

## 六、后续方向

- 从 Space 切换扩展到更多效率相关的 macOS 控制能力
- 增加更多对用户可见的隐藏设置开关
- 保持菜单栏工作流的轻量与快速响应

## 七、许可证

- 采用 [MIT License](./LICENSE)

**MacBackroom**

[English](./README.md)

MacBackroom 是一个 macOS 菜单栏应用，当前提供快速切换 Space 和少量效率相关的系统控制。

## 一、当前功能

- 在菜单栏弹窗中向左或向右切换 Space
- 支持全局快捷键：`⌃⌥⌘←` 与 `⌃⌥⌘→`
- 在接近 Space 边界时拦截连续快速点击带来的过冲
- 快速调节 Dock 的 Space 切换动画、自动隐藏延迟和自动隐藏动画速度，并可重启 Dock 应用设置
- 展示当前受管 Space 快照，并支持手动刷新

## 二、下载 Release

- 从 [Releases](https://github.com/OneChirpZ/MacBackroom/releases/latest) 下载打包好的应用
- 当前 release 没有进行代码签名
- 首次打开时，macOS 可能会拦截启动；可以先在 Finder 中对应用执行一次 `打开`，或者手动移除 quarantine 属性：

```bash
xattr -dr com.apple.quarantine /Applications/MacBackroom.app
```

- 启动后需要授予 Accessibility 权限，应用才能发送切换手势

## 三、自行构建

```bash
git clone https://github.com/OneChirpZ/MacBackroom.git
cd MacBackroom
xcodebuild -project MacBackroom.xcodeproj -scheme MacBackroom -derivedDataPath .DerivedData build
```

- 也可以直接用 Xcode 打开 [MacBackroom.xcodeproj](./MacBackroom.xcodeproj) 进行构建和运行

## 四、说明

- 仅支持 macOS
- 使用私有 `SkyLight` API 与合成手势事件
- 不适合上架 App Store

## 五、许可证

- [MIT License](./LICENSE)

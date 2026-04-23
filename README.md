**MacBackroom**

[简体中文](./README.zh-CN.md)

MacBackroom is a macOS menu bar app for fast Space switching and a small set of efficiency-focused system controls.

## Features

- Switch to the left or right Space from the menu bar popup
- Trigger switching with global shortcuts: `⌃⌥⌘←` and `⌃⌥⌘→`
- Block repeated overshoot input near the Space boundary
- Adjust Dock Space animation, autohide delay, and autohide animation speed, then restart Dock to apply changes
- Show the current managed Space snapshot and refresh it manually

## Download

- Download the latest packaged app from [Releases](https://github.com/OneChirpZ/MacBackroom/releases/latest)
- The release build is not code signed
- macOS may block the first launch; use Finder `Open` once, or remove the quarantine attribute manually:

```bash
xattr -dr com.apple.quarantine /Applications/MacBackroom.app
```

- Grant Accessibility permission after launch so the app can send the switching gesture

## Build From Source

```bash
git clone https://github.com/OneChirpZ/MacBackroom.git
cd MacBackroom
xcodebuild -project MacBackroom.xcodeproj -scheme MacBackroom -derivedDataPath .DerivedData build
```

- You can also open [MacBackroom.xcodeproj](./MacBackroom.xcodeproj) in Xcode and run it directly

## Notes

- macOS only
- Uses private `SkyLight` APIs and synthetic gesture events
- Not suitable for App Store distribution

## License

- [MIT License](./LICENSE)

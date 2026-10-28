# 🧩 iVidiBlocks

> A circular puzzle game for iOS, built natively with SwiftUI and SpriteKit: shards fall from the rim into a spinning well, rings close, colour arcs fuse and cascades chain towards the core.

[![Report Bug](https://img.shields.io/badge/Report-Bug-red)](https://github.com/VidiPT89/iVidiBlocks/issues)
[![Request Feature](https://img.shields.io/badge/Request-Feature-blue)](https://github.com/VidiPT89/iVidiBlocks/issues)

## ✨ Features

- ✅ A round well of 16 sectors and 8 rings around a core, with no side walls: shards circle all the way round
- ✅ The falling shard always stays at the top; moving it turns the whole well underneath
- ✅ Shards of one to three cells in three colours, dealt in bags of twelve
- ✅ Two ways to clear: close a full ring, or fuse five cells of one colour along a ring into an arc
- ✅ Cells outside a clear slide inwards and can line up into cascades; each chain link multiplies the step
- ✅ Core pulse: cleared cells charge the core, and a full charge wipes the two innermost rings
- ✅ Three modes: Orbit (endless, speeds up), Target (160 shards against the clock) and Blitz (2 minutes)
- ✅ Guided practice: six drills on prepared wells, from the first drop to chains and the pulse, with progress saved
- ✅ SpriteKit effects: ring flares, shard bursts, chain rings, the pulse shock wave and a danger vignette near the rim
- ✅ Touch gestures plus optional on-screen buttons in a left or right handed layout
- ✅ Procedurally synthesized sound effects and music, with custom Core Haptics patterns
- ✅ Animated splash screen with developer credits, then straight into the main menu
- ✅ Runtime language switch: Português (PT-PT) and English, independent of the system locale
- ✅ Dark mode, Light mode and System mode
- ✅ Colour identity taken from [ividi.dev](https://ividi.dev/): burnt orange, amber and near-black
- ✅ Local records and lifetime stats, plus an in-app how-to-play reference
- ✅ Unfinished runs are saved when you leave the app or quit to the menu, ready to continue or discard
- ✅ Accessibility: VoiceOver labels, Reduce Motion and colour-blind glyphs on every cell

## 🛠️ Tech Stack

| Category | Technology |
|----------|------------|
| Language | Swift 5.9 |
| UI | SwiftUI |
| Graphics | SpriteKit |
| Architecture | MVVM + UI-free game core |
| Audio | AVAudioEngine (synthesized, no audio files) |
| Haptics | Core Haptics |
| Project | XcodeGen |
| Min. iOS | 17.0 |

## 🚀 Quick Start

### Prerequisites

- macOS with Xcode 15+
- iOS 17+ Simulator or device

### Installation

```bash
git clone https://github.com/VidiPT89/iVidiBlocks.git
cd iVidiBlocks
open iVidiBlocks.xcodeproj
```

Build and run (`⌘R`) on the simulator or a connected device.

> The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`. If you add or move Swift files, regenerate it with `xcodegen generate`.

## 📖 Usage

1. Pick a mode: Orbit, Target or Blitz
2. Drag left and right to turn the well under the shard, tap either side of the board to turn the shard
3. Swipe down to drop it to the core
4. Close a ring, or line up five cells of one colour, to clear them
5. When the core is charged, swipe up or tap the core to fire a pulse

Language, appearance, DAS/ARR, landing guide, control layout, music and haptics are all adjustable in Settings.

## 🎮 Controls

| Input | Action |
|-------|--------|
| Drag horizontally | Turn the well left / right |
| Drag down | Fall faster |
| Swipe down | Drop to the core |
| Tap left / right side of the board | Turn the shard counter-clockwise / clockwise |
| Swipe up, or tap the core | Core pulse |

Prefer buttons? Turn on **On-screen buttons** in Settings and pick a left or right handed layout. Hold a horizontal arrow to keep turning the well using DAS/ARR. Controls wrap to two rows on narrow screens and expose VoiceOver actions. The core panel in the HUD fills as you clear and can be tapped once charged.

## 🧪 Testing

```bash
xcodebuild -project iVidiBlocks.xcodeproj -scheme iVidiBlocks \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Earlier reviews of the previous falling-block ruleset: [2026-10-28 gameplay review](docs/2026-10-28-gameplay-review.md) and [2026-10-27 audit](docs/2026-10-27-audit.md).

## 📄 License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.

## 👨‍💻 Author

**David Arsénio Martins**

- 🌐 Website: [ividi.dev](https://ividi.dev/)
- 🐙 GitHub: [@VidiPT89](https://github.com/VidiPT89/)

## 🤝 Contributing

Contributions, issues and feature requests are welcome. Feel free to check the [issues page](https://github.com/VidiPT89/iVidiBlocks/issues).

---

<p align="center">Developed by <a href="https://ividi.dev">David Arsénio Martins</a></p>
<p align="center">⭐ If you like this project, give it a star!</p>

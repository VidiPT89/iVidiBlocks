# 🧩 iTetris

> The classic falling-block puzzle game, natively reimagined for iOS with SwiftUI and SpriteKit.

[![Report Bug](https://img.shields.io/badge/Report-Bug-red)](https://github.com/VidiPT89/iTetris/issues)
[![Request Feature](https://img.shields.io/badge/Request-Feature-blue)](https://github.com/VidiPT89/iTetris/issues)

## ✨ Features

- ✅ Modern guideline rules — Super Rotation System (SRS) with full wall kicks and a 7-bag randomizer
- ✅ Hold slot, next-piece preview queue and a toggleable ghost piece
- ✅ Lock delay with move reset, plus configurable DAS and ARR for competitive-feeling controls
- ✅ T-spin and T-spin mini detection, Back-to-Back bonus, combo chain and Perfect Clear
- ✅ Three game modes — Marathon, Sprint (40 lines) and Ultra (3 minutes)
- ✅ 20 speed levels with progressive gravity and a danger vignette when the stack gets high
- ✅ Fluid SpriteKit effects — hard-drop trails, line-clear particles, screen shake, spin rings and level-up flashes
- ✅ Touch gestures plus optional on-screen buttons in a left or right handed layout
- ✅ Procedurally synthesized sound effects and music, with custom Core Haptics patterns
- ✅ Animated splash screen with developer credits, then straight into the main menu
- ✅ Runtime language switch — Português (PT-PT) and English, independent of the system locale
- ✅ Dark mode, Light mode and System mode
- ✅ Colour identity taken from [ividi.dev](https://ividi.dev/) — burnt orange, amber and near-black
- ✅ Local records and lifetime stats, plus an in-app how-to-play reference
- ✅ Accessibility: VoiceOver labels, Reduce Motion and a colour-blind friendly mode

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
git clone https://github.com/VidiPT89/iTetris.git
cd iTetris
open iTetris.xcodeproj
```

Build and run (`⌘R`) on the simulator or a connected device.

> The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`. If you add or move Swift files, regenerate it with `xcodegen generate`.

## 📖 Usage

1. Pick a mode: Marathon, Sprint or Ultra
2. Drag left and right to move, tap either side of the board to rotate
3. Swipe down for a hard drop, swipe up to hold the current piece
4. Clear four lines at once for a Tetris, or rotate a T piece into a tight gap for a T-spin
5. Chain hard clears back to back for a 1.5× score bonus

Language, appearance, DAS/ARR, ghost piece, control layout, music and haptics are all adjustable in Settings.

## 🎮 Controls

| Input | Action |
|-------|--------|
| Drag horizontally | Move left / right |
| Drag down | Soft drop |
| Swipe down | Hard drop |
| Tap left / right side of the board | Rotate counter-clockwise / clockwise |
| Swipe up | Hold |

Prefer buttons? Turn on **On-screen buttons** in Settings and pick a left or right handed layout.

## 🧪 Testing

```bash
xcodebuild -project iTetris.xcodeproj -scheme iTetris \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## 📄 License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.

## 👨‍💻 Author

**David Arsénio Martins**

- 🌐 Website: [ividi.dev](https://ividi.dev/)
- 🐙 GitHub: [@VidiPT89](https://github.com/VidiPT89/)

## 🤝 Contributing

Contributions, issues and feature requests are welcome. Feel free to check the [issues page](https://github.com/VidiPT89/iTetris/issues).

---

<p align="center">Developed by <a href="https://ividi.dev">David Arsénio Martins</a></p>
<p align="center">⭐ If you like this project, give it a star!</p>

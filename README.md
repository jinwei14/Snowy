# Snowy 360 eCoach ❄️

**Real-time AI snowboard coach powered by Insta360 X5 + GitHub Models API.**

<p align="center">
  <img src="https://img.shields.io/badge/platform-iOS_17+-blue" alt="Platform">
  <img src="https://img.shields.io/badge/language-Swift-orange" alt="Language">
  <img src="https://img.shields.io/badge/AI-GPT--4.1--mini-green" alt="AI Model">
  <img src="https://img.shields.io/badge/camera-Insta360_X5-purple" alt="Camera">
</p>

Snowy turns your **Insta360 X5** into a personal AI snowboard coach. Mount the camera on your helmet or selfie stick, hit the slopes, and get **real-time voice feedback** on your technique — carving vs skidding, edge timing, body posture, and more.

## How It Works

```
Insta360 X5 ──WiFi Direct──► iPhone App ──4G/5G──► GitHub Models API
                                │                        │
                          Frame capture            GPT-4.1-mini
                          (every 3s,              (streaming SSE)
                           smart sampling)              │
                                │                       │
                                ◄───── Voice feedback ──┘
                                  AVSpeechSynthesizer
                                  → 骨传导耳机 🔊
```

1. **Connect** your Insta360 X5 via WiFi Direct  
2. **Choose** mount mode — helmet 🪖, handheld 🤳, or third-person 🎬  
3. **Ride** — AI analyzes frames in real-time and coaches via voice  
4. **Talk back** — ask questions through your headset mic  
5. **Review** — get a detailed AI training report after each session  

## Key Features

| Feature | Description |
|---------|-------------|
| 🎯 **Real-time coaching** | Voice feedback in < 3 seconds from action to audio |
| 📹 **Reference comparison** | Upload pro videos — AI tells you the gap between you and the pros |
| 🧠 **Smart sampling** | Motion detection via CoreMotion — only analyzes during turns, saving ~60% API calls |
| 🗣️ **Voice conversation** | Ask the AI coach questions mid-ride |
| 📊 **Session reports** | Post-session GPT-4o deep analysis with technical scores |
| 🔇 **On-device TTS** | Zero-latency speech via Apple AVSpeechSynthesizer |

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Mobile | Swift / SwiftUI (iOS 17+) |
| Camera | Insta360 X5 (iOS SDK V1.9.2) |
| AI (real-time) | GitHub Models API → GPT-4.1-mini (streaming) |
| AI (analysis) | GitHub Models API → GPT-4o |
| Voice out | Apple AVSpeechSynthesizer (on-device, Chinese) |
| Voice in | Apple SFSpeechRecognizer (on-device STT) |
| Motion | CoreMotion (accelerometer + gyroscope) |

## Project Structure

```
├── DESIGN.md                    # Full technical design document
├── MARKET_ANALYSIS.md           # Market research & business analysis
└── Snowy360eCoach/              # iOS source code
    ├── App/                     # Entry point & dependency container
    ├── Models/                  # Data models & persistence
    ├── Services/                # Camera, AI, Voice, Motion services
    ├── Views/                   # SwiftUI screens
    ├── Utilities/               # Image compression, config
    └── Resources/               # System prompts (Chinese)
```

## Getting Started

1. **Apply** for [Insta360 SDK access](https://www.insta360.com/sdk/apply)
2. **Create** an Xcode project and add the SDK + source files  
3. **Set** your GitHub PAT (`models:read` scope) as `GITHUB_TOKEN` env variable  
4. **Build & run** on a physical iPhone with an Insta360 X5 connected  

See [Snowy360eCoach/README.md](Snowy360eCoach/README.md) for detailed setup instructions.

## License

This project is for personal/educational use.

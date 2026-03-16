# Snowy 360 eCoach — iOS App

AI-powered real-time snowboard coach using Insta360 X5 and GitHub Models API.

## Project Structure

```
Snowy360eCoach/
├── App/
│   └── SnowyApp.swift              # App entry point + dependency container
├── Models/
│   ├── Models.swift                 # Core data models (mount modes, enums, reference video types)
│   └── TrainingSession.swift        # Training session model + persistence
├── Services/
│   ├── CameraService.swift          # Insta360 X5 SDK wrapper (connection, preview, frame capture)
│   ├── AICoachingService.swift      # GitHub Models API client (streaming vision analysis)
│   ├── VoiceService.swift           # TTS (AVSpeechSynthesizer) + STT (SFSpeechRecognizer)
│   ├── MotionDetectionService.swift # Smart sampling via CoreMotion (accelerometer + gyro)
│   ├── TrainingSessionManager.swift # Central orchestrator: camera → AI → voice pipeline
│   └── ReferenceVideoManager.swift  # Reference video upload, storage, AI pre-analysis
├── Views/
│   ├── HomeView.swift               # Main screen — connect camera, start training
│   ├── MountModeSelectionView.swift  # Choose helmet / handheld / third-person
│   ├── TrainingView.swift           # Active training — preview, feedback, voice controls
│   ├── TrainingSummaryView.swift    # Post-session AI analysis report
│   ├── ReferenceVideoListView.swift # Manage reference videos + trigger analysis
│   └── TrainingHistoryView.swift    # Past sessions + detailed review
├── Utilities/
│   ├── ImageCompressor.swift        # Frame resize (512px) + JPEG Q60 compression
│   └── AppConfig.swift              # Centralized configuration constants
├── Resources/
│   └── SystemPrompts.swift          # Chinese coaching prompts (mount-mode aware)
└── Info.plist                       # Privacy permissions (camera, mic, speech, motion, photos, network)
```

## Prerequisites

1. **Xcode 15+** with iOS 17 SDK
2. **Insta360 iOS SDK V1.9.2** — Apply at https://www.insta360.com/sdk/apply
3. **GitHub PAT** with `models:read` scope (Copilot Enterprise recommended)
4. **Insta360 X5** camera
5. **iPhone** with 4G/5G connectivity

## Setup

### 1. Create Xcode Project

1. Open Xcode → File → New → Project → iOS App
2. Product Name: `Snowy360eCoach`
3. Interface: **SwiftUI**, Language: **Swift**
4. Copy all source files from this directory into the project

### 2. Add Insta360 SDK

1. Apply for SDK access at https://www.insta360.com/sdk/apply
2. Download the iOS SDK V1.9.2
3. Add the framework to your Xcode project (drag into Frameworks folder)
4. Remove the `#if !canImport(INSCameraSDK)` placeholder block in `CameraService.swift`
5. Add `import INSCameraSDK` at the top of `CameraService.swift`

### 3. Configure GitHub Token

Set your GitHub PAT as an environment variable or in Keychain:

```bash
# For development — set in Xcode scheme environment variables:
GITHUB_TOKEN=ghp_your_token_here
```

For production, store the token in iOS Keychain and update `AppConfig.githubToken`.

### 4. Required Capabilities

In Xcode → Target → Signing & Capabilities:
- **Wireless Accessory Configuration** (for Insta360 WiFi Direct)
- **Background Modes** → Audio (for TTS during background)

## Architecture

```
┌───────────────┐   WiFi Direct    ┌─────────────────────────────────────┐
│  Insta360 X5  │ ──────────────► │          iPhone App                  │
│  (helmet/     │   H.264 stream  │                                      │
│   handheld)   │                  │  CameraService → FrameCapture       │
└───────────────┘                  │       │                              │
                                   │       ▼ (every 3s, smart sampling)  │
                                   │  ImageCompressor (512px, Q60)       │
                                   │       │                              │
                                   │       ▼                              │
                                   │  AICoachingService ──► GitHub Models │
                                   │  (GPT-4.1-mini, streaming SSE)      │
                                   │       │                              │
                                   │       ▼ (tokens as they arrive)     │
                                   │  VoiceService.feedStreamingToken()  │
                                   │  → AVSpeechSynthesizer              │
                                   │  → 骨传导耳机 🔊                     │
                                   └─────────────────────────────────────┘
```

## Key Design Decisions

| Decision | Implementation |
|----------|---------------|
| **Latency < 3s** | Streaming SSE + on-device TTS + 512px frames + pipeline overlap |
| **Smart Sampling** | CoreMotion detects turns → only analyze during active turns (~60% fewer API calls) |
| **Mount-Aware AI** | System prompt changes based on helmet/handheld/third-person mode |
| **Reference Comparison** | GPT-4o pre-analyzes reference videos → ReferenceProfile injected into real-time prompt |
| **Angle Matching (V1)** | Only compare when reference video and live stream use same camera angle |
| **Rate Limits** | Enterprise: 20 req/min, 450/day for GPT-4.1-mini — fits smart sampling at 1 session/day |

## API Usage

All AI calls go through GitHub Models API:
- **Endpoint:** `https://models.github.ai/inference/chat/completions`
- **Real-time coaching:** `openai/gpt-4.1-mini` (streaming)
- **Post-session analysis:** `openai/gpt-4o` (non-streaming)
- **Auth:** `Authorization: Bearer <GITHUB_PAT>`

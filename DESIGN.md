# Snowy 360 eCoach — Design Document

> **Decisions locked in:** Insta360 X5 · iOS first (Swift native) · Chinese coaching · Latency-first (target < 3 sec) · GitHub Models API (Copilot)

---

## 1. Vision

一个移动应用，将 **Insta360 X5**（安装在头盔上）变成 **实时 AI 单板滑雪教练**。摄像头实时传输视频到手机，AI 模型分析姿态、刃控和动作模式，通过**语音**给出指导建议——全程在雪道上完成。骑手还可以**对话回应**，提问或请求特定反馈。

A mobile app that turns an **Insta360 X5** (helmet-mounted) into a **real-time AI snowboard coach**. The camera streams live video to the rider's phone; an AI model analyzes posture, edge control, and movement; and coaching cues are delivered via **voice** — all on the slope. The rider can **talk back** to ask questions.

**Core value:** 不只是替代对讲机教练，而是比人类教练更强——让你能和高手做「逐帧对比」。

1. **实时教练**：滑行中即时告诉你刻滑还是扫雪，姿态哪里不对 
2. **参考对比**：上传高手视频（如八字刻滑），AI 自动分析并告诉你与高手的差距——入刃时机、折叠程度、立刃角度、旋转是否到位
3. **角度补偿**：Insta360 全景角度与教学视频角度不同，AI 自动识别差异并桥接分析

---

## 2. Confirmed Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Camera** | Insta360 X5 | User owns it. SDK V1.9.2 confirmed X5 support. |
| **Platform** | iOS first (native Swift) | Insta360 iOS SDK is Obj-C/Swift. Native = fastest SDK integration + best Core ML performance for on-device processing. Android later. |
| **Language** | 中文 (Chinese) first | Primary user base. Multilingual later. |
| **Latency target** | < 3 seconds end-to-end | From action → voice feedback. This is the #1 engineering constraint. |
| **AI API** | GitHub Models API | Copilot Enterprise (unlimited). Uses `models.github.ai` endpoint. OpenAI-compatible. |
| **Copilot Plan** | Enterprise (unlimited) | Best free-tier rate limits. Can opt in to paid usage for production-grade limits. |
| **Budget** | Not a constraint now | Optimize for speed, not cost. |

---

## 3. User Flow

```
┌───────────────┐   WiFi Direct    ┌────────────────┐
│  Insta360 X5  │ ──────────────► │   iPhone App    │
│ (头盔/手持)    │   H.264 stream  │  (Swift native) │
└───────────────┘                  └───────┬────────┘
                                           │
                              ┌────────────┼────────────┐
                              │            │            │
                              ▼            ▼            ▼
                     Frame Sampler   Voice Input    Session
                     (每 1-2 秒)     (STT mic)     Recorder
                              │            │
                              ▼            ▼
                     ┌─────────────────────────┐
                     │   AI Vision + Coaching   │
                     │  GitHub Models API       │
                     │  (GPT-4o / GPT-4.1)     │
                     │  streaming response      │
                     └────────────┬────────────┘
                                  │
                                  ▼
                         TTS → 骨传导耳机
                         "弯膝盖！你在扫雪，
                          加大脚踝压力立刃！"
```

**Steps:**

1. 骑手将 X5 安装在头盔上或手持自拍杆，打开 App，点击 **“连接相机”**
2. App 通过 Insta360 SDK 连接相机（WiFi Direct）
3. 选择安装方式：**“头盔安装”** 或 **“手持自拍杆”**
4. 点击 **“开始训练”** — 实时预览 + AI 教练启动
4. 每 1-2 秒抓取关键帧 → 发送 AI 分析 → 语音反馈
5. 骑手可通过耳机麦克风对话提问
6. 点击 **"结束训练"** — 保存录像 + AI 训练总结

---

## 4. Architecture — Latency-First Design

### 4.1 The Latency Problem (Most Critical)

You want feedback in < 3 seconds from when an action happens. Let's be brutally honest about the budget:

| Step | Cloud Path | Optimized Path |
|------|-----------|----------------|
| Frame capture + encode | 50 ms | 50 ms |
| Network upload (4G) | 300–800 ms | 200 ms (tiny image) |
| AI inference | 1–3 sec (GPT-4o) | 0.8–1.5 sec (GPT-4.1-mini / streaming via GitHub Models) |
| TTS generation | 300–500 ms | 0 ms (on-device TTS) |
| Audio playback | 50 ms | 50 ms |
| **Total** | **2–5 sec** ❌ | **~1–2 sec** ✅ |

### 4.2 Latency Optimization Strategy (How We Get to < 3 sec)

**Layer 1: On-Device TTS (saves 300–500 ms)**
- Use **Apple AVSpeechSynthesizer** (built-in, zero network latency, supports Chinese)
- The AI returns text → instantly spoken by on-device TTS
- No round-trip to a TTS API

**Layer 2: Streaming AI Response (saves 1–2 sec)**
- Use **streaming API** (SSE / Server-Sent Events) — don't wait for full response
- AI starts writing "弯膝盖" → TTS starts speaking the first word immediately
- By the time the full sentence arrives, TTS is already halfway done

**Layer 3: Use Fastest Vision Model via GitHub Models API**
- All models accessed through a single endpoint: `https://models.github.ai/inference/chat/completions`
- **GPT-4.1-mini** or **GPT-4o-mini**: fastest vision-capable models available on GitHub Models
- **GPT-4o** / **GPT-4.1**: higher quality but slower. Use for post-session analysis or complex questions.
- Auth with your GitHub PAT (Personal Access Token) — no separate OpenAI/Google API keys needed
- Test multiple models via the same API by just changing the `model` field

**Layer 4: Aggressive Image Compression**
- Resize preview frame to **512×256** JPEG quality 60 — tiny upload size (~30–50 KB)
- At 4G speeds, 50 KB uploads in ~100 ms
- The AI only needs to see body position and snow spray, not pixel-perfect detail

**Layer 5: Pipeline Overlap**
- While frame N is being analyzed, frame N+1 is already being captured
- The pipeline never waits — always analyzing the most recent frame
- Drop stale frames: if frame N's result arrives after frame N+2 is sent, discard N's result

**Layer 6: Smart Sampling — Only Analyze When Something Happens**
- Use on-device **motion detection** (Core Motion accelerometer data from iPhone, or gyro data from Insta360 SDK's `INSCameraSessionGyroDelegate`)
- Detect turn initiation, edge change, speed change
- Only send frames during active turns, not during straight runs or standing still
- This reduces API calls by ~60% and focuses feedback where it matters

```
┌─────────────────────────────────────────────────────────┐
│                    OPTIMIZED PIPELINE                     │
│                                                           │
│  Frame ──► Resize 512px ──► JPEG Q60 ──► GitHub Models  │
│  (50ms)     (10ms)           (10ms)   GPT-4.1-mini (1s)  │
│                                              │            │
│                                    first token arrives    │
│                                              │            │
│                                    AVSpeechSynthesizer   │
│                                         starts (0ms)     │
│                                              │            │
│                              🔊 "你在扫雪！立刃！"         │
│                                                           │
│  Total: ~1.2–2.5 sec from frame capture to voice start   │
└─────────────────────────────────────────────────────────┘
```

### 4.3 GitHub Models Rate Limits (Copilot Enterprise)

Your **Enterprise** plan gives the best free-tier limits:

| Tier | Requests/min | Requests/day | Tokens/request | Concurrent |
|------|-------------|-------------|----------------|------------|
| **Low models** (GPT-4o-mini, GPT-4.1-mini) | **20** | **450** | 8K in / **8K out** | 8 |
| **High models** (GPT-4o, GPT-4.1) | **15** | **150** | **16K in / 8K out** | 4 |
| **o1-mini, o3-mini, o4-mini** | 3 | 20 | 4K in / 4K out | 1 |

**The math for real-time coaching:**

| Scenario | Requests/session (30 min) | Fits in 450/day? | Coaching quality |
|----------|--------------------------|-------------------|------------------|
| 1 frame / 2 sec (aggressive) | 900 | ❌ No | Excellent |
| 1 frame / 5 sec | 360 | ✅ Yes (just barely) | Good |
| Smart sampling (turns only) | ~100–200 | ✅ Yes, comfortable | Good — focused on key moments |
| Smart + burst during turns | ~150–250 | ✅ Yes | Best — fast during turns, quiet on straights |

**Good news:** With Enterprise, **smart sampling + 1 session/day fits comfortably** within free limits.

**Strategy:**

1. **Phase 1 (prototyping):** Use GPT-4.1-mini at 1 frame/5 sec. 360 req/session fits in 450/day. Good enough to test the concept.
2. **Phase 2 (production):** Smart sampling — only analyze during detected turns. ~150–250 req/session. Room for 2+ sessions/day.
3. **Scale up:** If you need more sessions/day or faster frame rate, your org admin can **opt in to paid GitHub Models usage** → rate limits become Azure Foundry production-grade (essentially unlimited, pay-per-token).

**Rate limit per minute is fine:** 20 req/min for low models means we can comfortably send 1 frame every 3 seconds (= 20/min) with no throttling.

**Key advantage of Enterprise:** 16K input tokens for high-tier models means we can send **multiple frames + conversation history** in a single request — rich context for the AI.

### 4.4 Future: On-Device Vision (V2 — Sub-1-sec)

For truly instant feedback, the dream is **on-device inference**:
- **Apple Core ML** can run vision models locally on iPhone 15 Pro+ (Neural Engine)
- Train a custom lightweight classifier: "carving vs skidding vs stopping vs straight"
- ~50ms inference time = essentially instant
- Use the cloud LLM (GitHub Models) only for conversational coaching / detailed technique advice
- This is V2. For V1, cloud streaming is good enough at ~1.5–2.5 sec.

### 4.5 ⚠️ Important Reality Check on "3 ms"

I want to clarify: **3 milliseconds** is physically impossible — that's faster than a single video frame (1 frame at 30fps = 33ms). Even on-device neural network inference takes 50–200ms. I believe you mean **< 3 seconds**, which is achievable with the optimized pipeline above. If you truly need sub-second, we need on-device models (V2).

---

## 5. Insta360 X5 SDK Integration (Detailed)

### 5.1 How to Get the SDK — Registration Steps

**You need to apply for SDK access. Here's the process:**

1. **Go to:** https://www.insta360.com/sdk/apply
2. **Fill out the application form** — you'll need:
   - Your name / company name
   - App description (describe Snowy eCoach — AI snowboard coaching app)
   - Which camera model (Insta360 X5)
   - Which platform (iOS)
   - Your contact email
3. **Wait for approval** — typically 1–3 business days
4. **Once approved**, go to https://www.insta360.com/sdk/record → download the iOS SDK (V1.9.2)
5. You'll also receive an **App ID** and **Secret** — needed for camera activation in code

**Developer resources:**
- Developer home: https://www.insta360.com/developer/home
- iOS SDK repo (README/docs): https://github.com/Insta360Develop/iOS-SDK
- Integration guide: https://onlinemanual.insta360.com/developer/en-us/resource/integration
- SDK guide: https://onlinemanual.insta360.com/developer/en-us/resource/sdk
- Bug reports: https://insta.jinshuju.com/f/hZ4aMW

### 5.2 SDK Capabilities Confirmed for X5

From the iOS SDK V1.9.2 README (confirmed X5 support):

| Feature | Supported | Notes |
|---------|-----------|-------|
| WiFi connection | ✅ | `INSCameraManager.socket().setup()` |
| BLE connection | ✅ | Limited — no preview, no large data transfer |
| **Live Preview** | ✅ | H.264 decoded stream via `INSCameraSessionPlayer` |
| **Gyro/IMU data** | ✅ | `INSCameraSessionGyroDelegate` — real-time stabilization data during preview |
| Photo capture | ✅ | `takePicture` — can grab a snapshot frame |
| Video recording | ✅ | Start/stop recording |
| Camera settings | ✅ | Resolution, exposure, white balance, etc. |
| File download | ✅ | Download recorded files |
| Heartbeat | Required | Must send every 0.5s or camera disconnects after 30s |
| In-camera stitching | ✅ | X5 supports — means we get equirectangular frames directly |
| Camera shutdown | ✅ | X5 only — `closeCamera` |
| Screen lock | ✅ | X5 only — lock screen during session to save battery |

### 5.3 Key Integration Code Patterns

**Connection:**
```swift
// Connect via WiFi
INSCameraManager.socket().setup()

// Check state
if INSCameraManager.socket().cameraState == .connected {
    // Ready
}

// CRITICAL: Send heartbeats every 0.5s or camera disconnects!
GCDTimer.shared.scheduledDispatchTimer(
    WithTimerName: "HeartbeatsTimer",
    timeInterval: 0.5,
    queue: DispatchQueue.main,
    repeats: true
) {
    INSCameraManager.shared().commandManager.sendHeartbeats(with: nil)
}
```

**Live Preview Setup:**
```swift
// Create preview player
let player = INSCameraSessionPlayer()
player.delegate = self
player.dataSource = self
player.render.renderModelType.displayType = .sphereStitch  // 360° stitched view

// Add render view to UI
if let view = player.renderView {
    self.view.addSubview(view)
}

// Configure H.264 decoder
let config = INSH264DecoderConfig()
config.shouldReloadDecoder = false
config.decodeErrorMaxCount = 30
self.mediaSession.setDecoderConfig(config)
```

**Gyro Data (for smart motion detection):**
```swift
// Implement INSCameraSessionGyroDelegate
func onParsedGyroData(_ gyroItems: [INSGyroRawItem], timestampMs: Int64) {
    // Use this to detect turns, edge changes, speed
    // Only send frames to AI when motion is interesting
}
```

**Frame Capture Strategy:**
The SDK doesn't expose raw frame buffers directly. Options:
1. **Snapshot approach:** Call `takePicture` periodically (but has shutter lag)
2. **Preview render capture:** Use `UIView.drawHierarchy` or `CALayer.render` to screenshot the preview view
3. **Best option:** Use the preview stream's decoded callback — if accessible via `INSCameraMediaSession` hooks, we can intercept the decoded H.264 frame as a `CVPixelBuffer` before it hits the render view

**Camera Activation (required first time):**
```swift
// You need the App ID and Secret from Insta360 developer registration
INSCameraActivateManager.setAppid("YOUR_APP_ID", secret: "YOUR_SECRET")
INSCameraActivateManager.share().activateCamera(
    withSerial: serialNumber,
    commandManager: INSCameraManager.shared().commandManager
) { deviceInfo, error in
    // Camera activated
}
```

### 5.4 X5 Screen Lock (Save Camera Battery During Session)

The X5 supports locking the camera screen during our session, which saves battery:
```swift
// Lock camera screen during session
INSCameraManager.shared().commandManager.setAppAccessFileState(.liveView) { _ in }

// Unlock when done
INSCameraManager.shared().commandManager.setAppAccessFileState(.idle) { _ in }
```

---

## 6. AI Coaching — Model & Prompt Design

### 6.1 Model Selection (via GitHub Models API)

All models accessed through: `https://models.github.ai/inference/chat/completions`
Auth: GitHub PAT with `models:read` scope.

| Model | Model ID | Speed | Quality | Vision | Recommendation |
|-------|----------|-------|---------|--------|----------------|
| **GPT-4.1-mini** | `openai/gpt-4.1-mini` | ~0.8–1.5 sec | Good | ✅ | **Primary — fastest vision model** |
| **GPT-4o-mini** | `openai/gpt-4o-mini` | ~0.8–1.5 sec | Good | ✅ | Alternative fast option |
| **GPT-4o** | `openai/gpt-4o` | ~2–3 sec | Excellent | ✅ | Post-session analysis, complex questions |
| **GPT-4.1** | `openai/gpt-4.1` | ~2–3 sec | Excellent | ✅ | Alternative to GPT-4o |

**Decision:** Use **GPT-4.1-mini** for real-time coaching (speed + low rate-limit tier). Use **GPT-4o** for post-session analysis.

### 6.2 Multi-Frame Context Window

Instead of sending isolated frames, send **3 frames** with timestamps to show motion:

```
Frame 1 (t=0s): [image] — 入弯前
Frame 2 (t=1s): [image] — 弯中
Frame 3 (t=2s): [image] — 出弯后

分析这三帧，告诉骑手这个弯做得如何。
```

This gives the AI a sense of **motion direction** and **technique progression** through a turn, solving the single-frame limitation.

### 6.3 Reference Video Library & Gap Analysis (参考视频库 + 差距分析)

这是本产品的**核心差异化功能**——不只是告诉你“你在扫雪”，而是告诉你“和高手相比，你的入刃晚了0.5秒，膝盖折叠不够，立刃角度差15°”。

#### 功能流程

```
【训练前】
  用户上传参考视频 → AI 预分析 → 提取关键帧 + 技术要点
  “八字刻滑.mp4” → AI: “入刃时机、折叠角度、立刃角度、旋转幅度...”

【训练中】
  实时帧 → AI 对比参考视频 → 语音反馈差距
  🔊 “入刃晚了！参考视频里高手在板子过中线前就开始立刃”
  🔊 “折叠不够！你的膝盖角度约120°，高手是90°”
  🔊 “立刃角度不错！和参考视频很接近！”

【训练后】
  AI 生成详细对比报告:
  ├─ 你的关键帧 vs 参考视频关键帧（并排对比图）
  ├─ 各项技术指标评分（入刃时机、折叠、立刃、旋转）
  ├─ 进步趋势（如果有历史训练数据）
  └─ 下次训练重点建议
```

#### 参考视频预分析流程

用户上传视频后，AI 做一次性深度分析（用 GPT-4o，不需要实时）：

```
输入: 参考视频 (e.g., 八字刻滑教学视频)
         │
         ▼
1. 抽取关键帧 (每个弯 3-5 帧: 入弯前、入刃瞬间、弯中、出弯)
         │
         ▼
2. AI 分析每个关键帧的技术要点:
   - 入刃时机 (edge engagement timing)
   - 折叠程度 (knee/hip angulation)
   - 立刃角度 (edge angle)
   - 旋转幅度 (rotation completion)
   - 重心位置 (center of mass)
   - 肩臀分离 (shoulder-hip separation)
   - 手臂位置 (arm positioning)
         │
         ▼
3. 生成「参考模板」(ReferenceProfile)
   - 每个弯的技术参数基准值
   - 关键帧描述（文字）
   - 可选: 保存关键帧图片用于训练后对比
```

#### 角度差异补偿 (V1: 同角度策略 / V2: 跨角度智能补偿)

**V1 策略：确保参考视频和实时拍摄用同一角度，彻底消除角度差异问题。**

这是最聪明的 V1 方案——不解决角度补偿问题，而是让问题不存在：

```
参考视频(手持自拍) + 用户实时(手持自拍) = 同角度对比 ✅
参考视频(头盔)     + 用户实时(头盔)     = 同角度对比 ✅
参考视频(第三人称) + 用户实时(第三人称) = 同角度对比 ✅
参考视频(手持自拍) + 用户实时(头盔)     = 角度不同 ❌ V1 不支持
```

**V1 的视频匹配规则：**

| 用户安装方式 | 参考视频要求 | 说明 |
|------------|------------|------|
| 手持自拍杆 | 必须也是手持自拍杆拍摄 | 角度一致，AI 可以直接对比全身姿态 |
| 头盔安装 | 必须也是头盔安装拍摄 | 角度一致，AI 对比雪花模式和上半身 |
| 第三人称拍摄 | 必须也是第三人称拍摄 | 角度一致，外部视角直接对比全身 |

App 中的逻辑：
```swift
// V1: 上传参考视频时标记角度
enum VideoAngle {
    case handheld360     // 手持 360°（自拍杆）
    case helmet360       // 头盔 360°
    case thirdPerson     // 第三人称（别人拍）
}

// 开始训练时检查角度匹配
func canUseForRealtimeComparison(reference: ReferenceVideo, currentMount: CameraMountMode) -> Bool {
    switch (currentMount, reference.sourceAngle) {
    case (.handheld, .handheld360):       return true   // ✅ 同角度
    case (.helmet, .helmet360):           return true   // ✅ 同角度
    case (.thirdPerson, .thirdPerson):   return true   // ✅ 同角度
    default:                              return false  // ❌ 角度不匹配，仅训练后分析
    }
}
```

**V1 参考视频来源：** 从网上找高手滑行视频，确保和自己的拍摄角度一致。例如：
- 手持自拍杆模式：找其他用 Insta360 手持拍的刻滑视频（最容易找到，很多滑雪 UP 主用这种方式）
- 头盔模式：找其他用 GoPro/Insta360 头盔安装拍的视频
- 网络平台：小红书、B站、抖音上有大量手持 360° 滑雪视频

**V2 未来规划：** 加入跨角度智能补偿：

#### 数据模型

```swift
struct ReferenceVideo {
    let id: UUID
    let name: String                    // "八字刻滑 - 大神教学"
    let technique: TechniqueCategory    // .carving, .figure8, .turns, etc.
    let videoURL: URL                   // 本地存储
    let keyFrames: [ReferenceKeyFrame]  // AI 预分析提取的关键帧
    let profile: ReferenceProfile       // AI 生成的技术参数基准
    let sourceAngle: VideoAngle         // .handheld360, .helmet360, .thirdPerson
    let createdAt: Date
}

struct ReferenceKeyFrame {
    let timestamp: TimeInterval
    let phase: TurnPhase                // .preTurn, .edgeEngagement, .midTurn, .exitTurn
    let image: UIImage?
    let analysis: String                // AI 对这一帧的技术描述
}

struct ReferenceProfile {
    let edgeTimingDescription: String   // 入刃时机描述
    let angulationLevel: String         // 折叠程度
    let edgeAngleDescription: String    // 立刃角度
    let rotationDescription: String     // 旋转幅度
    let overallDescription: String      // 整体技术总结
    let keyPoints: [String]             // 核心技术要点列表
}

enum TechniqueCategory {
    case carving        // 刻滑
    case figure8        // 八字刻滑
    case turns          // 连续弯
    case jumps          // 跳跃
    case rails          // 道具
    case custom(String)
}

enum TurnPhase {
    case preTurn         // 入弯前
    case edgeEngagement  // 入刃瞬间
    case midTurn         // 弯中
    case exitTurn        // 出弯
}

enum VideoAngle {
    case handheld360     // 手持 360°（自拍杆）— 最常见，网上大量资源
    case helmet360       // 头盔 360°
    case thirdPerson     // 第三人称（别人拍）— 外部视角最佳，V1 支持同角度实时对比
}
```

#### 实时对比流程（训练中）

```
实时帧 + ReferenceProfile (text) → AI → 对比反馈

注意: 训练中不发送参考视频的图片，只发送预分析生成的文字描述
(ReferenceProfile)，这样不会增加 token 消耗和延迟。

API 调用示例:
messages: [
  { role: "system", content: systemPrompt + referenceProfile },
  { role: "user", content: [
      { type: "image_url", ... },  // 实时帧
      { type: "text", text: "分析这个弯，对比参考视频的技术要求" }
  ]}
]
```

### 6.4 System Prompt (Chinese, V1)

```
你是一位专业的单板滑雪教练，正在通过 Insta360 360° 摄像头实时观察骑手的动作。

【安装方式】
当前模式: {{mount_mode}}  // “头盔安装” 或 “手持自拍杆”

如果是头盔安装:
- 你能看到上半身、雪面、后方视角
- 你看不清膝盖和脚踝，需要从雪花飞溅和上半身姿态推断
- 重点关注：雪花模式、弯道形状、肩臀分离、手臂位置

如果是手持自拍杆:
- 你能看到全身姿态，包括膝盖、臀部、板刃角度
- 可以直接判断膝盖弯曲、重心位置、板刃立刃情况
- 重点关注：膝盖角度、板刃立刃、臀部高度、全身协调性

【技术知识】
- 刻滑（Carving）：雪面上的痕迹是一条细线，板子立刃，几乎没有雪花飞溅，
  S 弯流畅，身体低重心，角度倾斜（angulation），肩膀与板子方向一致
- 扫雪（Skidding）：大量雪花飞溅，板子平放或微微立刃，在雪面上刮擦，
  速度控制差，弯道半径大
- 常见错误：后坐（重心在后脚）、腿部僵硬、反向旋转（counter-rotation）、
  手臂乱甩、低头看脚下而不是看前方
- 进阶要点：前膝引导入弯、肩臀分离、脚踝压力控制立刃角度、
  重心前后转移、身体倾角与速度匹配

【输出规则】
- 用中文回答
- 保持极短："弯膝盖！" "好的刻滑！保持！" "你在扫雪——脚踝加压立刃！"
- 如果看不清，说"这个角度看不太清"而不是瞎猜
- 如果骑手在直线滑行或静止，可以说"准备好了吗？下一个弯注意立刃"
- 发现好的动作一定要表扬！正向反馈很重要
【参考视频对比模式】
{{#if reference_profile}}
当前已加载参考视频: {{reference_name}}
参考技术基准:
{{reference_profile}}

对比规则:
- 将骑手的动作与参考基准对比，指出具体差距
- 用“参考视频里...”开头给出对比反馈
- 例如: “入刃晚了！参考视频里高手在板子过中线前就立刃”
- 例如: “折叠不够！你膝盖约120°，高手是90°”
- 如果某项做得好，也要说: “立刃角度不错！和参考很接近！”
- 参考视频和实时拍摄使用相同角度，可以直接对比姿态和动作
{{/if}}```

---

## 7. Tech Stack (Confirmed)

| Layer | Choice | Rationale |
|-------|--------|-----------|
| **Mobile** | **Swift (native iOS)** | Insta360 SDK is Obj-C/Swift native. No bridging overhead. Best Core ML / AVFoundation performance. |
| **Camera SDK** | Insta360 iOS SDK V1.9.2 | Official, confirmed X5 support |
| **AI Vision (real-time)** | GitHub Models API → GPT-4.1-mini (streaming) | Fastest vision model, no separate API key, included with Copilot |
| **AI Vision (detailed)** | GitHub Models API → GPT-4o | Post-session analysis, complex questions |
| **TTS** | Apple AVSpeechSynthesizer | On-device, zero latency, supports Chinese |
| **STT** | Apple Speech Framework (on-device) | On-device, low latency, works offline |
| **Backend** | Firebase (Auth + Firestore + Storage) | Fast to set up, stores sessions |
| **Networking** | URLSession + SSE streaming | Native, lightweight, supports streaming responses |
| **AI Auth** | GitHub PAT (models:read scope) | No separate OpenAI/Google API keys needed |

**Why native Swift instead of React Native / Flutter:**
1. Insta360 SDK is already Obj-C/Swift — no bridging = faster development + fewer bugs
2. Core ML / Vision framework for future on-device analysis
3. AVSpeechSynthesizer / Speech framework are first-class Swift APIs
4. Better memory management for continuous video processing
5. When we add Android later, we build a separate Kotlin app (Insta360 has separate Android SDK anyway)

### GitHub Models API — iOS Integration Example

```swift
import Foundation

struct GitHubModelsClient {
    let endpoint = URL(string: "https://models.github.ai/inference/chat/completions")!
    let token: String  // GitHub PAT with models:read scope
    
    /// Send a frame to the AI for coaching analysis (streaming)
    func analyzeFrame(imageBase64: String, systemPrompt: String) async throws -> AsyncStream<String> {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        
        let body: [String: Any] = [
            "model": "openai/gpt-4.1-mini",  // Fast vision model
            "stream": true,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "image_url", "image_url": [
                        "url": "data:image/jpeg;base64,\(imageBase64)"
                    ]],
                    ["type": "text", "text": "分析这一帧，给出教练建议。"]
                ]]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        // Stream the response — start TTS as soon as first token arrives
        let (bytes, _) = try await URLSession.shared.bytes(for: request)
        return AsyncStream { continuation in
            Task {
                for try await line in bytes.lines {
                    if line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let delta = choices.first?["delta"] as? [String: Any],
                       let content = delta["content"] as? String {
                        continuation.yield(content)
                    }
                }
                continuation.finish()
            }
        }
    }
}
```

**Key points:**
- OpenAI-compatible format — same `chat/completions` structure
- Vision via `image_url` with base64 data URI
- Streaming via SSE (`stream: true`)
- Switch models by changing the `"model"` field (e.g., `"openai/gpt-4o"` for detailed analysis)
- Auth is just your GitHub PAT — no OpenAI/Google API key management

---

## 8. Voice I/O Design

### 8.1 TTS — Coach Voice Output

```swift
import AVFoundation

let synthesizer = AVSpeechSynthesizer()

func speakCoaching(_ text: String) {
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.2  // Slightly faster
    utterance.volume = 1.0
    synthesizer.speak(utterance)
}
```

**Streaming TTS playback:** As the AI streams tokens back, we accumulate until a sentence boundary (。！？) and speak each sentence immediately. Don't wait for the full response.

### 8.2 STT — Rider Voice Input

```swift
import Speech

// On-device recognition — no network required
let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
// Use push-to-talk via AirPods tap gesture or on-screen button
```

### 8.3 Audio Hardware Recommendation

| Device | Pros | Cons |
|--------|------|------|
| **骨传导耳机 (Shokz OpenRun)** | 不堵耳朵，能听到环境音，安全 | 风噪下麦克风效果一般 |
| **AirPods Pro** | 降噪好，麦克风质量高，支持手势 | 堵耳朵，不安全 |
| **Recommendation** | **骨传导耳机 + 按键对讲** | 安全第一，用按键替代语音输入 |

---

## 9. Camera Mounting & What AI Can See

支持三种安装方式，用户在 App 中选择当前模式，AI 会根据模式调整分析策略。

### 9.1 模式 A：头盔顶部安装（Helmet Mount）

```
        📷 X5 (360°)
        ┌───┐
        │ ○ │  ← 头盔顶部
    ┌───┴───┴───┐
    │   骑手    │
    │  (从上往下看) │
    └─────┬─────┘
          │
       ╔══╧══╗
       ║板子 ║
       ╚═════╝
```

**适用场景：** 独自练习，无人帮忙拍摄

| 能看到 ✅ | 看不清 ❌ |
|---------|----------|
| 肩膀位置和旋转 | 膝盖弯曲角度 |
| 手臂位置和动作 | 脚踝压力细节 |
| 头部朝向（看前方 vs 低头） | 脚部/板刃特写 |
| 雪面痕迹（刻滑 vs 扫雪关键指标） | 臀部高度（部分遮挡） |
| 雪花飞溅模式 | 前膝引导动作 |
| 弯道形状和半径 | |
| 行进速度（透视变化推断） | |
| 身体倾斜角度 | |
| 后方视角：背部、臀部旋转（360°） | |

**AI 分析策略（头盔模式）：**
- 重点关注：雪花飞溅模式、弯道形状、上半身姿态
- 360° 后视角分析肩臀分离
- 推荐发送 3 个视角：前方 + 下方 + 后方

### 9.2 模式 B：手持自拍杆安装（Handheld / Selfie Stick Mount）

```
    ┌───┐
    │ ○ │ 📷 X5 (360°)
    └─┬─┘
      │  自拍杆 (隐形)
      │
  ┌───┴───┐
  │  骑手  │  ← 全身可见！
  │       │
  ├───────┤
  │  膝盖  │
  ├───────┤
  │  板子  │
  └───────┘
```

**适用场景：** 单手持杆滑行（Insta360 自拍杆在 360° 视频中自动隐形）

| 能看到 ✅ | 看不清 ❌ |
|---------|----------|
| **全身姿态**（最大优势！） | 手持侧手臂动作受限 |
| **膝盖弯曲角度** | 持杆手的自然摆动 |
| **臀部高度和位置** | |
| **板刃角度**（更清晰） | |
| 肩膀旋转和对齐 | |
| 身体重心前后位置 | |
| 雪面痕迹和雪花飞溅 | |
| 弯道形状 | |
| 脚踝弯曲（部分可见） | |

**AI 分析策略（手持模式）：**
- **优势巨大**：能看到全身，技术分析更准确
- 重点关注：膝盖弯曲、臀部高度、板刃角度、重心位置
- 可以更精确判断 刻滑 vs 扫雪（直接看板刃 + 雪花）
- 推荐发送 2 个视角：正面全身 + 侧面/后方全身

### 9.3 模式 C：第三人称拍摄（Third-Person Filming）

```
                              📷 X5 (360°)
                              ┌───┐
                              │ ○ │  ← 朋友手持 / 三脚架
                              └─┬─┘
                                │  自拍杆
                                │
                           ┌────┴────┐
                           │  朋友    │
                           └─────────┘
         ← 5-15m →
  ┌───────────┐
  │   骑手    │  ← 完全独立、双手自由
  │  (全身)   │
  ├───────────┤
  │   板子    │
  └───────────┘
```

**适用场景：** 有朋友/教练帮忙拍摄，或在固定位置架设三脚架

| 能看到 ✅ | 看不清 ❌ |
|---------|----------|
| **全身姿态（最佳外部视角！）** | 微表情、细微手指动作 |
| **膝盖弯曲角度（清晰）** | 距离远时脚踝细节 |
| **臀部高度和位置** | 拍摄者跟不上时可能丢失目标 |
| **板刃角度（侧面清晰）** | 逆光/背光时细节丢失 |
| **身体倾斜角度（最佳视角）** | |
| **完整弯道轨迹** | |
| **雪面痕迹和雪花飞溅** | |
| **前后脚压力分配（可推断）** | |
| **骑手双手完全自由** | |

**AI 分析策略（第三人称模式）：**
- **优势最大**：完全外部视角，骑手双手自由、动作不受限
- 重点关注：全身协调性、身体倾角、膝盖折叠、板刃立刃角度
- 弯道轨迹和雪面痕迹从旁观者视角更直观
- 推荐发送 2 个视角：正面/侧面全身 + 后方追踪
- **劣势**：需要另一个人跟拍，机位不稳定，拍摄者也需要滑行能力

### 9.4 三种模式对比

| 维度 | 头盔安装 🪖 | 手持自拍杆 🤳 | 第三人称 🎬 |
|------|-----------|-------------|------------|
| **AI 分析精度** | 中等（靠推断下半身） | **高（全身可见）** | **最高（外部全身+自由动作）** |
| **便利性** | **高（装上就忘）** | 中（需要单手持杆） | 低（需要朋友帮忙） |
| **安全性** | **高（双手自由）** | 中（单手滑行有风险） | **高（双手自由）** |
| **适合水平** | 所有水平 | 中级以上（需要单手滑行能力） | 所有水平 |
| **最佳场景** | 日常练习、高速滑行 | 技术精细打磨、刻滑训练 | 精准技术分析、教练指导场景 |
| **视角丰富度** | 360° 但身体遮挡多 | 360° 全身清晰 | 360° 外部视角最佳 |
| **独立性** | 独立 | 独立 | 需要帮手 |

### 9.5 App 中的模式选择

```swift
enum CameraMountMode {
    case helmet       // 头盔安装
    case handheld     // 手持自拍杆
    case thirdPerson  // 第三人称拍摄（朋友持机/三脚架）
}
```

用户开始训练前选择安装方式，App 根据模式：
1. 调整 AI system prompt（告诉 AI 当前能看到什么）
2. 选择最优的 360° reframe 视角组合
3. 调整教练重点（头盔模式侧重雪面分析，手持/第三人称模式侧重全身姿态）
4. 第三人称模式下，相机连接的是**拍摄者的手机**（需两人同时在线），或使用延迟分析模式（先录后分析）

### 9.6 Key Insight: Snow Spray Is the Best Signal (All Modes)

无论哪种安装方式，**雪花飞溅模式**都是区分刻滑和扫雪最可靠的视觉指标：
- **刻滑**：雪面上留下一条细线，几乎没有雪花飞溅
- **扫雪**：大面积雪花飞溅，板子在刮雪

头盔模式：AI 主要依赖雪花模式 + 上半身姿态推断（~80% 准确率）
手持模式：AI 可以结合全身姿态 + 板刃 + 雪花模式（~90%+ 准确率）
第三人称模式：外部视角 + 全身自由动作 + 雪面痕迹（~95% 准确率，最佳）

### 9.7 Sending Multiple Views from 360°

X5 是 360° 相机，我们可以从同一帧提取多个视角发送给 AI：

**头盔模式（3 视角）：**
1. **前方视角** — 看雪面、弯道方向、前方路径
2. **下方视角** — 看板子和雪面痕迹（最关键！）
3. **后方视角** — 看骑手背部、臀部旋转

**手持模式（2 视角）：**
1. **正面全身视角** — 看全身姿态、膝盖、板刃（最关键！）
2. **后方/侧面视角** — 看背部线条、雪面痕迹

**第三人称模式（2 视角）：**
1. **面向骑手全身视角** — 正面/侧面全身姿态（最关键！）
2. **骑手后方跟拍视角** — 雪面痕迹、弯道轨迹、背部姿态

Composite image（多视角拼成一张图）发给 AI = 比单视角丰富得多的分析。

---

## 10. Network & Offline Strategy

### 10.1 Connection Architecture

```
Insta360 X5 ←── WiFi Direct ──► iPhone ←── 4G/5G ──► Cloud AI API
  (本地连接，不需要网络)                     (需要蜂窝网络)
```

- Camera ↔ Phone: **Local WiFi Direct** — always works, no internet needed
- Phone ↔ AI API: **Requires 4G/5G** — dependency on cellular coverage

### 10.2 Mountain Connectivity

- 大多数现代滑雪场有 4G/5G 覆盖
- 但偏远雪道可能信号弱
- **WiFi Direct 连接 X5 会占用 iPhone 的 WiFi**，所以必须用蜂窝数据连 AI API

### 10.3 Signal Loss Handling

```
信号好 → 正常实时教练模式
信号弱 → 降级模式：降低帧采样率，压缩图片更小，缓存未发送帧
无信号 → 离线模式：
  1. 停止 AI 分析
  2. 继续录像
  3. 用陀螺仪数据做基本动作检测（本地）
  4. 恢复信号后自动重连
  5. 训练结束后上传录像做详细分析
```

---

## 11. Safety Design

| Concern | Mitigation |
|---------|-----------|
| 骑手被语音分心 | 骨传导耳机（不堵耳朵），AI 在高速时减少输出 |
| 手持模式单手滑行风险 | App 提示“单手滑行有风险，建议中级以上水平使用”，选择模式时显示警告 |
| 突然的指令导致危险动作 | AI 永远不说"立刻转弯"类的指令，只给姿态建议 |
| 摔倒时继续播放 | 检测到剧烈加速度变化 → 暂停教练 → 询问"你还好吗？" |
| 法律责任 | App 首次使用时必须同意免责声明 |
| 电池耗尽 | 低电量警告，建议带充电宝 |

---

## 12. MVP Feature Set (V1)

| Feature | Priority | Notes |
|---------|----------|-------|
| X5 WiFi 连接 | P0 | INSCameraManager.socket().setup() |
| 实时预览显示 | P0 | INSCameraSessionPlayer 渲染 |
| 安装方式选择 | P0 | 头盔安装 / 手持自拍杆，影响 AI 分析策略 |
| 帧采样 + GitHub Models 分析 | P0 | GPT-4.1-mini, streaming response |
| 语音教练输出 (AVSpeechSynthesizer) | P0 | 中文，on-device TTS |
| 开始/结束训练 | P0 | 基本会话管理 |
| 心跳维持 (0.5s) | P0 | 否则相机 30 秒后断连 |
| 参考视频上传 + AI 预分析 | P1 | 上传高手视频，AI 提取关键帧 + 技术基准 |
| 实时对比反馈 | P1 | 训练中对比参考视频，语音告知差距 |
| 训练后对比报告 | P1 | 关键帧并排对比 + 各项指标评分 |
| 对话功能 (STT) | P1 | Apple Speech, push-to-talk |
| 训练录像保存 | P1 | 本地保存 + 可选云端 |
| 训练后总结 | P1 | GPT-4o via GitHub Models 详细分析 |
| 技术等级选择 | P2 | 初学/中级/高级 |
| 训练重点选择 | P2 | "今天练刻滑" |
| 进步追踪 | P2 | 跨训练比较 |
| 离线基础模式 | P3 | Core ML 本地模型 |

---

## 13. Development Phases

### Phase 1 — Proof of Concept
- [ ] 注册 Insta360 开发者账号 (https://www.insta360.com/sdk/apply)
- [ ] 用 SDK 连接 X5，显示实时预览
- [ ] 实现安装方式选择（头盔 / 手持）
- [ ] 从预览中截取帧（根据安装模式选择 reframe 视角）
- [ ] 发送帧到 GitHub Models API (GPT-4.1-mini)，获取教练文本（streaming）
- [ ] AVSpeechSynthesizer 播放中文教练语音
- [ ] 在雪场测试！

### Phase 2 — MVP
- [ ] 完整训练生命周期（开始/暂停/结束）
- [ ] 参考视频上传 + AI 预分析（提取关键帧、生成 ReferenceProfile）
- [ ] 参考视频角度匹配检查（确保参考视频和当前安装方式角度一致）
- [ ] 实时对比模式（训练中对比参考视频给出差距反馈）
- [ ] 对话功能（骑手可以提问）
- [ ] 智能采样（陀螺仪检测动作时才分析，减少 API 调用量）
- [ ] 多视角帧（前方 + 下方 + 后方 合成图）
- [ ] 训练后详细对比报告（关键帧并排 + 指标评分）
- [ ] 训练录像 + AI 文字记录保存
- [ ] UI/UX 打磨

### Phase 3 — Refinement
- [ ] 教练质量提升（更好的 prompt、测试集验证、多模型 A/B 测试）
- [ ] 参考视频库管理（多视频、分类、收藏）
- [ ] 社区参考视频共享（用户可以分享自己的参考视频给其他人）
- [ ] Core ML 本地动作分类器（刻滑/扫雪/直滑/停止）
- [ ] 针对特定技术的教练模式
- [ ] 进步追踪（跨训练对比、技术指标变化曲线）
- [ ] 延迟进一步优化

### Phase 4 — Scale
- [ ] Android 版本（Kotlin + Insta360 Android SDK）
- [ ] 滑雪（双板）支持
- [ ] 多语言教练（English, Japanese, etc.）
- [ ] 社交功能（分享训练、排行榜）
- [ ] 与滑雪场/租赁店合作

---

## 14. Risk Matrix

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| AI 给出错误技术建议 | 高 | 中 | 专家审核 prompt，测试集验证，置信度阈值 |
| 延迟 > 3 秒 | 高 | 中 | GPT-4.1-mini + streaming + on-device TTS |
| GitHub Models 速率限制 | 中 | 中 | Enterprise 450/day + 智能采样足够。可升级付费。 |
| Insta360 SDK 限制/bug | 高 | 中 | 早期原型验证，联系 Insta360 技术支持 |
| 雪场无网络 | 中 | 高 | 离线降级模式，Core ML 本地模型 |
| 电池在寒冷中快速耗尽 | 中 | 高 | 锁屏省电，低电量提醒，充电宝 |
| 骑手因语音教练分心 | 严重 | 低 | 骨传导耳机，智能语音控制，免责声明 |
| 单帧无法区分刻滑/扫雪 | 中 | 中 | 多帧上下文 + 多视角合成 + 雪花模式分析 |
| 参考视频角度与实时角度差异大 | 中 | ~~高~~ 低(V1) | V1 同角度策略消除此问题；V2 加入跨角度补偿 |
| SDK 无法直接获取帧缓冲 | 中 | 中 | Preview view 截图方案作为 fallback |
| WiFi Direct 占用 WiFi影响蜂窝 | 低 | 低 | iPhone 可同时用 WiFi Direct + 蜂窝数据 |

---

## 15. Open Questions (Remaining)

1. **帧获取方式**：SDK 能否直接访问解码后的帧缓冲（CVPixelBuffer），还是需要截图预览视图？需要拿到 SDK 后实测。
2. **360° reframe API**：SDK 是否有 API 可以从等距圆柱投影（equirectangular）重新映射到特定视角？还是我们需要自己做投影变换？
3. **并发连接**：WiFi Direct 连相机时，iPhone 的蜂窝数据是否稳定可用？需实测。
4. **GitHub Models 付费升级**：如果需要多次训练/天或更快帧率，需要 org admin opt in to paid GitHub Models。确认你的 Enterprise org 是否已开启此选项。
5. **Gemini 备选方案**：如果 GitHub Models 速率限制不够用且无法开启付费，是否考虑也申请 Google AI Studio API key 作为备选？Gemini 2.0 Flash 更快且速率限制更宽松。
6. **参考视频预分析成本**：每个参考视频预分析需要发送多帧给 GPT-4o，这会消耗较多 token。是在本地做还是上传时做？
7. ~~**参考视频来源**~~ ✅ 已确认：V1 从网上找同角度的高手滑行视频
8. ~~**角度补偿精度**~~ ✅ 已解决：V1 采用同角度策略，彻底消除角度差异问题
9. **训练数据**：是否需要收集标注过的滑雪视频来验证或微调 AI 的判断准确率？

> 📊 市场调研与商业分析已独立为 [MARKET_ANALYSIS.md](MARKET_ANALYSIS.md)

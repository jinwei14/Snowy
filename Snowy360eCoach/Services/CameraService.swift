import Foundation
import UIKit
import Combine

// MARK: - Insta360 SDK Type Placeholders
// These mirror the Insta360 iOS SDK V1.9.2 API.
// Replace with actual imports once the SDK is integrated:
//   import INSCameraSDK

#if !canImport(INSCameraSDK)
// Placeholder types for compilation without the SDK.
// Remove this block after adding the real Insta360 SDK.
class INSCameraManager {
    static let shared = INSCameraManager()
    let commandManager = INSCommandManager()

    static func socket() -> INSCameraSocket { INSCameraSocket.shared }
}

class INSCameraSocket {
    static let shared = INSCameraSocket()
    var cameraState: INSCameraState = .disconnected
    func setup() {}
}

class INSCommandManager {
    func sendHeartbeats(with completion: ((Error?) -> Void)?) { completion?(nil) }
    func setAppAccessFileState(_ state: INSAppAccessFileState, completion: ((Error?) -> Void)?) { completion?(nil) }
}

enum INSCameraState {
    case connected, disconnected
}

enum INSAppAccessFileState {
    case liveView, idle
}

class INSCameraSessionPlayer {
    var delegate: AnyObject?
    var dataSource: AnyObject?
    var renderView: UIView? { UIView() }
}
#endif

// MARK: - Camera Service

@MainActor
final class CameraService: ObservableObject {
    @Published var connectionState: CameraConnectionState = .disconnected
    @Published var isPreviewActive = false
    @Published var latestFrame: UIImage?

    private var heartbeatTimer: Timer?
    private var frameCaptureContinuation: AsyncStream<UIImage>.Continuation?
    private let frameCaptureInterval: TimeInterval

    /// Produces frames at the configured interval for AI analysis
    var frameStream: AsyncStream<UIImage> {
        AsyncStream { [weak self] continuation in
            self?.frameCaptureContinuation = continuation
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor [weak self] in
                    self?.frameCaptureContinuation = nil
                }
            }
        }
    }

    init(frameCaptureInterval: TimeInterval = 3.0) {
        self.frameCaptureInterval = frameCaptureInterval
    }

    // MARK: - Connection

    func connect() {
        connectionState = .connecting

        // Initialize Insta360 WiFi Direct connection
        INSCameraManager.socket().setup()

        // Check connection state after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            if INSCameraManager.socket().cameraState == .connected {
                self.connectionState = .connected
                self.startHeartbeat()
            } else {
                self.connectionState = .error("无法连接到 Insta360 X5，请确认相机已开启WiFi")
            }
        }
    }

    func disconnect() {
        stopHeartbeat()
        stopPreview()
        unlockCameraScreen()
        connectionState = .disconnected
    }

    // MARK: - Heartbeat (CRITICAL: every 0.5s or camera disconnects after 30s)

    private func startHeartbeat() {
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            INSCameraManager.shared.commandManager.sendHeartbeats(with: nil)
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Preview

    func startPreview() {
        guard connectionState == .connected else { return }
        isPreviewActive = true
        lockCameraScreen()
        startFrameCapture()
    }

    func stopPreview() {
        isPreviewActive = false
        stopFrameCapture()
    }

    // MARK: - Camera Screen Lock (save X5 battery)

    private func lockCameraScreen() {
        INSCameraManager.shared.commandManager.setAppAccessFileState(.liveView) { _ in }
    }

    private func unlockCameraScreen() {
        INSCameraManager.shared.commandManager.setAppAccessFileState(.idle) { _ in }
    }

    // MARK: - Frame Capture

    private var frameCaptureTimer: Timer?

    private func startFrameCapture() {
        frameCaptureTimer = Timer.scheduledTimer(
            withTimeInterval: frameCaptureInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.captureFrame()
            }
        }
    }

    private func stopFrameCapture() {
        frameCaptureTimer?.invalidate()
        frameCaptureTimer = nil
        frameCaptureContinuation?.finish()
    }

    private func captureFrame() {
        // In production: capture from INSCameraSessionPlayer's render view
        // Option 1: UIView snapshot of the preview render view
        // Option 2: Intercept decoded CVPixelBuffer from INSCameraMediaSession
        //
        // For now, use the preview view snapshot approach:
        guard let previewView = getPreviewRenderView() else { return }

        let renderer = UIGraphicsImageRenderer(size: previewView.bounds.size)
        let snapshot = renderer.image { ctx in
            previewView.drawHierarchy(in: previewView.bounds, afterScreenUpdates: false)
        }

        latestFrame = snapshot
        frameCaptureContinuation?.yield(snapshot)
    }

    private func getPreviewRenderView() -> UIView? {
        // Return the INSCameraSessionPlayer's render view
        // This would be set up during preview initialization
        // Placeholder — in production, store a reference to the player's renderView
        return nil
    }
}

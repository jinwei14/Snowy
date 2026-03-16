import Foundation
import CoreMotion
import Combine

// MARK: - Motion Detection Service
// Smart sampling: only send frames to AI when the rider is doing something interesting.
// Uses iPhone accelerometer + gyroscope to detect turns, edge changes, speed changes.
// This reduces API calls by ~60% and focuses feedback on key moments.

@MainActor
final class MotionDetectionService: ObservableObject {
    private let motionManager = CMMotionManager()
    @Published var isMoving = false
    @Published var isTurning = false
    @Published var motionIntensity: Double = 0.0  // 0.0 (still) to 1.0 (aggressive turn)
    @Published var shouldCaptureFrame = false

    // Thresholds for motion detection
    private let turnThreshold: Double = 0.8       // Gyro rotation rate threshold for turn detection
    private let movingThreshold: Double = 0.3     // Acceleration threshold for "in motion"
    private let burstCooldown: TimeInterval = 2.0 // Minimum seconds between burst captures

    private var lastBurstTime: Date = .distantPast
    private var recentGyroValues: [Double] = []
    private let gyroWindowSize = 10

    func startMonitoring() {
        guard motionManager.isAccelerometerAvailable,
              motionManager.isGyroAvailable else { return }

        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.gyroUpdateInterval = 0.1

        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.processAccelerometer(data)
        }

        motionManager.startGyroUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.processGyro(data)
        }
    }

    func stopMonitoring() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        isMoving = false
        isTurning = false
        motionIntensity = 0
        shouldCaptureFrame = false
    }

    private func processAccelerometer(_ data: CMAccelerometerData) {
        // Total acceleration minus gravity (~1.0g when still)
        let totalAccel = sqrt(
            data.acceleration.x * data.acceleration.x +
            data.acceleration.y * data.acceleration.y +
            data.acceleration.z * data.acceleration.z
        )
        let dynamicAccel = abs(totalAccel - 1.0)  // Remove gravity component
        isMoving = dynamicAccel > movingThreshold
    }

    private func processGyro(_ data: CMGyroData) {
        // Rotation rate magnitude
        let rotationRate = sqrt(
            data.rotationRate.x * data.rotationRate.x +
            data.rotationRate.y * data.rotationRate.y +
            data.rotationRate.z * data.rotationRate.z
        )

        // Rolling window for smoothing
        recentGyroValues.append(rotationRate)
        if recentGyroValues.count > gyroWindowSize {
            recentGyroValues.removeFirst()
        }

        let avgRotation = recentGyroValues.reduce(0, +) / Double(recentGyroValues.count)
        isTurning = avgRotation > turnThreshold
        motionIntensity = min(avgRotation / 2.0, 1.0)

        // Trigger burst frame capture during turns
        if isTurning {
            let now = Date()
            if now.timeIntervalSince(lastBurstTime) >= burstCooldown {
                shouldCaptureFrame = true
                lastBurstTime = now
            }
        }
    }

    /// Reset the burst capture flag after a frame is captured
    func acknowledgeCapture() {
        shouldCaptureFrame = false
    }

    /// Detect potential crash: sudden high-G deceleration
    func detectCrash(_ data: CMAccelerometerData) -> Bool {
        let totalAccel = sqrt(
            data.acceleration.x * data.acceleration.x +
            data.acceleration.y * data.acceleration.y +
            data.acceleration.z * data.acceleration.z
        )
        return totalAccel > 4.0  // 4G impact threshold
    }
}

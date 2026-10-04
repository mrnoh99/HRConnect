import SwiftUI
import HealthKit
import WatchKit

/// 워치 앱 진입점. 아이폰이 `startWatchApp(with:)` 으로 띄우면
/// `WatchAppDelegate.handle(_:)` 가 측정을 시작한다.
@main
struct HRConnectWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(WorkoutManager.shared)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        _ = WorkoutManager.shared   // WCSession 활성화
    }

    /// 아이폰 `startWatchApp` 으로 앱을 깨울 때 호출된다(이미 시작 중이면 무시된다).
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WorkoutManager.shared.startWorkout()
    }

    func handleActiveWorkoutRecovery() {
        WorkoutManager.shared.recoverActiveWorkout()
    }
}

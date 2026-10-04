import Foundation
import Combine
import UIKit

/// 심박 중계의 중심. 페어링된 워치(`WatchLink`)에서 받은 심박을 화면에 표시하고,
/// `HeartRateBroadcaster` 로 다시 광고한다(다른 아이폰의 BikeCom 이 심박 센서로 수신).
///
/// 화면이 꺼져(앱이 백그라운드로 가) 있어도 정지할 때까지 계속 동작한다: 워치가 1초마다 보내는
/// `WCSession` 메시지가 앱을 깨우고, 그때마다 `bluetooth-peripheral` 백그라운드 모드로 notify 한다.
final class HRSession: ObservableObject {
    static let shared = HRSession()

    let watch = WatchLink()
    let broadcaster = HeartRateBroadcaster()

    @Published private(set) var bpm = 0

    @Published var broadcastEnabled: Bool {
        didSet {
            UserDefaults.standard.set(broadcastEnabled, forKey: Keys.broadcast)
            applyBroadcast()
        }
    }
    @Published var keepScreenOn: Bool {
        didSet {
            UserDefaults.standard.set(keepScreenOn, forKey: Keys.keepScreenOn)
            applyIdleTimer()
        }
    }

    private enum Keys {
        static let broadcast = "hrconnect.broadcastEnabled"
        static let keepScreenOn = "hrconnect.keepScreenOn"
    }

    private var cancellables: Set<AnyCancellable> = []

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.broadcast: true, Keys.keepScreenOn: false])
        broadcastEnabled = defaults.bool(forKey: Keys.broadcast)
        keepScreenOn = defaults.bool(forKey: Keys.keepScreenOn)

        // 워치가 약 1초마다 값을 다시 보내므로, 도착할 때마다 그대로 notify 하면 스트랩과
        // 같은 주기가 된다(타이머가 멈추는 백그라운드에서도 메시지 수신으로 깨어나 동작).
        watch.onHeartRate = { [weak self] bpm in
            self?.broadcaster.update(bpm: bpm)
        }
        watch.$heartRateBPM
            .sink { [weak self] value in
                guard let self else { return }
                self.bpm = value ?? 0
                if value == nil { self.broadcaster.clear() }
                self.applyIdleTimer()
            }
            .store(in: &cancellables)
        applyBroadcast()
    }

    private func applyBroadcast() {
        if broadcastEnabled {
            broadcaster.start()
            if bpm > 0 { broadcaster.update(bpm: bpm) }
        } else {
            broadcaster.stop()
        }
    }

    /// 선택 사항: 심박이 들어오는 동안 화면이 꺼지지 않게 한다(심박을 계속 보고 싶을 때).
    private func applyIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn && bpm > 0
    }
}

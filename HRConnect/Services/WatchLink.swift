import Foundation
import Combine
import HealthKit
import WatchConnectivity

/// 이 폰과 페어링된 애플워치에서 측정한 실시간 심박을 `WCSession` 으로 받는다.
///
/// 측정 시작/정지는 폰이 `workoutActive` + 토큰을 방송하고 워치가 따라가는 방식이다
/// (워치는 더 새 토큰만 채택 — 재전달·중복에 안전). 워치에서 직접 시작한 경우에도
/// 심박은 그대로 들어오므로 폰은 값이 들어오는지만 보면 된다.
final class WatchLink: NSObject, ObservableObject {
    @Published private(set) var heartRateBPM: Int?
    @Published private(set) var paired = false
    @Published private(set) var appInstalled = false
    @Published private(set) var reachable = false
    /// 폰이 워치에 측정을 요청한 상태(워치가 정지하거나 오류를 보고하면 내려간다).
    @Published private(set) var requested = false
    @Published private(set) var statusMessage = "대기"
    @Published private(set) var lastError: String?

    /// 워치 심박이 도착할 때마다(값이 그대로여도, 약 1초 간격) 호출된다 — BLE 재광고용.
    var onHeartRate: ((Int) -> Void)?

    private let healthStore = HKHealthStore()
    private var token: Double = 0
    private var lastHeartRateAt: Date?
    private var freshnessTimer: AnyCancellable?
    /// start/stop 마다 증가 — 이전 요청의 재시도가 뒤늦게 실행되는 것을 막는다.
    private var launchGeneration = 0
    private let maxLaunchAttempts = 3

    override init() {
        super.init()
        activateSession()
        freshnessTimer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.decayIfStale() }
    }

    private func activateSession() {
        guard WCSession.isSupported() else {
            statusMessage = "WatchConnectivity 미지원"
            return
        }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    // MARK: 측정 시작 / 정지

    func start() {
        lastError = nil
        requested = true
        launchGeneration += 1
        broadcast(active: true)

        guard HKHealthStore.isHealthDataAvailable() else {
            statusMessage = "워치 측정 대기"
            return
        }
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .unknown
        statusMessage = "워치 앱 실행 중…"
        launchWatchApp(config: config, attempt: 1, generation: launchGeneration)
    }

    func stop() {
        requested = false
        launchGeneration += 1
        broadcast(active: false)
        heartRateBPM = nil
        lastHeartRateAt = nil
        lastError = nil
        statusMessage = "대기"
    }

    /// applicationContext(영구)로 항상 저장하고, reachable 이면 sendMessage 로 즉시도 보낸다.
    private func broadcast(active: Bool) {
        token = Date().timeIntervalSince1970
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        let payload: [String: Any] = [HRLink.workoutActive: active, HRLink.token: token]
        try? s.updateApplicationContext(payload)
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    /// 워치 앱을 깨운다. 세션 시작 자체는 `broadcast(active:)` 가 담당(레벨 기반).
    private func launchWatchApp(config: HKWorkoutConfiguration, attempt: Int, generation: Int) {
        healthStore.startWatchApp(with: config) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self, generation == self.launchGeneration, self.requested else { return }
                if success {
                    self.lastError = nil
                    if self.heartRateBPM == nil { self.statusMessage = "워치 측정 대기" }
                    return
                }
                self.lastError = error?.localizedDescription ?? """
                    워치 앱이 설치되지 않았습니다. iPhone Watch 앱 → HRConnect → "Apple Watch에 설치"를 켜세요.
                    """
                guard attempt < self.maxLaunchAttempts else {
                    self.statusMessage = "워치 실행 실패 — 워치에서 직접 시작하세요"
                    return
                }
                self.statusMessage = "워치 앱 실행 재시도… (\(attempt)/\(self.maxLaunchAttempts - 1))"
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.launchWatchApp(config: config, attempt: attempt + 1, generation: generation)
                }
            }
        }
    }

    // MARK: 수신

    private func decayIfStale() {
        guard heartRateBPM != nil,
              let at = lastHeartRateAt, Date().timeIntervalSince(at) > HRLink.freshness else { return }
        heartRateBPM = nil
        if lastError == nil { statusMessage = requested ? "워치 측정 대기" : "대기" }
    }

    private func handle(_ message: [String: Any]) {
        DispatchQueue.main.async { self.apply(message) }
    }

    private func apply(_ message: [String: Any]) {
        if let err = message[HRLink.workoutError] as? String {
            lastError = err
            requested = false
            statusMessage = "워치 측정 오류"
        }
        if HRLink.bool(message, HRLink.workoutStarted) == true, heartRateBPM == nil {
            statusMessage = "워치 측정 시작됨"
        }
        // 워치에서 직접 정지. 폰이 그 뒤에 다시 시작을 요청했다면(더 새 토큰) 무시한다.
        if HRLink.bool(message, HRLink.watchStopped) == true,
           (HRLink.double(message, HRLink.timestamp) ?? 0) >= token {
            requested = false
            heartRateBPM = nil
            lastHeartRateAt = nil
            statusMessage = "대기"
        }
        // applicationContext 에 남아 있던 옛 값이 재전달될 수 있으므로 시각을 확인한다.
        if let hr = HRLink.int(message, HRLink.hr), hr > 0,
           let ts = HRLink.double(message, HRLink.timestamp),
           abs(Date().timeIntervalSince1970 - ts) <= HRLink.freshness * 2 {
            lastHeartRateAt = Date()
            heartRateBPM = hr
            lastError = nil
            statusMessage = "워치 심박 수신 중"
            onHeartRate?(hr)
        }
    }

    private func refreshState(_ session: WCSession) {
        let activated = session.activationState == .activated
        let paired = activated && session.isPaired
        let installed = activated && session.isWatchAppInstalled
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.paired = paired
            self.appInstalled = installed
            self.reachable = reachable
        }
    }
}

extension WatchLink: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        refreshState(session)
        if let error {
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
                self.statusMessage = "Watch 연결 오류"
            }
        } else if state == .activated {
            let ctx = session.receivedApplicationContext
            if !ctx.isEmpty { handle(ctx) }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    func sessionWatchStateDidChange(_ session: WCSession) { refreshState(session) }
    func sessionReachabilityDidChange(_ session: WCSession) { refreshState(session) }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handle(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handle(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handle(userInfo)
    }
}

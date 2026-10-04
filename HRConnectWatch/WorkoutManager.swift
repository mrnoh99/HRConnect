import Foundation
import HealthKit
import WatchConnectivity

/// 워치에서 워크아웃 세션을 돌려 실시간 심박을 수집하고 `WCSession` 으로 아이폰에 전송한다.
/// 워크아웃 세션은 심박을 고빈도로 측정하고 앱을 백그라운드에서 살려 두기 위한 것이며,
/// 종료 시 워크아웃은 건강 앱에 저장하지 않고 버린다(BikeCom 등 받는 쪽이 따로 기록).
final class WorkoutManager: NSObject, ObservableObject {
    static let shared = WorkoutManager()

    @Published private(set) var heartRate = 0
    @Published private(set) var isRunning = false
    @Published private(set) var phoneReachable = false
    @Published private(set) var errorText: String?

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// 시작이 진행 중인지(beginCollection 콜백 전까지 isRunning 이 아직 false 인 구간).
    /// 이 구간의 재진입을 막아 두 번째 세션이 생기는 것을 차단한다.
    private var isStarting = false
    private var lastSampleAt: Date?
    private var relayTimer: Timer?
    /// `updateApplicationContext` 는 최신 스냅샷용 — 고빈도 호출은 피한다.
    private var lastContextUpdateAt = Date.distantPast

    /// 마지막으로 채택한 폰의 권위 토큰. 워치에서 직접 정지하면 그 시각으로 올려, 앱이
    /// 다시 뜰 때 applicationContext 에 남은 옛 "시작" 지시를 따르지 않게 한다(그래서 영속).
    private var workoutToken: Double = UserDefaults.standard.double(forKey: WorkoutManager.tokenKey) {
        didSet { UserDefaults.standard.set(workoutToken, forKey: Self.tokenKey) }
    }
    private static let tokenKey = "hrconnect.wToken"

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    // MARK: 시작 / 정지

    /// 워치 화면의 버튼. 정지는 폰에도 알려 폰 UI 가 대기 상태로 돌아가게 한다.
    func toggle() {
        if isRunning || isStarting {
            let now = Date().timeIntervalSince1970
            workoutToken = now
            stopWorkout()
            sendEphemeral([HRLink.watchStopped: true, HRLink.timestamp: now])
        } else {
            startWorkout()
        }
    }

    func startWorkout() {
        guard !isRunning, !isStarting else { return }
        guard HKHealthStore.isHealthDataAvailable(),
              let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            report(error: "이 기기에서 HealthKit을 사용할 수 없습니다.")
            return
        }
        isStarting = true
        errorText = nil
        healthStore.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [hrType]) { [weak self] _, error in
            DispatchQueue.main.async {
                guard let self, self.isStarting else { return }
                if let error {
                    self.isStarting = false
                    self.report(error: error.localizedDescription)
                    return
                }
                self.beginSession()
            }
        }
    }

    private func beginSession() {
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .unknown
        do {
            let s = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            attach(session: s, builder: b)

            let startDate = Date()
            s.startActivity(with: startDate)
            b.beginCollection(withStart: startDate) { [weak self] _, error in
                DispatchQueue.main.async {
                    guard let self, self.session === s else { return }
                    self.isStarting = false
                    if let error {
                        // 시작 실패 시 세션을 정리해 다음 시작이 깨끗한 세션으로 진행되게 한다.
                        s.end()
                        self.session = nil
                        self.builder = nil
                        self.report(error: error.localizedDescription)
                        return
                    }
                    self.didStart()
                }
            }
        } catch {
            isStarting = false
            report(error: error.localizedDescription)
        }
    }

    /// 주행 중 앱이 비정상 종료됐다가 다시 뜨면 watchOS 가 진행 중이던 세션을 돌려준다.
    func recoverActiveWorkout() {
        healthStore.recoverActiveWorkoutSession { [weak self] recovered, _ in
            DispatchQueue.main.async {
                guard let self, let recovered, self.session == nil else { return }
                self.attach(session: recovered, builder: recovered.associatedWorkoutBuilder())
                self.isStarting = false
                self.didStart()
            }
        }
    }

    private func attach(session s: HKWorkoutSession, builder b: HKLiveWorkoutBuilder) {
        s.delegate = self
        b.delegate = self
        session = s
        builder = b
    }

    private func didStart() {
        isRunning = true
        startRelayTimer()
        sendEphemeral([HRLink.workoutStarted: true])
    }

    func stopWorkout() {
        stopRelayTimer()
        isStarting = false
        isRunning = false
        heartRate = 0
        lastSampleAt = nil
        guard let activeSession = session else { return }
        let activeBuilder = builder
        session = nil
        builder = nil
        activeSession.end()
        activeBuilder?.endCollection(withEnd: Date()) { _, _ in
            activeBuilder?.discardWorkout()
        }
    }

    private func report(error: String) {
        errorText = error
        sendEphemeral([HRLink.workoutError: error])
    }

    // MARK: 폰으로 전송

    /// 심박 샘플은 몇 초 간격으로 올 수도 있다. 폰(과 그 뒤의 BLE 수신 기기)이 신호 끊김으로
    /// 보지 않도록 최신값을 1초마다 다시 보낸다.
    private func startRelayTimer() {
        stopRelayTimer()
        relayTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.sendHeartRate()
        }
    }

    private func stopRelayTimer() {
        relayTimer?.invalidate()
        relayTimer = nil
    }

    private func sendHeartRate() {
        guard isRunning, heartRate > 0 else { return }
        // 센서가 손목에서 떨어지는 등 샘플이 끊기면 옛 값을 계속 보내지 않는다.
        guard let at = lastSampleAt, Date().timeIntervalSince(at) <= 15 else {
            heartRate = 0
            return
        }
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        let now = Date()
        let payload: [String: Any] = [HRLink.hr: heartRate, HRLink.timestamp: now.timeIntervalSince1970]
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else if now.timeIntervalSince(lastContextUpdateAt) >= 1 {
            try? s.updateApplicationContext(payload)
            lastContextUpdateAt = now
        }
    }

    /// 1회성 이벤트(시작·오류·정지) — context 에 넣지 않는다(재처리 방지).
    private func sendEphemeral(_ payload: [String: Any]) {
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            s.transferUserInfo(payload)
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        guard toState == .ended else { return }
        DispatchQueue.main.async {
            // 시스템이 세션을 끝낸 경우(우리가 끝냈다면 session 은 이미 nil).
            guard self.session === workoutSession else { return }
            self.stopWorkout()
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            guard self.session === workoutSession else { return }
            self.stopWorkout()
            self.report(error: error.localizedDescription)
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(hrType),
              let quantity = workoutBuilder.statistics(for: hrType)?.mostRecentQuantity() else { return }
        let bpm = Int(quantity.doubleValue(for: .count().unitDivided(by: .minute())).rounded())
        guard bpm > 0 else { return }
        DispatchQueue.main.async {
            guard self.builder === workoutBuilder else { return }
            self.heartRate = bpm
            self.lastSampleAt = Date()
            self.sendHeartRate()
        }
    }
}

extension WorkoutManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        let reachable = session.isReachable
        DispatchQueue.main.async { self.phoneReachable = reachable }
        let ctx = session.receivedApplicationContext
        if !ctx.isEmpty { handleCommand(ctx) }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async { self.phoneReachable = reachable }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleCommand(message)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleCommand(applicationContext)
    }

    /// 폰이 방송한 권위 레벨에 세션을 맞춘다. 더 새 토큰만 채택하므로 재전달·중복에 안전하다.
    private func handleCommand(_ message: [String: Any]) {
        guard let active = HRLink.bool(message, HRLink.workoutActive),
              let token = HRLink.double(message, HRLink.token) else { return }
        DispatchQueue.main.async {
            guard token > self.workoutToken else { return }
            self.workoutToken = token
            if active {
                self.startWorkout()
            } else {
                self.stopWorkout()
            }
        }
    }
}

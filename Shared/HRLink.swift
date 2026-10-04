import Foundation

/// 폰 ↔ 워치 WatchConnectivity 페이로드 키와 파싱 헬퍼(양쪽 타깃 공용).
///
/// 폰 → 워치: `workoutActive` + `token` (폰이 측정 시작/정지를 지시. 워치는 더 새 토큰만 채택)
/// 워치 → 폰: `hr` + `timestamp` (실시간 심박), `workoutStarted` / `workoutError` / `watchStopped` (1회성 이벤트)
enum HRLink {
    static let hr = "hr"
    static let timestamp = "ts"
    static let workoutActive = "workoutActive"
    static let token = "wToken"
    static let workoutStarted = "workoutStarted"
    static let workoutError = "workoutError"
    static let watchStopped = "watchStopped"

    /// 이 시간(초) 안에 새 심박이 없으면 "신호 없음"으로 본다.
    static let freshness: TimeInterval = 5

    // WCSession 은 숫자를 NSNumber 로 넘기는 경우가 많다.
    static func int(_ dict: [String: Any], _ key: String) -> Int? {
        if let v = dict[key] as? Int { return v }
        if let v = dict[key] as? NSNumber { return v.intValue }
        return nil
    }

    static func double(_ dict: [String: Any], _ key: String) -> Double? {
        if let v = dict[key] as? NSNumber { return v.doubleValue }
        if let v = dict[key] as? Double { return v }
        return nil
    }

    static func bool(_ dict: [String: Any], _ key: String) -> Bool? {
        if let v = dict[key] as? Bool { return v }
        if let v = dict[key] as? NSNumber { return v.boolValue }
        return nil
    }
}

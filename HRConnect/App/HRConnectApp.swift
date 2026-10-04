import SwiftUI

/// 앱 진입점. 심박 중계 세션(워치·BLE 수신 + BLE 재광고)을 전역 상태로 주입한다.
@main
struct HRConnectApp: App {
    @StateObject private var session = HRSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}

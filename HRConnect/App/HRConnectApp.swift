import SwiftUI

/// 앱 진입점. 심박 중계 세션(워치 수신 + BLE 재광고)을 전역 상태로 주입한다.
@main
struct HRConnectApp: App {
    private let session = HRSession.shared

    init() {
        // 화면이 꺼진 동안 앱이 종료되면, 워치 메시지가 화면(Scene) 없이 앱을 백그라운드로
        // 다시 띄운다. 그때도 수신·광고가 바로 살아나도록 뷰가 아니라 여기서 세션을 만든다.
        _ = HRSession.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .preferredColorScheme(.dark)
        }
    }
}

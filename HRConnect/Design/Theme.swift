import SwiftUI

/// 색상·폰트 등 디자인 토큰(BikeCom 대시보드와 같은 색 코딩).
enum Theme {
    static let background = Color.black
    static let card = Color(white: 0.09)
    static let cardBorder = Color(white: 0.16)
    static let label = Color(white: 0.62)

    static let value = Color.white
    static let red = Color(red: 1.0, green: 0.30, blue: 0.27)    // 심박수
    static let blue = Color(red: 0.16, green: 0.55, blue: 1.0)   // BLE
    static let green = Color(red: 0.30, green: 0.78, blue: 0.40) // 시작·정상
    static let gold = Color(red: 1.0, green: 0.82, blue: 0.10)   // 대기·주의
    static let gray = Color(white: 0.30)                         // 정지 버튼

    /// 큰 숫자 폰트
    static func metricFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

import SwiftUI

/// 워치 화면: 현재 심박 + 시작/정지 버튼.
struct WatchContentView: View {
    @EnvironmentObject private var workout: WorkoutManager

    private static let red = Color(red: 1.0, green: 0.30, blue: 0.27)
    private static let green = Color(red: 0.30, green: 0.78, blue: 0.40)

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(workout.heartRate > 0 ? Self.red : .gray)
                Text(workout.heartRate > 0 ? "\(workout.heartRate)" : "--")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(workout.heartRate > 0 ? Self.red : .gray)
                    .contentTransition(.numericText())
                Text("bpm")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Button(workout.isRunning ? "정지" : "시작") {
                workout.toggle()
            }
            .tint(workout.isRunning ? .gray : Self.green)
        }
        .padding(.horizontal, 4)
    }

    private var status: String {
        if let error = workout.errorText { return error }
        guard workout.isRunning else { return "대기" }
        return workout.phoneReachable ? "iPhone으로 전송 중" : "iPhone 연결 대기"
    }
}

import SwiftUI

/// 단일 화면: 현재 심박, 워치 측정 시작/정지, BLE 브로드캐스트 상태.
struct ContentView: View {
    @EnvironmentObject private var session: HRSession

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HeartRateHero(bpm: session.bpm)
                WatchCard(watch: session.watch)
                BroadcastCard(broadcaster: session.broadcaster)
                Toggle("심박 수신 중 화면 켜짐 유지", isOn: $session.keepScreenOn)
                    .font(.subheadline)
                    .tint(Theme.green)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
    }
}

private struct HeartRateHero: View {
    let bpm: Int
    @State private var beat = false

    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(bpm > 0 ? Theme.red : Theme.gray)
                    .scaleEffect(beat ? 1.18 : 1.0)
                Text(bpm > 0 ? "\(bpm)" : "--")
                    .font(Theme.metricFont(96, weight: .bold))
                    .foregroundStyle(bpm > 0 ? Theme.red : Theme.gray)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("bpm")
                    .font(Theme.metricFont(20))
                    .foregroundStyle(Theme.label)
            }
            Text(bpm > 0 ? "Apple Watch" : "신호 없음")
                .font(.subheadline)
                .foregroundStyle(Theme.label)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        // 새 값이 올 때마다 하트를 한 번 뛰게 한다.
        .onChange(of: bpm) {
            guard bpm > 0 else { return }
            withAnimation(.easeOut(duration: 0.12)) { beat = true }
            withAnimation(.easeIn(duration: 0.25).delay(0.12)) { beat = false }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bpm > 0 ? "심박수 \(bpm) bpm" : "심박 신호 없음")
    }
}

/// 입력: 이 폰과 페어링된 애플워치.
private struct WatchCard: View {
    @ObservedObject var watch: WatchLink

    private var active: Bool { watch.requested || watch.heartRateBPM != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(icon: "applewatch", title: "Apple Watch",
                       status: watch.statusMessage,
                       color: watch.heartRateBPM != nil ? Theme.green : (watch.requested ? Theme.gold : Theme.label))
            if let error = watch.lastError {
                Text(error).font(.footnote).foregroundStyle(Theme.gold)
            }
            Button {
                active ? watch.stop() : watch.start()
            } label: {
                Text(active ? "워치 측정 정지" : "워치 측정 시작")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(active ? Theme.gray : Theme.green, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
        }
        .padding(14)
        .card()
    }
}

/// 출력: 표준 BLE 심박 서비스(0x180D)로 재광고.
private struct BroadcastCard: View {
    @EnvironmentObject private var session: HRSession
    @ObservedObject var broadcaster: HeartRateBroadcaster

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $session.broadcastEnabled) {
                CardHeader(icon: "dot.radiowaves.left.and.right", title: "심박 브로드캐스트",
                           status: status, color: broadcaster.advertising ? Theme.green : Theme.label)
            }
            .tint(Theme.green)
            Text("받는 아이폰의 BikeCom → ⚙️ → 장치 → 심박 센서(폰 BLE)에서 \"\(HeartRateBroadcaster.localName)\"를 찾아 연결합니다(페어링 불필요).")
                .font(.footnote)
                .foregroundStyle(Theme.label)
        }
        .padding(14)
        .card()
    }

    private var status: String {
        guard session.broadcastEnabled else { return "꺼짐" }
        if let reason = broadcaster.unavailableReason { return reason }
        guard broadcaster.advertising else { return "준비 중…" }
        return broadcaster.subscriberCount > 0 ? "광고 중 · \(broadcaster.subscriberCount)대 수신" : "광고 중"
    }
}

private struct CardHeader: View {
    let icon: String
    let title: String
    let status: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).foregroundStyle(Theme.value)
                Text(status).font(.footnote).foregroundStyle(color)
            }
            Spacer(minLength: 0)
        }
    }
}

private extension View {
    func card() -> some View {
        frame(maxWidth: .infinity)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder))
    }
}

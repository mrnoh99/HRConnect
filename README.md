# HRConnect (iOS + watchOS)

애플워치 심박을 **워치와 페어링되지 않은 다른 아이폰**으로 보내는 심박 중계 앱.
워치와 페어링된 아이폰이 워치 심박을 받아 표준 BLE 심박 센서(`0x180D`)처럼 광고하고,
다른 아이폰의 [BikeCom](https://github.com/mrnoh99/BikeCom) 이 그것을 심박 스트랩처럼 스캔·연결해 쓴다.

```
Apple Watch ──WCSession──▶ 아이폰 A (워치와 페어링, HRConnect) ──BLE 0x180D──▶ 아이폰 B (BikeCom)
 HRConnectWatch              HeartRateBroadcaster "HRConnect"                  BLEHeartRateManager
 HKWorkoutSession 심박
```

워치는 BLE 광고를 직접 할 수 없다(`CBPeripheralManager` 가 watchOS 에 없다). 그래서 광고는 항상
워치와 페어링된 **폰**이 한다.

> **최소 OS: iOS 17 / watchOS 10.** 받는 쪽(BikeCom)은 수정할 필요가 없다.

## 사용법

1. **아이폰 A**(워치와 페어링된 폰)에 HRConnect 를 설치한다. 워치 앱도 함께 설치된다
   (안 되면 iPhone Watch 앱 → HRConnect → "Apple Watch에 설치").
2. 아이폰 A 에서 HRConnect 를 열고 **워치 측정 시작**을 누른다(또는 워치의 HRConnect 에서 **시작**).
   처음에는 워치에서 건강 권한, 폰에서 블루투스 권한을 허용한다.
3. 심박이 표시되고 **심박 브로드캐스트**가 "광고 중"이 되면,
   **아이폰 B** 의 BikeCom → ⚙️ → 장치 → **심박 센서(폰 BLE)** 에서 `HRConnect` 를 찾아 연결한다.
   한 번 연결하면 BikeCom 이 기억해 다음부터 자동으로 다시 연결한다.
4. 끝나면 **워치 측정 정지**(폰) 또는 **정지**(워치).

## 동작 방식

- **워치**(`HRConnectWatch/WorkoutManager.swift`): `HKWorkoutSession` + `HKLiveWorkoutBuilder` 로 심박을
  고빈도 측정하고 `WCSession` 으로 폰에 보낸다. 샘플이 몇 초 간격으로 와도 최신값을 **1초마다 재전송**한다.
  워크아웃 세션은 측정과 백그라운드 유지를 위한 것이며, 종료 시 **건강 앱에 워크아웃을 저장하지 않는다**
  (`discardWorkout` — 기록은 받는 쪽 BikeCom 이 한다).
- **폰**(`HRConnect/Services/`):
  - `WatchLink` — 워치 심박 수신. 측정 시작/정지는 폰이 `workoutActive` + 토큰을 방송하고 워치가 따라간다
    (워치는 더 새 토큰만 채택 — 재전달·중복에 안전). 5초간 값이 없으면 "신호 없음".
  - `HeartRateBroadcaster` — GATT Heart Rate Service(`0x180D`) / Measurement(`0x2A37`, notify·read)를
    이름 `HRConnect` 로 광고. 워치 값이 도착할 때마다 구독자에게 notify.
  - `HRSession` — 위 둘을 연결하고 설정(브로드캐스트·화면 켜짐 유지)을 보관.

## 주의

- **아이폰 A 는 HRConnect 를 화면에 띄워 두는 것이 가장 안정적이다**(기본으로 심박 수신 중에는 화면이 꺼지지
  않는다). 백그라운드에서도 `bluetooth-peripheral` 모드로 이미 연결된 기기에는 계속 전송하지만, iOS 는
  백그라운드 앱의 광고에서 이름을 빼고 서비스 UUID 를 별도 영역으로 옮긴다 — 이 상태에서는 `0x180D` 를
  지정해 스캔하는 iOS 앱(BikeCom)만 찾을 수 있고, Garmin 등 다른 회사 기기는 찾지 못한다.
- BLE 도달 거리(대략 10m 안쪽) 안에 두 아이폰이 있어야 한다.
- 시뮬레이터에는 블루투스가 없어 광고가 동작하지 않는다. 실제 기기에서 확인해야 한다.

## 빌드

Xcode 16 이상. 별도 도구 없이 바로 연다:

```bash
open HRConnect.xcodeproj   # HRConnect 스킴을 아이폰 A 로 실행
```

- 소스 폴더(`HRConnect/`, `HRConnectWatch/`, `Shared/`)는 Xcode 의 파일 시스템 동기화 그룹이라, 폴더에
  파일을 추가하면 프로젝트에 자동으로 들어간다. `Shared/` 는 폰·워치 두 타깃에 모두 포함된다.
- Info.plist·entitlements 는 `Config/` 에 있다. HealthKit Capability 가 필요하다(두 타깃 모두).
- 번들 ID `com.jaisungnoh.hrconnect` / `.watchkitapp`, 팀은 프로젝트 빌드 설정의 `DEVELOPMENT_TEAM`.
- 아이콘 재생성: `swift scripts/generate_app_icons.swift`

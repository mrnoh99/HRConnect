import Foundation
import CoreBluetooth

/// 이 폰이 지금 갖고 있는 심박(워치 WCSession 또는 폰 BLE 스트랩에서 받은 값)을
/// 표준 BLE Heart Rate Service(`0x180D`)로 재광고한다.
///
/// `CBPeripheralManager`(BLE 페리페럴/광고 역할)는 **watchOS 에는 없다** — 센트럴 역할만
/// 지원한다. 그래서 워치가 직접 BLE 로 광고할 수는 없고, 대신 이미 심박을 받은 폰이
/// 일반 BLE 심박 스트랩처럼 재광고한다. 이렇게 하면 이 폰과 페어링되지 않은 다른
/// 기기(다른 아이폰의 HRConnect·BikeCom, 표준 HR 서비스를 스캔하는 임의의 앱·사이클링
/// 컴퓨터)도 근처에서 이 폰을 거쳐 심박을 받을 수 있다.
final class HeartRateBroadcaster: NSObject, ObservableObject {
    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")
    static let localName = "HRConnect"

    @Published private(set) var advertising = false
    @Published private(set) var subscriberCount = 0
    /// 블루투스가 꺼져 있거나 권한이 없을 때의 안내 문구(정상이면 nil).
    @Published private(set) var unavailableReason: String?

    private var peripheralManager: CBPeripheralManager?
    private var measurementCharacteristic: CBMutableCharacteristic?
    private var serviceAdded = false
    private var subscribers: Set<UUID> = []
    private var latestBPM: Int = 0

    /// 아직 켜져 있지 않으면 `CBPeripheralManager` 를 만들어 광고를 시작한다.
    func start() {
        guard peripheralManager == nil else {
            startAdvertisingIfNeeded()
            return
        }
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }

    /// 광고·서비스를 모두 내린다.
    func stop() {
        guard let pm = peripheralManager else { return }
        if advertising { pm.stopAdvertising() }
        pm.removeAllServices()
        peripheralManager = nil
        measurementCharacteristic = nil
        serviceAdded = false
        advertising = false
        subscribers = []
        subscriberCount = 0
        unavailableReason = nil
        latestBPM = 0
    }

    /// 최신 심박(bpm)을 구독 중인 모든 센트럴에 notify 한다. 값이 그대로여도 스트랩처럼
    /// 주기적으로(약 1초) 불러 줘야 수신 측이 신호 끊김으로 판단하지 않는다.
    func update(bpm: Int) {
        guard bpm > 0 else { return }
        latestBPM = bpm
        guard let pm = peripheralManager, pm.state == .poweredOn,
              let characteristic = measurementCharacteristic else { return }
        pm.updateValue(Self.encode(bpm: bpm), for: characteristic, onSubscribedCentrals: nil)
    }

    /// 심박 신호가 끊겼을 때 — 새 구독자·read 요청에 옛 값을 주지 않도록 비운다.
    func clear() {
        latestBPM = 0
    }

    /// GATT Heart Rate Measurement(`0x2A37`) 포맷: flags(1B, 0=UINT8 심박값) + 심박값(1B).
    private static func encode(bpm: Int) -> Data {
        Data([0x00, UInt8(clamping: bpm)])
    }

    private func setupServiceIfNeeded() {
        guard !serviceAdded, measurementCharacteristic == nil, let pm = peripheralManager else { return }
        let characteristic = CBMutableCharacteristic(
            type: Self.heartRateMeasurement,
            properties: [.notify, .read],
            value: nil,
            permissions: [.readable])
        measurementCharacteristic = characteristic
        let service = CBMutableService(type: Self.heartRateService, primary: true)
        service.characteristics = [characteristic]
        pm.add(service)
    }

    private func startAdvertisingIfNeeded() {
        guard let pm = peripheralManager, pm.state == .poweredOn, serviceAdded, !advertising else { return }
        pm.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [Self.heartRateService],
            CBAdvertisementDataLocalNameKey: Self.localName,
        ])
    }

    private static func reason(for state: CBManagerState) -> String? {
        switch state {
        case .poweredOn: return nil
        case .poweredOff: return "블루투스가 꺼져 있습니다"
        case .unauthorized: return "블루투스 권한이 필요합니다(설정 → HRConnect)"
        case .unsupported: return "이 기기는 BLE 광고를 지원하지 않습니다"
        default: return "블루투스 준비 중…"
        }
    }
}

extension HeartRateBroadcaster: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        unavailableReason = Self.reason(for: peripheral.state)
        if peripheral.state == .poweredOn {
            setupServiceIfNeeded()
            startAdvertisingIfNeeded()
        } else {
            // 블루투스가 꺼지면 등록한 서비스도 사라진다 — 다시 켜질 때 새로 올린다.
            advertising = false
            serviceAdded = false
            measurementCharacteristic = nil
            subscribers = []
            subscriberCount = 0
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil else {
            measurementCharacteristic = nil
            return
        }
        serviceAdded = true
        startAdvertisingIfNeeded()
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        advertising = error == nil
        if let error { unavailableReason = error.localizedDescription }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        subscribers.insert(central.identifier)
        subscriberCount = subscribers.count
        guard latestBPM > 0, let ch = measurementCharacteristic else { return }
        peripheral.updateValue(Self.encode(bpm: latestBPM), for: ch, onSubscribedCentrals: [central])
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribers.remove(central.identifier)
        subscriberCount = subscribers.count
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard request.characteristic.uuid == Self.heartRateMeasurement else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        request.value = Self.encode(bpm: latestBPM)
        peripheral.respond(to: request, withResult: .success)
    }
}

import CoreLocation
import Foundation

/// 位置情報の許可を求めるだけの薄い入れ物。
///
/// michinori は現在地を**地図を寄せるためにしか使わない**（記録も送信もしない）ので、
/// 追跡は `MKMapView.showsUserLocation` に任せ、こちらは許可を取るのが仕事。
final class LocationAuthorizer: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published private(set) var status: CLAuthorizationStatus

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    /// 未確認なら許可ダイアログを出す。拒否済みなら何もしない（設定アプリでしか変えられない）
    func requestIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    var isDenied: Bool {
        status == .denied || status == .restricted
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
    }
}

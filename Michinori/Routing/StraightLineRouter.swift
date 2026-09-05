import CoreLocation
import Foundation

/// 2点間の大円距離。
///
/// 通信に失敗した区間を埋めるのと、区間を引く前の暫定距離表示に使う。
enum Haversine {
    /// WGS84 の平均半径（メートル）
    private static let earthRadius = 6_371_008.8

    static func meters(from origin: CLLocationCoordinate2D,
                       to destination: CLLocationCoordinate2D) -> Double {
        let φ1 = origin.latitude * .pi / 180
        let φ2 = destination.latitude * .pi / 180
        let Δφ = (destination.latitude - origin.latitude) * .pi / 180
        let Δλ = (destination.longitude - origin.longitude) * .pi / 180

        let a = sin(Δφ / 2) * sin(Δφ / 2)
            + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * earthRadius * asin(min(1, sqrt(a)))
    }
}

/// 直線で結ぶだけのルータ（フォールバック）。
///
/// 道なりではないので距離は実際より短く出る。**そのぶん UI では破線で描き、
/// GPX の `<desc>` にも直線区間の本数を書き残す**——黙って混ぜない。
struct StraightLineRouter: SegmentRouter {
    func route(from origin: CLLocationCoordinate2D,
               to destination: CLLocationCoordinate2D) async throws -> RoutedSegment {
        RoutedSegment(points: [TrackPoint(origin), TrackPoint(destination)],
                      meters: Haversine.meters(from: origin, to: destination),
                      isFallback: true)
    }
}

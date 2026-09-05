import CoreLocation
import Foundation
import MapKit

/// Apple の `MKDirections(.walking)` で引くルータ（代替実装）。
///
/// 使っていないが**捨てずに置いてある**。BRouter は外部サーバ1本に依存しているので、
/// 落ちた日にここへ差し替えれば動く（`MichinoriApp` の `CachingSegmentRouter(primary:)` を
/// `MapKitRouter()` にするだけ）。
///
/// ⚠️ 経路の好みは指定できない（`transportType` しかない）ので、
/// 「国道10号を通す・バイパスを避ける」は作れない。だから常用はしない。
/// ⚠️ 短時間に叩くと `MKError.loadingThrottled` になるという開発者報告がある。
struct MapKitRouter: SegmentRouter {
    enum Failure: LocalizedError {
        case noRoute
        var errorDescription: String? { "MapKit が徒歩経路を返しませんでした" }
    }

    func route(from origin: CLLocationCoordinate2D,
               to destination: CLLocationCoordinate2D) async throws -> RoutedSegment {
        let request = MKDirections.Request()
        // iOS 26 で MKPlacemark 経由の初期化は非推奨になったので、座標から直に作る
        request.source = MKMapItem(
            location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
            address: nil)
        request.destination = MKMapItem(
            location: CLLocation(latitude: destination.latitude, longitude: destination.longitude),
            address: nil)
        request.transportType = .walking
        request.requestsAlternateRoutes = false

        let response = try await MKDirections(request: request).calculate()
        guard let route = response.routes.first else { throw Failure.noRoute }

        let polyline = route.polyline
        var coordinates = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(), count: polyline.pointCount)
        polyline.getCoordinates(&coordinates,
                                range: NSRange(location: 0, length: polyline.pointCount))

        return RoutedSegment(points: coordinates.map { TrackPoint($0) },
                             meters: route.distance,
                             isFallback: false)
    }
}

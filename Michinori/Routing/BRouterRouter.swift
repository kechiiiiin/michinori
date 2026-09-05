import CoreLocation
import Foundation

/// BRouter の公開サーバ（brouter.de）を直に叩くルータ。第1候補。
///
/// なぜ BRouter か: **経路の好みを `profile=` で指定できる**から。michinori の存在理由は
/// 「国道10号を通す・バイパスを避ける」という自分の好みでルートを組むことであって、
/// 最速の徒歩経路を求めることではない。`MKDirections` にはその手段が無い。
/// おまけに距離が `track-length` で一緒に返ってくる。
///
/// ```
/// GET https://brouter.de/brouter
///       ?lonlats=130.970173,33.728675|130.978730,33.785026
///       &profile=hiking-mountain&alternativeidx=0&format=geojson
/// ```
///
/// ⚠️ **座標は lon,lat の順**（`CLLocationCoordinate2D` と逆）。変換ミスの定番ポイント。
/// ⚠️ 公開サーバのフェアユース・レート制限は明文化されていない。呼ぶ側（`CachingSegmentRouter` と
/// エディタのデバウンス）で叩く回数を抑えている。
struct BRouterRouter: SegmentRouter {
    var profileID: String = RoutingProfile.current
    var session: URLSession = .shared

    enum Failure: LocalizedError {
        case badURL
        case httpStatus(Int, String)
        case emptyGeometry

        var errorDescription: String? {
            switch self {
            case .badURL:
                return "ルーティングの URL を組み立てられませんでした"
            case let .httpStatus(code, body):
                return "BRouter が \(code) を返しました: \(body.prefix(120))"
            case .emptyGeometry:
                return "BRouter が線形を返しませんでした"
            }
        }
    }

    func route(from origin: CLLocationCoordinate2D,
               to destination: CLLocationCoordinate2D) async throws -> RoutedSegment {
        var components = URLComponents(string: "https://brouter.de/brouter")
        components?.queryItems = [
            URLQueryItem(name: "lonlats", value: Self.lonLats(origin, destination)),
            URLQueryItem(name: "profile", value: profileID),
            URLQueryItem(name: "alternativeidx", value: "0"),
            URLQueryItem(name: "format", value: "geojson")
        ]
        guard let url = components?.url else { throw Failure.badURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw Failure.httpStatus(http.statusCode,
                                     String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(GeoJSON.self, from: data)
        guard let feature = decoded.features.first,
              !feature.geometry.coordinates.isEmpty else {
            throw Failure.emptyGeometry
        }

        // coordinates は [lon, lat] または [lon, lat, ele]
        let points: [TrackPoint] = feature.geometry.coordinates.compactMap { triple in
            guard triple.count >= 2 else { return nil }
            return TrackPoint(latitude: triple[1],
                              longitude: triple[0],
                              elevation: triple.count >= 3 ? triple[2] : nil)
        }
        guard points.count >= 2 else { throw Failure.emptyGeometry }

        // track-length は**文字列のメートル**。読めなければ線形から積み上げる
        let meters = feature.properties.trackLength.flatMap(Double.init)
            ?? Self.polylineMeters(points)

        return RoutedSegment(points: points, meters: meters, isFallback: false)
    }

    private static func lonLats(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> String {
        String(format: "%.6f,%.6f|%.6f,%.6f",
               a.longitude, a.latitude, b.longitude, b.latitude)
    }

    private static func polylineMeters(_ points: [TrackPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            total += Haversine.meters(from: points[index - 1].coordinate,
                                      to: points[index].coordinate)
        }
        return total
    }

    // MARK: - レスポンス

    private struct GeoJSON: Decodable {
        struct Feature: Decodable {
            struct Properties: Decodable {
                let trackLength: String?
                enum CodingKeys: String, CodingKey {
                    case trackLength = "track-length"
                }
            }
            struct Geometry: Decodable {
                let coordinates: [[Double]]
            }
            let properties: Properties
            let geometry: Geometry
        }
        let features: [Feature]
    }
}

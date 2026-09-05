import CoreLocation
import Foundation

/// 使うルーティングプロファイル。
///
/// ⚠️ **ここ1箇所だけ**を書き換えれば全体が切り替わるようにしてある。
/// `trekking` は名前に反して**自転車向け**なので使わない（cycleway 最優先・階段を実質禁止）。
/// 歩き用は `hiking-mountain`（poutnikl の Walking-Hiking テンプレート）。
/// 100キロウォーク専用のカスタムプロファイルを brouter.de に投げたら、
/// 返ってきた `custom_…` の id をここへ置き換える。
enum RoutingProfile {
    static let current = "hiking-mountain"
}

/// 2点を道なりに結んだ結果。
struct RoutedSegment {
    /// 線形（始点と終点を含む）
    var points: [TrackPoint]
    /// 距離（メートル）
    var meters: Double
    /// 直線で埋めたか（＝ルーティングに失敗した区間）
    var isFallback: Bool
}

/// ルーティングの差し替え点。
///
/// michinori がルーティングに触るのはこの1メソッドだけ。BRouter が落ちた日でも
/// `MapKitRouter` や `StraightLineRouter` に差し替えれば動く、という約束をここで作っている。
protocol SegmentRouter {
    func route(from origin: CLLocationCoordinate2D,
               to destination: CLLocationCoordinate2D) async throws -> RoutedSegment
}

/// 本命のルータに区間キャッシュとフォールバックを被せたもの。
///
/// - **同じ点ペアは二度引かない**（undo → 置き直しや、ドラッグの往復で無駄に叩かないため）
/// - 本命が失敗したら**直線で埋め、`isFallback` を立てて呼び出し側に知らせる**
/// - ⚠️ **直線で埋めた結果はキャッシュしない。** 一時的に圏外だっただけの区間を
///   ずっと直線のまま覚えてしまうため
actor CachingSegmentRouter {
    private let primary: SegmentRouter
    private let fallback: SegmentRouter
    private var cache: [String: RoutedSegment] = [:]

    init(primary: SegmentRouter = BRouterRouter(),
         fallback: SegmentRouter = StraightLineRouter()) {
        self.primary = primary
        self.fallback = fallback
    }

    /// 区間を引く。**失敗しても throw しない**（必ず直線で埋めて返す）。
    func segment(from origin: CLLocationCoordinate2D,
                 to destination: CLLocationCoordinate2D) async -> RoutedSegment {
        let key = Self.cacheKey(origin, destination)
        if let cached = cache[key] { return cached }

        do {
            let segment = try await primary.route(from: origin, to: destination)
            cache[key] = segment
            return segment
        } catch {
            let straight = (try? await fallback.route(from: origin, to: destination))
                ?? RoutedSegment(points: [TrackPoint(origin), TrackPoint(destination)],
                                 meters: Haversine.meters(from: origin, to: destination),
                                 isFallback: true)
            return RoutedSegment(points: straight.points,
                                 meters: straight.meters,
                                 isFallback: true)
        }
    }

    func clearCache() { cache.removeAll() }

    /// 1e-6 度（≒0.1m）まで丸めて鍵にする。ドラッグで戻ってきた点を同一視するため
    private static func cacheKey(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> String {
        String(format: "%.6f,%.6f|%.6f,%.6f",
               a.latitude, a.longitude, b.latitude, b.longitude)
    }
}

import Foundation
import SwiftData

/// 保存されたルート1本。
///
/// 端末内にしか置かない（iCloud 同期は非スコープ）。一覧に出すのは名前・作成日・距離の3つ。
@Model final class Route {
    var name: String
    var createdAt: Date
    var updatedAt: Date
    /// 総距離のキャッシュ（表示用）。正は `legs` の合計だが、一覧で毎回足し直さないために持つ
    var meters: Double
    /// 引いたときのルーティングプロファイル（"hiking-mountain" / "custom_…"）
    var profileID: String

    @Relationship(deleteRule: .cascade, inverse: \RoutePoint.route)
    var points: [RoutePoint] = []

    @Relationship(deleteRule: .cascade, inverse: \RouteLeg.route)
    var legs: [RouteLeg] = []

    init(name: String,
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         meters: Double = 0,
         profileID: String = RoutingProfile.current) {
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.meters = meters
        self.profileID = profileID
    }

    /// ⚠️ SwiftData の to-many は**配列順序を保証しない**ので、読むときは必ず order で並べ直す
    var orderedPoints: [RoutePoint] { points.sorted { $0.order < $1.order } }
    var orderedLegs: [RouteLeg] { legs.sorted { $0.order < $1.order } }
}

/// 地図に置いた点（ドラッグで動く方）。
@Model final class RoutePoint {
    /// ⚠️ 必須。配列の並びには頼らない
    var order: Int
    var latitude: Double
    var longitude: Double
    var route: Route?

    init(order: Int, latitude: Double, longitude: Double) {
        self.order = order
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// `points[i]` → `points[i+1]` を道なりに結んだ線形1本。
@Model final class RouteLeg {
    /// ⚠️ 必須。配列の並びには頼らない
    var order: Int
    /// この区間の距離（メートル）。BRouter の `track-length`、直線なら Haversine の値
    var meters: Double
    /// 直線で埋めた区間か（通信に失敗した区間。UI では破線、GPX では `<desc>` に本数を書く）
    var isFallback: Bool
    /// 線形の座標列。数百〜千点になるので `Data` に詰めて1カラムで持つ（`CoordinatePacking`）
    var packed: Data
    var route: Route?

    init(order: Int, meters: Double, isFallback: Bool, packed: Data) {
        self.order = order
        self.meters = meters
        self.isFallback = isFallback
        self.packed = packed
    }

    var trackPoints: [TrackPoint] { CoordinatePacking.unpack(packed) }
}

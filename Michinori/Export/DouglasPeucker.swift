import CoreLocation
import Foundation

/// 線形の点を間引く（Ramer–Douglas–Peucker）。
///
/// なぜ必要か: **トラックポイントが多すぎる GPX は Zepp / Active Max の取り込みと表示が不安定**
/// という既知の落とし穴がある。20km を BRouter で引くと数千点になるので、書き出す前に落とす。
///
/// ⚠️ 間引くのは**書き出しのときだけ**。SwiftData には元の線形を残す（再編集で劣化させない）。
enum DouglasPeucker {
    /// 許容誤差（メートル）の既定値。5〜10m なら道の形は保たれる
    static let defaultTolerance: Double = 8

    /// 1本の GPX に入れる点数の上限の目安。超えたら誤差を上げて引き直す
    static let defaultMaxPoints = 1_500

    /// 誤差を守りつつ、点数が上限を超えたら誤差を倍にして再実行する。
    static func simplify(_ points: [TrackPoint],
                         tolerance: Double = defaultTolerance,
                         maxPoints: Int = defaultMaxPoints) -> [TrackPoint] {
        guard points.count > 2 else { return points }

        var currentTolerance = tolerance
        var result = reduce(points, tolerance: currentTolerance)
        // 上限に収まるまで誤差を倍にする。10回で 8m → 約8km 相当なので必ず抜ける
        var attempts = 0
        while result.count > maxPoints, attempts < 10 {
            currentTolerance *= 2
            result = reduce(points, tolerance: currentTolerance)
            attempts += 1
        }
        return result
    }

    // MARK: - 本体（再帰ではなくスタックで回す。数千点で再帰すると深くなりすぎる）

    private static func reduce(_ points: [TrackPoint], tolerance: Double) -> [TrackPoint] {
        guard points.count > 2 else { return points }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last > first + 1 else { continue }

            var farthest = first
            var maxDistance = 0.0
            for index in (first + 1)..<last {
                let distance = perpendicularMeters(points[index],
                                                   from: points[first],
                                                   to: points[last])
                if distance > maxDistance {
                    maxDistance = distance
                    farthest = index
                }
            }

            if maxDistance > tolerance {
                keep[farthest] = true
                stack.append((first, farthest))
                stack.append((farthest, last))
            }
        }

        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    /// 点と線分の距離（メートル）。
    ///
    /// 数十メートル程度の局所計算なので、緯度経度を**正距円筒で平面に落として**から測る
    /// （経度は cos(緯度) で縮める）。数キロ以内なら誤差は無視できる。
    private static func perpendicularMeters(_ point: TrackPoint,
                                            from start: TrackPoint,
                                            to end: TrackPoint) -> Double {
        let metersPerDegree = 111_320.0
        let scale = cos(start.latitude * .pi / 180)

        let px = (point.longitude - start.longitude) * metersPerDegree * scale
        let py = (point.latitude - start.latitude) * metersPerDegree
        let ex = (end.longitude - start.longitude) * metersPerDegree * scale
        let ey = (end.latitude - start.latitude) * metersPerDegree

        let lengthSquared = ex * ex + ey * ey
        guard lengthSquared > 0 else { return sqrt(px * px + py * py) }

        // 線分上の最近傍へ射影する（端をはみ出したら端で止める）
        let t = max(0, min(1, (px * ex + py * ey) / lengthSquared))
        let dx = px - t * ex
        let dy = py - t * ey
        return sqrt(dx * dx + dy * dy)
    }
}

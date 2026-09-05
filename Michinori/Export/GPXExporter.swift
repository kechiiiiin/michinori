import CoreLocation
import Foundation

/// ルートを GPX 1.1 の文字列にする。
///
/// 構成は vault の既存 GPX（`hestia/hiking/行橋-北方-練習コース.gpx`）に合わせて
/// `<metadata>` ＋ `<wpt>`（自分で置いた点）＋ `<trk>`（道なりの全点列）。
///
/// **決めごと**
/// - `<trkseg>` は**1本にまとめる**（区間ごとに分けると Zepp 側で分断ルート扱いになる恐れ）
/// - 区間を繋ぐとき、**前区間の終点と次区間の始点が重複する**ので片方を落とす
/// - `<time>` を `<trkpt>` に入れない（これは計画ルートであって走行記録ではない）
/// - `<ele>` は BRouter が返した3要素目。無い点は省く
/// - 直線で埋めた区間があれば `<desc>` に本数を書き残す（黙って混ぜない）
enum GPXExporter {

    struct Result {
        var xml: String
        /// 間引いたあとのトラックポイント数（画面に出して当たりを取るため）
        var trackPointCount: Int
    }

    static func export(name: String,
                       waypoints: [CLLocationCoordinate2D],
                       legs: [(points: [TrackPoint], isFallback: Bool)],
                       totalMeters: Double,
                       createdAt: Date = Date(),
                       tolerance: Double = DouglasPeucker.defaultTolerance) -> Result {
        let merged = mergeLegs(legs.map(\.points))
        let thinned = DouglasPeucker.simplify(merged, tolerance: tolerance)
        let fallbackCount = legs.filter(\.isFallback).count

        let displayName = name.isEmpty ? "michinori" : name
        let kilometers = String(format: "%.1f", totalMeters / 1000)
        let fallbackNote = fallbackCount == 0
            ? "なし"
            : "\(fallbackCount)区間（通信に失敗したため直線で結んでいる）"
        let description = """
            michinori で作成。BRouter \(RoutingProfile.current) で道なりに接続。\
            総距離 \(kilometers)km / 点 \(waypoints.count)個 / \
            トラックポイント \(thinned.count)点（間引き後）。直線フォールバック区間: \(fallbackNote)。
            """

        var xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="michinori"
                 xmlns="http://www.topografix.com/GPX/1/1"
                 xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                 xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
              <metadata>
                <name>\(escape(displayName))</name>
                <desc>\(escape(description))</desc>
                <time>\(iso8601.string(from: createdAt))</time>
              </metadata>

            """

        for (index, waypoint) in waypoints.enumerated() {
            xml += "  <wpt lat=\"\(coordinate(waypoint.latitude))\" lon=\"\(coordinate(waypoint.longitude))\">"
            xml += "<name>P\(index + 1)</name></wpt>\n"
        }

        xml += "  <trk>\n    <name>\(escape(displayName))</name>\n    <trkseg>\n"
        for point in thinned {
            xml += "      <trkpt lat=\"\(coordinate(point.latitude))\" lon=\"\(coordinate(point.longitude))\">"
            if let elevation = point.elevation {
                xml += "<ele>\(String(format: "%.1f", elevation))</ele>"
            }
            xml += "</trkpt>\n"
        }
        xml += "    </trkseg>\n  </trk>\n</gpx>\n"

        return Result(xml: xml, trackPointCount: thinned.count)
    }

    /// 区間の線形を1本に繋ぐ。継ぎ目の重複点を落とす
    static func mergeLegs(_ legs: [[TrackPoint]]) -> [TrackPoint] {
        var merged: [TrackPoint] = []
        for leg in legs {
            guard !leg.isEmpty else { continue }
            if let last = merged.last, let first = leg.first,
               isSamePoint(last, first) {
                merged.append(contentsOf: leg.dropFirst())
            } else {
                merged.append(contentsOf: leg)
            }
        }
        return merged
    }

    private static func isSamePoint(_ a: TrackPoint, _ b: TrackPoint) -> Bool {
        // 1e-7 度 ≒ 1cm。BRouter は同じ座標を返すが、丸め差に耐えるようにしておく
        abs(a.latitude - b.latitude) < 1e-7 && abs(a.longitude - b.longitude) < 1e-7
    }

    private static func coordinate(_ value: Double) -> String {
        String(format: "%.6f", value)
    }

    /// ⚠️ ルート名は Keisuke の自由入力なので、XML エスケープは必須
    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static let iso8601: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter
    }()
}

import CoreLocation
import Foundation

/// 線形の1点。標高は BRouter が返したときだけ入る（MapKit や直線フォールバックでは nil）。
struct TrackPoint: Hashable {
    var latitude: Double
    var longitude: Double
    var elevation: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(latitude: Double, longitude: Double, elevation: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.elevation = elevation
    }

    init(_ coordinate: CLLocationCoordinate2D, elevation: Double? = nil) {
        self.init(latitude: coordinate.latitude,
                  longitude: coordinate.longitude,
                  elevation: elevation)
    }
}

/// 座標列 ⇄ `Data` の詰め替え。
///
/// なぜ必要か: `CLLocationCoordinate2D` は `Codable` ではないので SwiftData にそのまま入らない。
/// 区間の線形は数百〜千点になるため、`Double` を素で並べて1カラムに持つのがいちばん素直だった。
///
/// 形式は **(緯度, 経度, 標高) の3つ組を並べたもの**。標高が無い点は `NaN` を入れて、
/// 読むときに `nil` へ戻す。
///
/// ⚠️ エンディアンは同一端末内でしか保証しない（iCloud 同期は非スコープなので問題にならない）。
enum CoordinatePacking {
    private static let stride = 3

    static func pack(_ points: [TrackPoint]) -> Data {
        var flat: [Double] = []
        flat.reserveCapacity(points.count * stride)
        for point in points {
            flat.append(point.latitude)
            flat.append(point.longitude)
            flat.append(point.elevation ?? Double.nan)
        }
        return flat.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func unpack(_ data: Data) -> [TrackPoint] {
        let size = MemoryLayout<Double>.size
        let count = data.count / (size * stride)
        guard count > 0 else { return [] }

        // ⚠️ `bindMemory` はアライメントを前提にするので、Data からは常に loadUnaligned で読む
        return data.withUnsafeBytes { raw -> [TrackPoint] in
            var result: [TrackPoint] = []
            result.reserveCapacity(count)
            for index in 0..<count {
                let base = index * stride * size
                let latitude = raw.loadUnaligned(fromByteOffset: base, as: Double.self)
                let longitude = raw.loadUnaligned(fromByteOffset: base + size, as: Double.self)
                let elevation = raw.loadUnaligned(fromByteOffset: base + size * 2, as: Double.self)
                result.append(TrackPoint(latitude: latitude,
                                         longitude: longitude,
                                         elevation: elevation.isNaN ? nil : elevation))
            }
            return result
        }
    }
}

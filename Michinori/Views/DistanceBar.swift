import SwiftUI

/// 画面上部に常時出す総距離。**このアプリの主役の数字**なので大きく出す。
struct DistanceBar: View {
    var meters: Double
    var pointCount: Int
    var pendingCount: Int
    var fallbackCount: Int

    private var kilometers: String {
        String(format: "%.2f", meters / 1000)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(kilometers)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("km")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Spacer()

                if pendingCount > 0 {
                    ProgressView()
                        .controlSize(.small)
                    Text("\(pendingCount)区間を計算中")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Text("点 \(pointCount)個")
                if fallbackCount > 0 {
                    // ⚠️ 直線で埋めた区間は道なりではない。黙って距離に混ぜず、必ず見せる
                    Label("直線 \(fallbackCount)区間", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
    }
}

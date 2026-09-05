import SwiftData
import SwiftUI

/// michinori（道のり）— 地図をタップして点を置くと、点と点を徒歩ルーティングで道なりに繋ぎ、
/// 総距離を常時表示する。ルートは端末に保存し、GPX にして共有シートから Zepp へ渡す。
///
/// **サーバは持たない。ルートは端末の外に出ない**（GPX を自分で共有したときだけ出る）。
@main
struct MichinoriApp: App {
    /// SwiftData の入れ物。ルートは端末内だけに置く（iCloud 同期は非スコープ）
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Route.self, RoutePoint.self, RouteLeg.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: false))
        } catch {
            // ここで落ちるのはスキーマ不整合など開発時の事故。黙って握りつぶすと
            // 「保存したはずのルートが消える」形で出てくるので、原因を残して落とす
            fatalError("SwiftData の初期化に失敗した: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RouteListView()
        }
        .modelContainer(container)
    }
}

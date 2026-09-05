import CoreLocation
import Foundation
import SwiftData
import SwiftUI

/// 編集中のルートの状態と、区間の引き直しの段取りを持つ。
///
/// **リクエストを増やさない設計**（全区間を毎回引き直す実装は絶対にしない）:
/// - 点を1つ足す → 区間1本を引く（**1リクエスト**）
/// - 点をドラッグ → その点の**前後2本だけ**引き直す（両端なら1本）
/// - undo → 末尾の点と区間を落とすだけ（**リクエスト0**）
/// - 同じ点ペアは `CachingSegmentRouter` が覚えているので二度引かない
@MainActor
final class RouteEditorModel: ObservableObject {

    // MARK: - 状態

    @Published var name: String
    @Published private(set) var points: [CLLocationCoordinate2D] = []
    /// legs[i] は points[i] → points[i+1]。**必ず points.count - 1 本**に保つ
    @Published private(set) var legs: [MapLeg] = []
    /// 地図に「描き直せ」と伝えるための番号
    @Published private(set) var revision = 0
    /// 引いている最中の区間の本数（画面のスピナー用）
    @Published private(set) var pendingCount = 0
    /// 共有シートに渡す GPX。`refreshGPXFile()` で作り直す
    @Published private(set) var gpxFile: GPXFile?
    @Published var errorMessage: String?

    private let router: CachingSegmentRouter
    /// 編集元の保存済みルート（新規なら nil）
    private var editingRoute: Route?

    var totalMeters: Double { legs.reduce(0) { $0 + $1.meters } }
    var fallbackCount: Int { legs.filter { $0.isFallback && !$0.isPending }.count }
    var canUndo: Bool { !points.isEmpty }

    init(route: Route? = nil, router: CachingSegmentRouter = CachingSegmentRouter()) {
        self.router = router
        self.editingRoute = route
        self.name = route?.name ?? ""

        if let route {
            // ⚠️ SwiftData の to-many は順序を保証しないので order で並べ直してから読む
            points = route.orderedPoints.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            legs = route.orderedLegs.map {
                MapLeg(id: UUID(),
                       points: $0.trackPoints,
                       meters: $0.meters,
                       isFallback: $0.isFallback,
                       isPending: false)
            }
        }
    }

    // MARK: - 編集

    func addPoint(_ coordinate: CLLocationCoordinate2D) {
        points.append(coordinate)
        guard points.count >= 2 else {
            bump()
            return
        }
        // 新しい末尾の区間を1本だけ引く
        reroute(legIndex: points.count - 2)
    }

    /// ピンを動かした。前後2区間だけ引き直す
    func movePoint(at index: Int, to coordinate: CLLocationCoordinate2D) {
        guard points.indices.contains(index) else { return }
        points[index] = coordinate

        for legIndex in [index - 1, index] where legs.indices.contains(legIndex) {
            reroute(legIndex: legIndex)
        }
        bump()
    }

    /// 最後の点を消す。**通信は一切しない**
    func undo() {
        guard !points.isEmpty else { return }
        points.removeLast()
        if !legs.isEmpty { legs.removeLast() }
        recountPending()
        bump()
    }

    func clearAll() {
        points.removeAll()
        legs.removeAll()
        recountPending()
        bump()
    }

    // MARK: - 区間の引き直し

    /// 引く前の暫定として描く直線（線が一瞬も無い状態を作らないため）
    private func straightLeg(from origin: CLLocationCoordinate2D,
                             to destination: CLLocationCoordinate2D) -> MapLeg {
        MapLeg(id: UUID(),
               points: [TrackPoint(origin), TrackPoint(destination)],
               meters: Haversine.meters(from: origin, to: destination),
               isFallback: false,
               isPending: true)
    }

    /// 区間1本を引き直す。
    ///
    /// 結果の当て先は**添字ではなく id で探す**。引いている間に undo やもう一度のドラッグが
    /// 入ると添字がずれるため（ずれた場所へ書き戻すのがいちばん厄介なバグになる）。
    private func reroute(legIndex: Int) {
        guard points.indices.contains(legIndex),
              points.indices.contains(legIndex + 1) else { return }

        let origin = points[legIndex]
        let destination = points[legIndex + 1]
        let token = UUID()

        var placeholder = straightLeg(from: origin, to: destination)
        placeholder = MapLeg(id: token,
                             points: placeholder.points,
                             meters: placeholder.meters,
                             isFallback: false,
                             isPending: true)
        if legs.indices.contains(legIndex) {
            legs[legIndex] = placeholder
        } else {
            legs.append(placeholder)
        }
        recountPending()
        bump()

        Task { [weak self] in
            // 300ms のデバウンス。連続タップやドラッグの直後の取り消しを叩かずに済ませる
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard let self else { return }
            guard self.legs.contains(where: { $0.id == token }) else { return }

            let segment = await self.router.segment(from: origin, to: destination)

            guard let index = self.legs.firstIndex(where: { $0.id == token }) else { return }
            self.legs[index] = MapLeg(id: token,
                                      points: segment.points,
                                      meters: segment.meters,
                                      isFallback: segment.isFallback,
                                      isPending: false)
            if segment.isFallback {
                self.errorMessage = "この区間はルーティングに失敗したので直線で結びました（オレンジの破線）"
            }
            self.recountPending()
            self.bump()
        }
    }

    private func recountPending() {
        pendingCount = legs.filter(\.isPending).count
    }

    private func bump() {
        revision &+= 1
    }

    // MARK: - 保存

    /// 保存する。既存ルートなら中身を差し替え、新規なら作る。
    ///
    /// 点と区間は**消してから作り直す**（差分更新は order の付け替えが絡んで壊れやすい割に、
    /// 数十件しかないので得がない）。
    @discardableResult
    func save(into context: ModelContext) -> Route {
        let route: Route
        if let existing = editingRoute {
            route = existing
            for point in existing.points { context.delete(point) }
            for leg in existing.legs { context.delete(leg) }
            existing.points.removeAll()
            existing.legs.removeAll()
        } else {
            route = Route(name: name)
            context.insert(route)
            editingRoute = route
        }

        route.name = name.isEmpty ? defaultName() : name
        route.updatedAt = Date()
        route.meters = totalMeters
        route.profileID = RoutingProfile.current

        for (index, coordinate) in points.enumerated() {
            let point = RoutePoint(order: index,
                                   latitude: coordinate.latitude,
                                   longitude: coordinate.longitude)
            point.route = route
            context.insert(point)
        }
        for (index, leg) in legs.enumerated() {
            let stored = RouteLeg(order: index,
                                  meters: leg.meters,
                                  isFallback: leg.isFallback,
                                  packed: CoordinatePacking.pack(leg.points))
            stored.route = route
            context.insert(stored)
        }

        name = route.name
        return route
    }

    func defaultName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: Date())) のルート"
    }

    // MARK: - 書き出し

    /// GPX を作り直して `gpxFile` に載せる（`ShareLink` がこれを持っていく）。
    func refreshGPXFile() {
        guard legs.contains(where: { $0.points.count >= 2 }) else {
            gpxFile = nil
            return
        }
        let displayName = name.isEmpty ? defaultName() : name
        let result = GPXExporter.export(
            name: displayName,
            waypoints: points,
            legs: legs.map { (points: $0.points, isFallback: $0.isFallback) },
            totalMeters: totalMeters)

        do {
            gpxFile = try GPXFile.write(xml: result.xml,
                                        trackPointCount: result.trackPointCount,
                                        routeName: displayName)
        } catch {
            gpxFile = nil
            errorMessage = "GPX の書き出しに失敗しました: \(error.localizedDescription)"
        }
    }
}

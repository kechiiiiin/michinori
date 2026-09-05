import CoreLocation
import MapKit
import SwiftUI

/// 地図に描く区間1本ぶん（`MKMapView` に渡すための素の値）。
struct MapLeg: Identifiable {
    let id: UUID
    var points: [TrackPoint]
    var meters: Double
    /// 直線で埋めた区間（＝ルーティングに失敗した）
    var isFallback: Bool
    /// ルーティングの結果待ち（暫定の直線を描いている）
    var isPending: Bool
}

/// 置いた点。ドラッグで座標が変わるので `MKAnnotation` は class で持つ。
final class RoutePointAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    /// points 配列での位置。ドラッグ完了時にどの点が動いたかを呼び出し側へ返すのに使う
    let index: Int

    var title: String? { "P\(index + 1)" }

    init(index: Int, coordinate: CLLocationCoordinate2D) {
        self.index = index
        self.coordinate = coordinate
    }
}

/// 区間のポリライン。描き分けのために種別を持たせる。
final class LegPolyline: MKPolyline {
    var isFallback = false
    var isPending = false
}

/// `MKMapView` を SwiftUI から使うためのラッパ。
///
/// なぜ UIKit に倒すか: **ピンのドラッグが michinori の中核操作**（通したい道からズレたら直す）で、
/// `MKAnnotationView.isDraggable` ＋ `MKMapViewDelegate` の `didChange newState:` は正式サポートの
/// 枯れた API。SwiftUI 標準 `Annotation` のドラッグは確立した実装例が見つからず、
/// 地図自体のパン／ズームとジェスチャが競合するという報告もある。ここを未確認の上に建てない。
struct MapView: UIViewRepresentable {
    /// 置いた点（順番どおり）
    var points: [CLLocationCoordinate2D]
    /// points[i] → points[i+1] の線形
    var legs: [MapLeg]
    /// 中身が変わるたびに増える番号。これが変わったときだけ描き直す
    var revision: Int
    /// 増やすと現在地へ寄せる
    var centerOnUserRequest: Int
    var onTap: (CLLocationCoordinate2D) -> Void
    var onDragEnd: (Int, CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.showsCompass = true
        mapView.pointOfInterestFilter = .excludingAll

        // タップで点を追加する。地図自身のジェスチャと同時に成立させる（パンやズームを潰さない）
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        mapView.addGestureRecognizer(tap)

        // 起点は日本全体。⚠️ 自宅や特定の座標をソースに書かない（現在地ボタンで寄せる）
        mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.0, longitude: 135.0),
            span: MKCoordinateSpan(latitudeDelta: 12, longitudeDelta: 12)), animated: false)

        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.parent = self

        if context.coordinator.lastRevision != revision {
            context.coordinator.lastRevision = revision
            redraw(mapView, coordinator: context.coordinator)
        }

        if context.coordinator.lastCenterRequest != centerOnUserRequest {
            context.coordinator.lastCenterRequest = centerOnUserRequest
            centerOnUser(mapView)
        }
    }

    // MARK: - 描画

    /// 差分は取らずに全部消して引き直す。点は多くても数十個なので、これで足りるし壊れない。
    /// （ドラッグ中は revision が動かないので、掴んでいるピンが消えることはない）
    private func redraw(_ mapView: MKMapView, coordinator: Coordinator) {
        mapView.removeAnnotations(mapView.annotations.filter { $0 is RoutePointAnnotation })
        mapView.removeOverlays(mapView.overlays)

        mapView.addAnnotations(points.enumerated().map {
            RoutePointAnnotation(index: $0.offset, coordinate: $0.element)
        })

        for leg in legs where leg.points.count >= 2 {
            var coordinates = leg.points.map(\.coordinate)
            let polyline = LegPolyline(coordinates: &coordinates, count: coordinates.count)
            polyline.isFallback = leg.isFallback
            polyline.isPending = leg.isPending
            mapView.addOverlay(polyline)
        }

        // 保存済みルートを開いた直後だけ、全体が入るように寄せる
        if !coordinator.hasFittedOnce, !points.isEmpty {
            coordinator.hasFittedOnce = true
            fit(mapView, to: points)
        }
    }

    private func fit(_ mapView: MKMapView, to coordinates: [CLLocationCoordinate2D]) {
        guard let first = coordinates.first else { return }
        var rect = MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 0, height: 0))
        for coordinate in coordinates.dropFirst() {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        mapView.setVisibleMapRect(
            rect,
            edgePadding: UIEdgeInsets(top: 80, left: 60, bottom: 120, right: 60),
            animated: false)
    }

    private func centerOnUser(_ mapView: MKMapView) {
        let coordinate = mapView.userLocation.coordinate
        // 位置情報がまだ来ていないと (0,0) が入っている。そこへ飛ばない
        guard CLLocationCoordinate2DIsValid(coordinate),
              abs(coordinate.latitude) > 0.0001 || abs(coordinate.longitude) > 0.0001 else {
            return
        }
        mapView.setRegion(MKCoordinateRegion(center: coordinate,
                                             latitudinalMeters: 1_200,
                                             longitudinalMeters: 1_200), animated: true)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MapView
        var lastRevision = -1
        var lastCenterRequest = 0
        var hasFittedOnce = false

        init(_ parent: MapView) {
            self.parent = parent
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let mapView = recognizer.view as? MKMapView else { return }
            let location = recognizer.location(in: mapView)

            // ピンをタップしたときは点を追加しない（掴んで動かしたいだけなので）
            if let hit = mapView.hitTest(location, with: nil),
               hit is MKAnnotationView || hit.superview is MKAnnotationView {
                return
            }

            parent.onTap(mapView.convert(location, toCoordinateFrom: mapView))
        }

        /// 地図のパン・ズームを潰さないために同時認識を許す
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? RoutePointAnnotation else { return nil }

            let identifier = "routePoint"
            let view: MKMarkerAnnotationView
            if let reused = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                as? MKMarkerAnnotationView {
                reused.annotation = annotation
                view = reused
            } else {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }

            // ⭐ これがドラッグ移動の本体。長押しで掴んで動かせるようになる
            view.isDraggable = true
            view.canShowCallout = false
            view.glyphText = "\(point.index + 1)"
            view.markerTintColor = .systemBlue
            return view
        }

        /// ドラッグの終わりだけを拾う。⚠️ 途中で叩くとルーティングを何十回も呼んでしまう
        func mapView(_ mapView: MKMapView,
                     annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState,
                     fromOldState oldState: MKAnnotationView.DragState) {
            guard let point = view.annotation as? RoutePointAnnotation else { return }

            switch newState {
            case .ending:
                view.dragState = .none
                parent.onDragEnd(point.index, point.coordinate)
            case .canceling:
                view.dragState = .none
            default:
                break
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? LegPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.lineWidth = 5

            if polyline.isPending {
                // 引いている最中の暫定線（薄いグレーの破線）
                renderer.strokeColor = UIColor.systemGray.withAlphaComponent(0.6)
                renderer.lineDashPattern = [2, 6]
            } else if polyline.isFallback {
                // ⚠️ 直線で埋めた区間。道なりではないことが一目で分かるように
                renderer.strokeColor = UIColor.systemOrange
                renderer.lineDashPattern = [6, 6]
            } else {
                renderer.strokeColor = UIColor.systemBlue.withAlphaComponent(0.85)
            }
            return renderer
        }
    }
}

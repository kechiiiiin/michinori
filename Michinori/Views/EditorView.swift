import CoreLocation
import SwiftData
import SwiftUI

/// ルートの編集画面。地図 ＋ 上部の総距離 ＋ 下部の操作ボタン。
///
/// 操作は4つだけに絞ってある: **置く（タップ）/ 直す（ドラッグ）/ 戻す（undo）/ 出す（GPX 共有）**。
struct EditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model: RouteEditorModel
    @StateObject private var location = LocationAuthorizer()

    @State private var centerOnUserRequest = 0
    @State private var isNamingForSave = false
    @State private var draftName = ""
    @State private var showClearConfirmation = false
    @State private var savedNotice = false

    init(route: Route? = nil) {
        _model = StateObject(wrappedValue: RouteEditorModel(route: route))
    }

    var body: some View {
        VStack(spacing: 0) {
            DistanceBar(meters: model.totalMeters,
                        pointCount: model.points.count,
                        pendingCount: model.pendingCount,
                        fallbackCount: model.fallbackCount)

            ZStack(alignment: .bottomTrailing) {
                MapView(points: model.points,
                        legs: model.legs,
                        revision: model.revision,
                        centerOnUserRequest: centerOnUserRequest,
                        onTap: { model.addPoint($0) },
                        onDragEnd: { index, coordinate in
                            model.movePoint(at: index, to: coordinate)
                        })
                .ignoresSafeArea(edges: .bottom)

                currentLocationButton
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }

            toolbarRow
        }
        .navigationTitle(model.name.isEmpty ? "新しいルート" : model.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let file = model.gpxFile {
                    ShareLink(item: file,
                              preview: SharePreview(model.name.isEmpty ? "michinori" : model.name)) {
                        Label("GPX を共有", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        // 中身が変わるたびに GPX を作り直しておく（ShareLink は item を先に要求するため）
        .task(id: model.revision) {
            model.refreshGPXFile()
        }
        .onAppear { location.requestIfNeeded() }
        .alert("ルート名", isPresented: $isNamingForSave) {
            TextField("例: 行橋→北方 練習", text: $draftName)
            Button("保存") { commitSave() }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("この名前で一覧に出ます")
        }
        .confirmationDialog("置いた点を全部消しますか？", isPresented: $showClearConfirmation) {
            Button("全部消す", role: .destructive) { model.clearAll() }
            Button("やめる", role: .cancel) { }
        }
        .alert("保存しました", isPresented: $savedNotice) {
            Button("OK") { }
        }
        .alert("お知らせ",
               isPresented: Binding(get: { model.errorMessage != nil },
                                    set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - 部品

    private var currentLocationButton: some View {
        Button {
            location.requestIfNeeded()
            centerOnUserRequest += 1
        } label: {
            Image(systemName: location.isDenied ? "location.slash" : "location.fill")
                .font(.title3)
                .padding(12)
                .background(.thinMaterial, in: Circle())
        }
        .accessibilityLabel("現在地へ寄せる")
    }

    private var toolbarRow: some View {
        HStack(spacing: 12) {
            Button {
                model.undo()
            } label: {
                Label("戻す", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!model.canUndo)

            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label("全消し", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .disabled(model.points.isEmpty)

            Button {
                draftName = model.name.isEmpty ? model.defaultName() : model.name
                isNamingForSave = true
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .disabled(model.points.count < 2)
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private func commitSave() {
        model.name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        model.save(into: modelContext)
        do {
            try modelContext.save()
            savedNotice = true
        } catch {
            model.errorMessage = "保存に失敗しました: \(error.localizedDescription)"
        }
    }
}

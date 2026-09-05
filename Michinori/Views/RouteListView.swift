import SwiftData
import SwiftUI

/// 保存済みルートの一覧（アプリの入口）。名前・作成日・距離を出し、選べば続きから編集できる。
struct RouteListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.updatedAt, order: .reverse) private var routes: [Route]

    var body: some View {
        NavigationStack {
            Group {
                if routes.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(routes) { route in
                            NavigationLink {
                                EditorView(route: route)
                            } label: {
                                row(for: route)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("michinori")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        EditorView()
                    } label: {
                        Label("新規", systemImage: "plus")
                    }
                }
            }
        }
    }

    private func row(for route: Route) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(route.name)
                .font(.headline)
            HStack(spacing: 10) {
                Text(String(format: "%.2f km", route.meters / 1000))
                    .monospacedDigit()
                Text(route.createdAt, format: .dateTime.year().month().day())
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("ルートがありません", systemImage: "map")
        } description: {
            Text("右上の ＋ から始めて、地図をタップして点を置いてください。点と点は道なりに繋がります。")
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            // points / legs は deleteRule: .cascade で一緒に消える
            modelContext.delete(routes[index])
        }
        try? modelContext.save()
    }
}

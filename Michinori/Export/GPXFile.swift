import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// ⚠️ `.gpx` に Apple 標準の UTI は無い。`com.topografix.gpx` は OpenGpxTracker・OsmAnd 等が
    /// 各自 `UTExportedTypeDeclarations` で宣言している業界慣行の識別子で、Info.plist にも
    /// 同じものを書いてある（片方だけだと共有シートで .gpx として扱われない）。
    static let gpx = UTType(exportedAs: "com.topografix.gpx")
}

/// 共有シートに渡す GPX ファイル。
///
/// 「ファイル」アプリを経由せず `ShareLink` から直接 Zepp へ渡すための入れ物。
/// 実体は一時ディレクトリに書き出した `.gpx`。
struct GPXFile: Transferable, Identifiable {
    let id = UUID()
    let url: URL
    /// 間引いたあとの点数（画面に出して Zepp の受け入れ上限の当たりを取る）
    let trackPointCount: Int

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .gpx) { file in
            SentTransferredFile(file.url)
        }
    }

    /// GPX を一時ディレクトリに書き出す。
    ///
    /// ファイル名がそのまま共有先に渡るので、日付とルート名から人が読める名前を作る。
    static func write(xml: String, trackPointCount: Int, routeName: String) throws -> GPXFile {
        let stamp = DateFormatter.fileStamp.string(from: Date())
        let safeName = routeName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safeName.isEmpty ? "michinori" : safeName

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gpx", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("\(stamp)-\(base).gpx")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        return GPXFile(url: url, trackPointCount: trackPointCount)
    }
}

private extension DateFormatter {
    static let fileStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

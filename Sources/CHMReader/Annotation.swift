import AppKit
import Foundation
import SwiftData

@Model
final class Annotation {
    @Attribute(.unique) var id: UUID
    var bookKey: String
    var bookTitle: String
    var pagePath: String
    var pageTitle: String
    var exact: String
    var prefix: String
    var suffix: String
    var start: Int
    var end: Int
    var colorName: String
    var note: String
    var createdAt: Date
    var updatedAt: Date
    /// "highlight" (anchored to selected text) or "sticky" (a note placed at a spot). Defaults keep old stores migrating.
    var kind: String = "highlight"
    /// Sticky notes on PDF pages: position in page coordinates.
    var x: Double = 0
    var y: Double = 0

    init(
        bookKey: String, bookTitle: String, pagePath: String, pageTitle: String,
        exact: String, prefix: String, suffix: String, start: Int, end: Int, color: HighlightColor
    ) {
        id = UUID()
        self.bookKey = bookKey
        self.bookTitle = bookTitle
        self.pagePath = pagePath
        self.pageTitle = pageTitle
        self.exact = exact
        self.prefix = prefix
        self.suffix = suffix
        self.start = start
        self.end = end
        colorName = color.rawValue
        note = ""
        createdAt = .now
        updatedAt = .now
    }

    var isSticky: Bool { kind == "sticky" }

    /// A detached copy with the same id, kept to restore the annotation after it's deleted.
    func duplicate() -> Annotation {
        let copy = Annotation(
            bookKey: bookKey, bookTitle: bookTitle, pagePath: pagePath, pageTitle: pageTitle,
            exact: exact, prefix: prefix, suffix: suffix, start: start, end: end, color: color)
        copy.id = id
        copy.note = note
        copy.createdAt = createdAt
        copy.updatedAt = updatedAt
        copy.kind = kind
        copy.x = x
        copy.y = y
        return copy
    }

    var color: HighlightColor {
        get { HighlightColor(rawValue: colorName) ?? .yellow }
        set { colorName = newValue.rawValue }
    }

    /// Payload consumed by `chmReader.apply` in the page script.
    var jsPayload: [String: Any] {
        [
            "id": id.uuidString, "color": colorName, "note": !note.isEmpty, "kind": kind,
            "exact": exact, "prefix": prefix, "suffix": suffix, "start": start, "end": end,
        ]
    }
}

enum AnnotationStore {
    @MainActor static let container: ModelContainer = {
        let dir = URL.applicationSupportDirectory.appending(path: "CHMReader", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let config = ModelConfiguration(url: dir.appending(path: "annotations.store"))
        do {
            return try ModelContainer(for: Annotation.self, configurations: config)
        } catch {
            fatalError("無法開啟筆記資料庫：\(error)")
        }
    }()
}

enum NotesExporter {
    static func markdown(bookTitle: String, annotations: [Annotation]) -> String {
        var out = "# \(bookTitle)\n\n"
        var lastPage: String?
        for a in annotations {
            if a.pagePath != lastPage {
                out += "## \(a.pageTitle.isEmpty ? a.pagePath : a.pageTitle)\n\n"
                lastPage = a.pagePath
            }
            if a.isSticky {
                out += "📝 便利貼\n\n"
            } else {
                out += a.exact.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n") + "\n\n"
            }
            if !a.note.isEmpty { out += a.note + "\n\n" }
        }
        return out
    }

    @MainActor static func export(bookTitle: String, annotations: [Annotation]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(bookTitle) 筆記.md"
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? markdown(bookTitle: bookTitle, annotations: annotations).write(to: url, atomically: true, encoding: .utf8)
    }
}

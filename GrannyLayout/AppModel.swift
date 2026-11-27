import SwiftUI
import UIKit

struct ShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

enum Route: Hashable {
    case canvas(UUID)
    case assemble(UUID)
}

struct PendingCapture: Identifiable {
    let id = UUID()
    let image: UIImage
    var rows: Int
    var cols: Int
}

@MainActor
final class AppModel: ObservableObject {
    @Published var library = Library() { didSet { if library != oldValue { persist() } } }
    @Published var path: [Route] = []
    @Published var capturing = false
    @Published var renamingBlanket = false
    @Published var addingSquareTo: UUID?
    @Published var pending: PendingCapture?
    @Published var share: ShareItems?
    @Published var showMilestone = false
    @Published var toast: String?
    @Published private(set) var exportReviewReady = false
    private var savedLayout = false
    @Published var undo: [UUID: [Blanket]] = [:]

    let testing: Bool
    let folder: URL
    private var toastTask: Task<Void, Never>?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        testing = Launch.has("-ui-testing", in: arguments)
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        folder = base.appendingPathComponent(testing ? "Granny-ui-\(Launch.value("-data-id", in: arguments) ?? "x")" : "Granny", isDirectory: true)
        if testing && Launch.has("-reset", in: arguments) { try? FileManager.default.removeItem(at: folder) }
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("squares"), withIntermediateDirectories: true)
        if let raw = try? Data(contentsOf: folder.appendingPathComponent("library.json")),
           let saved = try? JSONDecoder().decode(Library.self, from: raw) {
            library = saved
        }
        if testing, let fixture = Launch.value("-fixture", in: arguments) { Fixtures.apply(fixture, to: self) }
    }

    private func persist() {
        do {
            let raw = try JSONEncoder().encode(library)
            try raw.write(to: folder.appendingPathComponent("library.json"), options: .atomic)
            savedLayout = true
        } catch { savedLayout = false }
    }

    func notify(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled { self.toast = nil }
        }
    }


    private var cache: [String: UIImage] = [:]

    func image(_ name: String?) -> UIImage? {
        guard let name, !name.contains("/") else { return nil }
        if let hit = cache[name] { return hit }
        let img = UIImage(contentsOfFile: folder.appendingPathComponent("squares").appendingPathComponent(name).path)
        cache[name] = img
        return img
    }

    func savePhoto(_ image: UIImage) -> String? {
        guard let data = ImageTools.jpeg(image) else { return nil }
        let name = UUID().uuidString + ".jpg"
        guard (try? data.write(to: folder.appendingPathComponent("squares").appendingPathComponent(name))) != nil else { return nil }
        cache[name] = UIImage(data: data)
        return name
    }

    func makeSquare(_ image: UIImage, label: String) -> Square {
        Square(label: label, photo: savePhoto(image), color: ImageTools.mainColor(image))
    }


    func blanket(_ id: UUID) -> Blanket? { library.blankets.first { $0.id == id } }

    func update(_ id: UUID, undoable: Bool = true, _ change: (inout Blanket) -> Void) {
        guard let i = library.blankets.firstIndex(where: { $0.id == id }) else { return }
        if undoable { undo[id, default: []].append(library.blankets[i]); if undo[id]!.count > 30 { undo[id]!.removeFirst() } }
        var next = library
        let previous = next.blankets[i].cells
        change(&next.blankets[i])
        let counted = previous != next.blankets[i].cells && !testing
        if counted { next.coreReviewProgress = .recording(next.coreReviewProgress) }
        library = next
        if counted && savedLayout { CoreReview.shared.record(library.coreReviewProgress) }
    }

    func undoLast(_ id: UUID) {
        guard let last = undo[id]?.popLast(), let i = library.blankets.firstIndex(where: { $0.id == id }) else { return }
        library.blankets[i] = last
    }

    func captured(_ image: UIImage?) {
        capturing = false
        guard let image else { return }
        Task {
            let flat = await ImageTools.flattenLayout(image)
            let grid = ImageTools.guessGrid(flat)
            pending = PendingCapture(image: flat, rows: grid.rows, cols: grid.cols)
        }
    }

    func confirm(_ capture: PendingCapture) {
        let pieces = ImageTools.split(capture.image, rows: capture.rows, cols: capture.cols)
        var squares: [Square] = []
        for (r, row) in pieces.enumerated() {
            for (c, piece) in row.enumerated() {
                squares.append(makeSquare(piece, label: Blanket.rowName(r) + "\(c + 1)"))
            }
        }
        var b = Blanket(name: L.f("blanket.default", library.blankets.count + 1), rows: capture.rows, cols: capture.cols, squares: squares)
        b.normalize()
        var next = library
        next.blankets.insert(b, at: 0)
        if !testing { next.coreReviewProgress = .recording(next.coreReviewProgress) }
        library = next
        if savedLayout && !testing { CoreReview.shared.record(library.coreReviewProgress) }
        pending = nil
        path = [.canvas(b.id)]
    }

    func addSquare(_ image: UIImage?, to id: UUID) {
        addingSquareTo = nil
        guard let image, let b = blanket(id) else { return }
        let square = makeSquare(ImageTools.centerSquare(image), label: "+\(b.squares.count + 1)")
        update(id) { b in
            b.squares.append(square)
            if !b.cells.contains(where: { $0 == nil }) { b.rows += 1 }
            b.normalize()
        }
        notify(L.f("square.added", square.label))
    }

    func shuffle(_ id: UUID) {
        guard let b = blanket(id) else { return }
        var rng = SystemRandomNumberGenerator()
        let result = Shuffler.shuffle(b, rng: &rng)
        update(id) { $0 = result }
        let left = result.clashes(threshold: Shuffler.defaultThreshold).count
        notify(left == 0 ? L.t("shuffle.ok") : L.f("shuffle.left", left))
    }

    func delete(_ id: UUID) {
        library.blankets.removeAll { $0.id == id }
        path = []
    }


    func advance(_ id: UUID) {
        let wasFinished = blanket(id)?.finished ?? false
        update(id, undoable: false) { $0.progress = min($0.progress + 1, $0.count) }
        if !wasFinished, blanket(id)?.finished == true, !library.milestones.firstFinished {
            library.milestones.firstFinished = true
            showMilestone = true
        }
    }

    func stepBack(_ id: UUID) { update(id, undoable: false) { $0.progress = max($0.progress - 1, 0) } }


    func export(_ id: UUID) {
        guard let b = blanket(id) else { return }
        let png = Renderer.blanketImage(b, model: self)
        var items: [Any] = [png]
        if let url = write(Renderer.orderPDF(b, model: self), name: b.name, ext: "pdf") { items.append(url) }
        share = ShareItems(items: items)
        exportReviewReady = !testing && !library.review.requested
    }

    func requestExportReview(_ request: () -> Void) {
        var next = library.review
        guard exportReviewReady, CoreReview.shared.attempt(ifEligible: { next.afterExport() }, request) else { return }
        exportReviewReady = false
        library.review = next
    }

    func shareCard(_ id: UUID) {
        guard let b = blanket(id) else { return }
        share = ShareItems(items: [Renderer.shareCard(b, model: self), L.t("share.text")])
    }

    func copyCode(_ id: UUID) {
        guard let b = blanket(id) else { return }
        UIPasteboard.general.string = L.t("code.intro") + "\n" + LayoutCode.make(b)
        notify(L.t("code.copied"))
    }

    func pasteCode(_ id: UUID, text: String?) {
        guard let text, let p = LayoutCode.decode(text) else { return notify(L.t("code.none")) }
        update(id) { LayoutCode.apply(p, to: &$0) }
        notify(L.f("code.applied", p.rows, p.cols))
    }

    private func write(_ data: Data, name: String, ext: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let url = dir.appendingPathComponent(safe.isEmpty ? "Blanket" : safe).appendingPathExtension(ext)
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }
}

enum Fixtures {
    static let palette: [(Double, Double, Double)] = [
        (0.85, 0.33, 0.31), (0.94, 0.68, 0.31), (0.36, 0.75, 0.87), (0.36, 0.72, 0.36),
        (0.61, 0.44, 0.75), (0.95, 0.90, 0.78), (0.91, 0.47, 0.61), (0.25, 0.50, 0.71),
    ]

    static func squareImage(_ rgb: (Double, Double, Double), seed: Int) -> UIImage {
        let size = CGSize(width: 300, height: 300)
        let main = UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        let accent = palette[(seed + 3) % palette.count]
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.97, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            main.setFill(); ctx.fill(CGRect(x: 30, y: 30, width: 240, height: 240))
            UIColor(red: accent.0, green: accent.1, blue: accent.2, alpha: 1).setFill()
            ctx.fill(CGRect(x: 105, y: 105, width: 90, height: 90))
            UIColor(white: 1, alpha: 0.35).setStroke()
            for k in 0..<4 {
                let r = CGRect(x: 45 + k * 15, y: 45 + k * 15, width: 210 - k * 30, height: 210 - k * 30)
                let path = UIBezierPath(rect: r); path.setLineDash([6, 6], count: 2, phase: 0); path.lineWidth = 3; path.stroke()
            }
        }
    }

    static func layoutPhoto(rows: Int = 7, cols: Int = 6) -> UIImage {
        let cell: CGFloat = 150
        let size = CGSize(width: CGFloat(cols) * cell + 120, height: CGFloat(rows) * cell + 120)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.43, green: 0.54, blue: 0.42, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            for r in 0..<rows {
                for c in 0..<cols {
                    squareImage(palette[(r * 5 + c * 3) % palette.count], seed: r + c)
                        .draw(in: CGRect(x: 60 + CGFloat(c) * cell, y: 60 + CGFloat(r) * cell, width: cell, height: cell))
                }
            }
        }
    }

    @MainActor
    static func apply(_ name: String, to model: AppModel) {
        guard name != "empty" else { return }
        var squares: [Square] = []
        for r in 0..<7 {
            for c in 0..<6 {
                let rgb = palette[(r * 6 + c) % palette.count]
                squares.append(model.makeSquare(squareImage(rgb, seed: r * 6 + c), label: Blanket.rowName(r) + "\(c + 1)"))
            }
        }
        var b = Blanket(name: L.t("fixture.name"), rows: 7, cols: 6, squares: squares)
        b.squares.sort { $0.color.l < $1.color.l }
        b.normalize()
        b.squares = squares
        if name == "assemble" { b.progress = 14 }
        if name == "almost" { b.progress = b.count - 1 }
        model.library.blankets = [b]
    }
}

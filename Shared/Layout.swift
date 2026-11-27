import Foundation

enum Launch {
    static func has(_ flag: String, in args: [String] = ProcessInfo.processInfo.arguments) -> Bool { args.contains(flag) }
    static func value(_ flag: String, in args: [String] = ProcessInfo.processInfo.arguments) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

struct LabColor: Codable, Equatable {
    var l: Double
    var a: Double
    var b: Double

    static func fromRGB(_ r: Double, _ g: Double, _ bl: Double) -> LabColor {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let R = lin(r), G = lin(g), B = lin(bl)
        let x = (0.4124 * R + 0.3576 * G + 0.1805 * B) / 0.95047
        let y = (0.2126 * R + 0.7152 * G + 0.0722 * B) / 1.0
        let z = (0.0193 * R + 0.1192 * G + 0.9505 * B) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? pow(t, 1.0 / 3) : 7.787 * t + 16.0 / 116 }
        return LabColor(l: 116 * f(y) - 16, a: 500 * (f(x) - f(y)), b: 200 * (f(y) - f(z)))
    }

    var rgb: (Double, Double, Double) {
        let fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - b / 200
        func inv(_ t: Double) -> Double { t * t * t > 0.008856 ? t * t * t : (t - 16.0 / 116) / 7.787 }
        let x = inv(fx) * 0.95047, y = inv(fy), z = inv(fz) * 1.08883
        func gam(_ c: Double) -> Double { let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055; return min(max(v, 0), 1) }
        return (gam(3.2406 * x - 1.5372 * y - 0.4986 * z), gam(-0.9689 * x + 1.8758 * y + 0.0415 * z), gam(0.0557 * x - 0.2040 * y + 1.0570 * z))
    }

    func distance(_ o: LabColor) -> Double {
        ((l - o.l) * (l - o.l) + (a - o.a) * (a - o.a) + (b - o.b) * (b - o.b)).squareRoot()
    }
}

struct Square: Codable, Identifiable, Equatable {
    var id = UUID()
    var label: String
    var photo: String?
    var color: LabColor
}

struct Blanket: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var rows: Int
    var cols: Int
    var squares: [Square] = []
    var cells: [UUID?] = []
    var locked: Set<UUID> = []
    var seam: SeamColor = .cream
    var progress = 0
    var created = Date()

    var count: Int { rows * cols }
    var finished: Bool { progress >= count && count > 0 }

    func square(_ id: UUID?) -> Square? { id.flatMap { i in squares.first { $0.id == i } } }
    func at(_ row: Int, _ col: Int) -> Square? { square(cells[row * cols + col]) }

    mutating func normalize() {
        rows = min(max(rows, 1), 30); cols = min(max(cols, 1), 30)
        var placed = cells.compactMap { $0 }.filter { id in squares.contains { $0.id == id } }
        var seen = Set<UUID>()
        placed = placed.filter { seen.insert($0).inserted }
        let missing = squares.map(\.id).filter { !seen.contains($0) }
        let ids = Array((placed + missing).prefix(count))
        cells = ids.map { Optional($0) } + Array(repeating: nil, count: max(0, count - ids.count))
        progress = min(progress, count)
    }

    mutating func swapCells(_ i: Int, _ j: Int) {
        guard cells.indices.contains(i), cells.indices.contains(j), i != j else { return }
        cells.swapAt(i, j)
    }

    func neighbors(_ i: Int) -> [Int] {
        let r = i / cols, c = i % cols
        var out: [Int] = []
        if r > 0 { out.append(i - cols) }
        if r < rows - 1 { out.append(i + cols) }
        if c > 0 { out.append(i - 1) }
        if c < cols - 1 { out.append(i + 1) }
        return out
    }

    func clashes(threshold: Double) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for i in cells.indices {
            for j in neighbors(i) where j > i {
                if let a = square(cells[i]), let b = square(cells[j]), a.color.distance(b.color) < threshold { out.append((i, j)) }
            }
        }
        return out
    }

    static func rowName(_ r: Int) -> String {
        var n = r, s = ""
        repeat { s = String(UnicodeScalar(65 + n % 26)!) + s; n = n / 26 - 1 } while n >= 0
        return s
    }
}

enum SeamColor: String, Codable, CaseIterable, Identifiable {
    case cream, white, black, gray, navy
    var id: String { rawValue }
    var rgb: (Double, Double, Double) {
        switch self {
        case .cream: (0.95, 0.91, 0.80)
        case .white: (1, 1, 1)
        case .black: (0.1, 0.1, 0.1)
        case .gray: (0.55, 0.55, 0.57)
        case .navy: (0.13, 0.20, 0.38)
        }
    }
}

struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Shuffler {
    static let defaultThreshold = 18.0

    static func cost(_ b: Blanket, threshold: Double) -> Double {
        var total = 0.0
        for i in b.cells.indices {
            for j in b.neighbors(i) where j > i {
                guard let x = b.square(b.cells[i]), let y = b.square(b.cells[j]) else { continue }
                let d = x.color.distance(y.color)
                total += d < threshold ? 1_000 + (threshold - d) * 10 : max(0, 60 - d) * 0.1
            }
        }
        return total
    }

    static func shuffle<R: RandomNumberGenerator>(_ input: Blanket, threshold: Double = defaultThreshold,
                                                  iterations: Int = 6_000, rng: inout R) -> Blanket {
        var b = input
        b.normalize()
        let free = b.cells.indices.filter { b.cells[$0].map { !b.locked.contains($0) } ?? true }
        guard free.count > 1 else { return b }
        var pool = free.map { b.cells[$0] }
        pool.shuffle(using: &rng)
        for (k, i) in free.enumerated() { b.cells[i] = pool[k] }
        var current = cost(b, threshold: threshold)
        var best = b, bestCost = current
        var temp = 400.0
        for _ in 0..<iterations {
            let i = free[Int.random(in: 0..<free.count, using: &rng)]
            let j = free[Int.random(in: 0..<free.count, using: &rng)]
            guard i != j else { continue }
            b.cells.swapAt(i, j)
            let next = cost(b, threshold: threshold)
            if next <= current || Double.random(in: 0..<1, using: &rng) < exp((current - next) / temp) {
                current = next
                if current < bestCost { best = b; bestCost = current }
            } else {
                b.cells.swapAt(i, j)
            }
            temp = max(temp * 0.999, 0.5)
            if bestCost < 1 { break }
        }
        return best
    }
}

enum LayoutCode {
    static let prefix = "GSQ1:"

    struct Payload: Codable, Equatable {
        var rows: Int
        var cols: Int
        var groups: [Int]
    }

    static func make(_ b: Blanket, threshold: Double = Shuffler.defaultThreshold) -> String {
        var reps: [LabColor] = []
        var groups: [Int] = []
        for id in b.cells {
            guard let s = b.square(id) else { groups.append(-1); continue }
            if let k = reps.firstIndex(where: { $0.distance(s.color) < threshold }) { groups.append(k) } else {
                reps.append(s.color); groups.append(reps.count - 1)
            }
        }
        let raw = (try? JSONEncoder().encode(Payload(rows: b.rows, cols: b.cols, groups: groups))) ?? Data()
        return prefix + raw.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Payload? {
        guard text.count < 20_000, let start = text.range(of: prefix) else { return nil }
        let body = text[start.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        var b64 = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard !body.isEmpty, let raw = Data(base64Encoded: b64), let p = try? JSONDecoder().decode(Payload.self, from: raw),
              (1...30).contains(p.rows), (1...30).contains(p.cols), p.groups.count == p.rows * p.cols,
              p.groups.allSatisfy({ (-1...900).contains($0) }) else { return nil }
        return p
    }

    static func apply(_ p: Payload, to b: inout Blanket, threshold: Double = Shuffler.defaultThreshold) {
        b.rows = p.rows; b.cols = p.cols
        b.normalize()
        var mine: [[UUID]] = []
        var reps: [LabColor] = []
        for s in b.squares.sorted(by: { $0.color.l < $1.color.l }) {
            if let k = reps.firstIndex(where: { $0.distance(s.color) < threshold }) { mine[k].append(s.id) } else {
                reps.append(s.color); mine.append([s.id])
            }
        }
        guard !mine.isEmpty else { return }
        var used = Set<UUID>()
        var cells: [UUID?] = Array(repeating: nil, count: b.count)
        for (i, g) in p.groups.enumerated() where g >= 0 {
            let bucket = mine[g % mine.count]
            if let id = bucket.first(where: { !used.contains($0) }) { cells[i] = id; used.insert(id) }
        }
        var rest = b.squares.map(\.id).filter { !used.contains($0) }
        for i in cells.indices where cells[i] == nil && !rest.isEmpty { cells[i] = rest.removeFirst() }
        b.cells = cells
        b.progress = 0
    }
}

struct Milestones: Codable, Equatable {
    var firstFinished = false
}

struct ReviewGate: Codable, Equatable {
    private(set) var requested = false
    mutating func afterExport() -> Bool {
        guard !requested else { return false }
        requested = true
        return true
    }
}

struct Library: Codable, Equatable {
    var coreReviewProgress: CoreReviewProgress?
    var blankets: [Blanket] = []
    var milestones = Milestones()
    var review = ReviewGate()
}

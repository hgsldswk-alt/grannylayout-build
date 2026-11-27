import Foundation
import XCTest

final class CoreTests: XCTestCase {
    private func sq(_ r: Double, _ g: Double, _ b: Double, _ label: String) -> Square {
        Square(label: label, photo: nil, color: .fromRGB(r, g, b))
    }

    private func clumped() -> Blanket {
        let colours: [(Double, Double, Double)] = [(0.85, 0.2, 0.2), (0.2, 0.3, 0.85), (0.95, 0.85, 0.2), (0.2, 0.7, 0.3)]
        var squares: [Square] = []
        for (k, c) in colours.enumerated() { for n in 0..<4 { squares.append(sq(c.0, c.1, c.2, "\(k)-\(n)")) } }
        var b = Blanket(name: "t", rows: 4, cols: 4, squares: squares)
        b.normalize()
        return b
    }

    func testRowNames() {
        XCTAssertEqual(Blanket.rowName(0), "A")
        XCTAssertEqual(Blanket.rowName(25), "Z")
        XCTAssertEqual(Blanket.rowName(26), "AA")
    }

    func testLabRoundTripAndDistance() {
        let red = LabColor.fromRGB(0.8, 0.1, 0.1)
        let back = red.rgb
        XCTAssertEqual(back.0, 0.8, accuracy: 0.01)
        XCTAssertEqual(back.1, 0.1, accuracy: 0.01)
        XCTAssertLessThan(red.distance(.fromRGB(0.82, 0.12, 0.1)), 5)
        XCTAssertGreaterThan(red.distance(.fromRGB(0.1, 0.2, 0.8)), 50)
    }

    func testNormalizeKeepsEverySquareOnce() {
        var b = clumped()
        b.rows = 3
        b.normalize()
        XCTAssertEqual(b.cells.count, 12)
        XCTAssertEqual(Set(b.cells.compactMap { $0 }).count, 12)
        b.rows = 5
        b.normalize()
        XCTAssertEqual(b.cells.count, 20)
        XCTAssertEqual(b.cells.compactMap { $0 }.count, 16)
    }

    func testShuffleRemovesClashes() {
        let b = clumped()
        XCTAssertGreaterThan(b.clashes(threshold: Shuffler.defaultThreshold).count, 0)
        var rng = SplitMix(state: 42)
        let out = Shuffler.shuffle(b, rng: &rng)
        XCTAssertEqual(out.clashes(threshold: Shuffler.defaultThreshold).count, 0)
        XCTAssertEqual(Set(out.cells.compactMap { $0 }), Set(b.cells.compactMap { $0 }))
    }

    func testShuffleRespectsLocked() {
        var b = clumped()
        let pinned = b.cells[5]!
        b.locked = [pinned]
        var rng = SplitMix(state: 7)
        let out = Shuffler.shuffle(b, rng: &rng)
        XCTAssertEqual(out.cells[5], pinned)
    }

    func testLayoutCodeRoundTripAndApply() {
        var rng = SplitMix(state: 3)
        let source = Shuffler.shuffle(clumped(), rng: &rng)
        let code = LayoutCode.make(source)
        let payload = LayoutCode.decode("Use my layout:\n" + code + " thanks")
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.rows, 4)
        var mine = clumped()
        LayoutCode.apply(payload!, to: &mine)
        XCTAssertEqual(Set(mine.cells.compactMap { $0 }).count, 16)
        XCTAssertEqual(mine.clashes(threshold: Shuffler.defaultThreshold).count, 0)
    }

    func testLayoutCodeRejectsGarbage() {
        XCTAssertNil(LayoutCode.decode("hello"))
        XCTAssertNil(LayoutCode.decode("GSQ1:!!!"))
        let bad = Data(#"{"rows":0,"cols":2,"groups":[]}"#.utf8).base64EncodedString()
        XCTAssertNil(LayoutCode.decode("GSQ1:" + bad))
    }

    func testCoreReviewRequiresThreeActionsOnTwoLocalDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let firstDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 23)))
        let nextDay = firstDay.addingTimeInterval(2 * 3600)
        let empty = try JSONDecoder().decode(CoreReviewProgress.self, from: Data("{}".utf8))
        XCTAssertFalse(empty.isEligible)
        var progress = CoreReviewProgress.recording(empty, at: firstDay, calendar: calendar)
        var twoDays = progress
        twoDays.record(at: nextDay, calendar: calendar)
        XCTAssertFalse(twoDays.isEligible)
        progress.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(progress.isEligible)

        var sameDay = progress
        sameDay.record(at: firstDay, calendar: calendar)
        XCTAssertFalse(sameDay.isEligible)

        let data = try JSONEncoder().encode(progress)
        progress = try JSONDecoder().decode(CoreReviewProgress.self, from: data)
        progress.record(at: nextDay, calendar: calendar)
        XCTAssertTrue(progress.isEligible)
    }

    func testReviewAsksOnce() {
        var gate = ReviewGate()
        XCTAssertTrue(gate.afterExport())
        XCTAssertFalse(gate.afterExport())
    }

    func testSwapAndProgress() {
        var b = clumped()
        let a = b.cells[0], c = b.cells[1]
        b.swapCells(0, 1)
        XCTAssertEqual(b.cells[0], c)
        XCTAssertEqual(b.cells[1], a)
        b.progress = 16
        XCTAssertTrue(b.finished)
    }
}

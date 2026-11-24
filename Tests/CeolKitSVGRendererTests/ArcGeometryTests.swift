import Testing
@testable import CeolKitSVGRenderer

/// abcm2ps's tie and slur heights (#292), checked rule by rule against `draw.c`.
///
/// Every case uses a staff size of 6, at which one abcm2ps unit is one SVG unit, so the
/// numbers below are the ones `draw_slur`, `draw_ties` and `slur_out` compute — with y
/// negated, since SVG's grows downward.
@Suite("Arc geometry")
struct ArcGeometryTests {
    private typealias Point = ArcGeometry.Point
    private typealias Obstacle = ArcGeometry.Obstacle

    private func arc(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                     below: Bool = false, kind: ArcGeometry.Kind) -> ArcGeometry {
        ArcGeometry(start: Point(x: x1, y: y1), end: Point(x: x2, y: y2),
                    below: below, kind: kind, staffSize: 6)
    }

    private func slur(notes: Int, _ obstacles: [Obstacle] = []) -> ArcGeometry.Kind {
        .slur(noteCount: notes, obstacles: obstacles)
    }

    /// How far the curve's middle stands out from the middle of the straight line between
    /// its ends, upward positive.  `slur_out` puts it at `0.75 · 0.45 · height`.
    private func rise(_ a: ArcGeometry) -> Double {
        (a.start.y + a.end.y) / 2 - a.midpointY
    }

    private func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    // MARK: - Ties

    @Test("A tie rises (0.04 · span + 10) · 0.3375")
    func tieHeight() {
        #expect(close(rise(arc(0, 0, 100, 0, kind: .tie)), 0.3375 * 14))
        #expect(close(rise(arc(0, 0, 20, 0, kind: .tie)), 0.3375 * 10.8))
    }

    @Test("A tie below drops by the same amount")
    func tieBelow() {
        #expect(close(rise(arc(0, 0, 100, 0, below: true, kind: .tie)), -0.3375 * 14))
    }

    @Test("A tie's ends stay where they were put")
    func tieEnds() {
        let a = arc(0, 7, 50, 7, kind: .tie)
        #expect(a.start == Point(x: 0, y: 7))
        #expect(a.end == Point(x: 50, y: 7))
    }

    // MARK: - Slur heights

    @Test("A slur over two or three notes rises (0.03 · span + 8) · 0.3375")
    func shortSlur() {
        #expect(close(rise(arc(0, 0, 30, 0, kind: slur(notes: 2))), 0.3375 * 8.9))
        #expect(close(rise(arc(0, 0, 30, 0, kind: slur(notes: 3))), 0.3375 * 8.9))
    }

    @Test("A slur over four notes or more rises (0.08 · span + 12) · 0.3375")
    func longSlur() {
        #expect(close(rise(arc(0, 0, 30, 0, kind: slur(notes: 4))), 0.3375 * 14.4))
    }

    @Test("A slur's height is capped at 40")
    func cap() {
        #expect(close(rise(arc(0, 0, 500, 0, kind: slur(notes: 6))), 0.3375 * 40))
        #expect(close(rise(arc(0, 0, 500, 0, below: true, kind: slur(notes: 6))), -0.3375 * 40))
    }

    // MARK: - Clearance

    @Test("A note standing out under the slur lifts its ends and its height")
    func clearance() {
        // The note stands 10 above the chord: the ends rise 4.5, and the height becomes
        // 3 · 0.65 · 10 = 19.5, more than the 11.6 the span alone would give.  It stands
        // more than 48 from either end, out of reach of the neighbour rule.
        let a = arc(0, 0, 120, 0, kind: slur(notes: 3, [Obstacle(x: 60, top: -10, bottom: 10)]))
        #expect(close(a.start.y, -4.5))
        #expect(close(a.end.y, -4.5))
        #expect(close(rise(a), 0.3375 * 19.5))
        #expect(a.midpointY < -10)
    }

    @Test("Only the side the slur is on counts")
    func clearanceSide() {
        // The obstacle reaches 10 above and 2 below: a slur below clears only the 2 —
        // which is above its ends at 0, so nothing at all.
        let obstacle = Obstacle(x: 30, top: -10, bottom: -2)
        let below = arc(0, 0, 60, 0, below: true, kind: slur(notes: 3, [obstacle]))
        #expect(below.start.y == 0)
        #expect(close(rise(below), -0.3375 * 9.8))
    }

    @Test("Clearance is measured from the line between the ends, not from the level")
    func clearanceAlongTheChord() {
        // The ends run from 0 up to 20 (SVG −20).  The jump shift first moves the upper end
        // in by 4 and down by 0.3 · 8 = 2.4, to (96, 17.6); at x = 50 the chord is then at
        // 50 · 17.6 / 96, and an obstacle reaching 12 there stands out by the difference.
        let a = arc(0, 0, 100, -20, kind: slur(notes: 3, [Obstacle(x: 50, top: -12, bottom: 0)]))
        let standsOut = 12 - 50 * 17.6 / 96
        #expect(close(a.start.y, -0.45 * standsOut))
    }

    @Test("The cap wins over the clearance, as abcm2ps applies them")
    func capBeatsClearance() {
        let a = arc(0, 0, 120, 0, kind: slur(notes: 3, [Obstacle(x: 60, top: -50, bottom: 0)]))
        #expect(close(rise(a), 0.3375 * 40))
    }

    // MARK: - Neighbouring notes

    @Test("Over three notes or more, an end is kept 2 units inside a close neighbour's top")
    func neighbourLiftsTheEnds() {
        // Both neighbours reach 10 up, 20 in from each end: the ends rise to 8, and the
        // clearance then finds them standing 2 above that chord, lifting the ends 0.45 · 2.
        let neighbours = [Obstacle(x: 20, top: -10, bottom: 0), Obstacle(x: 80, top: -10, bottom: 0)]
        let a = arc(0, 0, 100, 0, kind: slur(notes: 4, neighbours))
        #expect(close(a.start.y, -8.9))
        #expect(close(a.end.y, -8.9))
    }

    @Test("A slur over two notes is not lifted by its neighbours: it has none")
    func noNeighbourRuleUnderThreeNotes() {
        let a = arc(0, 0, 100, 0, kind: slur(notes: 2, [Obstacle(x: 20, top: -10, bottom: 0)]))
        // Only the clearance: 10 out, ends up 4.5.
        #expect(close(a.start.y, -4.5))
    }

    @Test("A neighbour more than 48 units from the end does not lift it")
    func farNeighbour() {
        let a = arc(0, 0, 200, 0, kind: slur(notes: 3, [Obstacle(x: 60, top: -10, bottom: 0)]))
        #expect(close(a.start.y, -4.5))
    }

    @Test("Below, the neighbour rule keeps the end 2 units inside the neighbour's bottom")
    func neighbourBelow() {
        let neighbours = [Obstacle(x: 20, top: 0, bottom: 10), Obstacle(x: 80, top: 0, bottom: 10)]
        let a = arc(0, 0, 100, 0, below: true, kind: slur(notes: 4, neighbours))
        #expect(close(a.start.y, 8.9))
    }

    // MARK: - Steep slurs

    @Test("A steep slur rises at least 0.8 of the drop between its ends")
    func steepnessFloor() {
        // Ends 0 and 40 apart over 100: the upper end moves in 4 and down 2.4, leaving a
        // drop of 37.6 — whose 0.8 is more than the 10.88 the span would give.
        let a = arc(0, 0, 100, -40, kind: slur(notes: 2))
        #expect(close(a.end.x, 96))
        #expect(close(a.end.y, -37.6))
        #expect(close(rise(a), 0.3375 * 0.8 * 37.6))
    }

    @Test("Slope is clamped to 1 by moving the end on the arc's inner side")
    func slopeClamp() {
        // Above: the higher end (30) stays, the lower comes up to 30 − 10 = 20.
        let above = arc(0, 0, 10, -30, kind: slur(notes: 2))
        #expect(close(above.start.y, -20))
        // Below: the lower end (0) stays, the higher comes down to 10; then the jump shift
        // moves the lower end in by 0.5 · 8 = 4 and up 0.3 · 8 = 2.4 (in abcm2ps's frame).
        let below = arc(0, 0, 10, -30, below: true, kind: slur(notes: 2))
        #expect(close(below.end.y, -10))
        #expect(close(below.start.x, 4))
        #expect(close(below.start.y, -2.4))
    }

    @Test("A big jump moves the end on the arc's outer side in by half of it, at most 4")
    func jumpShift() {
        // Above, rising 30 over 100: the upper end moves in 0.5 · 8 and down 0.3 · 8.
        let a = arc(0, 0, 100, -30, kind: slur(notes: 2))
        #expect(close(a.end.x, 96))
        #expect(close(a.end.y, -27.6))
        #expect(a.start == ArcGeometry.Point(x: 0, y: 0))
    }

    // MARK: - Shape

    @Test("A wide, flat arc pushes its control points out towards its ends")
    func wideArcSquaresItsShoulders() {
        // Narrow: alfa 0.3, so the control point is 0.45 of the way to 20 − 0.3 · 20 = 14.
        #expect(close(arc(0, 0, 40, 0, kind: .tie).control1.x, 0.45 * 14))
        // Wide: alfa reaches its 0.7 limit, and the point sits 0.45 of the way to 36.
        #expect(close(arc(0, 0, 240, 0, kind: .tie).control1.x, 0.45 * 36))
    }

    @Test("Staff size scales everything together")
    func scales() {
        let small = arc(0, 0, 100, 0, kind: slur(notes: 4))
        let big = ArcGeometry(start: Point(x: 0, y: 0), end: Point(x: 200, y: 0),
                              below: false, kind: slur(notes: 4), staffSize: 12)
        #expect(close(2 * rise(small), rise(big)))
    }
}

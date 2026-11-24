/// The centre line of a tie or slur, shaped as abcm2ps shapes it (#292).
///
/// abcm2ps makes an arc taller the wider it is, and a slur taller still where a note under
/// it would otherwise poke through: `draw_slur` and the tie branch of `draw_ties` decide a
/// `height`, and `slur_out` turns that into the curve's two control points (all in
/// abcm2ps's `draw.c`).  This type is a transcription of those three, so it works in
/// abcm2ps's own frame — y grows upward, and a staff space is 6 units — and converts from
/// and to SVG at its edges.  Every constant below is then the one `draw.c` uses.
///
/// The caller places the arc's ends against its notes, as abcm2ps does too (#293); what
/// happens to them from there on is this type's.
struct ArcGeometry: Equatable {
    struct Point: Equatable {
        var x: Double
        var y: Double
    }

    /// What lies under a slur between its two ends: one note, chord, grace note or rest, as
    /// the horizontal position it is drawn at and the SVG y of its top and bottom — stem tip
    /// and beam included, on whichever side they are drawn.
    struct Obstacle: Equatable {
        var x: Double
        var top: Double
        var bottom: Double
    }

    enum Kind: Equatable {
        case tie
        /// `noteCount` is abcm2ps's `nn`: the notes, chords and rests the slur spans, its two
        /// ends included.  `obstacles` are those strictly between the ends.
        case slur(noteCount: Int, obstacles: [Obstacle])
    }

    /// The curve's end points and control points, in SVG coordinates.
    let start: Point
    let control1: Point
    let control2: Point
    let end: Point

    /// abcm2ps's `SLUR_SLOPE`: the steepest a slur's chord may run.
    static let maxSlope = 1.0

    /// - Parameters:
    ///   - start: the arc's left end, in SVG coordinates.
    ///   - end: its right end.
    ///   - below: whether it curves below the notes rather than above them.
    ///   - staffSize: one staff space, in SVG units.
    init(start: Point, end: Point, below: Bool, kind: Kind, staffSize: Double) {
        let unit = staffSize / 6.0
        let s: Double = below ? -1 : 1
        var x1 = start.x / unit, y1 = -start.y / unit
        var x2 = end.x / unit, y2 = -end.y / unit
        let height: Double

        switch kind {
        case .tie:
            height = (0.04 * (x2 - x1) + 10) * s

        case .slur(let noteCount, let obstacles):
            // A slur over three notes or more keeps each end clear of the note next to it,
            // where that note is close by: no lower (for a slur above) than 2 units inside
            // its top.
            func outer(_ o: Obstacle) -> Double { s > 0 ? -o.top / unit : -o.bottom / unit }
            if noteCount >= 3 {
                if let next = obstacles.first, next.x / unit < x1 + 48 {
                    let y = outer(next) - 2 * s
                    y1 = s > 0 ? max(y1, y) : min(y1, y)
                }
                if let previous = obstacles.last, previous.x / unit > x2 - 48 {
                    let y = outer(previous) - 2 * s
                    y2 = s > 0 ? max(y2, y) : min(y2, y)
                }
            }

            // Slope clamp: the end on the arc's outer side stays put, the other is pulled
            // level with it as far as the clamp needs.
            if x2 - x1 > 0 {
                var a = (y2 - y1) / (x2 - x1)
                if a > Self.maxSlope || a < -Self.maxSlope {
                    a = a > Self.maxSlope ? Self.maxSlope : -Self.maxSlope
                    if a * s > 0 {
                        y1 = y2 - a * (x2 - x1)
                    } else {
                        y2 = y1 + a * (x2 - x1)
                    }
                }
            }

            // A big vertical jump: the end on the arc's outer side moves in, and part way
            // back towards the other.
            let jump = min(8, max(-8, y2 - y1))
            let inward = 0.5 * abs(jump)
            if jump * s > 0 {
                x2 -= inward
                y2 -= 0.3 * jump
            } else {
                x1 += inward
                y1 += 0.3 * jump
            }

            // Clearance: how far the notes under the slur stand out past the straight line
            // between its ends, on its side.  The ends rise by part of that, and the arc's
            // height makes up the rest.
            var h = 0.0
            if x2 - x1 > 0 {
                let a = (y2 - y1) / (x2 - x1)
                let addy = y1 - a * x1
                for obstacle in obstacles {
                    let y = outer(obstacle) - (a * obstacle.x / unit + addy)
                    h = s > 0 ? max(h, y) : min(h, y)
                }
            }
            y1 += 0.45 * h
            y2 += 0.45 * h
            h *= 0.65

            var raw = noteCount > 3
                ? (0.08 * (x2 - x1) + 12) * s
                : (0.03 * (x2 - x1) + 8) * s
            // abcm2ps applies the cap after the clearance floor, so the cap wins.
            if s > 0 {
                raw = min(max(raw, 3 * h), 40)
            } else {
                raw = max(min(raw, 3 * h), -40)
            }
            let rise = abs(y2 - y1)
            height = s > 0 ? max(raw, 0.8 * rise) : min(raw, -0.8 * rise)
        }

        // `slur_out`: each control point sits part way (`beta`) from its end towards a point
        // `height` above the chord, `alfa` of the way from the chord's middle to that end.
        // A wide, flat arc pushes them outwards, squaring its shoulders.
        var alfa = 0.3
        let beta = 0.45
        let dx = x2 - x1
        if dx > 40, abs(y2 - y1) / dx < 0.7 {
            alfa = min(0.7, 0.3 + 0.002 * (dx - 40))
        }
        let mx = 0.5 * (x1 + x2), my = 0.5 * (y1 + y2)
        func control(_ x: Double, _ y: Double) -> Point {
            let px = mx + alfa * (x - mx)
            let py = my + alfa * (y - my) + height
            return Point(x: x + beta * (px - x), y: y + beta * (py - y))
        }
        let c1 = control(x1, y1)
        let c2 = control(x2, y2)

        func svg(_ p: Point) -> Point { Point(x: p.x * unit, y: -p.y * unit) }
        self.start = svg(Point(x: x1, y: y1))
        self.control1 = svg(c1)
        self.control2 = svg(c2)
        self.end = svg(Point(x: x2, y: y2))
    }

    /// The curve's y at its middle (t = ½), in SVG coordinates.
    var midpointY: Double {
        (start.y + 3 * control1.y + 3 * control2.y + end.y) / 8
    }
}

/// The outlines of a TrueType-flavoured face: its `glyf` table, indexed by `loca`
/// (issue #189).
///
/// The counterpart of ``Type2Interpreter`` for faces that are not CFF — most of what is
/// installed on a machine (`Times.ttc`, `Courier New.ttf`, DejaVu, Liberation, Noto).  It
/// reads:
///
/// - **Simple glyphs**: contours of on- and off-curve points, run-length flags, and short
///   and long coordinate deltas.  Two off-curve points in a row imply an on-curve point
///   midway between them, and a contour may start off-curve or have no on-curve point at
///   all.  Each quadratic arc is emitted as a ``GlyphPath/Segment/quadCurve(control:to:)``.
/// - **Composite glyphs**: each component's outline, offset and transformed by a single
///   scale, separate x and y scales, or a 2×2 matrix, nested up to ``maxCompositeDepth``.
///   A component positioned by point matching rather than an offset is skipped — rare
///   outside CJK fonts, and not worth a second pass over the parent's points.
///
/// Hinting instructions are skipped: outlines are drawn unhinted, as the CFF path draws them.
///
/// Contours start where fontTools and FreeType's outline decomposition start them — on the
/// first on-curve point, or, where there is none, midway between the last point and the
/// first — and a contour that returns to its start along a straight line leaves that line
/// to its `close`.
struct TrueTypeGlyphs: Sendable {
    private let bytes: FontBytes
    private let glyf: Int
    /// Each glyph's byte range within `glyf`, as `offsets[g]..<offsets[g + 1]`.
    private let offsets: [Int]

    /// How deeply composites may nest.  The format sets no limit, so this is a guard against
    /// a cycle — a composite that includes itself would otherwise recurse forever.
    static let maxCompositeDepth = 8

    var glyphCount: Int { max(0, offsets.count - 1) }

    /// - Parameter longOffsets: `head.indexToLocFormat == 1` — `loca` holds 32-bit offsets
    ///   rather than 16-bit halved ones.
    init(bytes: FontBytes, glyf: Int, loca: Int, numGlyphs: Int, longOffsets: Bool) throws {
        self.bytes = bytes
        self.glyf = glyf
        var offsets: [Int] = []
        offsets.reserveCapacity(numGlyphs + 1)
        for g in 0...numGlyphs {
            offsets.append(longOffsets ? try bytes.u32(loca + 4 * g, "loca")
                                       : 2 * (try bytes.u16(loca + 2 * g, "loca")))
        }
        self.offsets = offsets
    }

    func outline(forGlyph glyph: Int) throws -> GlyphPath {
        try outline(forGlyph: glyph, depth: 0)
    }

    private func outline(forGlyph glyph: Int, depth: Int) throws -> GlyphPath {
        guard glyph >= 0, glyph < glyphCount else {
            throw OpenTypeError.glyphIndexOutOfRange(glyph)
        }
        let start = offsets[glyph], end = offsets[glyph + 1]
        // An empty range is a glyph with no outline — a space.
        guard end > start else { return GlyphPath() }
        let base = glyf + start
        let contours = try bytes.i16(base, "glyf")
        if contours >= 0 { return try simpleOutline(at: base, contours: contours) }
        guard depth < Self.maxCompositeDepth else { throw OpenTypeError.compositeTooDeep }
        return try compositeOutline(at: base, depth: depth)
    }

    // MARK: - Simple glyphs

    private struct OutlinePoint {
        var point: GlyphPath.Point
        var onCurve: Bool
    }

    private func simpleOutline(at base: Int, contours: Int) throws -> GlyphPath {
        guard contours > 0 else { return GlyphPath() }
        var endPoints: [Int] = []
        for c in 0..<contours { endPoints.append(try bytes.u16(base + 10 + 2 * c, "glyf")) }
        let pointCount = (endPoints.last ?? -1) + 1
        let instructionLength = try bytes.u16(base + 10 + 2 * contours, "glyf")
        var cursor = base + 12 + 2 * contours + instructionLength

        // Flags, with bit 3 repeating a flag the number of times the next byte says.
        var flags: [Int] = []
        flags.reserveCapacity(pointCount)
        while flags.count < pointCount {
            let flag = try bytes.u8(cursor, "glyf"); cursor += 1
            flags.append(flag)
            if flag & 0x08 != 0 {
                let repeats = try bytes.u8(cursor, "glyf"); cursor += 1
                flags.append(contentsOf: repeatElement(flag, count: repeats))
            }
        }
        guard flags.count == pointCount else {
            throw OpenTypeError.malformedGlyph("flag run overruns the glyph's points")
        }

        /// One axis of coordinate deltas: `short` marks a one-byte delta whose sign `same`
        /// gives; without `short`, `same` repeats the previous value and its absence means
        /// a two-byte signed delta.
        func coordinates(short: Int, same: Int) throws -> [Double] {
            var value = 0, values: [Double] = []
            values.reserveCapacity(pointCount)
            for flag in flags {
                if flag & short != 0 {
                    let delta = try bytes.u8(cursor, "glyf"); cursor += 1
                    value += flag & same != 0 ? delta : -delta
                } else if flag & same == 0 {
                    value += try bytes.i16(cursor, "glyf"); cursor += 2
                }
                values.append(Double(value))
            }
            return values
        }
        let xs = try coordinates(short: 0x02, same: 0x10)
        let ys = try coordinates(short: 0x04, same: 0x20)

        var path = GlyphPath()
        var first = 0
        for last in endPoints {
            guard last >= first, last < pointCount else {
                throw OpenTypeError.malformedGlyph("contour end points out of order")
            }
            let contour = (first...last).map {
                OutlinePoint(point: GlyphPath.Point(x: xs[$0], y: ys[$0]),
                             onCurve: flags[$0] & 0x01 != 0)
            }
            append(contour, to: &path)
            first = last + 1
        }
        return path
    }

    /// Draws one closed contour of quadratic B-spline points.
    private func append(_ contour: [OutlinePoint], to path: inout GlyphPath) {
        guard let firstOn = contour.firstIndex(where: \.onCurve) ?? (contour.isEmpty ? nil : -1)
        else { return }
        func midpoint(_ a: GlyphPath.Point, _ b: GlyphPath.Point) -> GlyphPath.Point {
            GlyphPath.Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }

        // Walk from the start round to it again, so the last step lands back on the start.
        let start: GlyphPath.Point
        var walk: [OutlinePoint]
        if firstOn >= 0 {
            start = contour[firstOn].point
            walk = Array(contour[(firstOn + 1)...] + contour[...firstOn])
        } else {
            // Nothing on the curve: begin at the point implied between the last and first.
            start = midpoint(contour[contour.count - 1].point, contour[0].point)
            walk = contour + [OutlinePoint(point: start, onCurve: true)]
        }

        path.segments.append(.move(to: start))
        var control: GlyphPath.Point?
        for point in walk {
            switch (point.onCurve, control) {
            case (true, nil):
                path.segments.append(.line(to: point.point))
            case (true, let c?):
                path.segments.append(.quadCurve(control: c, to: point.point))
                control = nil
            case (false, nil):
                control = point.point
            case (false, let c?):
                // Two off-curve points in a row: the curve passes midway between them.
                path.segments.append(.quadCurve(control: c, to: midpoint(c, point.point)))
                control = point.point
            }
        }
        if case .line(let end) = path.segments.last, end == start {
            path.segments.removeLast()
        }
        path.segments.append(.close)
    }

    // MARK: - Composite glyphs

    private func compositeOutline(at base: Int, depth: Int) throws -> GlyphPath {
        var path = GlyphPath()
        var cursor = base + 10
        var more = true
        while more {
            let flags = try bytes.u16(cursor, "glyf")
            let component = try bytes.u16(cursor + 2, "glyf")
            cursor += 4
            more = flags & 0x0020 != 0                      // MORE_COMPONENTS

            let wordArgs = flags & 0x0001 != 0               // ARG_1_AND_2_ARE_WORDS
            let xyValues = flags & 0x0002 != 0               // ARGS_ARE_XY_VALUES
            let arg1: Int, arg2: Int
            if wordArgs {
                arg1 = try bytes.i16(cursor, "glyf"); arg2 = try bytes.i16(cursor + 2, "glyf")
                cursor += 4
            } else {
                arg1 = Int(Int8(truncatingIfNeeded: try bytes.u8(cursor, "glyf")))
                arg2 = Int(Int8(truncatingIfNeeded: try bytes.u8(cursor + 1, "glyf")))
                cursor += 2
            }

            func f2dot14(_ offset: Int) throws -> Double {
                Double(try bytes.i16(offset, "glyf")) / 16384
            }
            var (a, b, c, d) = (1.0, 0.0, 0.0, 1.0)
            if flags & 0x0008 != 0 {                          // WE_HAVE_A_SCALE
                a = try f2dot14(cursor); d = a
                cursor += 2
            } else if flags & 0x0040 != 0 {                   // WE_HAVE_AN_X_AND_Y_SCALE
                a = try f2dot14(cursor); d = try f2dot14(cursor + 2)
                cursor += 4
            } else if flags & 0x0080 != 0 {                   // WE_HAVE_A_TWO_BY_TWO
                a = try f2dot14(cursor); b = try f2dot14(cursor + 2)
                c = try f2dot14(cursor + 4); d = try f2dot14(cursor + 6)
                cursor += 8
            }

            // Point matching — aligning a point of the component with one of the glyph built
            // so far — is not read; the component is left out rather than misplaced.
            guard xyValues else { continue }
            var (dx, dy) = (Double(arg1), Double(arg2))
            // SCALED_COMPONENT_OFFSET, unless UNSCALED_COMPONENT_OFFSET overrides it: the
            // offset goes through the component's transform too.
            if flags & 0x0800 != 0, flags & 0x1000 == 0 {
                (dx, dy) = (a * dx + c * dy, b * dx + d * dy)
            }
            let outline = try self.outline(forGlyph: component, depth: depth + 1)
            path.segments += outline.transformed(a: a, b: b, c: c, d: d, dx: dx, dy: dy).segments
        }
        return path
    }
}

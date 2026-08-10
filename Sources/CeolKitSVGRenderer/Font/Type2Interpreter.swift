/// Executes Type 2 charstrings, producing glyph outlines in font units.
///
/// Type 2 is a stack machine whose operators encode deltas rather than absolute points, so
/// an outline can only be recovered by running the program — there is no table of contours
/// to read. Hinting operators are parsed but discarded: they exist to snap stems to a pixel
/// grid at small sizes, which is a rasteriser's job and not something an SVG `<path>` can
/// express anyway. They still have to be *counted*, because `hintmask` is followed by a
/// variable number of raw mask bytes that would otherwise be read as operators.
struct Type2Interpreter: Sendable {

    let cff: CFFTable

    var glyphCount: Int { cff.glyphCount }

    func outline(forGlyph glyph: Int) throws -> GlyphPath {
        guard cff.charStrings.indices.contains(glyph) else {
            throw OpenTypeError.glyphIndexOutOfRange(glyph)
        }
        var machine = Machine(
            cff: cff,
            localSubrs: cff.localSubrs(forGlyph: glyph),
            globalSubrs: cff.globalSubrs
        )
        try machine.run(cff.charStrings[glyph], depth: 0)
        machine.closeContour()
        return machine.path
    }
}

// MARK: - The machine

private struct Machine {

    /// The format caps the operand stack at 48 and subroutine nesting at 10. Both are
    /// enforced so a corrupt charstring fails cleanly instead of exhausting memory or
    /// the Swift stack.
    private static let maxStack = 48
    private static let maxDepth = 10

    let cff: CFFTable
    let localSubrs: [Range<Int>]
    let globalSubrs: [Range<Int>]
    private let localBias: Int
    private let globalBias: Int

    var stack: [Double] = []
    var x = 0.0
    var y = 0.0
    var stemCount = 0
    /// Set once the leading optional width operand has been dealt with — it may only
    /// appear before the charstring's first stack-clearing operator.
    var widthConsumed = false
    var contourOpen = false
    var finished = false
    var path = GlyphPath()

    init(cff: CFFTable, localSubrs: [Range<Int>], globalSubrs: [Range<Int>]) {
        self.cff = cff
        self.localSubrs = localSubrs
        self.globalSubrs = globalSubrs
        localBias = Machine.bias(localSubrs.count)
        globalBias = Machine.bias(globalSubrs.count)
    }

    /// Subroutine numbers are stored biased so that small indices can use the compact
    /// single-byte operand encoding.
    private static func bias(_ count: Int) -> Int {
        if count < 1240 { return 107 }
        if count < 33900 { return 1131 }
        return 32768
    }

    // MARK: Execution

    mutating func run(_ range: Range<Int>, depth: Int) throws {
        guard depth <= Machine.maxDepth else { throw OpenTypeError.charstringTooDeep }
        let bytes = cff.bytes
        var i = range.lowerBound

        while i < range.upperBound, !finished {
            let b0 = try bytes.u8(i, "charstring")
            i += 1

            // Operands: everything from 32 up, plus the 16-bit escape at 28.
            if b0 == 28 {
                try push(Double(try bytes.i16(i, "charstring")))
                i += 2
                continue
            }
            if b0 >= 32 {
                switch b0 {
                case 32...246:
                    try push(Double(b0 - 139))
                case 247...250:
                    try push(Double((b0 - 247) * 256 + (try bytes.u8(i, "charstring")) + 108))
                    i += 1
                case 251...254:
                    try push(Double(-(b0 - 251) * 256 - (try bytes.u8(i, "charstring")) - 108))
                    i += 1
                default:  // 255: 16.16 fixed point
                    let raw = Int32(truncatingIfNeeded: try bytes.u32(i, "charstring"))
                    try push(Double(raw) / 65536.0)
                    i += 4
                }
                continue
            }

            switch b0 {
            case 1, 3, 18, 23:  // hstem, vstem, hstemhm, vstemhm
                consumeWidthIfOddArgumentCount()
                stemCount += stack.count / 2
                stack.removeAll(keepingCapacity: true)

            case 19, 20:  // hintmask, cntrmask
                // Any operands still pending are an implicit vstem declaration.
                consumeWidthIfOddArgumentCount()
                stemCount += stack.count / 2
                stack.removeAll(keepingCapacity: true)
                i += (stemCount + 7) / 8

            case 21:  // rmoveto
                consumeWidth(ifArgumentsExceed: 2)
                moveTo(deltaX: stack.count >= 2 ? stack[stack.count - 2] : 0,
                       deltaY: stack.count >= 2 ? stack[stack.count - 1] : 0)
                stack.removeAll(keepingCapacity: true)

            case 22:  // hmoveto
                consumeWidth(ifArgumentsExceed: 1)
                moveTo(deltaX: stack.last ?? 0, deltaY: 0)
                stack.removeAll(keepingCapacity: true)

            case 4:  // vmoveto
                consumeWidth(ifArgumentsExceed: 1)
                moveTo(deltaX: 0, deltaY: stack.last ?? 0)
                stack.removeAll(keepingCapacity: true)

            case 5:  // rlineto
                var j = 0
                while j + 1 < stack.count {
                    lineTo(deltaX: stack[j], deltaY: stack[j + 1])
                    j += 2
                }
                stack.removeAll(keepingCapacity: true)

            case 6, 7:  // hlineto, vlineto — alternating axes
                var horizontal = (b0 == 6)
                var j = 0
                while j < stack.count {
                    let value = stack[j]
                    lineTo(deltaX: horizontal ? value : 0, deltaY: horizontal ? 0 : value)
                    horizontal.toggle()
                    j += 1
                }
                stack.removeAll(keepingCapacity: true)

            case 8:  // rrcurveto
                var j = 0
                while j + 5 < stack.count {
                    relativeCurve(Array(stack[j..<(j + 6)]))
                    j += 6
                }
                stack.removeAll(keepingCapacity: true)

            case 24:  // rcurveline — curves, then one line
                var j = 0
                while stack.count - j >= 8 {
                    relativeCurve(Array(stack[j..<(j + 6)]))
                    j += 6
                }
                if j + 1 < stack.count {
                    lineTo(deltaX: stack[j], deltaY: stack[j + 1])
                }
                stack.removeAll(keepingCapacity: true)

            case 25:  // rlinecurve — lines, then one curve
                var j = 0
                while stack.count - j >= 8 {
                    lineTo(deltaX: stack[j], deltaY: stack[j + 1])
                    j += 2
                }
                if j + 5 < stack.count {
                    relativeCurve(Array(stack[j..<(j + 6)]))
                }
                stack.removeAll(keepingCapacity: true)

            case 26:  // vvcurveto
                var j = 0
                var dx1 = 0.0
                if stack.count % 4 == 1, !stack.isEmpty {
                    dx1 = stack[0]
                    j = 1
                }
                while j + 3 < stack.count {
                    let control1 = point(x + dx1, y + stack[j])
                    let control2 = point(control1.x + stack[j + 1], control1.y + stack[j + 2])
                    curveTo(control1, control2, point(control2.x, control2.y + stack[j + 3]))
                    dx1 = 0
                    j += 4
                }
                stack.removeAll(keepingCapacity: true)

            case 27:  // hhcurveto
                var j = 0
                var dy1 = 0.0
                if stack.count % 4 == 1, !stack.isEmpty {
                    dy1 = stack[0]
                    j = 1
                }
                while j + 3 < stack.count {
                    let control1 = point(x + stack[j], y + dy1)
                    let control2 = point(control1.x + stack[j + 1], control1.y + stack[j + 2])
                    curveTo(control1, control2, point(control2.x + stack[j + 3], control2.y))
                    dy1 = 0
                    j += 4
                }
                stack.removeAll(keepingCapacity: true)

            case 30, 31:  // vhcurveto, hvcurveto — alternating start tangents
                var horizontal = (b0 == 31)
                var j = 0
                while stack.count - j >= 4 {
                    // A trailing fifth operand on the final curve gives the otherwise
                    // implied zero delta of the end point's off-axis coordinate.
                    let isLast = (stack.count - j == 5)
                    let extra = isLast ? stack[j + 4] : 0
                    let control1: GlyphPath.Point
                    let control2: GlyphPath.Point
                    let end: GlyphPath.Point
                    if horizontal {
                        control1 = point(x + stack[j], y)
                        control2 = point(control1.x + stack[j + 1], control1.y + stack[j + 2])
                        end = point(control2.x + extra, control2.y + stack[j + 3])
                    } else {
                        control1 = point(x, y + stack[j])
                        control2 = point(control1.x + stack[j + 1], control1.y + stack[j + 2])
                        end = point(control2.x + stack[j + 3], control2.y + extra)
                    }
                    curveTo(control1, control2, end)
                    j += isLast ? 5 : 4
                    horizontal.toggle()
                }
                stack.removeAll(keepingCapacity: true)

            case 10, 29:  // callsubr, callgsubr
                let subrs = (b0 == 10) ? localSubrs : globalSubrs
                let bias = (b0 == 10) ? localBias : globalBias
                guard let operand = stack.popLast() else {
                    throw OpenTypeError.unsupportedCharstringOperator("callsubr with empty stack")
                }
                let index = Int(operand) + bias
                guard subrs.indices.contains(index) else {
                    throw OpenTypeError.malformedCFF("subroutine \(index) out of range")
                }
                try run(subrs[index], depth: depth + 1)
                if finished { return }

            case 11:  // return
                return

            case 14:  // endchar
                consumeWidthForEndchar()
                if stack.count >= 4 {
                    // `seac`-style accent composition. Neither bundled face uses it, and
                    // supporting it means dragging in the CFF charset and the 391 standard
                    // strings to resolve the component glyph names.
                    throw OpenTypeError.unsupportedCharstringOperator("endchar (seac)")
                }
                stack.removeAll(keepingCapacity: true)
                finished = true
                return

            case 12:
                let b1 = try bytes.u8(i, "charstring")
                i += 1
                try runEscaped(b1)

            default:
                throw OpenTypeError.unsupportedCharstringOperator("reserved operator \(b0)")
            }
        }
    }

    /// The two-byte (`12 x`) operators. Only the four flex variants are implemented; the
    /// arithmetic, storage, and conditional operators are legal Type 2 but appear in no
    /// real font, and guessing at them would produce silently wrong outlines.
    private mutating func runEscaped(_ op: Int) throws {
        switch op {
        case 35:  // flex — two curves plus a flex depth that only affects hinting
            guard stack.count >= 13 else { break }
            relativeCurve(Array(stack[0..<6]))
            relativeCurve(Array(stack[6..<12]))

        case 34:  // hflex — horizontal flex, returning to the starting y
            guard stack.count >= 7 else { break }
            let startY = y
            var control1 = point(x + stack[0], y)
            var control2 = point(control1.x + stack[1], control1.y + stack[2])
            curveTo(control1, control2, point(control2.x + stack[3], control2.y))
            control1 = point(x + stack[4], y)
            control2 = point(control1.x + stack[5], startY)
            curveTo(control1, control2, point(control2.x + stack[6], startY))

        case 36:  // hflex1 — as hflex, but the first curve may leave the baseline
            guard stack.count >= 9 else { break }
            let startY = y
            var control1 = point(x + stack[0], y + stack[1])
            var control2 = point(control1.x + stack[2], control1.y + stack[3])
            curveTo(control1, control2, point(control2.x + stack[4], control2.y))
            control1 = point(x + stack[5], y)
            control2 = point(control1.x + stack[6], control1.y + stack[7])
            curveTo(control1, control2, point(control2.x + stack[8], startY))

        case 37:  // flex1 — the final point's minor axis returns to the start
            guard stack.count >= 11 else { break }
            let startX = x
            let startY = y
            let deltaX = stack[0] + stack[2] + stack[4] + stack[6] + stack[8]
            let deltaY = stack[1] + stack[3] + stack[5] + stack[7] + stack[9]
            var control1 = point(x + stack[0], y + stack[1])
            var control2 = point(control1.x + stack[2], control1.y + stack[3])
            curveTo(control1, control2, point(control2.x + stack[4], control2.y + stack[5]))
            control1 = point(x + stack[6], y + stack[7])
            control2 = point(control1.x + stack[8], control1.y + stack[9])
            let end = abs(deltaX) > abs(deltaY)
                ? point(control2.x + stack[10], startY)
                : point(startX, control2.y + stack[10])
            curveTo(control1, control2, end)

        default:
            throw OpenTypeError.unsupportedCharstringOperator("12 \(op)")
        }
        stack.removeAll(keepingCapacity: true)
    }

    // MARK: Width

    /// Drops the leading width operand of stem and `*moveto` operators, which is present
    /// only when the operator carries more arguments than its signature calls for.
    private mutating func consumeWidth(ifArgumentsExceed expected: Int) {
        guard !widthConsumed else { return }
        widthConsumed = true
        if stack.count > expected { stack.removeFirst() }
    }

    /// Stem hints come in pairs, so an odd operand count means the first is a width.
    private mutating func consumeWidthIfOddArgumentCount() {
        guard !widthConsumed else { return }
        widthConsumed = true
        if stack.count % 2 == 1 { stack.removeFirst() }
    }

    /// `endchar` takes either nothing or four `seac` arguments, so only counts of one and
    /// five carry a width.
    private mutating func consumeWidthForEndchar() {
        guard !widthConsumed else { return }
        widthConsumed = true
        if stack.count == 1 || stack.count == 5 { stack.removeFirst() }
    }

    // MARK: Path building

    private mutating func push(_ value: Double) throws {
        guard stack.count < Machine.maxStack else {
            throw OpenTypeError.malformedCFF("charstring operand stack overflow")
        }
        stack.append(value)
    }

    private func point(_ atX: Double, _ atY: Double) -> GlyphPath.Point {
        GlyphPath.Point(x: atX, y: atY)
    }

    mutating func closeContour() {
        if contourOpen {
            path.segments.append(.close)
            contourOpen = false
        }
    }

    private mutating func moveTo(deltaX: Double, deltaY: Double) {
        closeContour()
        x += deltaX
        y += deltaY
        path.segments.append(.move(to: point(x, y)))
        contourOpen = true
    }

    private mutating func lineTo(deltaX: Double, deltaY: Double) {
        x += deltaX
        y += deltaY
        path.segments.append(.line(to: point(x, y)))
    }

    private mutating func curveTo(_ control1: GlyphPath.Point, _ control2: GlyphPath.Point,
                                  _ end: GlyphPath.Point) {
        path.segments.append(.curve(control1: control1, control2: control2, to: end))
        x = end.x
        y = end.y
    }

    /// Six relative deltas: two control points and an end point.
    private mutating func relativeCurve(_ deltas: [Double]) {
        let control1 = point(x + deltas[0], y + deltas[1])
        let control2 = point(control1.x + deltas[2], control1.y + deltas[3])
        curveTo(control1, control2, point(control2.x + deltas[4], control2.y + deltas[5]))
    }
}

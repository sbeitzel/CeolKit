//
//  StaffPlanLayout.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 8/19/26.
//

import Foundation

/// A `StaffPlan` tree resolved to the ordered staff table the layout engine consumes.
///
/// Voice selection, span threading, bar-line continuation and brace/bracket drawing each
/// need a different flat view of the same tree.  Deriving all four here, once, keeps every
/// downstream step from re-implementing the traversal and getting the nesting subtly
/// different.
///
/// Staff indices are positions in ``staves``, counted from zero at the top of the plan, and
/// every other member of this type is expressed in them.
public struct StaffPlanLayout: Hashable, Sendable {
    /// Top to bottom.  Each staff lists the voices printed on it, in plan order.
    ///
    /// Floating voices are not here — they have no staff of their own; see ``floating``.
    public let staves: [[VoiceId]]

    /// Brace and bracket spans over staff indices, outermost first.
    public let spans: [Span]

    /// Staff index `i` is joined to `i + 1` by a continued bar line.
    public let barlineJoins: Set<Int>

    /// Voices whose staff is chosen per note, with the staff indices they may land on.
    public let floating: [FloatingVoice]

    public init(
        staves: [[VoiceId]],
        spans: [Span],
        barlineJoins: Set<Int>,
        floating: [FloatingVoice]
    ) {
        self.staves = staves
        self.spans = spans
        self.barlineJoins = barlineJoins
        self.floating = floating
    }

    public struct Span: Hashable, Sendable {
        public let bracket: StaffPlanBracket
        public let staves: ClosedRange<Int>
        /// 0 = outermost; drives sub-bracket thickness.
        public let depth: Int

        public init(bracket: StaffPlanBracket, staves: ClosedRange<Int>, depth: Int) {
            self.bracket = bracket
            self.staves = staves
            self.depth = depth
        }
    }

    /// A `*V` voice and the two staves it sits between.  Either neighbour is `nil` where
    /// the plan has none — the assigner diagnoses that and prints the voice on the staff
    /// it does have.
    public struct FloatingVoice: Hashable, Sendable {
        public let id: VoiceId
        /// Staff index, `nil` at the top of the plan.
        public let above: Int?
        /// Staff index, `nil` at the bottom of the plan.
        public let below: Int?

        public init(id: VoiceId, above: Int?, below: Int?) {
            self.id = id
            self.above = above
            self.below = below
        }
    }
}

/// Which of the two grouping delimiters a ``StaffPlanLayout/Span`` was drawn from.
public enum StaffPlanBracket: Hashable, Sendable {
    case brace     // `{ … }`
    case bracket   // `[ … ]`
}

public extension StaffPlan {

    /// The plan flattened to the staff table the layout engine consumes.
    ///
    /// Three readings the tree leaves open are settled here, none of them dictated by
    /// §11.1:
    ///
    /// - A floating voice occupies no staff, so the joint written *before* it joins
    ///   nothing and is discarded; the joint written *after* it governs the boundary
    ///   between the staves on either side.  That is the sense the standard's own
    ///   `%%score {RH *M| LH}` is spelled in, and it inverts correctly for `%%staves`.
    /// - A `( … )` group is one staff, so grouping delimiters nested inside one draw no
    ///   span, and a `*` inside one marks nothing: the voice is simply printed on the
    ///   shared staff.
    /// - A grouping delimiter that ends up covering no staff at all — `{*A}`, say —
    ///   draws no span, there being no staff to draw it over.
    var layout: StaffPlanLayout {
        var walk = Walk()
        walk.branch(root)
        return StaffPlanLayout(
            staves: walk.staves,
            spans: walk.spans.map {
                StaffPlanLayout.Span(bracket: $0.bracket, staves: $0.first...$0.last, depth: $0.depth)
            },
            barlineJoins: walk.barlineJoins,
            floating: walk.floating
        )
    }
}

/// The single in-order traversal every member of `StaffPlanLayout` falls out of.
private struct Walk {
    var staves: [[VoiceId]] = []
    var spans: [OpenSpan] = []
    var barlineJoins: Set<Int> = []
    var floating: [StaffPlanLayout.FloatingVoice] = []

    /// A span whose last staff is not known until its branch has been walked.  Spans that
    /// never cover a staff are dropped rather than closed.
    struct OpenSpan {
        let bracket: StaffPlanBracket
        let depth: Int
        let first: Int
        var last: Int
    }

    /// The staff most recently emitted, and so the one a continued bar line would reach
    /// down from.
    private var lastStaff: Int?
    /// The joint waiting to be settled by the next staff.  A joint that meets a floating
    /// voice instead of a staff is overwritten by the next one rather than consumed.
    private var pendingJoint: StaffPlanJoint = .separate
    /// Floating voices still waiting to learn which staff is below them.
    private var floatingAwaitingBelow: [Int] = []
    /// How many grouping delimiters enclose the node being walked.
    private var depth = 0

    mutating func branch(_ branch: StaffPlanBranch) {
        node(branch.head)
        for sibling in branch.tail {
            pendingJoint = sibling.joint
            node(sibling.node)
        }
    }

    private mutating func node(_ node: StaffPlanNode) {
        switch node {
        case .voice(let voice):
            if voice.isFloating {
                floatingAwaitingBelow.append(floating.count)
                floating.append(StaffPlanLayout.FloatingVoice(id: voice.id, above: lastStaff, below: nil))
            } else {
                emitStaff([voice.id])
            }

        case .shared(let branch):
            // One staff, and every voice written anywhere inside it lands on that staff —
            // including one marked `*`, which has no adjacent staff to float between.
            emitStaff(Self.voices(in: branch))

        case .brace(let branch):
            group(branch, bracket: .brace)

        case .bracket(let branch):
            group(branch, bracket: .bracket)
        }
    }

    private mutating func group(_ inner: StaffPlanBranch, bracket: StaffPlanBracket) {
        // Reserved before the branch is walked so that spans come out outermost first.
        let slot = spans.count
        spans.append(OpenSpan(bracket: bracket, depth: depth, first: staves.count, last: -1))

        depth += 1
        branch(inner)
        depth -= 1

        if staves.count > spans[slot].first {
            spans[slot].last = staves.count - 1
        } else {
            spans.remove(at: slot)
        }
    }

    private mutating func emitStaff(_ voices: [VoiceId]) {
        let index = staves.count
        staves.append(voices)

        if pendingJoint == .continuedBarline, let above = lastStaff {
            barlineJoins.insert(above)
        }
        pendingJoint = .separate

        for pending in floatingAwaitingBelow {
            floating[pending] = StaffPlanLayout.FloatingVoice(
                id: floating[pending].id,
                above: floating[pending].above,
                below: index
            )
        }
        floatingAwaitingBelow.removeAll()

        lastStaff = index
    }

    /// Every voice under `branch`, in written order, whatever delimiters it is nested in.
    private static func voices(in branch: StaffPlanBranch) -> [VoiceId] {
        branch.nodes.flatMap { node -> [VoiceId] in
            switch node {
            case .voice(let voice):
                return [voice.id]
            case .shared(let inner), .brace(let inner), .bracket(let inner):
                return voices(in: inner)
            }
        }
    }
}

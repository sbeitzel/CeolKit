//
//  StaffPlan.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 8/18/26.
//

import Foundation

/// Resolved staff layout from `%%score` / `%%staves` (ABC v2.2 §11.1).
///
/// The two spellings differ only in the sense of `|`, and both normalise to this tree,
/// so nothing downstream can tell which one was written.
///
/// Equality covers the layout only, not where it was written: `%%staves [S|A|T|B]` and
/// `%%score [S A T B]` describe the same plan and compare equal, even though the two
/// payloads are different lengths and so can never carry matching source ranges.  The
/// ranges are provenance for diagnostics, not part of what the plan *is*.  `StaffPlanVoice`
/// does the same for the same reason; every other type in the tree gets there through them.
public struct StaffPlan: Hashable, Sendable {
    /// The outermost siblings.  The top level has no delimiter of its own, so it is a
    /// bare branch rather than a node.
    public let root: StaffPlanBranch
    public let source: SourceRange

    public init(root: StaffPlanBranch, source: SourceRange) {
        self.root = root
        self.source = source
    }

    public static func == (lhs: StaffPlan, rhs: StaffPlan) -> Bool {
        lhs.root == rhs.root
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(root)
    }
}

public indirect enum StaffPlanNode: Hashable, Sendable {
    case voice(StaffPlanVoice)
    case shared(StaffPlanBranch)   // `( … )` — these voices share one staff
    case brace(StaffPlanBranch)    // `{ … }`
    case bracket(StaffPlanBranch)  // `[ … ]`
}

/// One or more sibling nodes and the joints between them.  `head` guarantees non-emptiness;
/// each `tail` element carries the joint that *precedes* it, so there are always exactly
/// `count - 1` joints and no index arithmetic.
public struct StaffPlanBranch: Hashable, Sendable {
    public let head: StaffPlanNode
    public let tail: [Sibling]

    public struct Sibling: Hashable, Sendable {
        public let joint: StaffPlanJoint
        public let node: StaffPlanNode

        public init(joint: StaffPlanJoint, node: StaffPlanNode) {
            self.joint = joint
            self.node = node
        }
    }

    public init(head: StaffPlanNode, tail: [Sibling] = []) {
        self.head = head
        self.tail = tail
    }

    /// The siblings in written order, joints discarded.
    public var nodes: [StaffPlanNode] {
        [head] + tail.map(\.node)
    }
}

public enum StaffPlanJoint: Hashable, Sendable {
    case separate
    case continuedBarline
}

/// Equality ignores `source`, so that plans written differently but meaning the same
/// thing compare equal — see `StaffPlan`.
public struct StaffPlanVoice: Hashable, Sendable {
    public let id: VoiceId
    public let isFloating: Bool    // `*V`
    public let source: SourceRange

    public init(id: VoiceId, isFloating: Bool, source: SourceRange) {
        self.id = id
        self.isFloating = isFloating
        self.source = source
    }

    public static func == (lhs: StaffPlanVoice, rhs: StaffPlanVoice) -> Bool {
        lhs.id == rhs.id && lhs.isFloating == rhs.isFloating
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(isFloating)
    }
}

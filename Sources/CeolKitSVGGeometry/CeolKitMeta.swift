//
//  CeolKitMeta.swift
//  CeolKitSVGGeometry
//
//  Decoding of the `ceolkit-meta` comment the emitter writes for scroll-sync (issue #25).
//

import Foundation

/// The `ceolkit-meta` payload: one anchor per staff system, in emission order.
public struct CeolKitMeta: Sendable, Codable, Equatable {
    public struct Anchor: Sendable, Codable, Equatable {
        public let abcLine: Int
        public let y: Double
    }

    public let page: Int
    public let anchors: [Anchor]
}

extension CeolKitMeta {
    /// Extracts and decodes the `ceolkit-meta` comment from a page of SVG.
    ///
    /// Returns `nil` when the comment is absent or unreadable — callers treat the
    /// metadata as an optional enrichment, never as a precondition.
    public static func extract(from svg: String) -> CeolKitMeta? {
        guard let match = svg.firstMatch(of: #/<!--\s*ceolkit-meta:\s*(\{.*?\})\s*-->/#),
              let data = String(match.1).data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(CeolKitMeta.self, from: data)
    }
}

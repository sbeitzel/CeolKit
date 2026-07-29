//
//  StaffProperties.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct StaffProperties: Hashable, Sendable {
    public let staffLines: Int     // default 5

    public init(staffLines: Int) {
        self.staffLines = staffLines
    }
}

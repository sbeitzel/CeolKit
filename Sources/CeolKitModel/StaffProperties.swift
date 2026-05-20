//
//  StaffProperties.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public struct StaffProperties: Hashable {
    public let staffLines: Int     // default 5
    public let scale: Double?      // optional rendering scale factor; nil = default
}

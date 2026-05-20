//
//  ScoreLineBreak.swift
//  CeolKit
//
//  Created by Stephen Beitzel on 5/19/26.
//

import Foundation

public enum ScoreLineBreak {
    case hard      // forces a system break in output
    case soft      // permits but does not force
    case suppressed // the source line ended with \
}

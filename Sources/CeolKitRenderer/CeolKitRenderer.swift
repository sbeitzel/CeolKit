
import CeolKitModel
import Foundation

// CeolKitRenderer module — depends on CeolKitModel only
public protocol CeolKitRenderer<Output> {
    associatedtype Output
    func render(_ score: Score) throws -> Output
}

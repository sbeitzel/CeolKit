import CeolKitModel

/// Tracks which ABC information fields should be typeset, per §11.4.6.
///
/// The default field set is `TCOPQwW` as specified in §6.1.3.
/// Each `%%writefields` directive adds to or removes from this set cumulatively.
struct WriteFieldsConfig {
    private(set) var enabled: Set<Character>

    static let `default` = WriteFieldsConfig()

    init() {
        enabled = Set("TCOPQwW")
    }

    mutating func apply(_ directive: CeolKitDirective) {
        guard case .writeFields(let fields, let on) = directive else { return }
        for ch in fields {
            if on { enabled.insert(ch) } else { enabled.remove(ch) }
        }
    }

    func includes(_ field: Character) -> Bool {
        enabled.contains(field)
    }
}

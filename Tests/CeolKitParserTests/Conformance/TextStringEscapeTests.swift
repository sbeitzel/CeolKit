// Comments and escapes in information-field text. ABC §2.2.5, §8.2.
//
// A `%` starts a comment that runs to the end of the line; `\%` is a literal percent sign,
// and `\\` a literal backslash — so `\\%` is a backslash followed by a comment (issue #145).
import Testing
import CeolKitModel
import CeolKitParser

@Suite("Text string escapes (§2.2.5, §8.2)")
struct TextStringEscapeTests {

    private func title(_ payload: String) -> String? {
        parse("X:1\nT:\(payload)\nK:none\n").score.tunes.first?.titles.first?.value
    }

    @Test("\\% is a literal percent sign, not a comment")
    func escapedPercent() {
        #expect(title(#"100\% Pipes"#) == "100% Pipes")
    }

    @Test("An unescaped % still starts a comment")
    func unescapedPercent() {
        #expect(title("50% off % note") == "50")
    }

    @Test("An escaped percent may be followed by a comment")
    func escapedThenComment() {
        #expect(title(#"100\% Pipes % a remark"#) == "100% Pipes")
    }

    @Test("\\\\ is a literal backslash")
    func escapedBackslash() {
        #expect(title(#"A\\B"#) == #"A\B"#)
    }

    @Test("\\\\% is a backslash followed by a comment")
    func escapedBackslashThenComment() {
        #expect(title(#"A\\% remark"#) == #"A\"#)
    }

    @Test("\\\\\\% is a backslash then a literal percent sign")
    func escapedBackslashThenEscapedPercent() {
        #expect(title(#"A\\\% B"#) == #"A\% B"#)
    }

    @Test("Other backslash sequences reach the value verbatim")
    func otherEscapesVerbatim() {
        #expect(title(#"A\&B"#) == #"A\&B"#)
        #expect(title(#"caf\'e"#) == #"caf\'e"#)
        #expect(title(#"trailing\"#) == #"trailing\"#)
    }

    @Test("Other text fields honour \\% too")
    func otherTextFields() {
        let abc = "X:1\nT:T\nC:50\\% Smith % remark\nN:a \\% note\nK:none\n"
        let metadata = parse(abc).score.tunes.first?.metadata
        #expect(metadata?.composer?.value == "50% Smith")
        #expect(metadata?.notes?.value == "a % note")
    }

    @Test("I: keeps \\% for the directive to read, as %%name does")
    func instructionKeepsEscape() {
        let abc = #"X:1\#nT:T\#nK:C\#nI:dateformat \%Y-\%m % remark\#nC|"#
        let directive = parse(abc).score.tunes.flatMap(\.directives).first {
            if case .dateFormat = $0.directive { return true }
            return false
        }
        guard case .dateFormat(let format) = directive?.directive else {
            Issue.record("Expected a dateFormat directive, got \(String(describing: directive))")
            return
        }
        #expect(format.contains(#"\%Y-\%m"#))
        #expect(!format.contains("remark"))
    }
}

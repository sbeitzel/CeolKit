// Comment and escape handling shared by the information fields (§2.2.5, §8.2).

/// The payload up to the `%` that starts its comment, or the whole payload when it has none.
///
/// §2.2.5: a `%` ignores the rest of the line, "to get a percent symbol, type `\%`".  A
/// backslash escapes the one character after it, so `\%` is not a comment and `\\%` — an
/// escaped backslash, then a bare `%` — is.  The escapes themselves are left in place; see
/// ``decodeTextEscapes(_:)``.
func stripFieldComment(_ s: String) -> Substring {
    var escaped = false
    for idx in s.indices {
        let ch = s[idx]
        if escaped {
            escaped = false
        } else if ch == "\\" {
            escaped = true
        } else if ch == "%" {
            return s[..<idx]
        }
    }
    return s[...]
}

/// A text string with its `\%` and `\\` escapes decoded (§8.2, *Special characters*).
///
/// These two are decoded together because they are the ones comment stripping reads: `\\%`
/// is a backslash followed by a comment, so the backslash it leaves behind must come out as
/// one.  Any other backslash sequence reaches the value verbatim.
func decodeTextEscapes(_ s: some StringProtocol) -> String {
    var result = ""
    var escaped = false
    for ch in s {
        if escaped {
            if ch != "%" && ch != "\\" { result.append("\\") }
            result.append(ch)
            escaped = false
        } else if ch == "\\" {
            escaped = true
        } else {
            result.append(ch)
        }
    }
    if escaped { result.append("\\") }
    return result
}

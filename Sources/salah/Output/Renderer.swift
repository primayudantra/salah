import Foundation

/// A run of text with one style.
struct Span {
    enum Kind { case normal, bold, dim, accent }
    var text: String
    var kind: Kind = .normal

    static func normal(_ t: String) -> Span { Span(text: t, kind: .normal) }
    static func bold(_ t: String) -> Span { Span(text: t, kind: .bold) }
    static func dim(_ t: String) -> Span { Span(text: t, kind: .dim) }
    static func accent(_ t: String) -> Span { Span(text: t, kind: .accent) }
}

typealias Line = [Span]

enum OutputMode: Equatable {
    case pretty, plain, compact, json
}

/// Renders sections of lines as a rounded box (pretty) or as bare text (plain).
struct Renderer {
    let mode: OutputMode
    let color: Bool

    static let minInnerWidth = 44

    func render(_ sections: [[Line]]) -> String {
        let style = Style(enabled: color && mode == .pretty)
        let nonEmpty = sections.filter { !$0.isEmpty }
        guard mode == .pretty else {
            return nonEmpty.map { $0.map { Self.plainText($0) }.joined(separator: "\n") }.joined(separator: "\n\n") + "\n"
        }
        let widest = nonEmpty.flatMap { $0 }.map { Self.width($0) }.max() ?? 0
        let inner = max(Self.minInnerWidth, widest + 4)
        var out = ["╭" + String(repeating: "─", count: inner) + "╮"]
        for (i, section) in nonEmpty.enumerated() {
            if i > 0 { out.append("├" + String(repeating: "─", count: inner) + "┤") }
            for line in section {
                let pad = inner - 2 - Self.width(line)
                out.append("│  " + Self.styled(line, style) + String(repeating: " ", count: max(0, pad)) + "│")
            }
        }
        out.append("╰" + String(repeating: "─", count: inner) + "╯")
        return out.joined(separator: "\n") + "\n"
    }

    static func width(_ line: Line) -> Int { line.reduce(0) { $0 + $1.text.count } }

    static func plainText(_ line: Line) -> String {
        line.map(\.text).joined().replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
    }

    static func styled(_ line: Line, _ style: Style) -> String {
        line.map { span in
            switch span.kind {
            case .normal: return span.text
            case .bold: return style.bold(span.text)
            case .dim: return style.dim(span.text)
            case .accent: return style.accent(span.text)
            }
        }.joined()
    }

    /// Left-aligns `s` in a column of `width` characters.
    static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }
}

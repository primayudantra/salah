import Foundation

enum Terminal {
    /// Color only on an interactive stdout, and never when NO_COLOR is set or TERM=dumb.
    static func colorAllowed(environment env: [String: String] = ProcessInfo.processInfo.environment, isTTY: Bool = stdoutIsTTY) -> Bool {
        guard isTTY else { return false }
        if let v = env["NO_COLOR"], !v.isEmpty { return false }
        if env["TERM"] == "dumb" { return false }
        return true
    }

    static var stdoutIsTTY: Bool { isatty(STDOUT_FILENO) != 0 }
    static var stdinIsTTY: Bool { isatty(STDIN_FILENO) != 0 }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data(("salah: " + message + "\n").utf8))
    }
}

/// ANSI styling that collapses to plain text when color is off.
struct Style {
    let enabled: Bool

    func bold(_ s: String) -> String { wrap(s, "1") }
    func dim(_ s: String) -> String { wrap(s, "2") }
    func accent(_ s: String) -> String { wrap(s, "1;31") }

    private func wrap(_ s: String, _ code: String) -> String {
        enabled && !s.isEmpty ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s
    }
}

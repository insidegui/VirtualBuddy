import Foundation
import MacDebugProtocol

extension DebugScheme {
    public static func launchOptions(from xml: XMLDocument, settings: [String: String]) throws -> DebugLaunchOptions {
        let pattern = try NSRegularExpression(pattern: #"\$\(([a-zA-Z_][a-zA-Z_0-9]*)\)|\$\{([a-zA-Z_][a-zA-Z_0-9]*)\}"#)
        func expand(_ raw: String) throws -> String {
            let result = NSMutableString(string: raw)
            let source = raw as NSString
            for match in pattern.matches(in: raw, range: NSRange(location: 0, length: source.length)).reversed() {
                let first = match.range(at: 1)
                let name = source.substring(with: first.location == NSNotFound ? match.range(at: 2) : first)
                guard let value = settings[name] else { throw MacDebugError("The Run action references an unavailable build setting, " + name + ".") }
                result.replaceCharacters(in: match.range, with: value)
            }
            return String(result)
        }
        var args: [String] = []
        for case let node as XMLElement in try xml.nodes(forXPath: "/Scheme/LaunchAction/CommandLineArguments/CommandLineArgument[@isEnabled='YES']") {
            let raw = node.attribute(forName: "argument")?.stringValue ?? ""
            // Xcode allows several shell-quoted words in one row. Expand each word
            // after tokenization so spaces in a build setting stay in one argument.
            var word = "", quote: Character?, escaped = false, started = false
            for c in raw {
                if escaped {
                    word.append(c)
                    escaped = false
                    continue
                }
                if c == "\\", quote != "'" {
                    escaped = true
                    started = true
                    continue
                }
                if let q = quote {
                    if c == q { quote = nil } else { word.append(c) }
                } else if c == "\"" || c == "'" {
                    quote = c
                    started = true
                } else if c.isWhitespace {
                    if started {
                        args.append(try expand(word))
                        word = ""
                        started = false
                    }
                } else {
                    word.append(c)
                    started = true
                }
            }
            guard quote == nil, !escaped else { throw MacDebugError("Unterminated quote or escape in Run argument “\(raw)”.") }
            if started || raw.isEmpty { args.append(try expand(word)) }
        }
        var env: [String: String] = [:]
        for case let node as XMLElement in try xml.nodes(forXPath: "/Scheme/LaunchAction/EnvironmentVariables/EnvironmentVariable[@isEnabled='YES']") {
            guard let name = node.attribute(forName: "key")?.stringValue, !name.isEmpty, !name.contains("=") else { throw MacDebugError("Invalid Run environment variable name.") }
            env[name] = try expand(node.attribute(forName: "value")?.stringValue ?? "")
        }
        return DebugLaunchOptions(arguments: args, environment: env)
    }
}

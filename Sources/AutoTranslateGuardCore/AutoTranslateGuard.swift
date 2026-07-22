import Foundation
import SwiftParser
import SwiftSyntax

public struct GuardDiagnostic: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case rawDynamicDisplay
        case rawUIKitAssignment
    }

    public let file: String
    public let line: Int
    public let column: Int
    public let kind: Kind
    public let message: String
    public let suggestion: String

    public init(
        file: String,
        line: Int,
        column: Int,
        kind: Kind,
        message: String,
        suggestion: String
    ) {
        self.file = file
        self.line = line
        self.column = column
        self.kind = kind
        self.message = message
        self.suggestion = suggestion
    }
}

public struct GuardScanResult: Sendable {
    public let diagnostics: [GuardDiagnostic]
    public let fixedSource: String
    public let appliedFixCount: Int
}

public enum AutoTranslateGuard {
    public static func scan(
        source: String,
        file: String = "<memory>",
        applyingFixes: Bool = false
    ) -> GuardScanResult {
        let tree = Parser.parse(source: source)
        let collector = DisplayCallCollector(
            source: source,
            file: file,
            knownSafeIdentifiers: safeIdentifiers(in: source),
            knownUIKitIdentifiers: uiKitIdentifiers(in: source),
            applyingFixes: applyingFixes
        )
        collector.walk(tree)

        var diagnostics = collector.diagnostics
        diagnostics.sort {
            ($0.line, $0.column, $0.message) < ($1.line, $1.column, $1.message)
        }

        let fixed = apply(edits: collector.edits, to: source)
        return GuardScanResult(
            diagnostics: diagnostics,
            fixedSource: fixed,
            appliedFixCount: collector.edits.count
        )
    }

    private static func safeIdentifiers(in source: String) -> Set<String> {
        let pattern = #"\b([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?:LocalizedStringResource|DisplayString)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return Set(regex.matches(in: source, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[range])
        })
    }

    private static func uiKitIdentifiers(in source: String) -> Set<String> {
        let pattern = #"\b([A-Za-z_][A-Za-z0-9_]*)\s*:\s*UI(?:Label|Button|NavigationItem|TextField|TextView|SearchBar)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return Set(regex.matches(in: source, range: range).compactMap { match in
            guard let range = Range(match.range(at: 1), in: source) else { return nil }
            return String(source[range])
        })
    }

    private static func apply(edits: [SourceEdit], to source: String) -> String {
        var bytes = Array(source.utf8)
        for edit in edits.sorted(by: { $0.offset > $1.offset }) {
            bytes.replaceSubrange(
                edit.offset..<(edit.offset + edit.length),
                with: Array(edit.replacement.utf8)
            )
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

private final class DisplayCallCollector: SyntaxVisitor {
    private let source: String
    private let file: String
    private let knownSafeIdentifiers: Set<String>
    private let knownUIKitIdentifiers: Set<String>
    private let applyingFixes: Bool

    fileprivate var diagnostics: [GuardDiagnostic] = []
    fileprivate var edits: [SourceEdit] = []

    init(
        source: String,
        file: String,
        knownSafeIdentifiers: Set<String>,
        knownUIKitIdentifiers: Set<String>,
        applyingFixes: Bool
    ) {
        self.source = source
        self.file = file
        self.knownSafeIdentifiers = knownSafeIdentifiers
        self.knownUIKitIdentifiers = knownUIKitIdentifiers
        self.applyingFixes = applyingFixes
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let callee = compact(node.calledExpression.description)
        let name = callee.split(separator: ".").last.map(String.init) ?? callee
        let guarded = ["Text", "Button", "Label", "navigationTitle", "accessibilityLabel", "alert"]

        if guarded.contains(name), let argument = displayArgument(in: node, named: name) {
            inspect(argument: argument, callName: name, call: node)
        } else if name == "setTitle", let argument = node.arguments.first {
            inspect(argument: argument, callName: name, call: node)
        }
        return .visitChildren
    }

    override func visit(_ node: SequenceExprSyntax) -> SyntaxVisitorContinueKind {
        let expression = compact(node.description)
        let pattern = #"([A-Za-z_][A-Za-z0-9_\.]*)\.(?:text|title)\s*=\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: expression,
                range: NSRange(expression.startIndex..., in: expression)
              ),
              let receiverRange = Range(match.range(at: 1), in: expression),
              let assignmentRange = Range(match.range(at: 0), in: expression) else {
            return .visitChildren
        }

        let receiver = expression[receiverRange].split(separator: ".").last.map(String.init) ?? ""
        guard knownUIKitIdentifiers.contains(receiver) else { return .visitChildren }

        let assignment = String(expression[assignmentRange])
        let value = assignment.split(separator: "=", maxSplits: 1)
            .last
            .map { compact(String($0)) } ?? ""
        let line = lineText(at: node.positionAfterSkippingLeadingTrivia.utf8Offset)
        guard !isExplicitlyExcluded(line),
              !isSafeText(value) else {
            return .visitChildren
        }

        let location = lineAndColumn(at: node.positionAfterSkippingLeadingTrivia.utf8Offset)
        diagnostics.append(GuardDiagnostic(
            file: file,
            line: location.line,
            column: location.column,
            kind: .rawUIKitAssignment,
            message: "Raw dynamic string assigned to a UIKit display property.",
            suggestion: "Resolve a DisplayString through the translation broker, or mark this line noTranslation."
        ))
        return .visitChildren
    }

    private func displayArgument(
        in call: FunctionCallExprSyntax,
        named name: String
    ) -> LabeledExprSyntax? {
        guard let first = call.arguments.first else { return nil }
        if name == "Text", first.label?.text == "verbatim" {
            return nil
        }
        if ["Button", "Label"].contains(name), first.label != nil {
            return nil
        }
        return first
    }

    private func inspect(
        argument: LabeledExprSyntax,
        callName: String,
        call: FunctionCallExprSyntax
    ) {
        let expression = argument.expression
        let text = compact(expression.description)
        guard !isSafe(expression: expression, text: text),
              !lineText(at: call.positionAfterSkippingLeadingTrivia.utf8Offset)
                .contains("noTranslation") else {
            return
        }

        let location = lineAndColumn(at: expression.positionAfterSkippingLeadingTrivia.utf8Offset)
        diagnostics.append(GuardDiagnostic(
            file: file,
            line: location.line,
            column: location.column,
            kind: .rawDynamicDisplay,
            message: "Raw dynamic value displayed by \(callName).",
            suggestion: suggestion(for: callName)
        ))

        if applyingFixes,
           callName == "Text",
           compact(call.calledExpression.description) == "Text",
           isSimpleIdentifier(text) {
            edits.append(SourceEdit(
                offset: call.calledExpression.positionAfterSkippingLeadingTrivia.utf8Offset,
                length: call.calledExpression.trimmedLength.utf8Length,
                replacement: "TranslatedText"
            ))
        }
    }

    private func isSafe(expression: ExprSyntax, text: String) -> Bool {
        if expression.is(StringLiteralExprSyntax.self) { return true }
        if knownSafeIdentifiers.contains(text) { return true }
        if text.contains(".noTranslation()") { return true }
        return isSafeText(text)
    }

    private func isSafeText(_ text: String) -> Bool {
        text.first == "\""
            || knownSafeIdentifiers.contains(text)
            || text.contains(".noTranslation()")
            || text.hasPrefix("String(localized:")
            || text.hasPrefix("LocalizedStringResource(")
            || text.hasPrefix("DisplayString.")
            || text.hasPrefix("TranslatedText(")
            || text.hasPrefix("Text(")
    }

    private func suggestion(for callName: String) -> String {
        if callName == "Text" {
            return "Use TranslatedText(value), DisplayString, String(localized:), or mark it noTranslation."
        }
        return "Resolve this value with DisplayString/TranslatedText, or mark it noTranslation."
    }

    private func lineText(at utf8Offset: Int) -> String {
        let bytes = Array(source.utf8)
        let start = bytes[..<min(utf8Offset, bytes.count)].lastIndex(of: 10).map { $0 + 1 } ?? 0
        let end = bytes[min(utf8Offset, bytes.count)...].firstIndex(of: 10) ?? bytes.count
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    private func lineAndColumn(at utf8Offset: Int) -> (line: Int, column: Int) {
        let prefix = source.utf8.prefix(utf8Offset)
        let line = prefix.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
        let lastNewline = prefix.lastIndex(of: 10)
        let column = lastNewline.map { prefix.distance(from: prefix.index(after: $0), to: prefix.endIndex) + 1 }
            ?? prefix.count + 1
        return (line, column)
    }
}

private struct SourceEdit {
    let offset: Int
    let length: Int
    let replacement: String
}

private func compact(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func isSimpleIdentifier(_ value: String) -> Bool {
    guard let first = value.unicodeScalars.first,
          CharacterSet.letters.union(CharacterSet(charactersIn: "_")).contains(first) else {
        return false
    }
    return value.unicodeScalars.dropFirst().allSatisfy {
        CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_")).contains($0)
    }
}

private func isExplicitlyExcluded(_ line: String) -> Bool {
    line.contains("noTranslation") || line.contains("autotranslate:ignore")
}

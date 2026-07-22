import Foundation
import PackagePlugin

@main
struct AutoTranslateGuardCommandPlugin: CommandPlugin {
    func performCommand(
        context: PluginContext,
        arguments: [String]
    ) async throws {
        let scanner = try context.tool(named: "AutoTranslateGuardScanner")
        let sources = context.package.targets
            .compactMap { $0 as? SourceModuleTarget }
            .flatMap { $0.sourceFiles(withSuffix: "swift").map(\.path.string) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: scanner.path.string)
        process.arguments = arguments + sources
        try process.run()
        process.waitUntilExit()

        if process.terminationReason != .exit || process.terminationStatus != 0 {
            throw GuardCommandError.failed(process.terminationStatus)
        }
    }
}

private enum GuardCommandError: Error, CustomStringConvertible {
    case failed(Int32)

    var description: String {
        switch self {
        case let .failed(code):
            "AutoTranslateGuard failed with exit code \(code)."
        }
    }
}

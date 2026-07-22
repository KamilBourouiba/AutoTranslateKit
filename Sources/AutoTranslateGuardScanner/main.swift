import AutoTranslateGuardCore
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let appliesFixes = arguments.contains("--fix")
let stampIndex = arguments.firstIndex(of: "--stamp")
let stampPath = stampIndex.flatMap { index in
    arguments.indices.contains(index + 1) ? arguments[index + 1] : nil
}

let optionValues = Set(stampPath.map { [$0] } ?? [])
let inputs = arguments.filter {
    !$0.hasPrefix("--") && !optionValues.contains($0)
}
let files = swiftFiles(from: inputs)

guard !files.isEmpty else {
    FileHandle.standardError.write(
        Data("AutoTranslateGuard: no Swift source files were provided.\n".utf8)
    )
    exit(2)
}

var diagnostics: [GuardDiagnostic] = []
var fixedCount = 0

for file in files {
    do {
        let original = try String(contentsOfFile: file, encoding: .utf8)
        let firstPass = AutoTranslateGuard.scan(
            source: original,
            file: file,
            applyingFixes: appliesFixes
        )
        var finalSource = original

        if appliesFixes, firstPass.appliedFixCount > 0 {
            finalSource = firstPass.fixedSource
            try finalSource.write(toFile: file, atomically: true, encoding: .utf8)
            fixedCount += firstPass.appliedFixCount
        }

        diagnostics.append(contentsOf: AutoTranslateGuard.scan(
            source: finalSource,
            file: file
        ).diagnostics)
    } catch {
        FileHandle.standardError.write(
            Data("AutoTranslateGuard: \(file): \(error)\n".utf8)
        )
        exit(2)
    }
}

for diagnostic in diagnostics {
    print(
        "\(diagnostic.file):\(diagnostic.line):\(diagnostic.column): "
            + "error: \(diagnostic.message) \(diagnostic.suggestion)"
    )
}

if appliesFixes, fixedCount > 0 {
    print("AutoTranslateGuard: safely rewrote \(fixedCount) Text call(s).")
}

if diagnostics.isEmpty, let stampPath {
    try? "ok\n".write(toFile: stampPath, atomically: true, encoding: .utf8)
}

exit(diagnostics.isEmpty ? 0 : 1)

private func swiftFiles(from inputs: [String]) -> [String] {
    let manager = FileManager.default
    var results: [String] = []

    for input in inputs {
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: input, isDirectory: &isDirectory) else {
            continue
        }
        if !isDirectory.boolValue {
            if input.hasSuffix(".swift") { results.append(input) }
            continue
        }

        let root = URL(fileURLWithPath: input)
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            continue
        }
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            results.append(url.path)
        }
    }
    return Array(Set(results)).sorted()
}

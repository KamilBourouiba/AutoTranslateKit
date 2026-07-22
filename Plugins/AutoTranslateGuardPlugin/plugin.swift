import PackagePlugin

@main
struct AutoTranslateGuardPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: Target
    ) async throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }

        let sources = target.sourceFiles(withSuffix: "swift").map(\.path)
        guard !sources.isEmpty else { return [] }

        let scanner = try context.tool(named: "AutoTranslateGuardScanner")
        let stamp = context.pluginWorkDirectory.appending("\(target.name)-guard.stamp")

        return [
            .buildCommand(
                displayName: "Guard dynamic display strings in \(target.name)",
                executable: scanner.path,
                arguments: ["--stamp", stamp.string] + sources.map(\.string),
                inputFiles: sources,
                outputFiles: [stamp]
            )
        ]
    }
}

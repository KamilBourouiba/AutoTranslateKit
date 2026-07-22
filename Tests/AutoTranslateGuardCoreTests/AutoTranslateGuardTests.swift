#if canImport(Testing)
import AutoTranslateGuardCore
import Testing

struct AutoTranslateGuardTests {
    @Test
    func testFlagsDynamicSwiftUIAndUIKitDisplays() {
        let source = """
        struct Screen: View {
            let title: String
            var body: some View {
                Text(title)
                    .navigationTitle(title)
            }
            func update(_ label: UILabel) {
                label.text = title
            }
        }
        """

        let result = AutoTranslateGuard.scan(source: source)

        #expect(result.diagnostics.count == 3)
        #expect(result.diagnostics.map(\.line) == [4, 5, 8])
    }

    @Test
    func testAllowsCatalogAndExplicitlyExcludedValues() {
        let source = """
        let resource: LocalizedStringResource = "Settings"
        Text("Settings")
        Text(resource)
        Text(String(localized: "Settings"))
        Text(name.noTranslation())
        Text(name) // autotranslate:ignore noTranslation
        """

        #expect(AutoTranslateGuard.scan(source: source).diagnostics.isEmpty)
    }

    @Test
    func testFixOnlyRewritesSimpleTextIdentifier() {
        let source = """
        Text(title)
        Text(model.title)
        Button(title) {}
        """

        let result = AutoTranslateGuard.scan(source: source, applyingFixes: true)

        #expect(result.appliedFixCount == 1)
        #expect(
            result.fixedSource ==
            """
            TranslatedText(title)
            Text(model.title)
            Button(title) {}
            """
        )
    }

    @Test
    func testLiteralInterpolationRemainsNativeAndLocalizable() {
        let source = #"Text("Welcome, \(name)")"#
        #expect(AutoTranslateGuard.scan(source: source).diagnostics.isEmpty)
    }
}
#endif

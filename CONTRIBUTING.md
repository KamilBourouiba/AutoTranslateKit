# Contributing

Contributions are welcome. Before opening a pull request:

1. Discuss substantial API changes in an issue.
2. Keep public APIs documented and preserve source compatibility when practical.
3. Add or update XCTest coverage for behavior changes.
4. Run `swift test` with a standard Xcode or SwiftPM toolchain.
5. Exercise `AutoTranslateGuardScanner` fixtures when changing guard rules.
6. Do not add absolute paths, local framework search paths, generated build products, or machine-specific configuration.

Please keep pull requests focused and explain both the motivation and the testing performed.

## Versioning

AutoTranslateKit follows Semantic Versioning. Public API removals or behavior
changes require a major release; additive APIs use a minor release; compatible
fixes use a patch release. Deprecate public APIs before removing them whenever
practical.

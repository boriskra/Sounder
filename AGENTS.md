# Repository Guidelines

## Project Structure & Module Organization
`Sounder/` hosts the SwiftUI macOS app split into `Models`, `ViewModels`, `Services`, and `Views`; keep feature code near its view model and service so previews stay fast. Shared assets live in `Sounder/Assets.xcassets`, while configuration files (`Sounder.entitlements`, `Info.plist`) stay at the module root. Unit suites sit under `SounderTests/` with folders that mirror the production layout, and UI workflows live in `SounderUITests/`. Business and UX specs collected in `specs/` provide context before introducing large changes.

## Build, Test, and Development Commands
Open the project in Xcode with `open Sounder.xcodeproj` for day-to-day work. From the CLI, `xcodebuild -project Sounder.xcodeproj -scheme Sounder -destination "platform=macOS" build` produces a deterministic build, and `xcodebuild test -project Sounder.xcodeproj -scheme Sounder -destination "platform=macOS"` runs the XCTest suites. Run static checks locally with `swiftlint lint --strict` to catch style regressions before pushing.

## Coding Style & Naming Conventions
Follow Swift 5 conventions: four-space indentation, braces on the same line, and use `PascalCase` for types, `camelCase` for properties and methods. Prefer protocol-oriented abstractions in `Services/` and keep mocks under `SounderTests/Services`. The `.swiftlint.yml` in the repo defines the authoritative rule set—respect its warnings, especially around function complexity and missing documentation for public APIs.

## Testing Guidelines
Use `XCTestCase` subclasses with filenames ending in `Tests.swift`, mirroring the source module path (`ContentViewModelTests.swift` exercises `ViewModels/ContentViewModel.swift`). Favor focused unit tests under `SounderTests/` and scenario coverage in `SounderUITests/`. When adding features, include regression coverage for audio parameter validation to satisfy the custom lint rule and aim to maintain or raise the coverage reported by Xcode's test navigator.

## Commit & Pull Request Guidelines
Existing history uses concise, descriptive subjects (for example, "Initial commit from Specify template"); keep commits in the imperative mood and under 72 characters. Reference related specs or issues in the body when context lives outside the diff. Pull requests should summarize intent, call out impacted UI, attach screenshots or screen recordings for visual updates, and note any manual verification steps so reviewers can reproduce them quickly.

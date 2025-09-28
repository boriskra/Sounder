# Sounder: Visual Audio Signal Processing

Sounder is a macOS application for generating and processing audio signals using a visual, block-based editor. Users can create complex audio configurations by dragging, dropping, and connecting different audio processing blocks.

## Key Technologies

- **Swift 5.9+** & **SwiftUI**
- **AVFoundation** for the core audio engine
- **XCTest** for unit and UI testing
- Native SwiftUI Canvas for the block editor and Drag & Drop

## Project Structure

The project follows a standard MVVM architecture with a strong service layer.

```
Sounder/
├── Sounder/                          # Main application target
│   ├── Models/                       # Data models (BlockType, OutputDevice, etc.)
│   ├── Views/                        # SwiftUI user interface components
│   ├── ViewModels/                   # View models for UI logic
│   └── Services/                     # Core business logic and audio processing
│       ├── AudioBlockService.swift   # Main service for managing and processing audio blocks
│       ├── AVFAudioService.swift     # Low-level AVFoundation integration
│       └── AudioBlocks/              # Implementations for individual audio blocks
├── SounderTests/                     # Unit and integration tests
├── SounderUITests/                   # UI automation tests
└── specs/                            # Business and UX specifications
```

## Core Architectural Principles

- **Timeline Coherence:** All audio processing is designed to be stateless and sample-accurate. Block processing functions receive an absolute `startSample` position to prevent phase drift and ensure deterministic output. Phase accumulation is strictly forbidden.
- **Real-time Safety:** The audio rendering thread is non-blocking. Memory allocation, lock contention, and any other operations that cannot guarantee real-time execution are avoided.
- **Thread Safety:** Concurrency is managed carefully, with atomic operations used for sharing metrics and lock-free patterns preferred for communication with the audio thread.

## Key Features

- **Visual Block Editor:** Drag, drop, and connect blocks on a canvas to build audio processing graphs.
- **Generators:** Sine, Square, Triangle, Sawtooth, White Noise, Pink Noise, and Chirp oscillators.
- **Modulation:** Amplitude, Frequency (FM), and Ring modulation blocks.
- **Processing:** A suite of filters (LPF, HPF, BPF), a Mixer, and an Amplifier.
- **Analysis:** Real-time Spectrum Analyzer, Level Meter, and Frequency Counter blocks.
- **I/O:** Audio output device selection and a main output block.
- **Persistence:** Save and load complex configurations as documents.

## Build and Test Commands

- **Open in Xcode:** `open Sounder.xcodeproj`
- **Build from CLI:** `xcodebuild -project Sounder.xcodeproj -scheme Sounder -destination "platform=macOS" build`
- **Run Tests from CLI:** `xcodebuild test -project Sounder.xcodeproj -scheme Sounder -destination "platform=macOS"`
- **Lint Code:** `swiftlint lint --strict`

---

## TODO: Agent Implementation Tasks

This section contains a list of specific, actionable tasks to improve the codebase.

### 1. High Priority: Resolve Documentation Conflict

**Goal:** Create a single source of truth for project documentation and eliminate outdated, conflicting information.

**Instructions:**
1.  This `README.md` file now serves as the single source of truth.
2.  Execute the following shell command to delete all the old, conflicting `.md` files:
    ```bash
    rm AGENTS.md AI_BOOTSTRAP.md CLAUDE.md GEMINI.md PLAN.md QWEN.md
    ```

### 2. Medium Priority: Implement Missing UI Controls

**Goal:** Complete the UI for the `Mixer` and `Amplifier` blocks.

**Instructions:**
1.  **File to Modify:** `Sounder/Views/ParameterControlsView.swift`.
2.  **Locate Function:** Find the `blockSpecificControls(for block: SignalBlock)` function.
3.  **Identify Placeholder:** Inside the `switch block.type` statement, find these cases:
    ```swift
    case .mixer, .amplifier:
        Text("Processing controls not implemented")
    ```
4.  **Implement UI:**
    *   Replace the `Text(...)` placeholder with a new view builder function (e.g., `mixerControls(for: block)`).
    *   Inside the new function, create `ParameterControlRow` views for each parameter of the `Mixer` and `Amplifier` blocks (e.g., "gain", "volume", "pan").
    *   You can use the existing `filterControls(for:)` or `modulatorControls(for:)` as a template for your implementation.

### 3. Medium Priority: Refactor `nonisolated(unsafe)` for Improved Concurrency Safety

**Goal:** Remove the use of `nonisolated(unsafe)` in `AudioBlockService.swift` to eliminate the risk of data races and improve thread safety.

**Instructions:**
1.  **File to Modify:** `Sounder/Services/AudioBlockService.swift`.
2.  **Identify Properties:** Locate the block of properties marked with `nonisolated(unsafe)`. This includes `analysisFFTSetup`, `analysisWindow`, `latestSpectrumMagnitudes`, etc.
3.  **Refactoring Plan:**
    *   Create a new `actor` named `AnalysisState` to encapsulate all of these properties.
    *   Move the properties and the functions that exclusively operate on them (`updateAnalysis`, `refreshSpectrumIfNeeded`, `computeDominantFrequency`, `resetAnalysisStateLocked`) inside the `AnalysisState` actor.
    *   In `AudioBlockService`, replace the direct property declarations with a single instance of the new actor: `private let analysisState = AnalysisState()`.
    *   Update all call sites that previously accessed the unsafe properties to now `await` calls to the methods on the `analysisState` actor. For example, `scheduleAnalysisUpdate(...)` will now call `await analysisState.updateAnalysis(...)`.
    *   The `getSpectrumData` and `getLevelMeterData` functions will also need to be updated to `await` the results from the actor.

### 4. Low Priority: Make Audio Device Handling More Robust

**Goal:** Refactor the device handling logic in `AVFAudioService.swift` to use safer, more idiomatic Swift APIs.

**Instructions:**
1.  **File to Modify:** `Sounder/Services/AVFAudioService.swift`.
2.  **Task 1: Update `OutputDevice` Model:**
    *   Locate the `OutputDevice` model (likely in `Sounder/Models/OutputDevice.swift`).
    *   Change the `id` property from `String` to `AudioDeviceID` (which is a `UInt32`).
3.  **Task 2: Update `enumerateOutputDevices()`:**
    *   Modify the function to stop converting the `AudioDeviceID` to a `String`.
    *   Instead of using `kAudioDevicePropertyDeviceName` with an unsafe C-string buffer, use `kAudioDevicePropertyDeviceNameCFString` to fetch the name as a `CFString`, which can be safely cast to a Swift `String`.
4.  **Task 3: Update `applyEngineOutputDevice()`:**
    *   This function takes an `OutputDevice` as input. Modify it to use the `device.id` (which is now a `UInt32`) directly when setting the `kAudioOutputUnitProperty_CurrentDevice` property. This removes the need to parse a `String` back into a `UInt32`.

### 5. Low Priority: Remove Obsolete Fallback Code

**Goal:** Clean up dead code in the audio render callback.

**Instructions:**
1.  **File to Modify:** `Sounder/Services/AudioBlockService.swift`.
2.  **Locate Function:** Find the `connectOutputBlockToEngine(_:)` function.
3.  **Identify Code Block:** Inside the `AVAudioSourceNode` render closure, find the following conditional block:
    ```swift
    // If no proper graph output, fall back to direct sine generation for compatibility
    if outputSamples.allSatisfy({ $0 == 0.0 }) {
        // ... (15-20 lines of sine wave generation logic) ...
    }
    ```
4.  **Action:** Delete this entire `if` block. The audio graph scheduler is now the single source of truth, and this fallback is no longer necessary.


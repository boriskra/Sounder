# AI Bootstrap Guide for Sounder Project

## Project Overview

**Sounder** is a SwiftUI-based modular audio processing application that provides a visual block editor for creating audio signal processing chains. The system emphasizes **timeline coherence**, **real-time performance**, and **thread safety** for professional audio applications.

### Core Philosophy
- **Timeline Coherence**: All audio processing must maintain absolute sample position tracking
- **Real-time Safety**: Audio thread operations must be lock-free and deterministic
- **Modular Design**: Signal processing blocks are composable and reusable
- **Thread Safety**: Atomic operations and careful concurrency management throughout

## Project Structure

```
Sounder/
├── Sounder/                          # Main application target
│   ├── Models/                       # Data models and core types
│   │   ├── BlockEditor/              # Block editor domain models
│   │   │   ├── BlockType.swift       # Enum defining all audio block types (20 types)
│   │   │   ├── BlockCategory.swift   # UI organization categories
│   │   │   ├── BlockConnection.swift # Audio routing connections
│   │   │   └── ...
│   │   ├── OutputDevice.swift        # Audio device abstraction
│   │   ├── Parameter.swift           # Audio parameter types
│   │   └── Sound.swift               # Audio file abstractions
│   ├── Views/                        # SwiftUI user interface
│   │   ├── BlockEditor/              # Visual block editor components
│   │   │   ├── BlockEditorView.swift # Main editor interface
│   │   │   ├── BlockEditorView+*.swift # Editor extensions
│   │   │   └── ...
│   │   ├── BlockView.swift           # Individual block visualization
│   │   ├── ConnectionView.swift      # Visual connections
│   │   └── ...
│   ├── ViewModels/                   # MVVM pattern view models
│   │   ├── BlockCanvasViewModel.swift # Block editor logic
│   │   └── ContentViewModel.swift    # Main app logic
│   ├── Services/                     # Business logic and audio processing
│   │   ├── AudioBlockService.swift   # Main service containing ALL AudioBlock implementations
│   │   ├── AudioBlocks/              # Individual AudioBlock files (some implementations)
│   │   │   ├── DSP/                  # Shared DSP utilities
│   │   │   │   ├── OscillatorPhaseAccumulator.swift # Timeline-coherent phase calculation
│   │   │   │   ├── GainAndSmoothing.swift # Parameter smoothing utilities
│   │   │   │   ├── NoiseGeneratorBase.swift # High-quality noise generation
│   │   │   │   ├── ChirpEnvelopeEngine.swift # Frequency sweep generation
│   │   │   │   ├── BiquadFilterCore.swift # Digital filter implementations
│   │   │   │   └── SignalAnalysisKit.swift # Analysis utilities
│   │   │   ├── SineOscillatorBlock.swift # Standalone implementation
│   │   │   ├── SpectrumAnalyzerBlock.swift # Analysis block
│   │   │   └── ... (other standalone implementations)
│   │   ├── BlockManagerService.swift # Block lifecycle management
│   │   ├── AVFAudioService.swift     # Real audio service implementation
│   │   ├── MockAudioService.swift    # Mock for testing (not production!)
│   │   ├── AudioGraphScheduler.swift # Audio graph execution
│   │   └── ...
│   ├── ContentView.swift             # Root SwiftUI view
│   └── Info.plist                    # App configuration
├── SounderTests/                     # Unit and integration tests
│   ├── AudioServiceTests.swift      # Audio processing tests
│   ├── ModelTests.swift              # Data model tests
│   └── ...
├── SounderUITests/                   # UI automation tests
├── specs/                            # Project specifications
└── build/                            # Build artifacts (gitignored)
```

## Architecture Patterns

### 1. Timeline-Coherent Audio Processing

**Critical Pattern**: All audio processing must maintain absolute sample position tracking.

```swift
// CORRECT - Timeline coherent processing
func processAudio(
    inputs: [String: [Float]],
    frameCount: Int,
    startSample: UInt64,        // Absolute timeline position
    sampleRate: Double          // For timeline calculations
) -> [String: [Float]] {
    for frame in 0..<frameCount {
        let sampleIndex = startSample + UInt64(frame)
        let time = Double(sampleIndex) / sampleRate
        let phase = 2.0 * Double.pi * frequency * time  // Phase from absolute time
        // ...
    }
}

// WRONG - Accumulating phase (causes drift)
var phase: Double = 0.0
func processAudio(...) {
    for frame in 0..<frameCount {
        phase += phaseIncrement  // Accumulates numerical errors
        // ...
    }
}
```

### 2. Thread-Safe Atomic Operations

**Pattern**: Use OSAtomic operations for metrics and lock-free data sharing.

```swift
// Performance metrics with atomic operations
private var samplesProcessedRaw: Int64 = 0
private var parameterValueBits: Int64 = Int64(bitPattern: Double(0.0).bitPattern)

// Atomic updates
OSAtomicAdd64Barrier(Int64(frameCount), &samplesProcessedRaw)
withUnsafeMutablePointer(to: &parameterValueBits) {
    atomicStoreDouble(newValue, $0)
}

// Atomic reads
let samples = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &samplesProcessedRaw))
let value = withUnsafeMutablePointer(to: &parameterValueBits, atomicLoadDouble)
```

### 3. Shared DSP Utilities

**Pattern**: Use shared utilities for consistent behavior across blocks.

```swift
// Use shared utilities instead of reimplementing
class MyOscillatorBlock: AudioBlock {
    private let phaseAccumulator = OscillatorPhaseAccumulator()
    private let gainProcessor = GainAndSmoothing()

    func processAudio(...) {
        let phase = phaseAccumulator.calculatePhase(
            frequency: frequency,
            startSample: startSample,
            sampleRate: sampleRate
        )
        let samples = generateWaveform(phase: phase)
        return gainProcessor.applyGain(samples: samples, gainDB: amplitudeDB)
    }
}
```

### 4. MVVM with Services

- **Views**: Pure SwiftUI, no business logic
- **ViewModels**: `@MainActor` classes handling UI state and user interactions
- **Services**: Business logic, audio processing, data persistence
- **Models**: Value types for data representation

## Coding Standards

### Swift Style
- Use meaningful variable names: `currentFrequency` not `freq`
- Prefer `let` over `var` when possible
- Use explicit types for clarity in audio processing: `Double` for calculations, `Float` for audio samples
- Group related functionality with `// MARK: -` comments

### Documentation
- Document all public APIs with standard Swift documentation
- Include parameter descriptions for audio processing functions
- Document thread safety requirements
- Explain mathematical algorithms and their precision requirements

### Error Handling
```swift
// Use typed errors for specific domains
enum AudioBlockError: LocalizedError {
    case blockRegistrationError(String)
    case audioEngineError(String)
    case parameterValidationError(String, Double)
}

// Validate parameters with clear error messages
guard frequency > 0 && frequency < sampleRate / 2 else {
    throw AudioBlockError.parameterValidationError("frequency", frequency)
}
```

### Performance Patterns
```swift
// Pre-allocate buffers
var output: [Float] = []
output.reserveCapacity(frameCount)

// Use @inline(__always) for hot paths
@inline(__always)
private func sanitizeInput(_ input: Double) -> Double {
    guard input.isFinite else { return 0.0 }
    return max(-1.0, min(1.0, input))
}

// Minimize allocations in audio threads
// Use inout parameters for buffer processing
func applyGain(to buffer: inout [Float], gain: Double) {
    for i in 0..<buffer.count {
        buffer[i] *= Float(gain)
    }
}
```

## Audio Processing Specifics

### Block Implementation Checklist
When creating new audio blocks:

1. **Inherit from AudioBlock protocol**
2. **Implement timeline-coherent processAudio()**
3. **Support parameter updates via setParameter()**
4. **Implement reset() for timeline jumps**
5. **Add to AudioBlockService.createAudioBlock() switch**
6. **Update BlockType enum if needed**
7. **Create unit tests**

### Required Methods
```swift
public protocol AudioBlock {
    var id: UUID { get }
    var type: BlockType { get }
    var inputPorts: [String] { get }
    var outputPorts: [String] { get }

    // Timeline-coherent processing (PRIMARY)
    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]]

    // Legacy compatibility
    func processAudio(inputs: [String: [Float]], frameCount: Int) -> [String: [Float]]

    // Real-time parameter updates
    func setParameter(name: String, value: Double)

    // Timeline synchronization
    func reset(to startSample: UInt64, sampleRate: Double)
    func reset() // Legacy
}
```

### DSP Utility Usage
Always prefer shared DSP utilities over custom implementations:

- **OscillatorPhaseAccumulator**: For all oscillator phase calculations
- **GainAndSmoothing**: For parameter ramping and gain processing
- **NoiseGeneratorBase**: For noise generation
- **ChirpEnvelopeEngine**: For frequency sweeps and envelopes
- **BiquadFilterCore**: For filtering operations
- **SignalAnalysisKit**: For analysis functions

## Testing Standards

### Unit Tests
- Test each audio block in isolation
- Verify timeline coherence with sample-accurate positioning
- Test parameter ranges and edge cases
- Test reset behavior and state management

### Integration Tests
- Test complete audio processing chains
- Verify inter-block communication
- Test device switching and audio engine lifecycle

### Test Naming
```swift
func testSineOscillator_WithTimelineReset_MaintainsPhaseCoherence()
func testParameterUpdate_WithInvalidRange_ThrowsValidationError()
func testAudioProcessing_WithDisconnectedInputs_ReturnsExpectedOutput()
```

## Common Patterns

### Adding New Block Types

**IMPORTANT**: AudioBlock implementations can be in two locations:
- **Embedded in AudioBlockService.swift** (most implementations as private classes)
- **Standalone files** in `Services/AudioBlocks/` (some complex blocks)

Steps to add new block types:
1. **Add to BlockType enum** in `Models/BlockEditor/BlockType.swift`
2. **Create block implementation** either:
   - As private class in `AudioBlockService.swift` (preferred for most blocks)
   - As standalone file in `Services/AudioBlocks/` (for complex analysis blocks)
3. **Add to createAudioBlock() switch** in `AudioBlockService.swift`
4. **Update UI components** if needed (icons, descriptions)
5. **Write comprehensive tests**

### Parameter Handling
```swift
// Standard parameter update pattern
func setParameter(name: String, value: Double) {
    switch name {
    case "frequency":
        // Validate range
        let clampedFreq = max(20.0, min(20000.0, value))
        frequency = clampedFreq
    case "amplitude":
        // Convert dB to linear
        let clampedDb = max(-60.0, min(0.0, value))
        amplitude = pow(10.0, clampedDb / 20.0)
    default:
        break
    }
}
```

### Timeline Reset Handling
```swift
func reset(to startSample: UInt64, sampleRate: Double) {
    // Reset only mutable state, not configuration
    currentEnvelopeLevel = 0.0
    filterState.reset()

    // Don't reset: frequency, amplitude, user parameters
    print("🎵 [DEBUG] \(type).reset(to:) - Reset to sample \(startSample)")
}
```

## Things to Avoid

### ❌ Never Do
- **Phase accumulation without drift compensation**
- **Blocking operations in audio processing**
- **Memory allocation in processAudio()**
- **Direct UI updates from audio threads**
- **Ignoring timeline parameters in audio processing**
- **Using float for mathematical calculations (use Double)**

### ❌ Anti-Patterns
```swift
// WRONG - Blocking in audio thread
func processAudio(...) {
    DispatchQueue.main.sync { /* UI update */ }  // NEVER!
}

// WRONG - Memory allocation in hot path
func processAudio(...) {
    let newArray = Array(repeating: 0.0, count: frameCount)  // AVOID!
}

// WRONG - Ignoring timeline
func processAudio(...) {
    // Ignoring startSample parameter
    for frame in 0..<frameCount {
        phase += phaseIncrement  // Causes drift!
    }
}
```

## Debugging and Diagnostics

### Debug Logging Pattern
```swift
// Use structured debug logging with emojis for categories
print("🎵 [DEBUG] BlockName.method() - Description")
print("🔧 [ERROR] ServiceName.method() - Error: \(error)")
print("📊 [METRICS] Component - Value: \(value)")
```

### Performance Monitoring
All DSP utilities include atomic performance metrics:
```swift
public func metrics() -> ComponentMetrics {
    let samplesProcessed = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &samplesProcessedRaw))
    let parameterUpdates = UInt64(bitPattern: OSAtomicAdd64Barrier(0, &parameterUpdatesRaw))

    return ComponentMetrics(
        samplesProcessed: samplesProcessed,
        parameterUpdates: parameterUpdates,
        // ... other metrics
    )
}
```

## Build System Notes

### Xcode Project Structure
- Main target: `Sounder`
- Test targets: `SounderTests`, `SounderUITests`
- Deployment target: iOS 15.0+
- Swift version: 5.x

### Dependencies
- **AVFoundation**: Core audio processing
- **Accelerate**: DSP optimizations (vDSP)
- **SwiftUI**: User interface
- **Combine**: Reactive programming
- **GameplayKit**: Random number generation

### Build Configurations
- Debug: Full logging, assertions enabled
- Release: Optimized, minimal logging

## Extension Guidelines

### Adding New DSP Utilities
Follow the established pattern:
1. **Timeline coherence** with startSample/sampleRate parameters
2. **Atomic metrics** for performance monitoring
3. **Thread-safe state management** with spinlocks
4. **Comprehensive documentation** with usage examples
5. **Factory methods** for common configurations

### UI Extensions
- Follow SwiftUI best practices
- Use MVVM pattern with `@MainActor` view models
- Implement proper error handling and loading states
- Maintain accessibility support

## Current Implementation Status (December 2024)

### AudioBlock Implementation Progress: 85% Complete (17/20)

**✅ IMPLEMENTED (17 blocks) - All in AudioBlockService.swift as private classes:**
- SineOscillatorAudioBlock, SawtoothOscillatorAudioBlock, SquareOscillatorAudioBlock
- LinearChirpAudioBlock, HyperbolicChirpAudioBlock
- PinkNoiseAudioBlock, WhiteNoiseAudioBlock, TriangleOscillatorAudioBlock
- LowPassFilterAudioBlock, HighPassFilterAudioBlock, BandPassFilterAudioBlock
- MixerAudioBlock, AmplifierAudioBlock
- AudioOutputAudioBlock, FrequencyModulatorAudioBlock, RingModulatorAudioBlock, AmplitudeModulatorAudioBlock

**❌ MISSING (3 analysis blocks):**
- SpectrumAnalyzerAudioBlock *(complex FFT analysis)*
- LevelMeterAudioBlock *(RMS/peak level measurement)*
- FrequencyCounterAudioBlock *(frequency detection algorithms)*

### Known Critical Issues

**🚨 PRIORITY 1 - BLOCKERS:**
1. **Mock services used in production views** - Views use `MockAudioBlockService()` instead of real audio processing
   - Files: BlockView.swift, BlockCanvasView.swift, AudioDeviceView.swift, BlockLibraryView.swift, ParameterControlsView.swift
   - **Impact**: Users get fake functionality instead of real audio processing

**🔧 PRIORITY 2 - MISSING FUNCTIONALITY:**
2. **Missing switch cases** for 3 analysis blocks in `AudioBlockService.createAudioBlock()`
3. **Stub implementations**:
   - XML import in ConfigurationPersistenceService.swift
   - Template creation in BlockLibraryView.swift
   - Parameter frequency extraction in AVFAudioService.swift

### Service Architecture Notes

**Real vs Mock Services:**
- **Production**: Use `AVFAudioService()` for real audio processing
- **Testing**: Use `MockAudioService()` for unit tests only
- **Views**: Should inject real services, not instantiate mocks directly

**CRITICAL**: Many SwiftUI views directly instantiate mock services in their body or previews, which causes production users to get non-functional audio processing.

## Critical Success Factors

1. **Always maintain timeline coherence** in audio processing
2. **Use shared DSP utilities** instead of reimplementing
3. **Follow atomic operation patterns** for thread safety
4. **Test thoroughly** with various parameter ranges
5. **Document performance characteristics** and limitations
6. **Validate all parameters** with appropriate error handling
7. **Maintain backward compatibility** when possible
8. **🚨 NEVER use mock services in production views** - Always inject real services
9. **⚠️ Check AudioBlockService.swift first** - Most blocks are implemented as private classes, not separate files

This guide should enable any AI agent to understand the project structure, follow established patterns, and make appropriate technical decisions when extending or modifying the Sounder codebase.
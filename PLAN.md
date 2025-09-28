# Sounder Implementation Plan

This document provides a detailed, step-by-step plan for bringing the Sounder project to complete functionality. The plan is designed for AI coding agents and prioritizes implementing missing audio blocks while fixing critical infrastructure issues.

## Plan Overview

**Total Estimated Tasks: 89**
- Phase 1 (Critical Infrastructure): 23 tasks
- Phase 2 (Missing Audio Blocks): 38 tasks
- Phase 3 (Integration & Testing): 16 tasks
- Phase 4 (Features & Polish): 12 tasks

## Phase 1: Critical Infrastructure (Priority: CRITICAL)

### 1.1 Fix Test Infrastructure (Tasks 1-6)

#### Task 1: Fix Test Compilation Errors
**File:** `/SounderTests/ModelTests.swift:19`
**Issue:** Missing arguments for `OutputDevice` constructor
**Action:**
```swift
// Replace line 19:
let device = OutputDevice(id: "test", name: "Test Device")
// With:
let device = OutputDevice(id: 1, name: "Test Device", isDefault: false, isAvailable: true)
```

#### Task 2: Fix AudioBlockServiceTests Setup
**File:** `/SounderTests/Services/AudioBlockServiceTests.swift:12-15`
**Action:**
```swift
// Replace commented lines 12-15:
override func setUp() {
    super.setUp()
    // This will fail until implementation exists
    // audioBlockService = AudioBlockServiceImpl()
}

// With:
override func setUp() {
    super.setUp()
    let avfService = AVFAudioService()
    audioBlockService = AudioBlockServiceImpl(avfAudioService: avfService)
}
```

#### Task 3: Enable AudioBlockService Tests
**File:** `/SounderTests/Services/AudioBlockServiceTests.swift`
**Action:** Remove all `XCTFail("AudioBlockService implementation not available")` lines and enable actual test logic

#### Task 4: Fix AudioServiceError Test References
**File:** `/SounderTests/Services/AudioBlockServiceTests.swift:337-341`
**Action:**
```swift
// Replace:
let invalidDevice = OutputDevice(
    id: "invalid-device-id",
    name: "Non-existent Device",
    isDefault: false,
    isAvailable: false
)

// With:
let invalidDevice = OutputDevice(
    id: 999999,
    name: "Non-existent Device",
    isDefault: false,
    isAvailable: false
)
```

#### Task 5: Add Missing AudioBlockError Enum
**File:** Create `/Sounder/Models/AudioBlockError.swift`
**Content:**
```swift
import Foundation

public enum AudioBlockError: Error, LocalizedError {
    case audioEngineError(String)
    case blockRegistrationError(String)
    case blockNotFoundError(UUID)
    case invalidParameterError(String)
    case connectionError(String)
    case audioDeviceError(String)

    public var errorDescription: String? {
        switch self {
        case .audioEngineError(let message): return "Audio Engine Error: \(message)"
        case .blockRegistrationError(let message): return "Block Registration Error: \(message)"
        case .blockNotFoundError(let id): return "Block not found: \(id)"
        case .invalidParameterError(let message): return "Invalid Parameter: \(message)"
        case .connectionError(let message): return "Connection Error: \(message)"
        case .audioDeviceError(let message): return "Audio Device Error: \(message)"
        }
    }
}
```

#### Task 6: Update Test Target Dependencies
**File:** `Sounder.xcodeproj`
**Action:** Ensure test targets can access AudioBlockError and all required models

### 1.2 Remove Production Mocks (Tasks 7-9)

#### Task 7: Move MockAudioBlockService to Tests
**Action:**
1. Move `/Sounder/Services/MockAudioBlockService.swift` to `/SounderTests/Services/`
2. Update target membership in Xcode project
3. Add `@testable import Sounder` to mock file

#### Task 8: Move MockAudioService to Tests
**Action:**
1. Move `/Sounder/Services/MockAudioService.swift` to `/SounderTests/Services/`
2. Update target membership in Xcode project
3. Update any preview code using mocks

#### Task 9: Update SounderApp Mock Usage
**File:** `/Sounder/SounderApp.swift:8-12`
**Action:**
```swift
// Replace:
if ProcessInfo.processInfo.arguments.contains("-ui_testing") {
    self.audioService = MockAudioService()
} else {
    self.audioService = AVFAudioService()
}

// With:
self.audioService = AVFAudioService()
// UI testing will use dependency injection instead
```

### 1.3 Fix Thread Safety Issues (Tasks 10-15)

#### Task 10: Create AnalysisState Actor
**File:** Create `/Sounder/Services/AnalysisState.swift`
**Content:**
```swift
import Foundation
import Accelerate

@MainActor
class AnalysisState {
    private let analysisFFTSize: Int = 2048
    private let analysisSmoothing: Float = 0.85
    private let minimumLevel: Float = 1.0e-5
    private let analysisLog2n: vDSP_Length

    private var analysisFFTSetup: FFTSetup?
    private var analysisWindow: [Float]
    private var analysisRingBuffer: [Float]
    private var analysisRingIndex: Int = 0
    private var analysisRingCount: Int = 0
    private var analysisWorkingBuffer: [Float]
    private var analysisReal: [Float]
    private var analysisImag: [Float]
    private var latestSpectrumMagnitudes: [Float]
    private var latestPeakLinear: Float = 0.0
    private var latestRMSLinear: Float = 0.0
    private var latestFrequencyEstimate: Double?
    private var analysisSampleRate: Double = 48_000.0

    init() {
        analysisLog2n = vDSP_Length(log2(Float(analysisFFTSize)))
        analysisWindow = Array(repeating: 0.0, count: analysisFFTSize)
        vDSP_hann_window(&analysisWindow, vDSP_Length(analysisFFTSize), Int32(vDSP_HANN_NORM))
        analysisRingBuffer = Array(repeating: 0.0, count: analysisFFTSize)
        analysisWorkingBuffer = Array(repeating: 0.0, count: analysisFFTSize)
        analysisReal = Array(repeating: 0.0, count: analysisFFTSize / 2)
        analysisImag = Array(repeating: 0.0, count: analysisFFTSize / 2)
        latestSpectrumMagnitudes = Array(repeating: 0.0, count: analysisFFTSize / 2)
        analysisFFTSetup = vDSP_create_fftsetup(analysisLog2n, FFTRadix(kFFTRadix2))
    }

    // Implement all analysis methods here...
}
```

#### Task 11: Remove nonisolated(unsafe) from AudioBlockService
**File:** `/Sounder/Services/AudioBlockService.swift:102-114`
**Action:** Remove all `nonisolated(unsafe)` property declarations and replace with AnalysisState actor usage

#### Task 12: Update Analysis Method Signatures
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Add `async` keyword to all analysis methods and update call sites with `await`

#### Task 13: Fix Analysis Method Implementations
**File:** `/Sounder/Services/AudioBlockService.swift:654-773`
**Action:** Move all analysis methods to AnalysisState actor and update AudioBlockService to delegate to actor

#### Task 14: Update getSpectrumData Method
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:**
```swift
func getSpectrumData(for blockId: UUID?) async -> [Float] {
    return await analysisState.getLatestSpectrumMagnitudes()
}
```

#### Task 15: Update getLevelMeterData Method
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:**
```swift
func getLevelMeterData(for blockId: UUID?) async -> (peak: Float, rms: Float) {
    return await analysisState.getLatestLevels()
}
```

### 1.4 Error Handling Infrastructure (Tasks 16-23)

#### Task 16: Implement AudioBlockService Error Handling
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Add proper error throwing throughout service methods

#### Task 17: Add Validation to registerBlock
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Validate block type is supported before registration

#### Task 18: Add Validation to connectBlocks
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Validate ports exist and are compatible

#### Task 19: Add Device Validation to setOutputDevice
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Validate device exists and is available

#### Task 20: Add Parameter Validation to updateBlockParameter
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Validate parameter exists and value is in range

#### Task 21: Add Block Existence Check to unregisterBlock
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Check if block exists before attempting to unregister

#### Task 22: Add Connection Validation to disconnectBlocks
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Validate connection exists before disconnection

#### Task 23: Add Error Recovery in Audio Callback
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Add try-catch blocks around audio processing with fallback behavior

## Phase 2: Missing Audio Blocks (Priority: HIGH)

### 2.1 Oscillator Blocks (Tasks 24-27)

#### Task 24: Implement SquareOscillatorBlock
**File:** Create `/Sounder/Services/AudioBlocks/SquareOscillatorBlock.swift`
**Requirements:**
- Use `OscillatorPhaseAccumulator` base class
- Implement duty cycle parameter (0.1-0.9, default 0.5)
- Anti-aliasing using band-limited synthesis
- Thread-safe parameter updates
**Reference:** `SineOscillatorBlock.swift` for structure
**Parameters:** frequency, amplitude, dutyCycle

#### Task 25: Implement SawtoothOscillatorBlock
**File:** Create `/Sounder/Services/AudioBlocks/SawtoothOscillatorBlock.swift`
**Requirements:**
- Use `OscillatorPhaseAccumulator` base class
- Band-limited sawtooth using Polyblep algorithm
- Thread-safe parameter updates
**Reference:** `TriangleOscillatorBlock.swift` for anti-aliasing approach
**Parameters:** frequency, amplitude

#### Task 26: Implement PinkNoiseBlock
**File:** Create `/Sounder/Services/AudioBlocks/PinkNoiseBlock.swift`
**Requirements:**
- Use `NoiseGeneratorBase` for seeding
- Implement Paul Kellet's pink noise filter algorithm
- Thread-safe parameter updates
**Reference:** `WhiteNoiseBlock.swift` for noise generation structure
**Parameters:** amplitude, seed

#### Task 27: Update BlockType Registration
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Add cases for new oscillator types in block creation factory method

### 2.2 Chirp Blocks (Tasks 28-31)

#### Task 28: Implement LinearChirpBlock
**File:** Create `/Sounder/Services/AudioBlocks/LinearChirpBlock.swift`
**Requirements:**
- Use `ChirpEnvelopeEngine` for sweep calculations
- Linear frequency sweep from start to end frequency
- Configurable duration and amplitude envelope
**Reference:** `ChirpEnvelopeEngine.swift` for implementation guidance
**Parameters:** startFrequency, endFrequency, duration, amplitude

#### Task 29: Implement HyperbolicChirpBlock
**File:** Create `/Sounder/Services/AudioBlocks/HyperbolicChirpBlock.swift`
**Requirements:**
- Use `ChirpEnvelopeEngine` for sweep calculations
- Hyperbolic frequency sweep for constant bandwidth per octave
- Optimized for acoustic analysis applications
**Reference:** `ChirpEnvelopeEngine.swift` for mathematical basis
**Parameters:** startFrequency, endFrequency, bandwidth, amplitude

#### Task 30: Enhance ChirpEnvelopeEngine
**File:** `/Sounder/Services/AudioBlocks/DSP/ChirpEnvelopeEngine.swift`
**Action:** Add hyperbolic chirp calculation method if not present

#### Task 31: Update BlockType Registration for Chirps
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Add cases for chirp types in block creation factory method

### 2.3 Modulation Blocks (Tasks 32-36)

#### Task 32: Implement AmplitudeModulatorBlock
**File:** Create `/Sounder/Services/AudioBlocks/AmplitudeModulatorBlock.swift`
**Requirements:**
- Two audio inputs: carrier and modulation
- Depth parameter (0-100%)
- AM formula: output = carrier * (1 + depth * modulation)
**Reference:** `FrequencyModulatorBlock.swift` for modulation structure
**Parameters:** depth
**Ports:** carrier (input), modulation (input), output (output)

#### Task 33: Implement RingModulatorBlock
**File:** Create `/Sounder/Services/AudioBlocks/RingModulatorBlock.swift`
**Requirements:**
- Two audio inputs: signal1 and signal2
- Simple multiplication: output = signal1 * signal2
- No parameters needed
**Reference:** `FrequencyModulatorBlock.swift` for dual input handling
**Parameters:** none
**Ports:** signal1 (input), signal2 (input), output (output)

#### Task 34: Add Modulation Input Validation
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Validate modulation blocks have required inputs before processing

#### Task 35: Update BlockType Registration for Modulation
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Add cases for modulation types in block creation factory method

#### Task 36: Test Modulation Block Integration
**File:** Create `/SounderTests/Services/ModulationBlockTests.swift`
**Content:** Unit tests for all modulation blocks

### 2.4 Filter Blocks (Tasks 37-43)

#### Task 37: Implement LowPassFilterBlock
**File:** Create `/Sounder/Services/AudioBlocks/LowPassFilterBlock.swift`
**Requirements:**
- Use `BiquadFilterCore` for filter implementation
- Cutoff frequency and resonance parameters
- Real-time parameter updates with smoothing
**Reference:** `BiquadFilterCore.swift` for filter mathematics
**Parameters:** cutoffFrequency, resonance

#### Task 38: Implement HighPassFilterBlock
**File:** Create `/Sounder/Services/AudioBlocks/HighPassFilterBlock.swift`
**Requirements:**
- Use `BiquadFilterCore` for filter implementation
- Cutoff frequency and resonance parameters
- Real-time parameter updates with smoothing
**Reference:** `BiquadFilterCore.swift` for filter mathematics
**Parameters:** cutoffFrequency, resonance

#### Task 39: Implement BandPassFilterBlock
**File:** Create `/Sounder/Services/AudioBlocks/BandPassFilterBlock.swift`
**Requirements:**
- Use `BiquadFilterCore` for filter implementation
- Center frequency and Q factor parameters
- Real-time parameter updates with smoothing
**Reference:** `BiquadFilterCore.swift` for filter mathematics
**Parameters:** centerFrequency, qFactor

#### Task 40: Enhance BiquadFilterCore
**File:** `/Sounder/Services/AudioBlocks/DSP/BiquadFilterCore.swift`
**Action:** Ensure all filter types (LPF, HPF, BPF) are supported

#### Task 41: Add Filter Stability Checks
**File:** `/Sounder/Services/AudioBlocks/DSP/BiquadFilterCore.swift`
**Action:** Add coefficient validation to prevent filter instability

#### Task 42: Update BlockType Registration for Filters
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Add cases for filter types in block creation factory method

#### Task 43: Test Filter Block Integration
**File:** Create `/SounderTests/Services/FilterBlockTests.swift`
**Content:** Unit tests for all filter blocks

### 2.5 Processing Blocks (Tasks 44-48)

#### Task 44: Implement MixerBlock
**File:** Create `/Sounder/Services/AudioBlocks/MixerBlock.swift`
**Requirements:**
- Variable number of inputs (up to 8)
- Individual level controls for each input
- Master output level control
- Use `GainAndSmoothing` for parameter changes
**Reference:** `GainAndSmoothing.swift` for level control
**Parameters:** input1Level, input2Level, input3Level, input4Level, masterLevel

#### Task 45: Implement AmplifierBlock
**File:** Create `/Sounder/Services/AudioBlocks/AmplifierBlock.swift`
**Requirements:**
- Single audio input and output
- Gain parameter in dB (-60 to +20 dB)
- Use `GainAndSmoothing` for smooth gain changes
**Reference:** `GainAndSmoothing.swift` for gain implementation
**Parameters:** gain

#### Task 46: Enhance GainAndSmoothing
**File:** `/Sounder/Services/AudioBlocks/DSP/GainAndSmoothing.swift`
**Action:** Ensure proper dB to linear conversion and smoothing algorithms

#### Task 47: Update BlockType Registration for Processing
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Add cases for processing types in block creation factory method

#### Task 48: Test Processing Block Integration
**File:** Create `/SounderTests/Services/ProcessingBlockTests.swift`
**Content:** Unit tests for mixer and amplifier blocks

### 2.6 Analysis Blocks (Tasks 49-53)

#### Task 49: Implement LevelMeterBlock
**File:** Create `/Sounder/Services/AudioBlocks/LevelMeterBlock.swift`
**Requirements:**
- Audio input for signal analysis
- Peak and RMS level calculation
- Time constant parameter for smoothing
- Use `SignalAnalysisKit` for level calculations
**Reference:** `SignalAnalysisKit.swift` for analysis algorithms
**Parameters:** timeConstant

#### Task 50: Implement FrequencyCounterBlock
**File:** Create `/Sounder/Services/AudioBlocks/FrequencyCounterBlock.swift`
**Requirements:**
- Audio input for frequency analysis
- Dominant frequency detection using autocorrelation
- Sample window parameter for analysis length
- Use `SignalAnalysisKit` for frequency detection
**Reference:** `SignalAnalysisKit.swift` for frequency analysis
**Parameters:** sampleWindow

#### Task 51: Enhance SignalAnalysisKit
**File:** `/Sounder/Services/AudioBlocks/DSP/SignalAnalysisKit.swift`
**Action:** Ensure autocorrelation and frequency detection algorithms are complete

#### Task 52: Update BlockType Registration for Analysis
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Add cases for analysis types in block creation factory method

#### Task 53: Test Analysis Block Integration
**File:** Create `/SounderTests/Services/AnalysisBlockTests.swift`
**Content:** Unit tests for level meter and frequency counter blocks

### 2.7 Block Factory Integration (Tasks 54-61)

#### Task 54: Create AudioBlockFactory
**File:** Create `/Sounder/Services/AudioBlockFactory.swift`
**Content:**
```swift
import Foundation

class AudioBlockFactory {
    static func createBlock(type: BlockType, id: UUID) -> AudioBlock? {
        switch type {
        case .sineOscillator:
            return SineOscillatorBlock(id: id)
        case .squareOscillator:
            return SquareOscillatorBlock(id: id)
        case .triangleOscillator:
            return TriangleOscillatorBlock(id: id)
        case .sawtoothOscillator:
            return SawtoothOscillatorBlock(id: id)
        case .whiteNoise:
            return WhiteNoiseBlock(id: id)
        case .pinkNoise:
            return PinkNoiseBlock(id: id)
        // Add all other block types...
        default:
            return nil
        }
    }
}
```

#### Task 55: Update AudioBlockService to Use Factory
**File:** `/Sounder/Services/AudioBlockService.swift`
**Action:** Replace block creation logic with AudioBlockFactory calls

#### Task 56: Add Block Validation to Factory
**File:** `/Sounder/Services/AudioBlockFactory.swift`
**Action:** Add validation that created blocks match expected interfaces

#### Task 57: Test All Block Types Creation
**File:** Create `/SounderTests/Services/AudioBlockFactoryTests.swift`
**Content:** Test that all 18 block types can be created successfully

#### Task 58: Add Block Parameter Initialization
**File:** `/Sounder/Services/AudioBlockFactory.swift`
**Action:** Ensure all blocks are initialized with default parameters

#### Task 59: Add Block Port Validation
**File:** `/Sounder/Services/AudioBlockFactory.swift`
**Action:** Validate that created blocks have expected input/output ports

#### Task 60: Update BlockManagerService Integration
**File:** `/Sounder/Services/BlockManagerService.swift`
**Action:** Use AudioBlockFactory for block creation

#### Task 61: Test End-to-End Block Creation
**File:** Create `/SounderTests/Integration/BlockCreationTests.swift`
**Content:** Test complete flow from UI to audio block creation

## Phase 3: Integration & Testing (Priority: MEDIUM)

### 3.1 Audio Graph Validation (Tasks 62-67)

#### Task 62: Implement Connection Validation
**File:** `/Sounder/Services/AudioGraphValidator.swift`
**Content:** Validate audio graph for cycles, port compatibility, and signal flow

#### Task 63: Add Port Type Checking
**File:** `/Sounder/Services/AudioGraphValidator.swift`
**Action:** Ensure audio ports only connect to audio ports, control to control, etc.

#### Task 64: Implement Cycle Detection
**File:** `/Sounder/Services/AudioGraphValidator.swift`
**Action:** Detect and prevent feedback loops in audio graph

#### Task 65: Add Graph Optimization
**File:** `/Sounder/Services/AudioGraphScheduler.swift`
**Action:** Optimize processing order for minimal latency

#### Task 66: Test Graph Validation
**File:** Create `/SounderTests/Services/AudioGraphValidatorTests.swift`
**Content:** Test all validation scenarios

#### Task 67: Integration Test Audio Pipeline
**File:** Create `/SounderTests/Integration/AudioPipelineTests.swift`
**Content:** Test complete audio processing pipeline

### 3.2 Performance Testing (Tasks 68-71)

#### Task 68: Add Real-time Performance Tests
**File:** Create `/SounderTests/Performance/AudioPerformanceTests.swift`
**Content:** Test audio processing meets real-time constraints

#### Task 69: Add Memory Allocation Tests
**File:** Create `/SounderTests/Performance/MemoryAllocationTests.swift`
**Content:** Ensure no memory allocation in audio callback

#### Task 70: Add CPU Usage Monitoring
**File:** `/Sounder/Services/PerformanceMonitor.swift`
**Content:** Real CPU usage monitoring for audio thread

#### Task 71: Test Performance Under Load
**File:** Create `/SounderTests/Performance/LoadTests.swift`
**Content:** Test with complex audio graphs

### 3.3 UI Integration Tests (Tasks 72-77)

#### Task 72: Test Block Creation UI
**File:** Create `/SounderUITests/BlockCreationTests.swift`
**Content:** Test all block types can be created from UI

#### Task 73: Test Parameter Control UI
**File:** Create `/SounderUITests/ParameterControlTests.swift`
**Content:** Test parameter changes affect audio processing

#### Task 74: Test Connection UI
**File:** Create `/SounderUITests/ConnectionTests.swift`
**Content:** Test block connections can be made and broken

#### Task 75: Test Device Selection UI
**File:** Create `/SounderUITests/DeviceSelectionTests.swift`
**Content:** Test audio device selection affects output

#### Task 76: Test Audio Visualization
**File:** Create `/SounderUITests/VisualizationTests.swift`
**Content:** Test spectrum analyzer and level meters display correctly

#### Task 77: Test Complete Workflows
**File:** Create `/SounderUITests/WorkflowTests.swift`
**Content:** Test complete user workflows from start to finish

## Phase 4: Features & Polish (Priority: LOW)

### 4.1 Parameter Control UI (Tasks 78-81)

#### Task 78: Implement Mixer Parameter Controls
**File:** `/Sounder/Views/ParameterControlsView.swift:80-82`
**Action:** Replace placeholder text with actual mixer controls

#### Task 79: Implement Amplifier Parameter Controls
**File:** `/Sounder/Views/ParameterControlsView.swift:80-82`
**Action:** Replace placeholder text with actual amplifier controls

#### Task 80: Add Parameter Validation UI
**File:** `/Sounder/Views/ParameterControlsView.swift`
**Action:** Add input validation and error display

#### Task 81: Add Parameter Presets
**File:** `/Sounder/Views/ParameterControlsView.swift`
**Action:** Add preset saving/loading for block parameters

### 4.2 Configuration Persistence (Tasks 82-85)

#### Task 82: Implement Configuration Saving
**File:** `/Sounder/Services/ConfigurationPersistenceService.swift`
**Action:** Implement actual file saving (currently stubbed)

#### Task 83: Implement Configuration Loading
**File:** `/Sounder/Services/ConfigurationPersistenceService.swift`
**Action:** Implement actual file loading (currently stubbed)

#### Task 84: Add Configuration Validation
**File:** `/Sounder/Services/ConfigurationPersistenceService.swift`
**Action:** Validate loaded configurations before applying

#### Task 85: Test Configuration Persistence
**File:** Create `/SounderTests/Services/ConfigurationPersistenceTests.swift`
**Content:** Test save/load functionality

### 4.3 Audio Analysis Visualization (Tasks 86-89)

#### Task 86: Enhance Spectrum Analyzer Display
**File:** `/Sounder/Views/SpectrumVisualizerView.swift`
**Action:** Add frequency labels and dB scale

#### Task 87: Add Level Meter Visualization
**File:** Create `/Sounder/Views/LevelMeterView.swift`
**Content:** Real-time level meter display with peak hold

#### Task 88: Add Frequency Counter Display
**File:** Create `/Sounder/Views/FrequencyCounterView.swift`
**Content:** Digital frequency display with update rate control

#### Task 89: Test All Visualizations
**File:** Create `/SounderTests/Views/VisualizationTests.swift`
**Content:** Test all audio visualizations update correctly

## Implementation Guidelines

### Code Style Requirements
- Follow existing code patterns in the codebase
- Use meaningful variable and function names
- Add comprehensive documentation comments
- Ensure thread safety for all audio-related code
- Use `GainAndSmoothing` for all parameter changes
- Implement proper error handling with specific error types

### Testing Requirements
- Write unit tests for every new audio block
- Include edge case testing (extreme parameter values)
- Test real-time performance constraints
- Verify thread safety of all audio code
- Test UI integration for all new features

### Performance Requirements
- No memory allocation in audio callback
- Maximum 10% CPU usage for complex graphs
- Sub-10ms latency for audio processing
- Smooth parameter changes without clicks/pops
- Stable operation for extended periods

### Documentation Requirements
- Document all public APIs
- Include usage examples for complex blocks
- Update README.md as features are completed
- Create troubleshooting guides for common issues

## Success Criteria

The project will be considered complete when:

1. **All 18 block types are implemented and functional**
2. **Test suite passes with >90% code coverage**
3. **Real-time audio performance is stable**
4. **UI is fully functional for all features**
5. **Configuration save/load works reliably**
6. **No memory allocation occurs in audio callback**
7. **Thread safety is verified through testing**
8. **Performance monitoring shows stable operation**

Each task should be implemented incrementally with testing before moving to the next task. The plan is designed to build functionality progressively while maintaining a stable, working codebase throughout the implementation process.
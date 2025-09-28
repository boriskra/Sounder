# Sounder: Visual Audio Signal Processing

**⚠️ PROJECT STATUS: DEVELOPMENT/PROTOTYPE ⚠️**

Sounder is a **work-in-progress** macOS application for generating and processing audio signals using a visual, block-based editor. **This is not a production-ready application.** Many features are incomplete, broken, or exist only as mock implementations.

## Build Status

✅ **Builds Successfully** - The project compiles without errors
❌ **Tests Failing** - Test suite has compilation errors and many tests are incomplete
⚠️ **Incomplete Implementation** - Core functionality is partially implemented

## Technologies

- **Swift 5.9+** & **SwiftUI**
- **AVFoundation** for audio engine (partially implemented)
- **XCTest** for testing (many tests are stubs)
- SwiftUI Canvas for block editor (basic implementation)

## Current Implementation State

### ✅ **What Works**
- Project builds and compiles
- Basic SwiftUI UI structure
- Mock services for development/preview
- Audio block type definitions
- Basic dependency injection setup

### ⚠️ **Partially Implemented**
- **Audio Engine**: `AudioBlockServiceImpl` exists but uses unsafe concurrency patterns
- **Audio Blocks**: Only 6 out of 18 block types are implemented:
  - ✅ SineOscillatorBlock
  - ✅ TriangleOscillatorBlock
  - ✅ FrequencyModulatorBlock
  - ✅ WhiteNoiseBlock
  - ✅ SpectrumAnalyzerBlock
  - ✅ AudioOutputBlock
- **Block Manager**: Core service exists but integration is incomplete
- **UI Components**: Basic structure exists, many controls are placeholders

### ❌ **Not Implemented**
- **12 Block Types Missing**: squareOscillator, sawtoothOscillator, pinkNoise, linearChirp, hyperbolicChirp, amplitudeModulator, ringModulator, lowPassFilter, highPassFilter, bandPassFilter, mixer, amplifier, levelMeter, frequencyCounter
- **Audio Persistence**: Save/load functionality is stubbed
- **Real-time Audio Processing**: Graph scheduler partially implemented
- **Error Handling**: Minimal error handling throughout
- **Performance Monitoring**: Mock implementations only
- **Device Selection**: UI exists but backend integration incomplete

## Critical Issues

### 🚨 **Thread Safety Problems**
- `AudioBlockService.swift` uses `nonisolated(unsafe)` extensively (lines 102-114)
- Data races possible in audio rendering thread
- Mock services don't reflect real concurrency requirements

### 🚨 **Test Infrastructure Broken**
- `AudioBlockServiceTests.swift`: All tests disabled with `XCTFail("implementation not available")`
- Test compilation errors due to outdated model signatures
- No integration tests for audio pipeline
- Mock vs real implementation coverage gap

### 🚨 **Architecture Inconsistencies**
- Mixed use of real implementations vs mocks in production code
- `MockAudioBlockService` and `MockAudioService` are in main target, not test target
- Dependency injection incomplete - many hardcoded dependencies
- Protocol contracts don't match actual implementations

### 🚨 **Audio Engine Issues**
- Real-time safety not guaranteed
- Buffer management incomplete
- Device switching partially implemented
- No proper audio graph validation

## Project Structure

```
Sounder/
├── Sounder/                          # Main application target
│   ├── Models/                       # Data models (complete)
│   ├── Views/                        # SwiftUI components (partial)
│   ├── ViewModels/                   # View models (basic implementation)
│   └── Services/                     # Business logic (mixed state)
│       ├── AudioBlockService.swift   # Main service (partial, unsafe)
│       ├── AVFAudioService.swift     # Audio foundation (basic)
│       ├── Mock*.swift               # Mock implementations (shouldn't be here)
│       └── AudioBlocks/              # Block implementations (6/18 done)
├── SounderTests/                     # Unit tests (mostly broken)
├── SounderUITests/                   # UI tests (minimal)
└── specs/                            # Documentation (outdated)
```

## Mock vs Real Implementation Analysis

### 🎭 **Mock Service Issues**
1. **Production Code Pollution**: Mock services are in main target instead of test-only
2. **False Capabilities**: Mocks claim to support features that aren't implemented
3. **Data Inconsistency**: Mock data doesn't reflect real audio device constraints
4. **Testing Gap**: No verification that mocks match real service behavior

### 🔧 **Real Service Gaps**
1. **AudioBlockServiceImpl**: Exists but has concurrency safety issues
2. **AVFAudioService**: Basic implementation, missing advanced features
3. **BlockManagerService**: Service exists but audio integration incomplete

## Build and Development

### **Prerequisites**
- macOS 14.0+ (due to API usage)
- Xcode 15.0+
- No external dependencies

### **Build Commands**
```bash
# Build (works)
xcodebuild -project Sounder.xcodeproj -scheme Sounder -destination "platform=macOS" build

# Test (fails - compilation errors)
xcodebuild test -project Sounder.xcodeproj -scheme Sounder -destination "platform=macOS"

# Open in Xcode
open Sounder.xcodeproj
```

### **Known Build Issues**
- Tests fail compilation due to outdated model signatures
- Many deprecation warnings (SwiftUI APIs)
- Concurrency warnings throughout codebase

## Recommended Next Steps

### **Phase 1: Fix Foundation (High Priority)**
1. **Fix Test Suite**: Update test models to match current signatures
2. **Remove Production Mocks**: Move mock services to test-only targets
3. **Thread Safety**: Refactor `nonisolated(unsafe)` code in AudioBlockService
4. **Error Handling**: Add proper error types and handling throughout

### **Phase 2: Core Audio (Medium Priority)**
1. **Complete Audio Blocks**: Implement remaining 12 block types
2. **Audio Graph**: Finish audio graph scheduler implementation
3. **Device Management**: Complete audio device selection backend
4. **Performance**: Add real performance monitoring

### **Phase 3: Features (Low Priority)**
1. **Persistence**: Implement save/load functionality
2. **UI Polish**: Complete parameter controls and visualizations
3. **Templates**: Add block configuration templates
4. **Documentation**: Update specifications to match implementation

## Developer Warning

**Do not rely on this codebase for production use.** This is a prototype with significant gaps:

- Audio processing may not work correctly
- Data may be lost (no persistence)
- Performance is unoptimized
- Error handling is minimal
- Thread safety is not guaranteed

The project serves as a starting point for a visual audio editor but requires substantial additional development to be usable.

## Technical Background for AI Agents

### **Audio Block Architecture**
Audio blocks follow the `AudioBlock` protocol defined in `AudioBlockService.swift:41-58`. Each block must implement:
```swift
public protocol AudioBlock {
    var id: UUID { get }
    var type: BlockType { get }
    var inputPorts: [String] { get }
    var outputPorts: [String] { get }

    func processAudio(
        inputs: [String: [Float]],
        frameCount: Int,
        startSample: UInt64,
        sampleRate: Double
    ) -> [String: [Float]]

    func setParameter(name: String, value: Double)
    func getParameter(name: String) -> Double?
}
```

### **Existing Block Implementations**
Reference implementations exist in `/Sounder/Services/AudioBlocks/`:
- `SineOscillatorBlock.swift` - Pure sine wave generator
- `TriangleOscillatorBlock.swift` - Triangle wave with anti-aliasing
- `FrequencyModulatorBlock.swift` - FM synthesis implementation
- `WhiteNoiseBlock.swift` - Random noise with seeding
- `SpectrumAnalyzerBlock.swift` - FFT-based frequency analysis
- `AudioOutputBlock.swift` - Device output routing

### **DSP Library Components**
Reusable DSP components in `/Sounder/Services/AudioBlocks/DSP/`:
- `OscillatorPhaseAccumulator.swift` - Phase-coherent oscillator base
- `BiquadFilterCore.swift` - Digital filter implementation
- `NoiseGeneratorBase.swift` - Seeded noise generation
- `GainAndSmoothing.swift` - Parameter smoothing utilities
- `SignalAnalysisKit.swift` - Frequency/level analysis tools
- `ChirpEnvelopeEngine.swift` - Sweep signal generation

### **Block Type Definitions**
All 18 block types are defined in `BlockType.swift` with:
- Display names and descriptions
- Required parameters and default values
- Input/output port configurations
- Parameter creation methods

### **Audio Engine Integration**
The `AudioBlockServiceImpl` class manages:
- Block registration and lifecycle
- Audio graph scheduling via `AudioGraphScheduler`
- Real-time parameter updates
- Performance monitoring
- Device management integration

### **Thread Safety Requirements**
- Audio processing runs on real-time thread
- Parameter updates must use atomic operations
- Memory allocation forbidden in audio callback
- Use `nonisolated` functions for thread-safe operations

### **Testing Patterns**
Follow test patterns in existing files:
- Unit tests for individual blocks in `/SounderTests/`
- Mock implementations for UI previews
- Integration tests for audio pipeline
- Performance tests for real-time constraints

### **UI Integration Points**
- Block creation via `BlockManagerService.createBlock()`
- Parameter controls in `ParameterControlsView.swift`
- Visual feedback through analysis blocks
- Device selection in `AudioDeviceView.swift`

### **Development Environment**
- Xcode 15.0+ required for Swift 5.9 features
- macOS 14.0+ for AVFoundation APIs
- No external dependencies - pure Swift/AVFoundation
- SwiftLint for code style consistency

---

*This README reflects the actual state of the codebase as of the latest code review. See PLAN.md for detailed implementation steps.*
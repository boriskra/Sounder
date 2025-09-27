# Sounder Project Implementation Plan

## Executive Summary

Based on comprehensive code review, the Sounder audio processing application requires significant implementation work to reach production readiness. While the architecture is solid and mock service usage has been properly cleaned up, critical missing implementations prevent core functionality from working.

## Current State Assessment

### ✅ Working Components
- Audio Engine core infrastructure (AVFoundation integration)
- Block Editor UI and canvas system
- 17/20 AudioBlock implementations (85% complete)
- Service dependency injection (no mock leakage to production)
- Configuration persistence (JSON export/import)
- Real-time timeline-coherent audio processing framework

### 🚨 Critical Blockers
- **Missing AudioBlock factory cases** - Analysis blocks cause app crashes
- **Placeholder analysis methods** - All audio analysis returns fake data
- **Stub device switching** - Cannot change audio output devices
- **Broken XML import** - Cannot import exported configurations
- **Incomplete parameter controls** - Most block parameters cannot be edited

### 🔴 High Priority Missing Features
- Template system completely non-functional
- Audio device management stubs
- Parameter validation and real-time updates
- Advanced parameter controls (automation, modulators, filters)

## Implementation Plan

### Phase 1: Critical Infrastructure (Weeks 1-3)
*Priority: CRITICAL - Required for basic functionality*

#### Block 1A: Missing AudioBlock Implementations (Week 1)
**Can be done in parallel by 3 agents**

**Step 1.1** - Implement SpectrumAnalyzerAudioBlock factory case
- File: `Sounder/Services/AudioBlockService.swift:479`
- Add case `.spectrumAnalyzer: return SpectrumAnalyzerBlock(block: block)` to createAudioBlock switch
- Test: Verify spectrum analyzer blocks can be created without crashes
- **Parallel Task A**

**Step 1.2** - Implement LevelMeterAudioBlock factory case
- File: `Sounder/Services/AudioBlockService.swift:479`
- Add case `.levelMeter: return LevelMeterAudioBlock(block: block)` to createAudioBlock switch
- Create `LevelMeterAudioBlock` class if missing in `Services/AudioBlocks/`
- Test: Verify level meter blocks can be created without crashes
- **Parallel Task B**

**Step 1.3** - Implement FrequencyCounterAudioBlock factory case
- File: `Sounder/Services/AudioBlockService.swift:479`
- Add case `.frequencyCounter: return FrequencyCounterAudioBlock(block: block)` to createAudioBlock switch
- Create `FrequencyCounterAudioBlock` class if missing in `Services/AudioBlocks/`
- Test: Verify frequency counter blocks can be created without crashes
- **Parallel Task C**

**Step 1.4** - Integration test for all analysis blocks
- Test creating each analysis block type in the UI
- Verify audio engine starts successfully with analysis blocks
- Test basic audio processing through analysis blocks
- **Sequential after 1.1-1.3**

#### Block 1B: Real Audio Analysis Implementation (Week 1-2)
**Can be done in parallel by 2 agents after Block 1A**

**Step 1.5** - Implement real spectrum analysis
- File: `Sounder/Services/AudioBlockService.swift:433-442`
- Replace `getSpectrumData()` placeholder with real FFT implementation
- Use vDSP framework for efficient FFT computation
- Return actual frequency domain magnitude data
- Test: Verify spectrum analyzer displays real audio spectrum
- **Parallel Task D**

**Step 1.6** - Implement real level meter analysis
- File: `Sounder/Services/AudioBlockService.swift:444-450`
- Replace `getLevelMeterData()` placeholder with real RMS/peak calculation
- Implement proper level measurement with configurable integration time
- Return actual audio level measurements
- Test: Verify level meters show real audio levels
- **Parallel Task E**

**Step 1.7** - Implement real frequency analysis
- File: `Sounder/Services/AudioBlockService.swift:452-456`
- Replace `getFrequencyAnalysis()` placeholder with pitch detection
- Implement autocorrelation or YIN algorithm for frequency detection
- Return actual dominant frequency measurements
- Test: Verify frequency counter shows real pitch data
- **Sequential after 1.5**

**Step 1.8** - Implement real latency measurement
- File: `Sounder/Services/AudioBlockService.swift:471-475`
- Replace `getAudioLatency()` placeholder with actual latency measurement
- Measure round-trip audio latency using test signals
- Return real system latency values
- Test: Verify performance metrics show actual latency
- **Parallel Task F**

#### Block 1C: Audio Device Management (Week 2-3)
**Can be done in parallel by 2 agents**

**Step 1.9** - Implement real device switching
- File: `Sounder/Services/AVFAudioService.swift:164-171`
- Replace `setEngineOutputDevice()` stub with CoreAudio device switching
- Handle audio engine restart if required for device changes
- Implement proper error handling for device switching failures
- Test: Verify audio output switches between devices
- **Parallel Task G**

**Step 1.10** - Fix parameter-aware audio generation
- File: `Sounder/Services/AVFAudioService.swift:182`
- Replace hardcoded 440Hz TODO with real parameter extraction
- Implement parameter lookup from block configurations
- Support dynamic frequency and amplitude changes
- Test: Verify audio output reflects parameter changes
- **Parallel Task H**

**Step 1.11** - Implement device enumeration improvements
- File: `Sounder/Services/AVFAudioService.swift:140-162`
- Enhance device discovery with proper device properties
- Add device capability detection (sample rates, channel counts)
- Implement device change notifications
- Test: Verify device list updates dynamically
- **Sequential after 1.9**

#### Block 1D: Configuration Import/Export (Week 3)
**Can be done in parallel by 2 agents**

**Step 1.12** - Implement XML configuration import
- File: `Sounder/Services/ConfigurationPersistenceService.swift:832`
- Replace "not yet implemented" with actual XML parsing
- Implement XML-to-BlockConfiguration conversion
- Add proper error handling and validation
- Test: Verify XML files can be imported successfully
- **Parallel Task I**

**Step 1.13** - Implement legacy configuration import
- File: `Sounder/Services/ConfigurationPersistenceService.swift:275`
- Define legacy format specification
- Implement conversion from legacy format to current BlockConfiguration
- Add migration logic for deprecated parameters
- Test: Verify legacy files can be imported
- **Parallel Task J**

**Step 1.14** - Integration test for import/export
- Test round-trip export/import for all supported formats
- Verify configuration fidelity through export/import cycle
- Test error handling for corrupted files
- **Sequential after 1.12-1.13**

### Phase 2: Core Feature Implementation (Weeks 4-7)
*Priority: HIGH - Required for full functionality*

#### Block 2A: Parameter Controls Implementation (Weeks 4-5)
**Can be done in parallel by 4 agents**

**Step 2.1** - Implement oscillator parameter controls
- File: `Sounder/Views/ParameterControlsView.swift:130-140`
- Add real frequency, amplitude, phase controls for all oscillator types
- Implement real-time parameter updates with proper validation
- Add waveform visualization for oscillators
- Test: Verify oscillator parameters can be adjusted in real-time
- **Parallel Task K**

**Step 2.2** - Implement filter parameter controls
- File: `Sounder/Views/ParameterControlsView.swift:151`
- Replace "Filter controls not implemented" with real filter controls
- Add cutoff frequency, resonance, filter type controls
- Implement frequency response visualization
- Test: Verify filter parameters affect audio output
- **Parallel Task L**

**Step 2.3** - Implement modulator parameter controls
- File: `Sounder/Views/ParameterControlsView.swift:149`
- Replace "Modulator controls not implemented" with real modulator controls
- Add modulation depth, rate, waveform controls
- Implement modulation visualization
- Test: Verify modulation parameters work correctly
- **Parallel Task M**

**Step 2.4** - Implement meter parameter controls
- File: `Sounder/Views/ParameterControlsView.swift:155`
- Replace "Meter controls not implemented" with real meter controls
- Add integration time, scale, range controls
- Implement real-time meter display
- Test: Verify meter controls affect display behavior
- **Parallel Task N**

**Step 2.5** - Implement chirp parameter controls
- File: `Sounder/Views/ParameterControlsView.swift:147`
- Replace "Chirp controls not implemented" with real chirp controls
- Add start/end frequency, sweep duration, curve type controls
- Implement chirp waveform preview
- Test: Verify chirp parameters generate correct sweeps
- **Sequential after 2.1**

**Step 2.6** - Implement parameter automation system
- File: `Sounder/Views/ParameterControlsView.swift` (new automation section)
- Add automation recording and playback
- Implement automation curve editing
- Add automation sync with timeline
- Test: Verify parameters can be automated over time
- **Sequential after 2.1-2.4**

#### Block 2B: Template System Implementation (Week 5-6)
**Can be done in parallel by 3 agents**

**Step 2.7** - Implement template creation
- File: `Sounder/Views/BlockLibraryView.swift:394-395`
- Uncomment and implement template creation functionality
- Add UI for capturing current configuration as template
- Implement template metadata editing (name, description, tags)
- Test: Verify templates can be created from existing configurations
- **Parallel Task O**

**Step 2.8** - Implement template application
- File: `Sounder/Views/BlockLibraryView.swift:435`
- Implement `applyTemplate()` method functionality
- Add template instantiation logic with position management
- Handle parameter conflicts and dependencies
- Test: Verify templates can be applied to canvas
- **Parallel Task P**

**Step 2.9** - Implement template management
- File: `Sounder/Views/BlockLibraryView.swift` (new template management)
- Add template storage and retrieval system
- Implement template sharing and import/export
- Add template versioning and compatibility checks
- Test: Verify template library management works
- **Parallel Task Q**

**Step 2.10** - Template integration testing
- Test template creation from complex configurations
- Verify template application preserves functionality
- Test template sharing between users
- **Sequential after 2.7-2.9**

#### Block 2C: Advanced Parameter System (Week 6-7)
**Can be done in parallel by 3 agents**

**Step 2.11** - Implement parameter validation system
- File: `Sounder/Models/BlockEditor/SignalBlock.swift` (enhance parameter validation)
- Add comprehensive parameter range validation
- Implement parameter dependency checking
- Add parameter constraint enforcement
- Test: Verify invalid parameters are rejected gracefully
- **Parallel Task R**

**Step 2.12** - Implement parameter presets
- File: `Sounder/Views/ParameterControlsView.swift` (add preset system)
- Add parameter preset saving and loading
- Implement preset categorization and search
- Add preset sharing functionality
- Test: Verify parameter presets work across block types
- **Parallel Task S**

**Step 2.13** - Implement parameter MIDI control
- File: `Sounder/Services/` (new MIDI service)
- Add MIDI input handling for parameter control
- Implement MIDI learn functionality
- Add MIDI controller mapping persistence
- Test: Verify parameters can be controlled via MIDI
- **Parallel Task T**

**Step 2.14** - Advanced parameter testing
- Test parameter validation with edge cases
- Verify preset system maintains parameter integrity
- Test MIDI control responsiveness and accuracy
- **Sequential after 2.11-2.13**

### Phase 3: Enhanced Features (Weeks 8-10)
*Priority: MEDIUM - Polish and advanced functionality*

#### Block 3A: Advanced Audio Features (Week 8)
**Can be done in parallel by 3 agents**

**Step 3.1** - Implement advanced spectrum analysis
- File: `Sounder/Services/AudioBlocks/SpectrumAnalyzerBlock.swift`
- Add octave analysis, peak detection, spectral centroid
- Implement multiple window functions and overlap settings
- Add waterfall display support
- Test: Verify advanced analysis features work correctly
- **Parallel Task U**

**Step 3.2** - Implement multi-channel level metering
- File: `Sounder/Services/AudioBlocks/` (enhance level meter)
- Add stereo and surround sound level metering
- Implement loudness measurement (LUFS, LKFS)
- Add level history and peak hold functionality
- Test: Verify multi-channel metering works correctly
- **Parallel Task V**

**Step 3.3** - Implement advanced frequency analysis
- File: `Sounder/Services/AudioBlocks/` (enhance frequency counter)
- Add harmonic analysis and pitch confidence
- Implement polyphonic frequency detection
- Add musical note display and tuning reference
- Test: Verify advanced frequency features work correctly
- **Parallel Task W**

#### Block 3B: Performance and Optimization (Week 9)
**Can be done in parallel by 2 agents**

**Step 3.4** - Implement performance monitoring
- File: `Sounder/Services/AudioBlockService.swift` (enhance performance metrics)
- Add detailed CPU usage per block
- Implement memory usage tracking
- Add performance alerts and optimization suggestions
- Test: Verify performance monitoring provides useful data
- **Parallel Task X**

**Step 3.5** - Implement audio buffer optimization
- File: `Sounder/Services/AudioBlockService.swift` (optimize buffer management)
- Add adaptive buffer sizing based on system load
- Implement buffer underrun prevention
- Add latency optimization algorithms
- Test: Verify optimizations improve performance without artifacts
- **Parallel Task Y**

#### Block 3C: User Experience Enhancements (Week 10)
**Can be done in parallel by 4 agents**

**Step 3.6** - Implement advanced UI features
- Files: Various view files
- Add keyboard shortcuts for common operations
- Implement drag-and-drop improvements
- Add multi-select and bulk operations
- Test: Verify UI enhancements improve workflow efficiency
- **Parallel Task Z**

**Step 3.7** - Implement configuration management
- File: `Sounder/Services/ConfigurationPersistenceService.swift`
- Add configuration versioning and backup
- Implement auto-save and recovery
- Add configuration comparison and merging
- Test: Verify configuration management prevents data loss
- **Parallel Task AA**

**Step 3.8** - Implement help and documentation
- Files: New help system files
- Add context-sensitive help
- Implement interactive tutorials
- Add parameter explanations and examples
- Test: Verify help system assists new users effectively
- **Parallel Task BB**

**Step 3.9** - Implement accessibility features
- Files: Various view files
- Add VoiceOver support for audio professionals
- Implement high contrast and large text support
- Add keyboard navigation for all features
- Test: Verify accessibility compliance
- **Parallel Task CC**

## Implementation Guidelines

### For AI Agents
1. **Each step should be implemented independently** - no step should depend on incomplete work from another step unless explicitly marked as sequential
2. **Include comprehensive tests** for each implementation step
3. **Maintain backward compatibility** - don't break existing functionality
4. **Follow established code patterns** - use existing DSP utilities and maintain timeline coherence
5. **Document all new code** with Swift documentation comments
6. **Validate parameters** at all entry points
7. **Handle errors gracefully** with appropriate user feedback

### Parallel Execution Strategy
- **Week 1**: Tasks A, B, C can run in parallel (3 agents)
- **Week 1-2**: Tasks D, E, F can run in parallel after Block 1A (3 agents)
- **Week 2-3**: Tasks G, H, I, J can run in parallel (4 agents)
- **Week 4-5**: Tasks K, L, M, N can run in parallel (4 agents)
- **Week 5-6**: Tasks O, P, Q can run in parallel (3 agents)
- **Week 6-7**: Tasks R, S, T can run in parallel (3 agents)
- **Week 8**: Tasks U, V, W can run in parallel (3 agents)
- **Week 9**: Tasks X, Y can run in parallel (2 agents)
- **Week 10**: Tasks Z, AA, BB, CC can run in parallel (4 agents)

### Testing Strategy
- **Unit tests** for each new component
- **Integration tests** after each block completion
- **Performance tests** for audio processing components
- **UI tests** for user interface components
- **End-to-end tests** for complete workflows

### Success Criteria
- All AudioBlock types can be created and processed without errors
- All audio analysis methods return real data
- All parameter controls are functional and update audio in real-time
- All configuration formats can be imported and exported successfully
- Template system allows creation, application, and sharing of templates
- Performance meets real-time audio processing requirements
- User interface is responsive and provides good user experience

## Risk Mitigation
- **Incremental implementation** - each step builds on stable foundation
- **Parallel development** - reduces timeline risk through concurrent work
- **Comprehensive testing** - catches issues early in development
- **Backward compatibility** - prevents regression during implementation
- **Performance monitoring** - ensures real-time audio requirements are met

This plan provides a clear roadmap for completing all missing implementations in the Sounder project, with specific steps sized for AI agent implementation and clear parallelization opportunities to minimize development time.
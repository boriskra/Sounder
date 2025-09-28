# Sounder Project Implementation Plan

## Executive Summary

**UPDATED: January 2025** - Following comprehensive code review and implementation efforts, significant progress has been made. The application now has working audio analysis, configuration import/export, and parameter controls. Some integration issues remain.

## Current State Assessment

### ✅ Working Components
- Audio Engine core infrastructure (AVFoundation integration)
- Block Editor UI and canvas system
- **ALL 20 AudioBlock implementations working** (100% complete - verified AudioBlockService.swift:710-750)
- **Real FFT/RMS/zero-crossing audio analysis** (verified lines 484-542, 2931, 3066)
- **XML and legacy JSON import/export working** (verified ConfigurationPersistenceService.swift:260, 1330)
- **Parameter controls with live updates** (core functionality works)
- Service dependency injection (no mock leakage to production)
- Real-time timeline-coherent audio processing framework

### ⚠️ Partially Working
- **Device switching**: Real CoreAudio implementation exists in AVFAudioService.swift:171-205 but app uses stub in AudioBlockService.swift:466
- **Template system**: Apply template works, create template not implemented (BlockLibraryView.swift:394)
- **Parameter UI**: Core updates work but Reset/Validate buttons are stubs

### 🚨 Remaining Issues
- **AudioBlockService device switching stub** - App can't actually switch devices (line 466)
- **CPU usage monitoring** - Returns random values (AudioBlockService.swift:547)
- **Template creation** - UI exists but functionality missing
- **Some UI buttons** - Reset Analysis, Reseed Generator do nothing

## Remaining Implementation Work

### Priority 1: Critical Integration Fixes

#### Task 1.1: Add AVFAudioService dependency to AudioBlockService
**Complexity: LOW | Est. Time: 15 min**
- File: `Sounder/Services/AudioBlockService.swift`
- Add private property: `private let avfAudioService: AVFAudioService`
- Update initializer to accept AVFAudioService parameter
- Modify call sites to pass AVFAudioService instance

#### Task 1.2: Replace device switching stub with real implementation
**Complexity: LOW | Est. Time: 10 min**
- File: `Sounder/Services/AudioBlockService.swift:466-476`
- Replace method body in `setOutputDevice()` with:
  ```swift
  try await avfAudioService.setEngineOutputDevice(device)
  currentOutputDevice = device
  eventPublisher.send(.outputDeviceChanged(device))
  ```
- Remove old stub comments and print statements

#### Task 1.3: Test device switching integration
**Complexity: LOW | Est. Time: 10 min**
- Build and run project
- Test device switching from UI works end-to-end
- Verify audio actually routes to selected device

#### Task 2.1: Research CPU monitoring APIs on macOS
**Complexity: MEDIUM | Est. Time: 20 min**
- File: `Sounder/Services/AudioBlockService.swift:546-551`
- Add imports: `import Darwin` and `import os`
- Research `host_processor_info()` vs `ProcessInfo.processInfo.thermalState`
- Choose appropriate API for audio thread CPU usage

#### Task 2.2: Implement real CPU usage monitoring
**Complexity: MEDIUM | Est. Time: 30 min**
- Replace `getAudioCPUUsage()` method body
- Use chosen API to get actual CPU percentage for audio processing
- Add error handling for API failures
- Cache values to avoid frequent system calls
- Return real percentage (0.0-1.0 range)

### Priority 2: Complete Missing Features

#### Task 3.1: Add template creation UI button
**Complexity: LOW | Est. Time: 10 min**
- File: `Sounder/Views/BlockLibraryView.swift:394-397`
- Uncomment "Create Template" button
- Add action: `createTemplate()`
- Position next to "Apply Template" button

#### Task 3.2: Implement template creation logic
**Complexity: MEDIUM | Est. Time: 45 min**
- Add `createTemplate()` method to TemplateDetailView
- Capture current blockManager.currentConfiguration
- Create new BlockTemplate from configuration
- Add template name/description input fields
- Show confirmation dialog

#### Task 3.3: Implement template persistence
**Complexity: MEDIUM | Est. Time: 30 min**
- Extend `BlockTemplate` with save/load methods
- Store templates in Documents/Templates/ directory
- Update `BlockTemplate.allTemplates` to load from disk
- Add template deletion functionality

#### Task 4.1: Implement Reset Analysis button
**Complexity: LOW | Est. Time: 15 min**
- File: `Sounder/Views/ParameterControlsView.swift:221-224`
- Replace button action with actual reset logic
- Clear spectrum analyzer buffers
- Reset analysis history arrays
- Update UI to show reset state

#### Task 4.2: Implement Reseed Generator button
**Complexity: LOW | Est. Time: 15 min**
- File: `Sounder/Views/ParameterControlsView.swift:236-239`
- Replace button action with actual reseed logic
- Call `srand()` or similar to reseed noise generators
- Update noise block parameters to use new seed
- Show confirmation feedback

#### Task 4.3: Add parameter validation buttons
**Complexity: MEDIUM | Est. Time: 25 min**
- Add "Validate" button to parameter controls
- Implement range checking for all parameters
- Show validation errors in UI
- Add "Reset to Default" functionality

### Priority 3: Performance Optimization (OPTIONAL)

#### Task 5.1: Profile thread safety bottlenecks
**Complexity: HIGH | Est. Time: 60 min**
- Use Instruments to profile audio processing
- Identify thread contention points
- Document findings in comments

#### Task 5.2: Review nonisolated(unsafe) usage
**Complexity: HIGH | Est. Time: 45 min**
- Audit all `nonisolated(unsafe)` properties
- Ensure they're truly safe or add proper synchronization
- Document thread safety assumptions

#### Task 6.1: Profile memory allocation hot paths
**Complexity: HIGH | Est. Time: 60 min**
- Use Instruments Allocations tool
- Identify frequent allocations in audio thread
- Document optimization opportunities

## Implementation Guidelines

### Architecture Principles
1. **Timeline Coherence** - All audio processing must maintain sample-accurate positioning
2. **Thread Safety** - Use atomic operations and avoid locks in audio thread
3. **Real-time Safety** - No memory allocations or blocking calls in audio processing
4. **Error Handling** - Graceful degradation, never crash in audio thread

### Testing Requirements (per task)
- **Tasks 1.1-1.3**: Manual testing of device switching from UI
- **Tasks 2.1-2.2**: Verify CPU metrics show real values, not random
- **Tasks 3.1-3.3**: Test template creation, editing, and persistence
- **Tasks 4.1-4.3**: Verify all UI buttons perform expected actions
- **Tasks 5.1-6.1**: Use Instruments for performance profiling

### Task Dependencies
- Task 1.2 depends on Task 1.1 (dependency injection)
- Task 1.3 depends on Task 1.2 (implementation complete)
- Task 2.2 depends on Task 2.1 (API research complete)
- Task 3.2 depends on Task 3.1 (UI button exists)
- Task 3.3 depends on Task 3.2 (creation logic exists)
- Tasks 5.1-6.1 are independent and optional

### Success Criteria (by Priority)
**Priority 1 (Required)**:
✅ Task 1.3: Audio output switches to selected device
✅ Task 2.2: CPU usage displays real percentages

**Priority 2 (Recommended)**:
✅ Task 3.3: Templates can be created, saved, and loaded
✅ Task 4.3: All UI buttons perform intended functions

**Priority 3 (Optional)**:
✅ Task 6.1: Performance profiling identifies optimization opportunities

## Summary

The Sounder project has made significant progress with most Phase 1 and 2 implementations complete. The main remaining work involves:
1. Connecting existing implementations (device switching)
2. Replacing placeholders (CPU monitoring)
3. Completing partial features (template creation, UI buttons)

The architecture is solid and the core audio processing works well. With these remaining fixes, the application will be production-ready.
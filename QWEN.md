# Sounder Project Documentation

## Project Overview

Sounder is a macOS application for generating and processing audio signals with a focus on visual block-based audio editing. The application allows users to create complex audio configurations using a drag-and-drop interface where different audio processing blocks can be connected together.

The project is built using:
- **Swift 5.9+**
- **SwiftUI** for the user interface
- **AVFoundation** for audio processing
- **XCTest** for testing
- **AudioKit Flow** (MIT) for visual block editing
- Native SwiftUI Canvas and Drag & Drop functionality

## Project Structure

```
Sounder/
├── Models/
│   ├── BlockEditor/          # Block-specific data models
│   ├── OutputDevice.swift    # Audio output device representation
│   ├── Parameter.swift       # Audio parameter definitions
│   └── Sound.swift           # Basic sound definitions
├── Services/                 # Business logic and audio services
│   ├── AudioBlocks/          # Specific implementations for audio blocks
│   ├── AudioBlockService.swift
│   ├── AudioService.swift
│   ├── AVFAudioService.swift
│   ├── BlockCanvasService.swift
│   ├── BlockManagerService.swift
│   ├── ConfigurationPersistenceService.swift
│   ├── MockAudioBlockService.swift
│   ├── MockAudioService.swift
│   └── MockBlockManagerService.swift
├── ViewModels/
│   ├── BlockCanvasViewModel.swift
│   ├── BlockEditorViewModel.swift
│   ├── ConfigurationViewModel.swift
│   └── ContentViewModel.swift
├── Views/
│   ├── BlockEditor/          # Block editor-specific UI components
│   ├── BlockCanvasView.swift
│   ├── BlockEditorView.swift
│   ├── BlockLibraryView.swift
│   ├── BlockView.swift
│   ├── ConnectionView.swift
│   ├── AudioDeviceView.swift
│   ├── DeviceSelectionView.swift
│   ├── ParameterControlsView.swift
│   ├── SoundSelectionView.swift
│   └── SpectrumVisualizerView.swift
├── ContentView.swift         # Main application view
├── SounderApp.swift          # Application entry point
├── Info.plist               # Application configuration
└── ...
```

## Key Features

### Core Audio Generation
- Basic audio signal generation (sine, square, triangle, sawtooth)
- Noise generation (white, pink)
- Chirp generation (linear and hyperbolic)
- Audio output device selection including Bluetooth support
- Parameter-driven sound generation

### Block-Based Visual Editor
- Drag-and-connect audio processing blocks
- Real-time parameter control
- Signal modulation (AM, FM, ring modulation)
- Audio analysis blocks (spectrum, level meters, frequency counter)
- Configuration save/load functionality

### Available Block Types

#### Generators
- Sine Oscillator
- Square Oscillator
- Triangle Oscillator
- Sawtooth Oscillator
- White Noise
- Pink Noise
- Linear Chirp
- Hyperbolic Chirp

#### Modulation
- Amplitude Modulator
- Frequency Modulator
- Ring Modulator

#### Processing
- Low Pass Filter
- High Pass Filter
- Band Pass Filter
- Mixer
- Amplifier

#### Analysis
- Spectrum Analyzer
- Level Meter
- Frequency Counter

#### Output
- Audio Output

## Architecture

The application follows the MVVM (Model-View-ViewModel) pattern with clean separation of concerns:

- **Models**: Define data structures for audio blocks, connections, and parameters
- **Views**: SwiftUI-based user interfaces that are reactive and data-driven
- **ViewModels**: Handle UI state and business logic, bridging models and views
- **Services**: Core business logic for audio processing, block management, and persistence

## Building and Running

To build and run the Sounder application:

1. Open `Sounder.xcodeproj` in Xcode
2. Select the target and a macOS device/simulator
3. Press Cmd+R or click the Run button

### Configuration
The project uses SwiftLint for code quality with the following configuration in `.swiftlint.yml`:
- Custom rules for audio parameter validation
- Length limits for type bodies, function bodies, and cyclomatic complexity
- Exclusion of certain directories from linting

### Testing
The project includes both unit tests (in `SounderTests`) and UI tests (in `SounderUITests`) with mock services for dependency injection during testing.

## Development Conventions

- Follows Swift API Design Guidelines with emphasis on clarity and consistency
- Uses SwiftLint to enforce coding standards and avoid common issues
- Implements comprehensive validation for audio block configurations
- Leverages SwiftUI's reactive programming model for UI updates
- Includes extensive error handling with custom error types
- Uses case studies to define block types, categories, and default parameters

## Keyboard Shortcuts

The application includes comprehensive keyboard shortcuts for efficient workflow:

- **File Operations**: Cmd+N (New), Cmd+S (Save), Cmd+Shift+S (Save As), Cmd+E (Export), Cmd+O (Open)
- **Edit Operations**: Cmd+A (Select All), Cmd+D (Deselect), Cmd+Shift+D (Duplicate), Delete (Delete Selected)
- **Audio Controls**: Space (Play/Pause), Escape (Stop), Cmd+Option+, (Audio Settings)
- **Block Editor**: Cmd+L (Show Library), Cmd+1-6 (Add specific blocks), Cmd+0 (Reset Canvas), Cmd+F (Fit to Content), Cmd+G (Toggle Grid)
- **View Controls**: Cmd+P (Parameters Panel), Cmd+M (Audio Devices Panel)
- **Help**: Cmd+? (Block Editor Help)

The application also provides customizable settings for auto-save intervals, audio engine parameters (buffer size, sample rate), and block editor preferences (grid visibility, snap-to-grid).

## Special Permissions

The application requests microphone access as indicated in Info.plist with the usage description: "This app requires microphone access to visualize the audio spectrum."
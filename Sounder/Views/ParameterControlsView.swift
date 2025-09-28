import SwiftUI

/// Parameter controls view for real-time adjustment of audio block parameters
/// Supports multiple control types, automation, and precise value entry
struct ParameterControlsView: View {
    @ObservedObject var blockManager: BlockManagerServiceImpl
    var selectedBlock: SignalBlock?
    @State private var localSelectedBlock: SignalBlock?
    @State private var showingAutomation: Bool = false
    @State private var parameterHistory: [String: [Double]] = [:]
    @State private var availableDevices: [OutputDevice] = []
    @State private var selectedOutputDevice: OutputDevice?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            parameterHeader

            if let block = localSelectedBlock ?? selectedBlock {
                // Parameter controls
                ScrollView {
                    parameterControlsContent(for: block)
                }
            } else {
                // No selection state
                noSelectionView
            }
        }
        .frame(minWidth: 280)
        .background(Color(NSColor.controlBackgroundColor))
        .onReceive(blockManager.blockUpdated) { updatedBlock in
            if updatedBlock.id == (localSelectedBlock ?? selectedBlock)?.id {
                localSelectedBlock = updatedBlock
            }
        }
        .onAppear {
            loadAvailableDevices()
        }
    }

    // MARK: - Header

    private var parameterHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Parameters")
                    .font(.headline)

                Spacer()

                if selectedBlock != nil {
                    Button(action: { showingAutomation.toggle() }) {
                        Image(systemName: showingAutomation ? "waveform.path" : "waveform.path.ecg")
                    }
                    .help("Toggle Automation View")
                }
            }

            if let block = localSelectedBlock ?? selectedBlock {
                HStack {
                    Circle()
                        .fill(block.type.category.color)
                        .frame(width: 8, height: 8)

                    Text(block.title)
                        .font(.subheadline.bold())

                    Spacer()

                    Text(block.type.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Parameter Controls Content

    private func parameterControlsContent(for block: SignalBlock) -> some View {
        LazyVStack(spacing: 16) {
            ForEach(Array(block.parameters.keys.sorted()), id: \.self) { parameterName in
                if let parameter = block.parameters[parameterName] {
                    ParameterControlRow(
                        parameter: parameter,
                        blockId: block.id,
                        blockManager: blockManager,
                        showingAutomation: showingAutomation,
                        history: parameterHistory[parameterName] ?? []
                    )
                    .onAppear {
                        initializeParameterHistory(parameterName: parameterName, initialValue: parameter.value)
                    }
                }
            }

            // Block-specific controls
            blockSpecificControls(for: block)
        }
        .padding()
    }

    // MARK: - No Selection View

    private var noSelectionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Block Selected")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("Select a block on the canvas to adjust its parameters")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Block-Specific Controls

    private func blockSpecificControls(for block: SignalBlock) -> some View {
        Group {
            switch block.type {
            case .sineOscillator:
                sineOscillatorControls(for: block)
            case .triangleOscillator:
                triangleOscillatorControls(for: block)
            case .frequencyModulator:
                frequencyModulatorControls(for: block)
            case .spectrumAnalyzer:
                spectrumAnalyzerControls(for: block)
            case .whiteNoise:
                whiteNoiseControls(for: block)
            case .audioOutput:
                audioOutputControls(for: block)
            case .squareOscillator, .sawtoothOscillator:
                sineOscillatorControls(for: block) // Use same controls as sine
            case .pinkNoise:
                whiteNoiseControls(for: block) // Use same controls as white noise
            case .linearChirp, .hyperbolicChirp:
                chirpControls(for: block)
            case .amplitudeModulator, .ringModulator:
                modulatorControls(for: block)
            case .lowPassFilter, .highPassFilter, .bandPassFilter:
                filterControls(for: block)
            case .mixer, .amplifier:
                Text("Processing controls not implemented")
            case .levelMeter, .frequencyCounter:
                meterControls(for: block)
            }
        }
    }

    private func sineOscillatorControls(for block: SignalBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sine Oscillator Settings")
                .font(.subheadline.bold())

            HStack {
                Text("Waveform Quality:")
                Spacer()
                Text("High Precision")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            Button("Reset Phase") {
                // Reset oscillator phase
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private func triangleOscillatorControls(for block: SignalBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Triangle Oscillator Settings")
                .font(.subheadline.bold())

            HStack {
                Text("Modulation Quality:")
                Spacer()
                Text("Optimized")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private func frequencyModulatorControls(for block: SignalBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FM Settings")
                .font(.subheadline.bold())

            Button("Validate Specification") {
                // Validate 10kHz ±3kHz specification
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private func spectrumAnalyzerControls(for block: SignalBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spectrum Analyzer Settings")
                .font(.subheadline.bold())

            Button("Reset Analysis") {
                // Reset spectrum analyzer
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private func whiteNoiseControls(for block: SignalBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Noise Generator Settings")
                .font(.subheadline.bold())

            Button("Reseed Generator") {
                // Reseed random number generator
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    private func audioOutputControls(for block: SignalBlock) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Output Settings")
                .font(.subheadline.bold())

            HStack {
                Text("Output Device:")
                    .font(.subheadline)

                Spacer()

                Menu {
                    ForEach(availableDevices, id: \.id) { device in
                        Button(device.displayName) {
                            selectOutputDevice(device)
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedOutputDevice?.displayName ?? "Default")
                            .foregroundColor(.primary)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.borderless)
            }

            if let device = selectedOutputDevice {
                HStack {
                    Circle()
                        .fill(device.isAvailable ? .green : .red)
                        .frame(width: 6, height: 6)

                    Text(device.isAvailable ? "Available" : "Unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if device.isBluetoothDevice {
                        Image(systemName: "bluetooth")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Helper Methods

    private func initializeParameterHistory(parameterName: String, initialValue: Double) {
        if parameterHistory[parameterName] == nil {
            parameterHistory[parameterName] = [initialValue]
        }
    }

    public func selectBlock(_ block: SignalBlock?) {
        localSelectedBlock = block
    }

    // MARK: - Device Management

    private func loadAvailableDevices() {
        // Load devices from block manager or use default set
        availableDevices = [
            OutputDevice(
                id: "default",
                name: "Default Output",
                isDefault: true,
                isAvailable: true
            ),
            OutputDevice(
                id: "builtin",
                name: "MacBook Pro Speakers",
                isDefault: false,
                isAvailable: true
            ),
            OutputDevice(
                id: "bluetooth1",
                name: "AirPods Pro",
                isDefault: false,
                isAvailable: true
            ),
            OutputDevice(
                id: "bluetooth2",
                name: "Sony WH-1000XM4",
                isDefault: false,
                isAvailable: true
            )
        ]

        // Set initial selection to default device
        if selectedOutputDevice == nil {
            selectedOutputDevice = availableDevices.first { $0.isDefault }
        }
    }

    private func selectOutputDevice(_ device: OutputDevice) {
        selectedOutputDevice = device

        // Update block manager with selected device
        Task {
            do {
                try await blockManager.setOutputDevice(device)
            } catch {
                print("Failed to set output device: \(error)")
            }
        }
    }

    // MARK: - Helper Functions

    private func generateMockHistory() -> [Double] {
        (0..<50).map { _ in Double.random(in: -60...0) }
    }

    // MARK: - Chirp Controls

    private func chirpControls(for block: SignalBlock) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(["startFrequency", "endFrequency", "duration"], id: \.self) { paramName in
                if let param = block.parameters[paramName] {
                    ParameterControlRow(
                        parameter: param,
                        blockId: block.id,
                        blockManager: blockManager,
                        showingAutomation: showingAutomation,
                        history: generateMockHistory()
                    )
                }
            }

            // Add sweep type picker
            VStack(alignment: .leading) {
                Text("Sweep Type").font(.caption).foregroundColor(.secondary)
                Picker("Sweep", selection: .constant("linear")) {
                    Text("Linear").tag("linear")
                    Text("Logarithmic").tag("log")
                    Text("Exponential").tag("exp")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Modulator Controls

    private func modulatorControls(for block: SignalBlock) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(["modulationDepth", "modulationRate", "carrierFrequency"], id: \.self) { paramName in
                if let param = block.parameters[paramName] {
                    ParameterControlRow(
                        parameter: param,
                        blockId: block.id,
                        blockManager: blockManager,
                        showingAutomation: showingAutomation,
                        history: generateMockHistory()
                    )
                }
            }

            // Add waveform selector for modulator
            VStack(alignment: .leading) {
                Text("Modulation Waveform").font(.caption).foregroundColor(.secondary)
                Picker("Waveform", selection: .constant("sine")) {
                    Text("Sine").tag("sine")
                    Text("Triangle").tag("triangle")
                    Text("Square").tag("square")
                    Text("Sawtooth").tag("sawtooth")
                }
                .pickerStyle(.menu)
            }
        }
    }

    // MARK: - Filter Controls

    private func filterControls(for block: SignalBlock) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(["cutoffFrequency", "resonance", "gain"], id: \.self) { paramName in
                if let param = block.parameters[paramName] {
                    ParameterControlRow(
                        parameter: param,
                        blockId: block.id,
                        blockManager: blockManager,
                        showingAutomation: showingAutomation,
                        history: generateMockHistory()
                    )
                }
            }

            // Add filter type selector
            if block.type == .bandPassFilter {
                ForEach(["bandwidth", "centerFrequency"], id: \.self) { paramName in
                    if let param = block.parameters[paramName] {
                        ParameterControlRow(
                            parameter: param,
                            blockId: block.id,
                            blockManager: blockManager,
                            showingAutomation: showingAutomation,
                            history: generateMockHistory()
                        )
                    }
                }
            }

            // Frequency response visualization
            FilterResponseView()
                .frame(height: 100)
                .padding(.top, 8)
        }
    }

    // MARK: - Meter Controls

    private func meterControls(for block: SignalBlock) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(["integrationTime", "scale", "range"], id: \.self) { paramName in
                if let param = block.parameters[paramName] {
                    ParameterControlRow(
                        parameter: param,
                        blockId: block.id,
                        blockManager: blockManager,
                        showingAutomation: showingAutomation,
                        history: generateMockHistory()
                    )
                }
            }

            // Display type selector
            VStack(alignment: .leading) {
                Text("Display Mode").font(.caption).foregroundColor(.secondary)
                Picker("Mode", selection: .constant("peak")) {
                    Text("Peak").tag("peak")
                    Text("RMS").tag("rms")
                    Text("Peak + RMS").tag("both")
                    Text("Average").tag("average")
                }
                .pickerStyle(.menu)
            }

            // Real-time meter display
            MeterDisplayView()
                .frame(height: 60)
                .padding(.top, 8)
        }
    }
}

// MARK: - Support Views

struct FilterResponseView: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height

                // Draw frequency response curve
                path.move(to: CGPoint(x: 0, y: height * 0.8))
                path.addCurve(
                    to: CGPoint(x: width, y: height * 0.2),
                    control1: CGPoint(x: width * 0.3, y: height * 0.1),
                    control2: CGPoint(x: width * 0.7, y: height * 0.1)
                )
            }
            .stroke(Color.accentColor, lineWidth: 2)
            .background(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.2), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .overlay(
            VStack {
                HStack {
                    Text("20Hz").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Text("20kHz").font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(4)
        )
    }
}

struct MeterDisplayView: View {
    @State private var currentLevel: Double = -20
    @State private var peakLevel: Double = -12

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))

                // Level bar
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .orange, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat((currentLevel + 60) / 66))

                // Peak indicator
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .offset(x: geometry.size.width * CGFloat((peakLevel + 60) / 66))
            }
        }
        .onAppear {
            // Simulate level changes
            Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.1)) {
                    currentLevel = Double.random(in: -40...0)
                    if currentLevel > peakLevel {
                        peakLevel = currentLevel
                    }
                }
            }
        }
    }
}

// MARK: - Parameter Control Row

struct ParameterControlRow: View {
    let parameter: BlockParameter
    let blockId: UUID
    @ObservedObject var blockManager: BlockManagerServiceImpl
    let showingAutomation: Bool
    let history: [Double]

    @State private var currentValue: Double
    @State private var isEditing: Bool = false
    @State private var textValue: String = ""
    @State private var isAnimating: Bool = false

    init(parameter: BlockParameter, blockId: UUID, blockManager: BlockManagerServiceImpl, showingAutomation: Bool, history: [Double]) {
        self.parameter = parameter
        self.blockId = blockId
        self.blockManager = blockManager
        self.showingAutomation = showingAutomation
        self.history = history
        self._currentValue = State(initialValue: parameter.value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Parameter header
            parameterHeader

            // Control based on parameter type
            parameterControl

            // Automation view
            if showingAutomation {
                automationView
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isAnimating ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        )
        .animation(.easeInOut(duration: 0.3), value: isAnimating)
        .onChange(of: parameter.value) { _, newValue in
            if !isEditing {
                currentValue = newValue
                animateValueChange()
            }
        }
    }

    // MARK: - Parameter Header

    private var parameterHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(parameter.displayName)
                    .font(.subheadline.bold())

                Text(formatValue(currentValue))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Precise value entry
            Button(action: { startTextEditing() }) {
                Image(systemName: "textformat.123")
            }
            .buttonStyle(.borderless)
            .help("Enter Precise Value")
        }
    }

    // MARK: - Parameter Control

    private var parameterControl: some View {
        Group {
            switch parameter.controlType {
            case .slider:
                sliderControl
            case .knob:
                knobControl
            case .toggle:
                toggleControl
            case .picker:
                pickerControl
            }
        }
    }

    private var sliderControl: some View {
        VStack(spacing: 4) {
            HStack {
                Text(formatValue(parameter.minimumValue))
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text(formatValue(parameter.maximumValue))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Slider(
                value: $currentValue,
                in: parameter.minimumValue...parameter.maximumValue,
                step: parameter.stepSize
            ) { editing in
                isEditing = editing
                if !editing {
                    updateParameter()
                }
            }
            .accentColor(parameterColor)
        }
    }

    private var knobControl: some View {
        HStack {
            Spacer()

            KnobControl(
                value: $currentValue,
                range: parameter.minimumValue...parameter.maximumValue,
                step: parameter.stepSize,
                color: parameterColor
            ) { editing in
                isEditing = editing
                if !editing {
                    updateParameter()
                }
            }

            Spacer()
        }
    }

    private var toggleControl: some View {
        HStack {
            Spacer()

            Toggle(isOn: Binding(
                get: { currentValue > 0.5 },
                set: { newValue in
                    currentValue = newValue ? 1.0 : 0.0
                    updateParameter()
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.switch)

            Spacer()
        }
    }

    private var pickerControl: some View {
        Picker(parameter.displayName, selection: $currentValue) {
            ForEach(parameterOptions, id: \.value) { option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: currentValue) { _ in
            updateParameter()
        }
    }

    // MARK: - Automation View

    private var automationView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Automation")
                .font(.caption.bold())

            // History graph
            automationGraph

            // Automation controls
            HStack {
                Button("Record") {
                    // Start automation recording
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Clear") {
                    // Clear automation
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
        }
        .padding(8)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(6)
    }

    private var automationGraph: some View {
        Canvas { context, size in
            guard !history.isEmpty else { return }

            let path: Path = Path { path in
                for (index, value) in history.enumerated() {
                    let xPosition: CGFloat = CGFloat(index) / CGFloat(history.count - 1) * size.width
                    let normalizedValue: Double = (value - parameter.minimumValue) / (parameter.maximumValue - parameter.minimumValue)
                    let yPosition: CGFloat = size.height - CGFloat(normalizedValue) * size.height

                    if index == 0 {
                        path.move(to: CGPoint(x: xPosition, y: yPosition))
                    } else {
                        path.addLine(to: CGPoint(x: xPosition, y: yPosition))
                    }
                }
            }

            context.stroke(path, with: .color(parameterColor), lineWidth: 2)
        }
        .frame(height: 60)
        .background(Color.black.opacity(0.1))
        .cornerRadius(4)
    }

    // MARK: - Computed Properties

    private var parameterColor: Color {
        switch parameter.name {
        case "frequency": return .blue
        case "amplitude": return .orange
        case "phase": return .purple
        case "gain": return .green
        default: return .accentColor
        }
    }

    private var parameterOptions: [(label: String, value: Double)] {
        // Return options for picker controls
        return [
            ("Low", parameter.minimumValue),
            ("Medium", (parameter.minimumValue + parameter.maximumValue) / 2),
            ("High", parameter.maximumValue)
        ]
    }

    // MARK: - Helper Methods

    private func formatValue(_ value: Double) -> String {
        let formatter: NumberFormatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0

        let formattedValue: String = formatter.string(from: NSNumber(value: value)) ?? "\(value)"

        if !parameter.unit.isEmpty {
            return "\(formattedValue) \(parameter.unit)"
        }
        return formattedValue
    }

    private func updateParameter() {
        blockManager.updateParameter(
            blockId: blockId,
            parameterName: parameter.name,
            value: currentValue
        )
    }

    private func startTextEditing() {
        textValue = String(currentValue)
        isEditing = true
        // Show text input dialog
    }

    private func animateValueChange() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isAnimating = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isAnimating = false
            }
        }
    }
}

// MARK: - Knob Control

struct KnobControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let color: Color
    let onEditingChanged: (Bool) -> Void

    @State private var isDragging: Bool = false
    @State private var lastDragValue: CGFloat = 0

    private let knobSize: CGFloat = 60

    var body: some View {
        ZStack {
            // Knob background
            Circle()
                .fill(Color(NSColor.controlBackgroundColor))
                .frame(width: knobSize, height: knobSize)
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                )

            // Value arc
            Circle()
                .trim(from: 0, to: normalizedValue)
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: knobSize - 8, height: knobSize - 8)
                .rotationEffect(.degrees(-90))

            // Knob indicator
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .offset(y: -(knobSize / 2 - 12))
                .rotationEffect(.degrees(indicatorAngle))

            // Center dot
            Circle()
                .fill(Color.primary.opacity(0.3))
                .frame(width: 4, height: 4)
        }
        .scaleEffect(isDragging ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isDragging)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if !isDragging {
                        isDragging = true
                        onEditingChanged(true)
                    }

                    let delta: CGFloat = gesture.translation.height - lastDragValue
                    let sensitivity: CGFloat = 2.0
                    let change: CGFloat = -delta / sensitivity

                    let newValue: Double = value + Double(change) * step
                    value = min(max(newValue, range.lowerBound), range.upperBound)

                    lastDragValue = gesture.translation.height
                }
                .onEnded { _ in
                    isDragging = false
                    lastDragValue = 0
                    onEditingChanged(false)
                }
        )
    }

    private var normalizedValue: CGFloat {
        CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }

    private var indicatorAngle: Double {
        let range: Double = 270.0 // Total rotation range in degrees
        return Double(normalizedValue) * range - 135.0 // Start at -135 degrees
    }
}

extension BlockParameter {
    var controlType: ParameterControlType {
        switch unit {
        case "Hz": return .knob
        case "dB": return .slider
        case "%": return .slider
        case "": return name.contains("enable") || name.contains("mute") ? .toggle : .slider
        default: return .slider
        }
    }
}

enum ParameterControlType {
    case slider
    case knob
    case toggle
    case picker
}

#Preview {
    let sampleBlock: SignalBlock = SignalBlock(
        type: .sineOscillator,
        title: "Sine Wave",
        position: CGPoint(x: 100, y: 100),
        parameters: [
            "frequency": BlockParameter.frequency(value: 440.0),
            "amplitude": BlockParameter.amplitude(value: -12.0),
            "phase": BlockParameter(
                name: "phase",
                displayName: "Phase",
                value: 0.0,
                minimumValue: 0.0,
                maximumValue: 360.0,
                unit: "°",
                stepSize: 1.0
            )
        ],
        inputPorts: [InputPort(name: "frequency", displayName: "Frequency", signalType: .frequency, isRequired: false, defaultValue: nil)],
        outputPorts: [OutputPort(name: "signal", displayName: "Signal", signalType: .audio, isRequired: false, defaultValue: nil)]
    )

    ParameterControlsView(
        blockManager: BlockManagerServiceImpl(audioService: AudioBlockServiceImpl()),
        selectedBlock: sampleBlock
    )
        .onAppear {
            // Simulate block selection
        }
        .frame(width: 300, height: 500)
}

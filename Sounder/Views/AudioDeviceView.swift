import SwiftUI
import AVFoundation

/// Audio device management view with Bluetooth isolation support
/// Provides device selection, monitoring, and isolation validation
struct AudioDeviceView: View {
    @ObservedObject var blockManager: BlockManagerServiceImpl
    @State private var availableDevices: [OutputDevice] = []
    @State private var selectedDevice: OutputDevice?
    @State private var isRefreshingDevices = false
    @State private var showingDeviceDetails = false
    @State private var deviceMonitoring = false
    @State private var isolationStatus: BluetoothIsolationStatus = .unknown

    // Monitoring state
    @State private var refreshTimer: Timer?
    @State private var deviceSwitchCount = 0
    @State private var lastSwitchTime: Date?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            deviceHeader

            // Device list
            deviceListView

            // Isolation status
            isolationStatusView

            // Device controls
            deviceControlsView
        }
        .frame(minWidth: 300)
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            refreshDevices()
            startDeviceMonitoring()
        }
        .onDisappear {
            stopDeviceMonitoring()
        }
        .sheet(isPresented: $showingDeviceDetails) {
            if let device = selectedDevice {
                DeviceDetailView(device: device)
            }
        }
    }

    // MARK: - Device Header

    private var deviceHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Audio Devices")
                    .font(.headline)

                Spacer()

                Button(action: refreshDevices) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshingDevices ? 360 : 0))
                        .animation(
                            isRefreshingDevices ?
                                .linear(duration: 1).repeatForever(autoreverses: false) :
                                .default,
                            value: isRefreshingDevices
                        )
                }
                .buttonStyle(.borderless)
                .help("Refresh Devices")
            }

            if let device = selectedDevice {
                HStack {
                    Circle()
                        .fill(device.isBluetoothDevice ? .blue : .green)
                        .frame(width: 8, height: 8)

                    Text(device.displayName)
                        .font(.subheadline.bold())
                        .lineLimit(1)

                    Spacer()

                    if device.isBluetoothDevice {
                        Image(systemName: "bluetooth")
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Device List

    private var deviceListView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(availableDevices, id: \.id) { device in
                    DeviceRow(
                        device: device,
                        isSelected: selectedDevice?.id == device.id,
                        onSelect: { selectDevice(device) },
                        onShowDetails: {
                            selectedDevice = device
                            showingDeviceDetails = true
                        }
                    )
                }

                if availableDevices.isEmpty && !isRefreshingDevices {
                    noDevicesView
                }
            }
            .padding()
        }
    }

    private var noDevicesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)

            Text("No Audio Devices Found")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Check that audio devices are connected and try refreshing")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Refresh") {
                refreshDevices()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Isolation Status

    private var isolationStatusView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bluetooth Isolation")
                    .font(.subheadline.bold())

                Spacer()

                isolationStatusIndicator
            }

            isolationStatusDetails

            if isolationStatus != .optimal {
                isolationRecommendations
            }
        }
        .padding()
        .background(isolationBackgroundColor)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.3)),
            alignment: .top
        )
    }

    private var isolationStatusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isolationStatusColor)
                .frame(width: 8, height: 8)

            Text(isolationStatus.displayName)
                .font(.caption.bold())
                .foregroundColor(isolationStatusColor)
        }
    }

    private var isolationStatusDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("System Audio Impact:")
                Spacer()
                Text(systemAudioImpact)
                    .font(.caption)
                    .foregroundColor(systemAudioImpactColor)
            }

            HStack {
                Text("Device Switches:")
                Spacer()
                Text("\(deviceSwitchCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let lastSwitch = lastSwitchTime {
                HStack {
                    Text("Last Switch:")
                    Spacer()
                    Text(RelativeDateTimeFormatter().localizedString(for: lastSwitch, relativeTo: Date()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var isolationRecommendations: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recommendations:")
                .font(.caption.bold())

            ForEach(isolationRecommendationsList, id: \.self) { recommendation in
                HStack(alignment: .top, spacing: 6) {
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(recommendation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Device Controls

    private var deviceControlsView: some View {
        VStack(spacing: 12) {
            // Quick actions
            HStack {
                Button("Default Device") {
                    selectDefaultDevice()
                }
                .buttonStyle(.bordered)

                Button("Bluetooth Only") {
                    selectBluetoothDevice()
                }
                .buttonStyle(.bordered)
                .disabled(!hasBluetoothDevices)
            }

            // Monitoring toggle
            HStack {
                Toggle("Monitor Device Changes", isOn: $deviceMonitoring)
                    .onChange(of: deviceMonitoring) { enabled in
                        if enabled {
                            startDeviceMonitoring()
                        } else {
                            stopDeviceMonitoring()
                        }
                    }

                Spacer()
            }

            // Advanced settings
            DisclosureGroup("Advanced Settings") {
                advancedSettings
            }
            .padding(.top)
        }
        .padding()
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Auto-select Bluetooth:")
                Spacer()
                Toggle("", isOn: .constant(false))
                    .toggleStyle(.switch)
            }

            HStack {
                Text("Isolation Alerts:")
                Spacer()
                Toggle("", isOn: .constant(true))
                    .toggleStyle(.switch)
            }

            Button("Reset Device Preferences") {
                resetDevicePreferences()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Computed Properties

    private var isolationBackgroundColor: Color {
        switch isolationStatus {
        case .optimal: return Color.green.opacity(0.1)
        case .good: return Color.yellow.opacity(0.1)
        case .poor: return Color.orange.opacity(0.1)
        case .none: return Color.red.opacity(0.1)
        case .unknown: return Color.gray.opacity(0.1)
        }
    }

    private var isolationStatusColor: Color {
        switch isolationStatus {
        case .optimal: return .green
        case .good: return .yellow
        case .poor: return .orange
        case .none: return .red
        case .unknown: return .gray
        }
    }

    private var systemAudioImpact: String {
        guard let device = selectedDevice else { return "Unknown" }

        if device.isDefault {
            return "High - Affects system audio"
        } else if device.isBluetoothDevice {
            return "Low - Isolated from system"
        } else {
            return "Medium - May affect system"
        }
    }

    private var systemAudioImpactColor: Color {
        guard let device = selectedDevice else { return .gray }

        if device.isDefault {
            return .red
        } else if device.isBluetoothDevice {
            return .green
        } else {
            return .orange
        }
    }

    private var isolationRecommendationsList: [String] {
        switch isolationStatus {
        case .optimal:
            return []
        case .good:
            return ["Consider using a dedicated Bluetooth device for better isolation"]
        case .poor:
            return [
                "Switch to a Bluetooth audio device",
                "Avoid using the default system output"
            ]
        case .none:
            return [
                "Connect a Bluetooth audio device",
                "Select a non-default output device",
                "System audio will be affected by this configuration"
            ]
        case .unknown:
            return ["Select an audio device to check isolation status"]
        }
    }

    private var hasBluetoothDevices: Bool {
        availableDevices.contains { $0.isBluetoothDevice }
    }

    // MARK: - Helper Methods

    private func refreshDevices() {
        isRefreshingDevices = true

        // Simulate device discovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
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
                    isAvailable: true,
                ),
                OutputDevice(
                    id: "bluetooth2",
                    name: "Sony WH-1000XM4",
                    isDefault: false,
                    isAvailable: true,
                )
            ]

            // Set initial selection
            if selectedDevice == nil {
                selectedDevice = availableDevices.first { $0.isDefault }
            }

            updateIsolationStatus()
            isRefreshingDevices = false
        }
    }

    private func selectDevice(_ device: OutputDevice) {
        guard device.isAvailable else { return }

        let previousDevice = selectedDevice
        selectedDevice = device

        // Update block manager with selected device
        Task {
            do {
                try await blockManager.setOutputDevice(device)
            } catch {
                print("Failed to set output device: \(error)")
            }
        }

        // Record device switch
        if previousDevice?.id != device.id {
            deviceSwitchCount += 1
            lastSwitchTime = Date()
        }

        updateIsolationStatus()
    }

    private func selectDefaultDevice() {
        if let defaultDevice = availableDevices.first(where: { $0.isDefault }) {
            selectDevice(defaultDevice)
        }
    }

    private func selectBluetoothDevice() {
        if let bluetoothDevice = availableDevices.first(where: { $0.isBluetoothDevice && $0.isAvailable }) {
            selectDevice(bluetoothDevice)
        }
    }

    private func updateIsolationStatus() {
        guard let device = selectedDevice else {
            isolationStatus = .unknown
            return
        }

        if device.isBluetoothDevice && !device.isDefault {
            isolationStatus = .optimal
        } else if !device.isDefault {
            isolationStatus = .good
        } else if device.isBluetoothDevice {
            isolationStatus = .poor
        } else {
            isolationStatus = .none
        }
    }

    private func startDeviceMonitoring() {
        deviceMonitoring = true
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            // Check for device changes
            refreshDevices()
        }
    }

    private func stopDeviceMonitoring() {
        deviceMonitoring = false
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func resetDevicePreferences() {
        deviceSwitchCount = 0
        lastSwitchTime = nil
        selectDefaultDevice()
    }
}

// MARK: - Device Row

struct DeviceRow: View {
    let device: OutputDevice
    let isSelected: Bool
    let onSelect: () -> Void
    let onShowDetails: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Device icon
            deviceIcon

            // Device info
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)

                HStack {
                    if device.isDefault {
                        Text("Default")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }

                    if device.isBluetoothDevice {
                        Text("Bluetooth")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(4)
                    }

                    Spacer()

                    deviceStatusIndicator
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                Button(action: onShowDetails) {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .opacity(isHovered ? 1 : 0.5)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Button(action: onSelect) {
                        Image(systemName: "circle")
                    }
                    .buttonStyle(.borderless)
                    .opacity(isHovered ? 1 : 0.3)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected ? Color.accentColor :
                            isHovered ? Color.gray.opacity(0.5) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private var deviceIcon: some View {
        ZStack {
            Circle()
                .fill(device.isAvailable ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                .frame(width: 40, height: 40)

            Image(systemName: deviceIconName)
                .font(.title3)
                .foregroundColor(device.isAvailable ? .primary : .secondary)
        }
    }

    private var deviceIconName: String {
        if device.isBluetoothDevice {
            return "headphones"
        } else if device.name.lowercased().contains("speaker") {
            return "speaker.2"
        } else {
            return "speaker.wave.2"
        }
    }

    private var deviceStatusIndicator: some View {
        Circle()
            .fill(device.isAvailable ? Color.green : Color.red)
            .frame(width: 6, height: 6)
    }
}

// MARK: - Device Detail View

struct DeviceDetailView: View {
    let device: OutputDevice
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Device Details")
                    .font(.title2.bold())

                Spacer()

                Button("Close") {
                    dismiss()
                }
            }

            // Device info
            VStack(alignment: .leading, spacing: 12) {
                DetailRow(label: "Name", value: device.name)
                DetailRow(label: "Type", value: device.isBluetoothDevice ? "Bluetooth" : "Wired")
                DetailRow(label: "Status", value: device.isAvailable ? "Available" : "Unavailable")
                DetailRow(label: "Default", value: device.isDefault ? "Yes" : "No")

                if device.isBluetoothDevice {
                    DetailRow(label: "Isolation", value: "Optimal")
                    DetailRow(label: "Latency", value: "~40ms")
                }
            }

            Spacer()
        }
        .padding()
        .frame(width: 300, height: 250)
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label + ":")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline.bold())
        }
    }
}

// MARK: - Supporting Types

enum BluetoothIsolationStatus: String, CaseIterable {
    case optimal
    case good
    case poor
    case none
    case unknown

    var displayName: String {
        switch self {
        case .optimal: return "Optimal"
        case .good: return "Good"
        case .poor: return "Poor"
        case .none: return "None"
        case .unknown: return "Unknown"
        }
    }
}

#Preview {
    AudioDeviceView(blockManager: BlockManagerServiceImpl(audioService: MockAudioBlockService()))
        .frame(width: 350, height: 600)
}

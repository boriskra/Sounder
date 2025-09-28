import Foundation
import Combine

class MockAudioService: AudioService, ObservableObject {
    // MARK: - AudioService Protocol Properties
    var availableSoundsPublisher: AnyPublisher<[Sound], Never> {
        return _availableSoundsSubject.eraseToAnyPublisher()
    }
    private let _availableSoundsSubject = CurrentValueSubject<[Sound], Never>([
        Sound(name: "Mock Sine", waveform: .sine),
        Sound(name: "Mock Square", waveform: .square)
    ])

    var availableOutputDevicesPublisher: AnyPublisher<[OutputDevice], Never> {
        return _availableOutputDevicesSubject.eraseToAnyPublisher()
    }
    private let _availableOutputDevicesSubject = CurrentValueSubject<[OutputDevice], Never>([
        OutputDevice(id: 1, name: "Mock Built-in Output", isDefault: true, isAvailable: true),
        OutputDevice(id: 2, name: "Mock External Headphones", isDefault: false, isAvailable: true)
    ])

    @Published var currentOutputDevice: OutputDevice?

    @Published var currentSound: Sound?

    var spectrum: AnyPublisher<[Float], Never> {
        return _spectrumSubject.eraseToAnyPublisher()
    }
    private let _spectrumSubject = PassthroughSubject<[Float], Never>()

    // MARK: - Internal Properties
    private var isPlaying: Bool = false
    private var spectrumTimer: Timer? // Keep track of the timer

    init() {
        // Set initial values for currentOutputDevice and currentSound
        currentOutputDevice = _availableOutputDevicesSubject.value.first
        currentSound = _availableSoundsSubject.value.first
    }

    // MARK: - AudioService Protocol Methods
    func play() throws {
        guard currentSound != nil else { throw AudioServiceError.soundNotSet }
        guard currentOutputDevice != nil else { throw AudioServiceError.outputDeviceNotSet }

        isPlaying = true
        // Simulate spectrum data
        spectrumTimer?.invalidate() // Invalidate any existing timer
        spectrumTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if self.isPlaying {
                let spectrumData = (0..<128).map { _ in Float.random(in: 0...1) }
                self._spectrumSubject.send(spectrumData)
            } else {
                timer.invalidate()
            }
        }
    }

    func stop() {
        isPlaying = false
        spectrumTimer?.invalidate() // Stop the timer when playback stops
    }
}

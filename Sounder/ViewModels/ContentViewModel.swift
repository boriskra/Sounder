import Foundation
import Combine

class ContentViewModel: ObservableObject {
    @Published var sounds: [Sound] = []
    @Published var selectedSound: Sound? {
        didSet {
            audioService.currentSound = selectedSound
        }
    }
    @Published var devices: [OutputDevice] = []
    @Published var selectedDevice: OutputDevice? {
        didSet {
            audioService.currentOutputDevice = selectedDevice
        }
    }
    @Published var spectrum: [Float] = []
    @Published var errorMessage: String?

    private var audioService: AudioService
    private var cancellables: Set<AnyCancellable> = Set<AnyCancellable>()

    init(audioService: AudioService = AVFAudioService()) {
        self.audioService = audioService

        // Subscribe to available sounds
        audioService.availableSoundsPublisher
            .sink { [weak self] newSounds in
                self?.sounds = newSounds
                if self?.selectedSound == nil {
                    self?.selectedSound = newSounds.first
                }
            }
            .store(in: &cancellables)

        // Subscribe to available output devices
        audioService.availableOutputDevicesPublisher
            .sink { [weak self] newDevices in
                self?.devices = newDevices
                if self?.selectedDevice == nil {
                    self?.selectedDevice = newDevices.first
                }
            }
            .store(in: &cancellables)

        // Subscribe to spectrum data
        audioService.spectrum
            .sink { [weak self] spectrum in
                self?.spectrum = spectrum
            }
            .store(in: &cancellables)
    }

    func play() {
        errorMessage = nil // Clear previous errors
        do {
            try audioService.play()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        audioService.stop()
    }
}

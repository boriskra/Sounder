import Combine

protocol AudioService {
    /// The currently available audio output devices.
    var availableSoundsPublisher: AnyPublisher<[Sound], Never> { get }
    var availableOutputDevicesPublisher: AnyPublisher<[OutputDevice], Never> { get }

    /// The currently selected audio output device.
    var currentOutputDevice: OutputDevice? { get set }

    /// The currently selected sound.
    var currentSound: Sound? { get set }

    /// Starts playing the current sound.
    func play() throws

    /// Stops playing the current sound.
    func stop()

    /// A publisher that emits the current audio spectrum.
    var spectrum: AnyPublisher<[Float], Never> { get }
}

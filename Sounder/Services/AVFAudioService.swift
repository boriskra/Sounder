import Foundation
import AVFoundation
import Combine
import CoreAudio
import AudioToolbox
import Accelerate

enum AudioServiceError: Error {
    case soundNotSet
    case outputDeviceNotSet
    case audioEngineError(Error)
    case deviceEnumerationFailed
}

class AVFAudioService: AudioService, ObservableObject {
    // MARK: - AudioService Protocol Properties
    var availableSoundsPublisher: AnyPublisher<[Sound], Never> {
        return _availableSoundsSubject.eraseToAnyPublisher()
    }
    private let _availableSoundsSubject = CurrentValueSubject<[Sound], Never>([])

    var availableOutputDevicesPublisher: AnyPublisher<[OutputDevice], Never> {
        return _availableOutputDevicesSubject.eraseToAnyPublisher()
    }
    private let _availableOutputDevicesSubject = CurrentValueSubject<[OutputDevice], Never>([])

    @Published var currentOutputDevice: OutputDevice? {
        didSet {
            if let device = currentOutputDevice {
                setEngineOutputDevice(device)
            }
        }
    }

    @Published var currentSound: Sound?

    var spectrum: AnyPublisher<[Float], Never> {
        return _spectrumSubject.eraseToAnyPublisher()
    }
    private let _spectrumSubject = PassthroughSubject<[Float], Never>()

    // MARK: - Internal Properties
    private var engine: AVAudioEngine!
    private var sourceNode: AVAudioSourceNode!
    private var time = 0.0
    private let sampleRate = 44100.0
    private let fftSize = 1024
    private var fftSetup: FFTSetup!
    private var cancellables = Set<AnyCancellable>()

    init() {
        engine = AVAudioEngine()
        let mainMixer = engine.mainMixerNode
        let output = engine.outputNode
        let format = output.inputFormat(forBus: 0)

        fftSetup = vDSP_create_fftsetup(vDSP_Length(log2(Float(fftSize))), FFTRadix(kFFTRadix2))!

        sourceNode = AVAudioSourceNode(format: format, renderBlock: { (isSilence, timestamp, frameCount, audioBufferList) -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sample = self.generateSample(at: self.time)
                self.time += 1 / self.sampleRate
                for buffer in ablPointer {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    buf[frame] = sample
                }
            }
            return noErr
        })

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: mainMixer, format: format)
        engine.connect(mainMixer, to: output, format: format)
        mainMixer.outputVolume = 0.5

        mainMixer.installTap(onBus: 0, bufferSize: AVAudioFrameCount(fftSize), format: format) { (buffer, time) in
            self.calculateSpectrum(buffer: buffer)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(audioEngineConfigurationChange(_:)), name: .AVAudioEngineConfigurationChange, object: engine)

        // Initial population of available devices and sounds
        _availableOutputDevicesSubject.send(enumerateOutputDevices())
        _availableSoundsSubject.send([
            Sound(
                name: "Sine Wave",
                waveform: .sine,
                parameters: [Parameter(name: "frequency", value: 440.0)]
            )
        ])

        // Set initial currentOutputDevice and currentSound
        currentOutputDevice = _availableOutputDevicesSubject.value.first
        currentSound = _availableSoundsSubject.value.first
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - AudioService Protocol Methods
    func play() throws {
        guard let sound = currentSound else { throw AudioServiceError.soundNotSet }
        guard currentOutputDevice != nil else { throw AudioServiceError.outputDeviceNotSet }

        self.time = 0.0 // Reset time for new playback
        do {
            try engine.start()
        } catch {
            throw AudioServiceError.audioEngineError(error)
        }
    }

    func stop() {
        engine.stop()
    }

    // MARK: - Internal Helper Methods
    private func enumerateOutputDevices() -> [OutputDevice] {
        var devices = [OutputDevice]()
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMaster
        )

        var propertySize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize)
        if status != noErr {
            print("Failed to get audio devices size: \(status)")
            return devices
        }

        let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        let deviceIDs = UnsafeMutablePointer<AudioDeviceID>.allocate(capacity: deviceCount)
        defer {
            deviceIDs.deallocate()
        }

        status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, deviceIDs)
        if status != noErr {
            print("Failed to get audio devices: \(status)")
            return devices
        }

        for index in 0..<deviceCount {
            let deviceID = deviceIDs[index]
            var propertyAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var propertySize: UInt32 = 256
            let deviceName = UnsafeMutablePointer<CChar>.allocate(capacity: Int(propertySize))
            defer {
                deviceName.deallocate()
            }

            let status3 = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, deviceName)
            if status3 == noErr {
                let name = String(cString: deviceName)
                devices.append(OutputDevice(id: String(deviceID), name: name, isDefault: false, isAvailable: true))
            }
        }

        return devices
    }

    private func setEngineOutputDevice(_ device: OutputDevice) {
        guard let deviceIDValue = UInt32(device.id) else {
            print("Invalid audio device identifier: \(device.id)")
            return
        }

        let wasRunning = engine.isRunning
        if wasRunning {
            engine.stop()
        }

        var audioDeviceID = AudioDeviceID(deviceIDValue)
        let propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let audioUnit = engine.outputNode.auAudioUnit.audioUnit
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &audioDeviceID,
            propertySize
        )

        if status != noErr {
            print("Failed to set output device \(device.name) (status: \(status))")
        }

        if wasRunning {
            do {
                try engine.start()
            } catch {
                print("Failed to restart engine after device switch: \(error)")
            }
        }
    }

    @objc private func audioEngineConfigurationChange(_ notification: Notification) {
        // Re-enumerate devices and update the publisher
        _availableOutputDevicesSubject.send(enumerateOutputDevices())
        // Potentially handle current device invalidation
        print("Audio device configuration changed.")
    }

    private func generateSample(at time: Double) -> Float {
        guard let sound = currentSound else { return 0.0 }
        let frequency = sound.parameter(named: "frequency")?.value ?? 440.0
        switch sound.waveform {
        case .sine:
            return sin(Float(2.0 * .pi * frequency * time))
        case .square:
            return sin(Float(2.0 * .pi * frequency * time)) > 0 ? 1.0 : -1.0
        case .triangle:
            return 2.0 * (abs(fmod(Float(frequency * time), 1.0) - 0.5) - 0.25)
        case .sawtooth:
            return 2.0 * (fmod(Float(frequency * time), 1.0) - 0.5)
        }
    }

    private func calculateSpectrum(buffer: AVAudioPCMBuffer) {
        let bufferPointer = UnsafeBufferPointer(start: buffer.floatChannelData?[0], count: Int(buffer.frameLength))
        var real = [Float](bufferPointer)
        var imag = [Float](repeating: 0.0, count: fftSize)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

                vDSP_fft_zip(fftSetup, &splitComplex, 1, vDSP_Length(log2(Float(fftSize))), FFTDirection(kFFTDirection_Forward))

                var magnitudes = [Float](repeating: 0.0, count: fftSize / 2)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))

                var normalizedMagnitudes = [Float](repeating: 0.0, count: fftSize / 2)
                vDSP_vsmul(magnitudes, 1, [2.0 / Float(fftSize)], &normalizedMagnitudes, 1, vDSP_Length(fftSize / 2))

                _spectrumSubject.send(normalizedMagnitudes)
            }
        }
    }
}

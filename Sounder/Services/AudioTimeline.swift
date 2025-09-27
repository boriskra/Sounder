import Foundation

/// Global audio timeline that provides time-coherent sample positioning across all audio blocks
/// Ensures all signal generation blocks are synchronized to the same temporal reference
public struct AudioTimeline {
    public let sampleRate: Double
    private(set) var currentSample: UInt64 = 0
    private let startTimestamp: UInt64

    /// Creates a new audio timeline with the specified sample rate
    /// - Parameter sampleRate: The sample rate in Hz (e.g., 48000.0)
    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.startTimestamp = mach_absolute_time()
        print("🕐 [DEBUG] AudioTimeline.init() - Created timeline at sample rate: \(sampleRate)")
    }

    /// Advances the timeline by the specified number of samples
    /// - Parameter frameCount: Number of samples to advance
    public mutating func advance(by frameCount: Int) {
        currentSample += UInt64(frameCount)
    }

    /// Calculates the absolute time in seconds for a given sample position
    /// - Parameter sample: Sample index from timeline start
    /// - Returns: Time in seconds
    public func timeForSample(_ sample: UInt64) -> Double {
        return Double(sample) / sampleRate
    }

    /// Gets the current time in seconds since timeline start
    public var currentTime: Double {
        return timeForSample(currentSample)
    }

    /// Resets the timeline to the beginning
    public mutating func reset() {
        currentSample = 0
        print("🕐 [DEBUG] AudioTimeline.reset() - Timeline reset to sample 0")
    }

    /// Resets the timeline to a specific sample position
    /// - Parameter sample: Sample position to reset to
    public mutating func reset(to sample: UInt64) {
        currentSample = sample
        print("🕐 [DEBUG] AudioTimeline.reset(to:) - Timeline reset to sample \(sample)")
    }

    /// Gets timeline statistics for debugging
    public func getStats() -> AudioTimelineStats {
        return AudioTimelineStats(
            sampleRate: sampleRate,
            currentSample: currentSample,
            currentTime: currentTime,
            totalSamples: currentSample
        )
    }
}

/// Statistics about the audio timeline state
public struct AudioTimelineStats {
    public let sampleRate: Double
    public let currentSample: UInt64
    public let currentTime: Double
    public let totalSamples: UInt64
}

// MARK: - Timeline Extensions for Common Operations

extension AudioTimeline {
    /// Creates a sample range for the current frame
    /// - Parameter frameCount: Number of samples in the frame
    /// - Returns: Range representing the current frame samples
    public func currentFrameRange(frameCount: Int) -> Range<UInt64> {
        return currentSample..<(currentSample + UInt64(frameCount))
    }

    /// Calculates phase for a given frequency at a specific sample
    /// - Parameters:
    ///   - frequency: Frequency in Hz
    ///   - sample: Sample index
    /// - Returns: Phase in radians (0 to 2π)
    public func phaseForFrequency(_ frequency: Double, at sample: UInt64) -> Double {
        let time = timeForSample(sample)
        return 2.0 * Double.pi * frequency * time
    }

    /// Calculates normalized phase for a given frequency at a specific sample
    /// - Parameters:
    ///   - frequency: Frequency in Hz
    ///   - sample: Sample index
    /// - Returns: Normalized phase (0.0 to 1.0)
    public func normalizedPhaseForFrequency(_ frequency: Double, at sample: UInt64) -> Double {
        let time = timeForSample(sample)
        return (frequency * time).truncatingRemainder(dividingBy: 1.0)
    }

    /// Gets the beat-synchronized position for musical timing
    /// - Parameters:
    ///   - bpm: Beats per minute
    ///   - sample: Sample index
    /// - Returns: Beat position as a fraction (0.0 to 1.0 per beat)
    public func beatPhaseForBPM(_ bpm: Double, at sample: UInt64) -> Double {
        let time = timeForSample(sample)
        let beatsPerSecond = bpm / 60.0
        return (beatsPerSecond * time).truncatingRemainder(dividingBy: 1.0)
    }
}

// MARK: - Timeline Validation

extension AudioTimeline {
    /// Validates that the timeline is in a consistent state
    /// - Throws: AudioTimelineError if validation fails
    public func validate() throws {
        guard sampleRate > 0 else {
            throw AudioTimelineError.invalidSampleRate(sampleRate)
        }

        guard currentSample >= 0 else {
            throw AudioTimelineError.invalidSamplePosition(currentSample)
        }

        // Check for reasonable bounds (max ~24 hours at 48kHz)
        let maxSamples: UInt64 = UInt64(sampleRate * 24 * 60 * 60)
        guard currentSample < maxSamples else {
            throw AudioTimelineError.timelineOverflow(currentSample, maxSamples)
        }
    }
}

// MARK: - Timeline Errors

public enum AudioTimelineError: Error, LocalizedError {
    case invalidSampleRate(Double)
    case invalidSamplePosition(UInt64)
    case timelineOverflow(UInt64, UInt64)

    public var errorDescription: String? {
        switch self {
        case .invalidSampleRate(let rate):
            return "Invalid sample rate: \(rate). Must be greater than 0."
        case .invalidSamplePosition(let position):
            return "Invalid sample position: \(position). Must be non-negative."
        case .timelineOverflow(let current, let max):
            return "Timeline overflow: current sample \(current) exceeds maximum \(max)."
        }
    }
}
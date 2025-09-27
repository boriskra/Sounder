import Foundation

enum Waveform {
    case sine
    case square
    case triangle
    case sawtooth
}

struct Sound {
    let name: String
    let waveform: Waveform
}

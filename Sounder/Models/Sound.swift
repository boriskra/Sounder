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
    let parameters: [Parameter]

    init(name: String, waveform: Waveform, parameters: [Parameter] = []) {
        self.name = name
        self.waveform = waveform
        self.parameters = parameters
    }

    func parameter(named name: String) -> Parameter? {
        return parameters.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

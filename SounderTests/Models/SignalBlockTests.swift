import XCTest
import Foundation
import SwiftUI
@testable import Sounder

final class SignalBlockTests: XCTestCase {

    // MARK: - Initialization Tests

    func testValidSignalBlockInitialization() {
        let frequency = BlockParameter.frequency(value: 440.0)
        let amplitude = BlockParameter.amplitude(value: -6.0)
        let parameters = ["frequency": frequency, "amplitude": amplitude]

        let inputPort = InputPort(name: "frequency", displayName: "Frequency", signalType: .frequency, isRequired: false, defaultValue: nil)
        let outputPort = OutputPort(name: "signal", displayName: "Signal", signalType: .audio, isRequired: false, defaultValue: nil)

        let block = SignalBlock(
            type: .sineOscillator,
            title: "Sine Wave",
            position: CGPoint(x: 100, y: 200),
            parameters: parameters,
            inputPorts: [inputPort],
            outputPorts: [outputPort],
            isActive: false
        )

        XCTAssertEqual(block.type, .sineOscillator)
        XCTAssertEqual(block.title, "Sine Wave")
        XCTAssertEqual(block.position, CGPoint(x: 100, y: 200))
        XCTAssertEqual(block.parameters.count, 2)
        XCTAssertEqual(block.inputPorts.count, 1)
        XCTAssertEqual(block.outputPorts.count, 1)
        XCTAssertFalse(block.isActive)
    }

    // MARK: - Position Validation Tests

    func testPositionValidation_PositiveCoordinates() {
        let block = createValidSineOscillatorBlock(position: CGPoint(x: 100, y: 200))
        XCTAssertEqual(block.position, CGPoint(x: 100, y: 200))
    }

    func testPositionValidation_ZeroCoordinates() {
        let block = createValidSineOscillatorBlock(position: CGPoint(x: 0, y: 0))
        XCTAssertEqual(block.position, CGPoint(x: 0, y: 0))
    }

    func testPositionValidation_NegativeXCoordinate() {
        expectFatalError {
            _ = createValidSineOscillatorBlock(position: CGPoint(x: -10, y: 100))
        }
    }

    func testPositionValidation_NegativeYCoordinate() {
        expectFatalError {
            _ = createValidSineOscillatorBlock(position: CGPoint(x: 100, y: -10))
        }
    }

    func testPositionValidation_BothNegativeCoordinates() {
        expectFatalError {
            _ = createValidSineOscillatorBlock(position: CGPoint(x: -10, y: -20))
        }
    }

    // MARK: - Title Validation Tests

    func testTitleValidation_ValidTitle() {
        let block = createValidSineOscillatorBlock(title: "My Sine Wave")
        XCTAssertEqual(block.title, "My Sine Wave")
    }

    func testTitleValidation_EmptyTitle() {
        expectFatalError {
            _ = createValidSineOscillatorBlock(title: "")
        }
    }

    func testTitleValidation_WhitespaceOnlyTitle() {
        expectFatalError {
            _ = createValidSineOscillatorBlock(title: "   \t\n   ")
        }
    }

    func testTitleValidation_TitleWithLeadingTrailingWhitespace() {
        let block = createValidSineOscillatorBlock(title: "  Valid Title  ")
        XCTAssertEqual(block.title, "  Valid Title  ")
    }

    // MARK: - Required Parameters Validation Tests

    func testRequiredParametersValidation_SineOscillatorWithFrequency() {
        let frequency = BlockParameter.frequency(value: 440.0)
        let block = createSineOscillatorBlock(parameters: ["frequency": frequency])
        XCTAssertNotNil(block.parameters["frequency"])
    }

    func testRequiredParametersValidation_SineOscillatorMissingFrequency() {
        expectFatalError {
            _ = createSineOscillatorBlock(parameters: [:])
        }
    }

    func testRequiredParametersValidation_WhiteNoiseMissingAmplitude() {
        expectFatalError {
            _ = createWhiteNoiseBlock(parameters: [:])
        }
    }

    func testRequiredParametersValidation_FrequencyModulatorMissingDeviation() {
        expectFatalError {
            _ = createFrequencyModulatorBlock(parameters: [:])
        }
    }

    func testRequiredParametersValidation_BandPassFilterMissingCenterFrequency() {
        expectFatalError {
            let qFactor = BlockParameter(name: "qFactor", displayName: "Q Factor", value: 1.0, minimumValue: 0.1, maximumValue: 100.0, unit: "", stepSize: 0.1)
            _ = createBandPassFilterBlock(parameters: ["qFactor": qFactor])
        }
    }

    func testRequiredParametersValidation_BandPassFilterMissingQFactor() {
        expectFatalError {
            let centerFreq = BlockParameter.frequency(name: "centerFrequency", displayName: "Center", value: 1000.0)
            _ = createBandPassFilterBlock(parameters: ["centerFrequency": centerFreq])
        }
    }

    // MARK: - Generator Block Output Port Validation Tests

    func testGeneratorBlockValidation_SineOscillatorWithOutputPorts() {
        let outputPort = OutputPort(name: "signal", displayName: "Signal", signalType: .audio, isRequired: false, defaultValue: nil)
        let block = createSineOscillatorBlock(outputPorts: [outputPort])
        XCTAssertEqual(block.outputPorts.count, 1)
    }

    func testGeneratorBlockValidation_SineOscillatorWithoutOutputPorts() {
        expectFatalError {
            _ = createSineOscillatorBlock(outputPorts: [])
        }
    }

    func testGeneratorBlockValidation_NonGeneratorWithoutOutputPorts() {
        let parameters = ["cutoffFrequency": BlockParameter.frequency(name: "cutoffFrequency", displayName: "Cutoff", value: 1000.0)]
        let inputPort = InputPort(name: "input", displayName: "Input", signalType: .audio, isRequired: true, defaultValue: nil)

        let block = SignalBlock(
            type: .lowPassFilter,
            title: "Low Pass Filter",
            position: CGPoint(x: 100, y: 200),
            parameters: parameters,
            inputPorts: [inputPort],
            outputPorts: [],
            isActive: false
        )

        XCTAssertEqual(block.outputPorts.count, 0)
    }

    // MARK: - Parameter Range Validation Tests

    func testParameterRangeValidation_ValidParameterValues() {
        let frequency = BlockParameter.frequency(value: 440.0)
        let amplitude = BlockParameter.amplitude(value: -6.0)
        let parameters = ["frequency": frequency, "amplitude": amplitude]

        let block = createSineOscillatorBlock(parameters: parameters)
        XCTAssertEqual(block.parameters["frequency"]?.value, 440.0)
        XCTAssertEqual(block.parameters["amplitude"]?.value, -6.0)
    }

    func testParameterRangeValidation_ParameterValueBelowMinimum() {
        expectFatalError {
            let invalidFrequency = BlockParameter(
                name: "frequency",
                displayName: "Frequency",
                value: 10.0, // Below minimum of 20 Hz
                minimumValue: 20.0,
                maximumValue: 20000.0,
                unit: "Hz",
                stepSize: 1.0
            )
            _ = createSineOscillatorBlock(parameters: ["frequency": invalidFrequency])
        }
    }

    func testParameterRangeValidation_ParameterValueAboveMaximum() {
        expectFatalError {
            let invalidAmplitude = BlockParameter(
                name: "amplitude",
                displayName: "Amplitude",
                value: 10.0, // Above maximum of 0 dB
                minimumValue: -60.0,
                maximumValue: 0.0,
                unit: "dB",
                stepSize: 0.1
            )
            _ = createSineOscillatorBlock(parameters: ["frequency": BlockParameter.frequency(), "amplitude": invalidAmplitude])
        }
    }

    func testParameterRangeValidation_ParameterValueAtMinimum() {
        let minFrequency = BlockParameter.frequency(value: 20.0)
        let block = createSineOscillatorBlock(parameters: ["frequency": minFrequency])
        XCTAssertEqual(block.parameters["frequency"]?.value, 20.0)
    }

    func testParameterRangeValidation_ParameterValueAtMaximum() {
        let maxFrequency = BlockParameter.frequency(value: 20000.0)
        let block = createSineOscillatorBlock(parameters: ["frequency": maxFrequency])
        XCTAssertEqual(block.parameters["frequency"]?.value, 20000.0)
    }

    // MARK: - Port Name Uniqueness Validation Tests

    func testPortNameUniqueness_UniqueInputPortNames() {
        let inputPort1 = InputPort(name: "carrier", displayName: "Carrier", signalType: .audio, isRequired: true, defaultValue: nil)
        let inputPort2 = InputPort(name: "modulation", displayName: "Modulation", signalType: .control, isRequired: true, defaultValue: nil)

        let block = createFrequencyModulatorBlock(inputPorts: [inputPort1, inputPort2])
        XCTAssertEqual(block.inputPorts.count, 2)
    }

    func testPortNameUniqueness_DuplicateInputPortNames() {
        expectFatalError {
            let inputPort1 = InputPort(name: "input", displayName: "Input 1", signalType: .audio, isRequired: true, defaultValue: nil)
            let inputPort2 = InputPort(name: "input", displayName: "Input 2", signalType: .audio, isRequired: true, defaultValue: nil)
            _ = createFrequencyModulatorBlock(inputPorts: [inputPort1, inputPort2])
        }
    }

    func testPortNameUniqueness_UniqueOutputPortNames() {
        let outputPort1 = OutputPort(name: "magnitude", displayName: "Magnitude", signalType: .control, isRequired: false, defaultValue: nil)
        let outputPort2 = OutputPort(name: "phase", displayName: "Phase", signalType: .control, isRequired: false, defaultValue: nil)

        let parameters = [
            "windowSize": BlockParameter(name: "windowSize", displayName: "Window Size", value: 1024, minimumValue: 256, maximumValue: 8192, unit: "samples", stepSize: 1),
            "overlap": BlockParameter.percentage(name: "overlap", displayName: "Overlap", value: 50.0)
        ]

        let block = createSpectrumAnalyzerBlock(parameters: parameters, outputPorts: [outputPort1, outputPort2])
        XCTAssertEqual(block.outputPorts.count, 2)
    }

    func testPortNameUniqueness_DuplicateOutputPortNames() {
        expectFatalError {
            let outputPort1 = OutputPort(name: "output", displayName: "Output 1", signalType: .audio, isRequired: false, defaultValue: nil)
            let outputPort2 = OutputPort(name: "output", displayName: "Output 2", signalType: .audio, isRequired: false, defaultValue: nil)

            let parameters = [
                "windowSize": BlockParameter(name: "windowSize", displayName: "Window Size", value: 1024, minimumValue: 256, maximumValue: 8192, unit: "samples", stepSize: 1),
                "overlap": BlockParameter.percentage(name: "overlap", displayName: "Overlap", value: 50.0)
            ]

            _ = createSpectrumAnalyzerBlock(parameters: parameters, outputPorts: [outputPort1, outputPort2])
        }
    }

    // MARK: - Parameter Update Tests

    func testUpdatingParameter_ValidParameterUpdate() throws {
        let block = createValidSineOscillatorBlock()
        let updatedBlock = try block.updatingParameter("frequency", to: 880.0)

        XCTAssertEqual(updatedBlock.parameters["frequency"]?.value, 880.0)
        XCTAssertEqual(block.parameters["frequency"]?.value, 440.0) // Original unchanged
    }

    func testUpdatingParameter_NonExistentParameter() throws {
        let block = createValidSineOscillatorBlock()

        XCTAssertThrowsError(try block.updatingParameter("nonexistent", to: 100.0)) { error in
            guard case ValidationError.parameterNotFound(let paramName) = error else {
                XCTFail("Expected parameterNotFound error")
                return
            }
            XCTAssertEqual(paramName, "nonexistent")
        }
    }

    func testUpdatingParameter_ValueBelowMinimum() throws {
        let block = createValidSineOscillatorBlock()

        XCTAssertThrowsError(try block.updatingParameter("frequency", to: 10.0)) { error in
            guard case ValidationError.parameterValueOutOfRange(let param, let value, let range) = error else {
                XCTFail("Expected parameterValueOutOfRange error")
                return
            }
            XCTAssertEqual(param, "frequency")
            XCTAssertEqual(value, 10.0)
            XCTAssertTrue(range.contains(440.0))
        }
    }

    func testUpdatingParameter_ValueAboveMaximum() throws {
        let block = createValidSineOscillatorBlock()

        XCTAssertThrowsError(try block.updatingParameter("frequency", to: 25000.0)) { error in
            guard case ValidationError.parameterValueOutOfRange(let param, let value, let range) = error else {
                XCTFail("Expected parameterValueOutOfRange error")
                return
            }
            XCTAssertEqual(param, "frequency")
            XCTAssertEqual(value, 25000.0)
            XCTAssertTrue(range.contains(440.0))
        }
    }

    func testUpdatingParameter_ValueAtBoundaries() throws {
        let block = createValidSineOscillatorBlock()

        let minBlock = try block.updatingParameter("frequency", to: 20.0)
        XCTAssertEqual(minBlock.parameters["frequency"]?.value, 20.0)

        let maxBlock = try block.updatingParameter("frequency", to: 20000.0)
        XCTAssertEqual(maxBlock.parameters["frequency"]?.value, 20000.0)
    }

    // MARK: - Position Update Tests

    func testMovingTo_ValidPosition() throws {
        let block = createValidSineOscillatorBlock()
        let movedBlock = try block.movingTo(CGPoint(x: 300, y: 400))

        XCTAssertEqual(movedBlock.position, CGPoint(x: 300, y: 400))
        XCTAssertEqual(block.position, CGPoint(x: 100, y: 200)) // Original unchanged
    }

    func testMovingTo_ZeroPosition() throws {
        let block = createValidSineOscillatorBlock()
        let movedBlock = try block.movingTo(CGPoint(x: 0, y: 0))

        XCTAssertEqual(movedBlock.position, CGPoint(x: 0, y: 0))
    }

    func testMovingTo_NegativeXPosition() throws {
        let block = createValidSineOscillatorBlock()

        XCTAssertThrowsError(try block.movingTo(CGPoint(x: -10, y: 100))) { error in
            guard case ValidationError.invalidPosition(let pos) = error else {
                XCTFail("Expected invalidPosition error")
                return
            }
            XCTAssertEqual(pos, CGPoint(x: -10, y: 100))
        }
    }

    func testMovingTo_NegativeYPosition() throws {
        let block = createValidSineOscillatorBlock()

        XCTAssertThrowsError(try block.movingTo(CGPoint(x: 100, y: -10))) { error in
            guard case ValidationError.invalidPosition(let pos) = error else {
                XCTFail("Expected invalidPosition error")
                return
            }
            XCTAssertEqual(pos, CGPoint(x: 100, y: -10))
        }
    }

    // MARK: - Active State Tests

    func testSettingActive_ToTrue() {
        let block = createValidSineOscillatorBlock()
        let activeBlock = block.settingActive(true)

        XCTAssertTrue(activeBlock.isActive)
        XCTAssertFalse(block.isActive) // Original unchanged
    }

    func testSettingActive_ToFalse() {
        let block = createValidSineOscillatorBlock().settingActive(true)
        let inactiveBlock = block.settingActive(false)

        XCTAssertFalse(inactiveBlock.isActive)
        XCTAssertTrue(block.isActive) // Original unchanged
    }

    // MARK: - Visual Size Tests

    func testVisualSize_BasicBlock() {
        let block = createValidSineOscillatorBlock()
        let size = block.visualSize

        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    func testVisualSize_BlockWithManyParameters() {
        let parameters = [
            "frequency": BlockParameter.frequency(),
            "amplitude": BlockParameter.amplitude(),
            "param3": BlockParameter.percentage(name: "param3", displayName: "Param 3"),
            "param4": BlockParameter.percentage(name: "param4", displayName: "Param 4"),
            "param5": BlockParameter.percentage(name: "param5", displayName: "Param 5")
        ]

        let block = createSineOscillatorBlock(parameters: parameters)
        let size = block.visualSize

        let baseBlock = createValidSineOscillatorBlock()
        let baseSize = baseBlock.visualSize

        XCTAssertGreaterThan(size.width, baseSize.width)
    }

    func testVisualSize_BlockWithManyPorts() {
        let inputPorts = [
            InputPort(name: "input1", displayName: "Input 1", signalType: .audio, isRequired: false, defaultValue: 0.0),
            InputPort(name: "input2", displayName: "Input 2", signalType: .audio, isRequired: false, defaultValue: 0.0),
            InputPort(name: "input3", displayName: "Input 3", signalType: .audio, isRequired: false, defaultValue: 0.0),
            InputPort(name: "input4", displayName: "Input 4", signalType: .audio, isRequired: false, defaultValue: 0.0),
            InputPort(name: "input5", displayName: "Input 5", signalType: .audio, isRequired: false, defaultValue: 0.0)
        ]

        let block = createMixerBlock(inputPorts: inputPorts)
        let size = block.visualSize

        let baseBlock = createValidSineOscillatorBlock()
        let baseSize = baseBlock.visualSize

        XCTAssertGreaterThan(size.height, baseSize.height)
    }

    // MARK: - Port Lookup Tests

    func testInputPort_FindByName() {
        let inputPort = InputPort(name: "carrier", displayName: "Carrier", signalType: .audio, isRequired: true, defaultValue: nil)
        let block = createFrequencyModulatorBlock(inputPorts: [inputPort])

        let foundPort = block.inputPort(named: "carrier")
        XCTAssertNotNil(foundPort)
        XCTAssertEqual(foundPort?.name, "carrier")
    }

    func testInputPort_NotFound() {
        let block = createValidSineOscillatorBlock()
        let foundPort = block.inputPort(named: "nonexistent")
        XCTAssertNil(foundPort)
    }

    func testOutputPort_FindByName() {
        let outputPort = OutputPort(name: "signal", displayName: "Signal", signalType: .audio, isRequired: false, defaultValue: nil)
        let block = createSineOscillatorBlock(outputPorts: [outputPort])

        let foundPort = block.outputPort(named: "signal")
        XCTAssertNotNil(foundPort)
        XCTAssertEqual(foundPort?.name, "signal")
    }

    func testOutputPort_NotFound() {
        let block = createValidSineOscillatorBlock()
        let foundPort = block.outputPort(named: "nonexistent")
        XCTAssertNil(foundPort)
    }

    // MARK: - Required Inputs Connection Tests

    func testHasRequiredInputsConnected_AllRequired() {
        let requiredInput = InputPort(name: "carrier", displayName: "Carrier", signalType: .audio, isRequired: true, defaultValue: nil)
        let block = createFrequencyModulatorBlock(inputPorts: [requiredInput])

        let connection = Connection(
            id: UUID(),
            sourceBlockId: UUID(),
            sourcePort: "output",
            destinationBlockId: block.id,
            destinationPort: "carrier",
            signalType: .audio
        )

        XCTAssertTrue(block.hasRequiredInputsConnected(connections: [connection]))
    }

    func testHasRequiredInputsConnected_MissingRequired() {
        let requiredInput = InputPort(name: "carrier", displayName: "Carrier", signalType: .audio, isRequired: true, defaultValue: nil)
        let block = createFrequencyModulatorBlock(inputPorts: [requiredInput])

        XCTAssertFalse(block.hasRequiredInputsConnected(connections: []))
    }

    func testHasRequiredInputsConnected_RequiredWithDefaultValue() {
        let requiredInputWithDefault = InputPort(name: "input", displayName: "Input", signalType: .audio, isRequired: true, defaultValue: 0.0)
        let block = createAmplifierBlock(inputPorts: [requiredInputWithDefault])

        XCTAssertTrue(block.hasRequiredInputsConnected(connections: []))
    }

    func testHasRequiredInputsConnected_NoRequiredInputs() {
        let optionalInput = InputPort(name: "frequency", displayName: "Frequency", signalType: .frequency, isRequired: false, defaultValue: nil)
        let block = createSineOscillatorBlock(inputPorts: [optionalInput])

        XCTAssertTrue(block.hasRequiredInputsConnected(connections: []))
    }

    // MARK: - Equatable Tests

    func testEquality_IdenticalBlocks() {
        let block1 = createValidSineOscillatorBlock()
        let block2 = SignalBlock(
            id: block1.id,
            type: block1.type,
            title: block1.title,
            position: block1.position,
            parameters: block1.parameters,
            inputPorts: block1.inputPorts,
            outputPorts: block1.outputPorts,
            isActive: block1.isActive
        )

        XCTAssertEqual(block1, block2)
    }

    func testEquality_DifferentIds() {
        let block1 = createValidSineOscillatorBlock()
        let block2 = SignalBlock(
            id: UUID(),
            type: block1.type,
            title: block1.title,
            position: block1.position,
            parameters: block1.parameters,
            inputPorts: block1.inputPorts,
            outputPorts: block1.outputPorts,
            isActive: block1.isActive
        )

        XCTAssertNotEqual(block1, block2)
    }

    func testEquality_DifferentPositions() {
        let block1 = createValidSineOscillatorBlock()
        let block2 = SignalBlock(
            id: block1.id,
            type: block1.type,
            title: block1.title,
            position: CGPoint(x: 300, y: 400),
            parameters: block1.parameters,
            inputPorts: block1.inputPorts,
            outputPorts: block1.outputPorts,
            isActive: block1.isActive
        )

        XCTAssertNotEqual(block1, block2)
    }

    // MARK: - Codable Tests

    func testCodable_EncodeDecode() throws {
        let originalBlock = createValidSineOscillatorBlock()

        let encoder = JSONEncoder()
        let data = try encoder.encode(originalBlock)

        let decoder = JSONDecoder()
        let decodedBlock = try decoder.decode(SignalBlock.self, from: data)

        XCTAssertEqual(originalBlock, decodedBlock)
    }

    func testCodable_DecodingTriggersValidation() throws {
        let invalidJSON = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "type": "sine_oscillator",
            "title": "",
            "position": {"x": 100, "y": 200},
            "parameters": {"frequency": {"name":"frequency","displayName":"Frequency","value":440,"minimumValue":20,"maximumValue":20000,"unit":"Hz","stepSize":1,"isLogarithmic":true}},
            "inputPorts": [],
            "outputPorts": [{"name":"signal","displayName":"Signal","signalType":"audio","isRequired":false,"defaultValue":null}],
            "isActive": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        XCTAssertThrowsError(try decoder.decode(SignalBlock.self, from: invalidJSON))
    }

    // MARK: - Helper Methods

    private func createValidSineOscillatorBlock(
        title: String = "Sine Wave",
        position: CGPoint = CGPoint(x: 100, y: 200)
    ) -> SignalBlock {
        let frequency = BlockParameter.frequency(value: 440.0)
        let amplitude = BlockParameter.amplitude(value: -6.0)
        let parameters = ["frequency": frequency, "amplitude": amplitude]

        let inputPort = InputPort(name: "frequency", displayName: "Frequency", signalType: .frequency, isRequired: false, defaultValue: nil)
        let outputPort = OutputPort(name: "signal", displayName: "Signal", signalType: .audio, isRequired: false, defaultValue: nil)

        return SignalBlock(
            type: .sineOscillator,
            title: title,
            position: position,
            parameters: parameters,
            inputPorts: [inputPort],
            outputPorts: [outputPort],
            isActive: false
        )
    }

    private func createSineOscillatorBlock(
        parameters: [String: BlockParameter] = ["frequency": BlockParameter.frequency()],
        inputPorts: [InputPort] = [InputPort(name: "frequency", displayName: "Frequency", signalType: .frequency, isRequired: false, defaultValue: nil)],
        outputPorts: [OutputPort] = [OutputPort(name: "signal", displayName: "Signal", signalType: .audio, isRequired: false, defaultValue: nil)]
    ) -> SignalBlock {
        return SignalBlock(
            type: .sineOscillator,
            title: "Sine Wave",
            position: CGPoint(x: 100, y: 200),
            parameters: parameters,
            inputPorts: inputPorts,
            outputPorts: outputPorts,
            isActive: false
        )
    }

    private func createWhiteNoiseBlock(
        parameters: [String: BlockParameter] = ["amplitude": BlockParameter.amplitude()]
    ) -> SignalBlock {
        let outputPort = OutputPort(name: "signal", displayName: "Signal", signalType: .audio, isRequired: false, defaultValue: nil)

        return SignalBlock(
            type: .whiteNoise,
            title: "White Noise",
            position: CGPoint(x: 100, y: 200),
            parameters: parameters,
            inputPorts: [],
            outputPorts: [outputPort],
            isActive: false
        )
    }

    private func createFrequencyModulatorBlock(
        parameters: [String: BlockParameter] = ["deviation": BlockParameter.frequency(name: "deviation", displayName: "Deviation", value: 1000.0, maxHz: 10000.0)],
        inputPorts: [InputPort] = [
            InputPort(name: "carrier", displayName: "Carrier", signalType: .audio, isRequired: true, defaultValue: nil),
            InputPort(name: "modulation", displayName: "Modulation", signalType: .control, isRequired: true, defaultValue: nil)
        ]
    ) -> SignalBlock {
        let outputPort = OutputPort(name: "output", displayName: "Output", signalType: .audio, isRequired: false, defaultValue: nil)

        return SignalBlock(
            type: .frequencyModulator,
            title: "FM",
            position: CGPoint(x: 100, y: 200),
            parameters: parameters,
            inputPorts: inputPorts,
            outputPorts: [outputPort],
            isActive: false
        )
    }

    private func createBandPassFilterBlock(
        parameters: [String: BlockParameter]
    ) -> SignalBlock {
        let inputPort = InputPort(name: "input", displayName: "Input", signalType: .audio, isRequired: true, defaultValue: nil)
        let outputPort = OutputPort(name: "output", displayName: "Output", signalType: .audio, isRequired: false, defaultValue: nil)

        return SignalBlock(
            type: .bandPassFilter,
            title: "Band Pass",
            position: CGPoint(x: 100, y: 200),
            parameters: parameters,
            inputPorts: [inputPort],
            outputPorts: [outputPort],
            isActive: false
        )
    }

    private func createSpectrumAnalyzerBlock(
        parameters: [String: BlockParameter],
        outputPorts: [OutputPort]
    ) -> SignalBlock {
        let inputPort = InputPort(name: "input", displayName: "Input", signalType: .audio, isRequired: true, defaultValue: nil)

        return SignalBlock(
            type: .spectrumAnalyzer,
            title: "Spectrum",
            position: CGPoint(x: 100, y: 200),
            parameters: parameters,
            inputPorts: [inputPort],
            outputPorts: outputPorts,
            isActive: false
        )
    }

    private func createMixerBlock(
        inputPorts: [InputPort]
    ) -> SignalBlock {
        let outputPort = OutputPort(name: "output", displayName: "Output", signalType: .audio, isRequired: false, defaultValue: nil)

        return SignalBlock(
            type: .mixer,
            title: "Mixer",
            position: CGPoint(x: 100, y: 200),
            parameters: [:],
            inputPorts: inputPorts,
            outputPorts: [outputPort],
            isActive: false
        )
    }

    private func createAmplifierBlock(
        inputPorts: [InputPort]
    ) -> SignalBlock {
        let parameters = ["gain": BlockParameter.amplitude(name: "gain", displayName: "Gain", value: 0.0, minDb: -60.0, maxDb: 20.0)]
        let outputPort = OutputPort(name: "output", displayName: "Output", signalType: .audio, isRequired: false, defaultValue: nil)

        return SignalBlock(
            type: .amplifier,
            title: "Amplifier",
            position: CGPoint(x: 100, y: 200),
            parameters: parameters,
            inputPorts: inputPorts,
            outputPorts: [outputPort],
            isActive: false
        )
    }

    private func expectFatalError(_ block: () -> Void) {
        // Note: In a real implementation, you would use a testing framework
        // that can capture fatal errors. For this example, we'll document
        // that these tests expect fatal errors.

        // This is a placeholder implementation.
        // In practice, you would use something like:
        // XCTExpectFailure("Expected precondition failure")

        let expectation = XCTestExpectation(description: "Fatal error expected")
        expectation.isInverted = true

        DispatchQueue.global().async {
            block()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
}
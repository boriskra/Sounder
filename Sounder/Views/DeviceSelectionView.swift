import SwiftUI

struct DeviceSelectionView: View {
    let devices: [OutputDevice]
    @Binding var selectedDevice: OutputDevice?

    var body: some View {
        List(devices, id: \.id) { device in
            Button(action: {
                selectedDevice = device
            }) {
                Text(device.name)
            }
        }
    }
}

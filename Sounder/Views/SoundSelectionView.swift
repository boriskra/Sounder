import SwiftUI

struct SoundSelectionView: View {
    let sounds: [Sound]
    @Binding var selectedSound: Sound?

    var body: some View {
        List(sounds, id: \.name) { sound in
            Button(action: {
                selectedSound = sound
            }) {
                Text(sound.name)
            }
        }
    }
}

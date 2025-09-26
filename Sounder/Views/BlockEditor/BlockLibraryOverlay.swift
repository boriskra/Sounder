import SwiftUI

struct BlockLibraryOverlay: View {
    let viewModel: BlockEditorViewModel

    var body: some View {
        Color.black.opacity(0.3)
            .onTapGesture {
                viewModel.hideBlockLibrary()
            }
    }
}

import SwiftUI

private extension BlockEditorView {
    var toolbarContent: some ToolbarContent {
        Group {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await viewModel.newConfiguration() }
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .help("New Configuration (⌘N)")

                Button {
                    Task { await viewModel.saveConfiguration() }
                } label: {
                    Image(systemName: "doc.badge.arrow.up")
                }
                .help("Save Configuration (⌘S)")
                .disabled(!viewModel.hasUnsavedChanges)

                Button {
                    Task { await viewModel.loadConfiguration() }
                } label: {
                    Image(systemName: "folder")
                }
                .help("Load Configuration (⌘O)")
            }

            ToolbarItem(placement: .primaryAction) {
                Button { viewModel.showBlockLibrary() } label: {
                    Image(systemName: "plus.square.on.square")
                }
                .help("Block Library (⌘L)")
            }

            ToolbarItem(placement: .automatic) {
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
    }
}

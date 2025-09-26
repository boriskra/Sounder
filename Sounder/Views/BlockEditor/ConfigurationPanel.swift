import SwiftUI

struct ConfigurationPanel: View {
    @ObservedObject var viewModel: BlockEditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            configurationInfo

            Divider()

            recentFilesSection

            Divider()

            templatesSection

            Spacer()
        }
        .padding()
    }

    private var configurationInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Configuration")
                .font(.headline)

            if let url = viewModel.currentConfigurationURL {
                Text(url.lastPathComponent)
                    .font(.subheadline.bold())

                Text(url.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else {
                Text("Untitled Configuration")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if viewModel.hasUnsavedChanges {
                Text("Unsaved changes")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var recentFilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Files")
                .font(.headline)

            if viewModel.recentConfigurations.isEmpty {
                Text("No recent files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(viewModel.recentConfigurations.prefix(5)), id: \.absoluteString) { url in
                    Button {
                        Task {
                            await viewModel.configurationViewModel.loadConfiguration(from: url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.accentColor)

                            VStack(alignment: .leading) {
                                Text(url.lastPathComponent)
                                    .font(.subheadline)

                                Text(url.path)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Templates")
                .font(.headline)

            ForEach(viewModel.configurationViewModel.getAvailableTemplates(), id: \.id) { template in
                Button {
                    Task {
                        await viewModel.configurationViewModel.createFromTemplate(template)
                    }
                } label: {
                    HStack {
                        Image(systemName: "doc.plaintext")
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.caption.bold())

                            Text(template.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

import SwiftUI

struct FolderPickerView: View {
    @EnvironmentObject var client: BridgeClient
    @Environment(\.dismiss) private var dismiss

    let initialPath: String
    let onSelect: (String) -> Void

    @State private var currentPath: String = ""
    @State private var parentPath: String?
    @State private var drives: [String] = []
    @State private var entries: [DirectoryEntry] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Drives strip
                if !drives.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(drives, id: \.self) { drv in
                                Button {
                                    Task { await load(path: drv) }
                                } label: {
                                    Text(drv)
                                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .foregroundColor(currentPath.uppercased().hasPrefix(drv.uppercased()) ? .white : AppTheme.textSecondary)
                                        .background(currentPath.uppercased().hasPrefix(drv.uppercased()) ? AppTheme.accent : AppTheme.card)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .background(AppTheme.surface)
                }

                // Current path display
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(AppTheme.cyan)
                    Text(currentPath.isEmpty ? initialPath : currentPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppTheme.bg)

                Divider().background(AppTheme.border)

                if isLoading {
                    Spacer()
                    ProgressView("Đang tải thư mục trên PC...")
                        .tint(AppTheme.cyan)
                    Spacer()
                } else if let err = errorText {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundColor(AppTheme.amber)
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    Spacer()
                } else {
                    List {
                        if let parent = parentPath {
                            Button {
                                Task { await load(path: parent) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.up.left.square.fill")
                                        .foregroundColor(AppTheme.amber)
                                    Text(".. (Thư mục cha)")
                                        .foregroundColor(AppTheme.textPrimary)
                                }
                            }
                            .listRowBackground(AppTheme.surface)
                        }

                        ForEach(entries) { entry in
                            Button {
                                Task { await load(path: entry.path) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder.fill")
                                        .foregroundColor(AppTheme.cyan)
                                    Text(entry.name)
                                        .foregroundColor(AppTheme.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(AppTheme.textSecondary)
                                }
                            }
                            .listRowBackground(AppTheme.surface)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.bg)
                }

                // Bottom select CTA
                VStack(spacing: 0) {
                    Divider().background(AppTheme.border)
                    Button {
                        let chosen = currentPath.isEmpty ? initialPath : currentPath
                        onSelect(chosen)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Mở phiên mới tại thư mục này")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .foregroundColor(.white)
                        .background(AppTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .padding(14)
                    .background(AppTheme.surface)
                }
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationTitle("Chọn thư mục PC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy") { dismiss() }
                        .foregroundColor(AppTheme.textSecondary)
                }
            }
            .task {
                await load(path: initialPath)
            }
        }
    }

    private func load(path: String?) async {
        isLoading = true
        errorText = nil
        do {
            let listing = try await client.listRemoteDirectory(path: path)
            currentPath = listing.path
            parentPath = listing.parent
            drives = listing.drives
            entries = listing.entries
            errorText = listing.error
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}

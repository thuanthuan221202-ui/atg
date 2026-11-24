import SwiftUI

struct FileBrowserView: View {
    @EnvironmentObject var client: BridgeClient
    @Environment(\.dismiss) private var dismiss

    let initialPath: String
    let onAskAboutFile: (String) -> Void

    @State private var currentPath: String = ""
    @State private var parentPath: String?
    @State private var drives: [String] = []
    @State private var entries: [DirectoryEntry] = []
    @State private var sortMode: String = "recent"
    @State private var searchText: String = ""
    @State private var isLoading = false
    @State private var errorText: String?

    private var filteredEntries: [DirectoryEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return entries }
        return entries.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Drives & Sort strip
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(drives, id: \.self) { drv in
                                Button {
                                    Task { await load(path: drv) }
                                } label: {
                                    Text(drv)
                                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .foregroundColor(currentPath.uppercased().hasPrefix(drv.uppercased()) ? .white : AppTheme.textSecondary)
                                        .background(currentPath.uppercased().hasPrefix(drv.uppercased()) ? AppTheme.accent : AppTheme.card)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    Picker("Sắp xếp", selection: $sortMode) {
                        Text("Mới nhất").tag("recent")
                        Text("A–Z").tag("name")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.surface)

                // Current path bar
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.caption)
                        .foregroundColor(AppTheme.cyan)
                    Text(currentPath.isEmpty ? initialPath : currentPath)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(AppTheme.bg)

                Divider().background(AppTheme.border)

                if isLoading {
                    Spacer()
                    ProgressView("Đang tải tệp trên PC...")
                        .tint(AppTheme.cyan)
                    Spacer()
                } else if let err = errorText {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundColor(AppTheme.amber)
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(AppTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button("Thử lại") {
                            Task { await load(path: currentPath.isEmpty ? initialPath : currentPath) }
                        }
                        .buttonStyle(.borderedProminent)
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
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(AppTheme.textPrimary)
                                }
                            }
                            .listRowBackground(AppTheme.surface)
                        }

                        ForEach(filteredEntries) { entry in
                            if entry.isDirectory {
                                Button {
                                    Task { await load(path: entry.path) }
                                } label: {
                                    entryRow(entry)
                                }
                                .listRowBackground(AppTheme.surface)
                            } else {
                                NavigationLink {
                                    FilePreviewView(entry: entry) { pathToAsk in
                                        dismiss()
                                        onAskAboutFile(pathToAsk)
                                    }
                                } label: {
                                    entryRow(entry)
                                }
                                .listRowBackground(AppTheme.surface)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(AppTheme.bg)
                    .refreshable {
                        await load(path: currentPath.isEmpty ? initialPath : currentPath)
                    }
                }
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .searchable(text: $searchText, prompt: "Tìm tên tệp hoặc thư mục...")
            .navigationTitle("Tệp tin trên PC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
                        .foregroundColor(AppTheme.cyan)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task { await load(path: currentPath.isEmpty ? initialPath : currentPath) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(AppTheme.cyan)
                    }
                }
            }
            .onChange(of: sortMode) { _ in
                Task { await load(path: currentPath.isEmpty ? initialPath : currentPath) }
            }
            .task {
                await load(path: initialPath)
            }
        }
    }

    private func entryRow(_ entry: DirectoryEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconFor(entry))
                .font(.title3)
                .foregroundColor(colorFor(entry))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.subheadline.weight(entry.isDirectory ? .semibold : .regular))
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if !entry.isDirectory && !entry.formattedSize.isEmpty {
                        Text(entry.formattedSize)
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                    if !entry.formattedDate.isEmpty {
                        Text(entry.formattedDate)
                            .font(.caption2)
                            .foregroundColor(AppTheme.textSecondary)
                    }
                }
            }

            Spacer()

            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(AppTheme.textSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func iconFor(_ entry: DirectoryEntry) -> String {
        if entry.isDirectory { return "folder.fill" }
        switch entry.previewKind {
        case "image": return "photo.fill"
        case "text": return "doc.text.fill"
        default:
            let ext = (entry.ext ?? "").lowercased()
            if ext == ".pdf" { return "doc.richtext.fill" }
            if ext == ".zip" || ext == ".ipa" || ext == ".rar" || ext == ".7z" { return "doc.zipper" }
            return "doc.fill"
        }
    }

    private func colorFor(_ entry: DirectoryEntry) -> Color {
        if entry.isDirectory { return AppTheme.cyan }
        switch entry.previewKind {
        case "image": return AppTheme.green
        case "text": return AppTheme.accent
        default: return AppTheme.amber
        }
    }

    private func load(path: String?) async {
        isLoading = true
        errorText = nil
        do {
            let listing = try await client.browseRemoteDirectory(path: path, sortBy: sortMode)
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

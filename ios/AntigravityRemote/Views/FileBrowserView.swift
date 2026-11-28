import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    @State private var showUploadImporter = false
    @State private var isUploading = false
    @State private var uploadStatusText: String?

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

                if let status = uploadStatusText {
                    HStack(spacing: 8) {
                        if isUploading {
                            ProgressView()
                                .tint(AppTheme.cyan)
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(AppTheme.green)
                        }
                        Text(status)
                            .font(.caption)
                            .foregroundColor(AppTheme.textPrimary)
                            .lineLimit(2)
                        Spacer()
                        if !isUploading {
                            Button {
                                uploadStatusText = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.textSecondary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppTheme.surface)
                    Divider().background(AppTheme.border)
                }

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
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showUploadImporter = true
                    } label: {
                        Image(systemName: "arrow.up.doc")
                            .foregroundColor(AppTheme.cyan)
                    }
                    .disabled(isUploading)

                    Button {
                        Task { await load(path: currentPath.isEmpty ? initialPath : currentPath) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(AppTheme.cyan)
                    }
                }
            }
            .fileImporter(
                isPresented: $showUploadImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                Task { await handleUploadSelection(result) }
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

    private func handleUploadSelection(_ result: Result<[URL], Error>) async {
        let urls: [URL]
        switch result {
        case .failure(let err):
            errorText = err.localizedDescription
            return
        case .success(let picked):
            urls = picked
        }
        guard !urls.isEmpty else { return }

        let targetDir = currentPath.isEmpty ? initialPath : currentPath
        isUploading = true
        errorText = nil
        var uploadedNames: [String] = []

        for (idx, url) in urls.enumerated() {
            var staged: AttachedFile?
            do {
                let file = try LocalFileStaging.copyToTemp(from: url)
                staged = file
                uploadStatusText = "Đang gửi lên PC (\(idx + 1)/\(urls.count)): \(file.name)..."
                let res = try await client.uploadRemoteFile(
                    localURL: file.localURL,
                    filename: file.name,
                    targetDirectory: targetDir
                )
                uploadedNames.append(res.name)
                try? FileManager.default.removeItem(at: file.localURL)
            } catch {
                if let f = staged {
                    try? FileManager.default.removeItem(at: f.localURL)
                }
                isUploading = false
                uploadStatusText = nil
                errorText = "Lỗi tải tệp lên PC: \(error.localizedDescription)"
                return
            }
        }

        isUploading = false
        uploadStatusText = "Đã gửi lên PC: \(uploadedNames.joined(separator: ", "))"
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        await load(path: targetDir)
    }
}

import SwiftUI
import PhotosUI
import UIKit

struct ChatWorkspaceView: View {
    @EnvironmentObject var client: BridgeClient
    @EnvironmentObject var settings: SettingsStore

    let onOpenConnections: () -> Void

    @State private var draftText: String = ""
    @State private var showDrawer: Bool = false
    @State private var showFileBrowser: Bool = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var attachedImages: [AttachedImage] = []
    @FocusState private var isInputFocused: Bool

    private var matchingSlashCommands: [SlashCommandItem] {
        guard draftText.hasPrefix("/"), !draftText.contains(" ") else { return [] }
        let query = String(draftText.dropFirst()).lowercased()
        let filtered = client.availableCommands.filter {
            query.isEmpty || $0.name.lowercased().contains(query)
        }
        return Array(filtered.prefix(6))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Sub-header status strip (Model / Mode / Workspace)
                statusBar

                // Chat transcript
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if client.messages.isEmpty {
                                emptyStateView
                            } else {
                                ForEach(client.messages) { msg in
                                    MessageBubbleView(message: msg)
                                        .id(msg.id)
                                }
                            }
                            Color.clear
                                .frame(height: 8)
                                .id("BOTTOM_ANCHOR")
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .background(AppTheme.bg)
                    .onTapGesture {
                        isInputFocused = false
                    }
                    .onChange(of: client.messages.count) { _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                        }
                    }
                    .onChange(of: client.messages.last?.text.count ?? 0) { _ in
                        proxy.scrollTo("BOTTOM_ANCHOR", anchor: .bottom)
                    }
                }

                // Live permission request banner
                if let firstPerm = client.pendingPermissions.first {
                    PermissionBannerView(
                        request: firstPerm,
                        totalCount: client.pendingPermissions.count
                    ) { option in
                        client.respondPermission(requestId: firstPerm.requestId, optionId: option.optionId, cancelled: false)
                    }
                }

                // Slash command autocomplete bar
                if !matchingSlashCommands.isEmpty {
                    slashSuggestionsBar
                }

                // Attached image thumbnails
                if !attachedImages.isEmpty {
                    attachedImagesStrip
                }

                // Bottom Composer
                composerBar
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(AppTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showDrawer = true
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.body.weight(.semibold))
                            .foregroundColor(AppTheme.textPrimary)
                    }
                }

                ToolbarItem(placement: .principal) {
                    Button {
                        showDrawer = true
                    } label: {
                        VStack(spacing: 1) {
                            Text(client.activeTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(AppTheme.textPrimary)
                                .lineLimit(1)
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(statusDotColor)
                                    .frame(width: 6, height: 6)
                                Text(client.connectionState.isConnected ? (client.hostName.isEmpty ? "PC" : client.hostName) : client.connectionState.label)
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showFileBrowser = true
                    } label: {
                        Image(systemName: "folder")
                            .font(.body.weight(.semibold))
                            .foregroundColor(AppTheme.textPrimary)
                    }

                    Button {
                        client.createNewSession(cwd: client.activeCwd)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.body.weight(.semibold))
                            .foregroundColor(AppTheme.cyan)
                    }
                }
            }
            .sheet(isPresented: $showDrawer) {
                SessionDrawerView(onOpenConnections: onOpenConnections)
            }
            .sheet(isPresented: $showFileBrowser) {
                FileBrowserView(initialPath: client.activeCwd.isEmpty ? client.defaultCwd : client.activeCwd) { filePath in
                    draftText = "Xem và tóm tắt file: \(filePath)"
                    isInputFocused = true
                }
            }
            .onChange(of: selectedPhotoItems) { items in
                Task { await loadSelectedPhotos(items) }
            }
        }
    }

    private var statusDotColor: Color {
        switch client.connectionState {
        case .connected: return AppTheme.green
        case .connecting: return AppTheme.amber
        case .disconnected, .error: return AppTheme.red
        }
    }

    private var statusBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Model pill
                if let model = client.modelConfig {
                    Menu {
                        ForEach(model.options) { opt in
                            Button {
                                client.setConfig(configId: model.id, value: opt.value)
                            } label: {
                                if opt.value == model.currentValue {
                                    Label(opt.name, systemImage: "checkmark")
                                } else {
                                    Text(opt.name)
                                }
                            }
                        }
                    } label: {
                        pillLabel(icon: "cpu", text: model.currentDisplayName, color: AppTheme.cyan)
                    }
                }

                // Thinking pill
                if let thought = client.thoughtConfig {
                    Menu {
                        ForEach(thought.options) { opt in
                            Button {
                                client.setConfig(configId: thought.id, value: opt.value)
                            } label: {
                                if opt.value == thought.currentValue {
                                    Label(opt.name, systemImage: "checkmark")
                                } else {
                                    Text(opt.name)
                                }
                            }
                        }
                    } label: {
                        pillLabel(icon: "brain", text: thought.currentDisplayName, color: AppTheme.accent)
                    }
                }

                // Mode pill
                if let mode = client.modeConfig {
                    Menu {
                        ForEach(mode.options) { opt in
                            Button {
                                client.setConfig(configId: mode.id, value: opt.value)
                            } label: {
                                if opt.value == mode.currentValue {
                                    Label(opt.name, systemImage: "checkmark")
                                } else {
                                    Text(opt.name)
                                }
                            }
                        }
                    } label: {
                        pillLabel(icon: "slider.horizontal.3", text: mode.currentDisplayName, color: AppTheme.green)
                    }
                }

                if !client.activeCwd.isEmpty {
                    Button {
                        showDrawer = true
                    } label: {
                        let folderName = (client.activeCwd as NSString).lastPathComponent
                        pillLabel(icon: "folder", text: folderName.isEmpty ? client.activeCwd : folderName, color: AppTheme.textSecondary)
                    }
                }

                if !client.connectionState.isConnected {
                    Button {
                        client.reconnectIfNeeded()
                    } label: {
                        pillLabel(icon: "arrow.clockwise", text: "Kết nối lại", color: AppTheme.amber)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(AppTheme.surface)
        .overlay(
            Rectangle().frame(height: 0.5).foregroundColor(AppTheme.border),
            alignment: .bottom
        )
    }

    private func pillLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(color)
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundColor(AppTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppTheme.card)
        .overlay(
            Capsule().stroke(AppTheme.border, lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 36)
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(AppTheme.cyan)
                .padding(18)
                .background(AppTheme.accent.opacity(0.14))
                .clipShape(Circle())

            Text("Sẵn sàng điều khiển PC")
                .font(.title3.bold())
                .foregroundColor(AppTheme.textPrimary)

            if !client.activeCwd.isEmpty {
                Text(client.activeCwd)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 8) {
                quickPromptChip("Kiểm tra git status và các file đang thay đổi")
                quickPromptChip("Tóm tắt cấu trúc thư mục dự án hiện tại")
                quickPromptChip("/plan Lập kế hoạch cho tính năng mới")
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func quickPromptChip(_ prompt: String) -> some View {
        Button {
            draftText = prompt
            isInputFocused = true
        } label: {
            HStack {
                Text(prompt)
                    .font(.footnote)
                    .foregroundColor(AppTheme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.up.left")
                    .font(.caption)
                    .foregroundColor(AppTheme.cyan)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var slashSuggestionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(matchingSlashCommands) { cmd in
                    Button {
                        draftText = "/\(cmd.name) "
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("/\(cmd.name)")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundColor(AppTheme.cyan)
                            Text(cmd.description)
                                .font(.caption2)
                                .foregroundColor(AppTheme.textSecondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: 190, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppTheme.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(AppTheme.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(AppTheme.surface)
    }

    private var attachedImagesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachedImages) { img in
                    ZStack(alignment: .topTrailing) {
                        if let uiImg = UIImage(data: img.data) {
                            Image(uiImage: uiImg)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 62, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        Button {
                            attachedImages.removeAll { $0.id == img.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .background(Color.black.clipShape(Circle()))
                        }
                        .offset(x: 6, y: -6)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
        .background(AppTheme.surface)
    }

    private var composerBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: 4,
                matching: .images
            ) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundColor(AppTheme.textSecondary)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.card)
                    .clipShape(Circle())
            }

            TextField("Nhắn lệnh cho Antigravity...", text: $draftText, axis: .vertical)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .font(.body)
                .foregroundColor(AppTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(AppTheme.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isInputFocused ? AppTheme.accent : AppTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            if client.isGenerating {
                Button {
                    client.cancelGeneration()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(AppTheme.red)
                        .clipShape(Circle())
                }
            } else {
                let canSend = !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedImages.isEmpty
                Button {
                    sendCurrentMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(canSend && client.connectionState.isConnected ? AppTheme.accent : AppTheme.border)
                        .clipShape(Circle())
                }
                .disabled(!canSend || !client.connectionState.isConnected)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppTheme.surface)
        .overlay(
            Rectangle().frame(height: 0.5).foregroundColor(AppTheme.border),
            alignment: .top
        )
    }

    private func sendCurrentMessage() {
        let text = draftText
        let imgs = attachedImages
        draftText = ""
        attachedImages = []
        selectedPhotoItems = []
        client.sendPrompt(text: text, images: imgs)
    }

    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        var loaded: [AttachedImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                // Compress large iPhone 13 Pro photos so WS upload stays snappy
                if let uiImage = UIImage(data: data),
                   let jpeg = compressImage(uiImage, maxDimension: 1600, quality: 0.78) {
                    loaded.append(AttachedImage(data: jpeg, mimeType: "image/jpeg"))
                } else {
                    loaded.append(AttachedImage(data: data, mimeType: "image/jpeg"))
                }
            }
        }
        attachedImages.append(contentsOf: loaded)
        selectedPhotoItems = []
    }

    private func compressImage(_ image: UIImage, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let maxSide = max(size.width, size.height)
        if maxSide <= maxDimension {
            return image.jpegData(compressionQuality: quality)
        }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

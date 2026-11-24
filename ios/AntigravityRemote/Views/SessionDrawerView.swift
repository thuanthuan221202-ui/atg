import SwiftUI

struct SessionDrawerView: View {
    @EnvironmentObject var client: BridgeClient
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    let onOpenConnections: () -> Void

    @State private var searchText = ""
    @State private var showFolderPicker = false

    private var filteredSessions: [SessionSummary] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return client.sessions }
        return client.sessions.filter {
            $0.title.lowercased().contains(q) || $0.cwd.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Connection status section
                Section {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(client.connectionState.isConnected ? AppTheme.green : AppTheme.amber)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(client.hostName.isEmpty ? (settings.activeProfile?.name ?? "PC") : client.hostName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(AppTheme.textPrimary)
                            Text(client.connectionState.label + (client.tierName.map { " • \($0)" } ?? ""))
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                        Spacer()
                        Button("Đổi PC") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                onOpenConnections()
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.cyan)
                    }
                    .listRowBackground(AppTheme.surface)

                    // Workspace picker
                    Button {
                        showFolderPicker = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(AppTheme.cyan)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Thư mục làm việc hiện tại")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.textSecondary)
                                Text(client.activeCwd.isEmpty ? client.defaultCwd : client.activeCwd)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(AppTheme.textPrimary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(AppTheme.textSecondary)
                        }
                    }
                    .listRowBackground(AppTheme.surface)
                } header: {
                    Text("Máy tính & Workspace")
                }

                // Model / Thinking / Mode Config Options
                if !client.configOptions.isEmpty {
                    Section {
                        ForEach(client.configOptions) { cfg in
                            Picker(cfg.name, selection: Binding(
                                get: { cfg.currentValue },
                                set: { newVal in
                                    client.setConfig(configId: cfg.id, value: newVal)
                                }
                            )) {
                                ForEach(cfg.options) { opt in
                                    Text(opt.name).tag(opt.value)
                                }
                            }
                            .tint(AppTheme.cyan)
                            .listRowBackground(AppTheme.surface)
                        }

                        // Context window indicator
                        if client.usage.size > 0 {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Ngữ cảnh đã dùng")
                                        .font(.caption)
                                        .foregroundColor(AppTheme.textSecondary)
                                    Spacer()
                                    Text("\(client.usage.formattedUsed) tokens (\(Int(client.usage.fraction * 100))%)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(AppTheme.textPrimary)
                                }
                                ProgressView(value: client.usage.fraction)
                                    .tint(client.usage.fraction > 0.8 ? AppTheme.amber : AppTheme.cyan)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(AppTheme.surface)
                        }
                    } header: {
                        Text("Cấu hình Agent")
                    }
                }

                // Conversations history
                Section {
                    Button {
                        client.createNewSession(cwd: client.activeCwd)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(AppTheme.accent)
                            Text("Tạo cuộc trò chuyện mới")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(AppTheme.accent)
                        }
                    }
                    .listRowBackground(AppTheme.surface)

                    ForEach(filteredSessions) { sess in
                        Button {
                            client.loadSession(sess)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sess.title)
                                        .font(.subheadline.weight(sess.sessionId == client.activeSessionId ? .bold : .medium))
                                        .foregroundColor(sess.sessionId == client.activeSessionId ? AppTheme.cyan : AppTheme.textPrimary)
                                        .lineLimit(2)
                                    Text(sess.cwd)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(AppTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if sess.sessionId == client.activeSessionId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(AppTheme.cyan)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .listRowBackground(sess.sessionId == client.activeSessionId ? AppTheme.card : AppTheme.surface)
                    }
                } header: {
                    Text("Cuộc trò chuyện (\(filteredSessions.count))")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .searchable(text: $searchText, prompt: "Tìm cuộc trò chuyện hoặc thư mục...")
            .navigationTitle("Phiên & Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Xong") { dismiss() }
                        .foregroundColor(AppTheme.cyan)
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPickerView(initialPath: client.activeCwd.isEmpty ? client.defaultCwd : client.activeCwd) { chosenCwd in
                    client.createNewSession(cwd: chosenCwd)
                    dismiss()
                }
            }
            .onAppear {
                client.requestSessionList()
            }
        }
    }
}

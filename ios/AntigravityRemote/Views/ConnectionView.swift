import SwiftUI
import UIKit

struct ConnectionView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var client: BridgeClient

    let canDismiss: Bool
    let onConnected: () -> Void

    @State private var pcName: String = "Windows PC"
    @State private var serverURL: String = ""
    @State private var token: String = ""
    @State private var isTesting: Bool = false
    @State private var errorMessage: String?
    @State private var showScanner: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerCard

                    // Primary QR Pairing CTA
                    Button {
                        showScanner = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 22, weight: .semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Quét mã QR từ máy tính")
                                    .font(.headline)
                                Text("Tự động điền địa chỉ IP & Token trong 1 giây")
                                    .font(.caption)
                                    .opacity(0.85)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .opacity(0.8)
                        }
                        .padding(16)
                        .foregroundColor(.white)
                        .background(
                            LinearGradient(
                                colors: [AppTheme.accent, Color(red: 0.14, green: 0.36, blue: 0.88)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    // Saved profiles section
                    if !settings.profiles.isEmpty {
                        savedProfilesSection
                    }

                    // Manual form section
                    manualFormSection
                }
                .padding(16)
            }
            .background(AppTheme.bg.ignoresSafeArea())
            .navigationTitle("Kết nối PC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canDismiss {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Đóng") {
                            onConnected()
                        }
                        .foregroundColor(AppTheme.cyan)
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { scanned in
                    showScanner = false
                    handleScannedCode(scanned)
                }
            }
            .onAppear {
                if let active = settings.activeProfile, serverURL.isEmpty {
                    pcName = active.name
                    serverURL = active.baseURL
                    token = active.token
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.18))
                    .frame(width: 68, height: 68)
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(AppTheme.cyan)
            }
            Text("Antigravity Remote")
                .font(.title2.bold())
                .foregroundColor(AppTheme.textPrimary)
            Text("Điều khiển Antigravity trên Windows qua Wi-Fi hoặc Tailscale — tối ưu cho iOS 16.")
                .font(.footnote)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .padding(.vertical, 8)
    }

    private var savedProfilesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MÁY TÍNH ĐÃ LƯU")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.textSecondary)
                .padding(.leading, 4)

            ForEach(settings.profiles) { profile in
                HStack(spacing: 12) {
                    Button {
                        settings.selectProfile(profile)
                        client.connect(to: profile)
                        onConnected()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: profile.baseURL.contains("100.") ? "globe" : "wifi")
                                .font(.title3)
                                .foregroundColor(AppTheme.cyan)
                                .frame(width: 34, height: 34)
                                .background(AppTheme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(profile.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(AppTheme.textPrimary)
                                    if settings.activeProfileId == profile.id && client.connectionState.isConnected {
                                        Circle()
                                            .fill(AppTheme.green)
                                            .frame(width: 7, height: 7)
                                    }
                                }
                                Text(profile.baseURL)
                                    .font(.caption)
                                    .foregroundColor(AppTheme.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }

                    Button {
                        settings.removeProfile(profile)
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundColor(AppTheme.red.opacity(0.85))
                            .padding(8)
                    }
                }
                .padding(12)
                .background(AppTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(settings.activeProfileId == profile.id ? AppTheme.accent : AppTheme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var manualFormSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NHẬP THỦ CÔNG (WI-FI / TAILSCALE)")
                .font(.caption.weight(.semibold))
                .foregroundColor(AppTheme.textSecondary)
                .padding(.leading, 4)

            VStack(spacing: 12) {
                inputField(title: "Tên gợi nhớ", placeholder: "VD: PC Ở Nhà (Wi-Fi) hoặc Tailscale", text: $pcName, isSecure: false)
                inputField(title: "Địa chỉ Bridge Server", placeholder: "http://192.168.1.10:8787", text: $serverURL, isSecure: false)
                inputField(title: "Auth Token", placeholder: "Dán token từ cửa sổ terminal PC", text: $token, isSecure: true)

                if let err = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppTheme.amber)
                        Text(err)
                            .font(.caption)
                            .foregroundColor(AppTheme.amber)
                        Spacer()
                    }
                    .padding(10)
                    .background(AppTheme.amber.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                Button {
                    Task { await verifyAndConnect() }
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .tint(.white)
                                .padding(.trailing, 4)
                        }
                        Text(isTesting ? "Đang kiểm tra kết nối..." : "Lưu & Kết nối")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundColor(.white)
                    .background(canSubmit ? AppTheme.accent : AppTheme.border)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(!canSubmit || isTesting)
            }
            .padding(14)
            .background(AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var canSubmit: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func inputField(title: String, placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundColor(AppTheme.textSecondary)
            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                } else {
                    TextField(placeholder, text: text)
                        .keyboardType(.URL)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .font(.subheadline)
            .padding(11)
            .background(AppTheme.bg)
            .foregroundColor(AppTheme.textPrimary)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func handleScannedCode(_ raw: String) {
        if let payload = PairingParser.parse(raw) {
            pcName = payload.name
            serverURL = payload.url
            token = payload.token
            errorMessage = nil
            Task { await verifyAndConnect() }
        } else {
            errorMessage = "Mã QR không phải định dạng ghép nối của Antigravity Bridge."
        }
    }

    private func verifyAndConnect() async {
        errorMessage = nil
        isTesting = true
        let result = await client.testConnection(baseURL: serverURL, token: token)
        isTesting = false

        switch result {
        case .success(let detectedHost):
            let finalName = pcName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? detectedHost : pcName
            let profile = settings.upsertProfile(name: finalName, baseURL: serverURL, token: token)
            client.connect(to: profile)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onConnected()
        case .failure(let error):
            errorMessage = "Không thể kết nối: \(error.localizedDescription). Hãy kiểm tra PC đã chạy start-bridge.bat và cùng mạng Wi-Fi / Tailscale."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

import SwiftUI
import UIKit

struct FilePreviewView: View {
    @EnvironmentObject var client: BridgeClient
    let entry: DirectoryEntry
    let onAskAboutFile: (String) -> Void

    @State private var textResponse: FileReadResponse?
    @State private var imagePreview: UIImage?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var wrapLines = true
    @State private var copied = false
    @State private var zoomScale: CGFloat = 1.0

    @State private var isDownloadingForShare = false
    @State private var shareFileURL: URL?
    @State private var showShareSheet = false

    private var kind: String {
        entry.previewKind ?? "binary"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Path & metadata bar
            HStack(spacing: 8) {
                Text(entry.path)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
                    .lineLimit(1)
                Spacer()
                if !entry.formattedSize.isEmpty {
                    Text(entry.formattedSize)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(AppTheme.cyan)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(AppTheme.surface)

            Divider().background(AppTheme.border)

            if isLoading {
                Spacer()
                ProgressView("Đang tải từ máy tính...")
                    .tint(AppTheme.cyan)
                Spacer()
            } else if let err = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(AppTheme.amber)
                    Text(err)
                        .font(.subheadline)
                        .foregroundColor(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button("Thử lại") {
                        Task { await loadPreview() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer()
            } else if kind == "image", let uiImg = imagePreview {
                imageViewer(uiImg)
            } else if kind == "text", let resp = textResponse {
                textViewer(resp)
            } else {
                binaryOverview
            }

            // Bottom action bar
            actionFooter
        }
        .background(AppTheme.bg.ignoresSafeArea())
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if kind == "text" {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        wrapLines.toggle()
                    } label: {
                        Image(systemName: wrapLines ? "text.alignleft" : "arrow.left.and.right.text.vertical")
                            .foregroundColor(AppTheme.cyan)
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let fileURL = shareFileURL {
                ActivityShareSheet(items: [fileURL])
            }
        }
        .task {
            await loadPreview()
        }
    }

    private func imageViewer(_ uiImg: UIImage) -> some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            Image(uiImage: uiImg)
                .resizable()
                .scaledToFit()
                .scaleEffect(zoomScale)
                .frame(maxWidth: UIScreen.main.bounds.width * max(1.0, zoomScale))
                .padding(12)
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in
                            zoomScale = min(4.0, max(1.0, val))
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        zoomScale = zoomScale > 1.1 ? 1.0 : 2.2
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func textViewer(_ resp: FileReadResponse) -> some View {
        VStack(spacing: 0) {
            if resp.truncated {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(AppTheme.amber)
                    Text("Tệp lớn hơn 512 KB — đang hiển thị phần đầu. Dùng nút Tải / Chia sẻ để lấy toàn bộ tệp.")
                        .font(.caption2)
                        .foregroundColor(AppTheme.amber)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.amber.opacity(0.12))
            }

            if wrapLines {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(resp.content.isEmpty ? "(Tệp trống)" : resp.content)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                .background(AppTheme.codeBg)
            } else {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Text(resp.content.isEmpty ? "(Tệp trống)" : resp.content)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                        .fixedSize(horizontal: true, vertical: false)
                        .textSelection(.enabled)
                        .padding(14)
                }
                .background(AppTheme.codeBg)
            }
        }
    }

    private var binaryOverview: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.zipper")
                .font(.system(size: 52))
                .foregroundColor(AppTheme.cyan)
                .padding(22)
                .background(AppTheme.card)
                .clipShape(Circle())

            Text(entry.name)
                .font(.headline)
                .foregroundColor(AppTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("Định dạng nhị phân (\(entry.formattedSize)). Bấm \"Tải / Chia sẻ\" bên dưới để xem bằng ứng dụng Tệp (Files), PDF Viewer hoặc gửi đi.")
                .font(.footnote)
                .foregroundColor(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var actionFooter: some View {
        VStack(spacing: 0) {
            Divider().background(AppTheme.border)
            HStack(spacing: 8) {
                if kind == "text", let content = textResponse?.content {
                    Button {
                        UIPasteboard.general.string = content
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            Text(copied ? "Đã chép" : "Chép")
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .foregroundColor(copied ? AppTheme.green : AppTheme.textPrimary)
                        .background(AppTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }

                Button {
                    onAskAboutFile(entry.path)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                        Text("Hỏi AI")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .foregroundColor(AppTheme.cyan)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Button {
                    Task { await downloadAndShare() }
                } label: {
                    HStack(spacing: 6) {
                        if isDownloadingForShare {
                            ProgressView().tint(.white).scaleEffect(0.85)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text(isDownloadingForShare ? "Đang tải..." : "Tải / Chia sẻ")
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundColor(.white)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(isDownloadingForShare)
            }
            .padding(12)
            .background(AppTheme.surface)
        }
    }

    private func loadPreview() async {
        guard kind == "text" || kind == "image" else { return }
        isLoading = true
        errorMessage = nil
        do {
            if kind == "text" {
                textResponse = try await client.readRemoteFile(path: entry.path)
            } else if kind == "image" {
                let data = try await client.downloadRemoteFileData(path: entry.path)
                if let img = UIImage(data: data) {
                    imagePreview = img
                } else {
                    errorMessage = "Không thể giải mã hình ảnh này."
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func downloadAndShare() async {
        isDownloadingForShare = true
        errorMessage = nil
        do {
            let data = try await client.downloadRemoteFileData(path: entry.path)
            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(entry.name)
            try data.write(to: tmpURL, options: .atomic)
            shareFileURL = tmpURL
            showShareSheet = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            errorMessage = error.localizedDescription
        }
        isDownloadingForShare = false
    }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

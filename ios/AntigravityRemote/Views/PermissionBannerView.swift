import SwiftUI

struct PermissionBannerView: View {
    let request: PermissionRequest
    let totalCount: Int
    let onRespond: (PermissionOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(AppTheme.amber)

                Text("Cần duyệt lệnh")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(AppTheme.amber)

                if totalCount > 1 {
                    Text("+\(totalCount - 1)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.amber.opacity(0.22))
                        .foregroundColor(AppTheme.amber)
                        .clipShape(Capsule())
                }

                Spacer()

                Text(request.toolCall.name)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(AppTheme.textSecondary)
            }

            if !request.toolCall.inputSummary.isEmpty {
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    Text(request.toolCall.inputSummary)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundColor(AppTheme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 96)
                .padding(10)
                .background(AppTheme.codeBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.amber.opacity(0.35), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(spacing: 10) {
                ForEach(request.options) { opt in
                    Button {
                        onRespond(opt)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: opt.isReject ? "xmark.circle.fill" : "checkmark.circle.fill")
                            Text(labelFor(opt))
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundColor(.white)
                        .background(opt.isReject ? AppTheme.red : AppTheme.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
        .background(Color(red: 0.145, green: 0.102, blue: 0.043))
        .overlay(
            Rectangle()
                .frame(height: 1.5)
                .foregroundColor(AppTheme.amber),
            alignment: .top
        )
    }

    private func labelFor(_ opt: PermissionOption) -> String {
        switch opt.kind.lowercased() {
        case "allow_once": return "Cho phép"
        case "allow_always": return "Luôn cho phép"
        case "reject_once": return "Từ chối"
        case "reject_always": return "Luôn từ chối"
        default: return opt.name
        }
    }
}

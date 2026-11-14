import SwiftUI
import TendbarDomain

/// Allow and Deny for a prompt Claude Code shows in the terminal, with the whole command or file above them, so
/// Allow never approves something unseen. The terminal prompt keeps working; whichever answers first decides.
struct PermissionPrompt: View {
    let ask: PermissionAsk
    /// Lines of the command shown before it is cut; the pill has less room than the panel.
    var lineLimit = 6
    let onAnswer: (PermissionDecision) -> Void
    /// The pill can open under a moving pointer, so the buttons wait a moment before they take a click.
    @State private var armed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Allow \(ask.tool)?")
                .fontWeight(.medium)
            if let detail = ask.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(lineLimit)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .help(detail)
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Deny", role: .destructive) { onAnswer(.deny) }
                Button("Allow") { onAnswer(.allow) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
            .disabled(!armed)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(500))
            armed = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Allow \(ask.tool)?"))
    }
}

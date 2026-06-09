import SwiftUI

/// A transient success pill pinned near the bottom of the window. Auto-dismisses
/// ~2.4s after `message` becomes non-nil by clearing the binding.
struct CopiedToast: View {
    @Binding var message: String?

    var body: some View {
        VStack {
            Spacer()
            if let message {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(OMWColor.sysGreen)
                    Text(message).font(.system(size: 12, weight: .medium)).foregroundStyle(OMWColor.labelPrimary)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .glassEffect(.regular, in: Capsule())
                .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
                .padding(.bottom, 46)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: message) {
                    // swiftlint:disable:next no_arbitrary_delay
                    try? await Task.sleep(for: .seconds(2.4))
                    self.message = nil
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: message)
        .allowsHitTesting(false)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

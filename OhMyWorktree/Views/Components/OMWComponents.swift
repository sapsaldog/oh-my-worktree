import SwiftUI

// Reusable Tahoe visual primitives shared by the row, detail pane, and menus.
// Dimensions match the prototype CSS (.wt-dot, .badge, .ab, .job-*, .diffstat, .chip).

// MARK: - Status dot

/// A 9pt colored status dot (root/active green · locked orange · detached yellow ·
/// bare gray). Gains a white ring when its row is selected.
struct StatusDot: View {
    var color: Color
    var diameter: CGFloat = 9
    var selected: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .overlay {
                if selected {
                    Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 2).padding(-2)
                }
            }
    }
}

// MARK: - Badge

/// A capsule badge (height 16, 10pt semibold) with an optional leading SF Symbol.
struct OMWBadge: View {
    var text: String
    var symbol: String?
    var foreground: Color
    var background: Color

    init(_ text: String, symbol: String? = nil, foreground: Color, background: Color) {
        self.text = text
        self.symbol = symbol
        self.foreground = foreground
        self.background = background
    }

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            }
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(background, in: Capsule())
        .fixedSize()
    }

    // Common variants (CSS: .badge.gray/.draft/.locked/.detached).
    static var main: OMWBadge { OMWBadge("main", foreground: OMWColor.labelSecondary, background: OMWColor.fillSecondary) }
    static var bare: OMWBadge { OMWBadge("bare", foreground: OMWColor.labelSecondary, background: OMWColor.fillSecondary) }
    static var draft: OMWBadge { OMWBadge("Draft", foreground: OMWColor.labelSecondary, background: OMWColor.fillSecondary) }
    static var locked: OMWBadge {
        OMWBadge("locked", symbol: "lock.fill", foreground: OMWColor.sysOrange, background: OMWColor.sysOrange.opacity(0.16))
    }
    static var detached: OMWBadge {
        OMWBadge("detached", foreground: OMWColor.detachedBadgeText, background: OMWColor.sysYellow.opacity(0.18))
    }
    /// A neutral gray badge with arbitrary text (e.g. the detail status label).
    static func gray(_ text: String) -> OMWBadge {
        OMWBadge(text, foreground: OMWColor.labelSecondary, background: OMWColor.fillSecondary)
    }
}

/// PR state badge: octicon + `#number` in a state-tinted capsule.
struct PRBadge: View {
    var state: PullRequestState
    var number: Int

    var body: some View {
        HStack(spacing: 3) {
            PullRequestStateIcon(state: state, size: 11)
            Text("#\(number)").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(state.color)
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(state.color.opacity(0.16), in: Capsule())
        .fixedSize()
    }
}

// MARK: - Ahead / behind

/// `↑ahead ↓behind` in mono, shown only for nonzero counts.
struct AheadBehindLabel: View {
    var ahead: Int
    var behind: Int

    var body: some View {
        HStack(spacing: 6) {
            if ahead > 0 {
                Label("\(ahead)", systemImage: "arrow.up").labelStyle(.titleAndIcon)
            }
            if behind > 0 {
                Label("\(behind)", systemImage: "arrow.down").labelStyle(.titleAndIcon)
            }
        }
        .font(.omwMono(10, weight: .medium))
        .foregroundStyle(OMWColor.labelTertiary)
    }
}

// MARK: - Job indicator

/// Background-job status: spinner / check / cross / clock, matching the prototype.
struct JobIndicator: View {
    var state: BackgroundJobState

    var body: some View {
        switch state {
        case .pending:
            Image(systemName: "clock").font(.system(size: 13)).foregroundStyle(OMWColor.labelSecondary)
        case .inProgress:
            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
        case .completed:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 14)).foregroundStyle(OMWColor.sysGreen)
        case .failed:
            Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(OMWColor.sysRed)
        case .cancelled:
            Image(systemName: "minus.circle").font(.system(size: 14)).foregroundStyle(OMWColor.labelTertiary)
        }
    }
}

// MARK: - Diff stat bar

/// `+added −removed` with a proportional green/red bar and file count.
struct DiffStatBar: View {
    var added: Int
    var removed: Int
    var files: Int

    var body: some View {
        let total = max(added + removed, 1)
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("+\(added)").foregroundStyle(OMWColor.sysGreen)
                Text("−\(removed)").foregroundStyle(OMWColor.sysRed)
            }
            .font(.omwMono(12, weight: .semibold))

            GeometryReader { geo in
                HStack(spacing: 0) {
                    OMWColor.sysGreen.frame(width: geo.size.width * CGFloat(added) / CGFloat(total))
                    OMWColor.sysRed.frame(width: geo.size.width * CGFloat(removed) / CGFloat(total))
                    OMWColor.fillSecondary
                }
            }
            .frame(height: 7)
            .clipShape(Capsule())

            Text("\(files) files")
                .font(.system(size: 11))
                .foregroundStyle(OMWColor.labelTertiary)
                .fixedSize()
        }
    }
}

// MARK: - Flow layout (wrapping chips)

/// A simple wrapping layout (CSS flex-wrap equivalent) for chips/badges.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                totalHeight += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        let width = maxWidth == .infinity ? x : maxWidth
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Copied-file chip

/// A `.worktreeinclude` copied-file chip (mono, file glyph, fill-tertiary pill).
struct CopiedFileChip: View {
    var name: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc").font(.system(size: 11)).foregroundStyle(OMWColor.labelTertiary)
            Text(name).font(.omwMono(11, weight: .medium)).foregroundStyle(OMWColor.labelSecondary)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(OMWColor.fillTertiary, in: Capsule())
    }
}

// MARK: - Switch toggle

/// The prototype's `.mac-switch` (components.css): a 38×22 pill that fills with the
/// accent when on, carrying an 18×18 white knob that slides 16px. Use via
/// `.toggleStyle(.omwSwitch)` so glass-sheet toggles match the Tahoe mockup exactly
/// instead of the native `.switch`.
struct OMWSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SwitchBody(configuration: configuration)
    }

    // A nested View so `@Environment(\.omwAccent)` is actually injected — environment
    // values are not reliably populated on a bare ToggleStyle struct.
    private struct SwitchBody: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.omwAccent) private var accent

        var body: some View {
            Button { configuration.isOn.toggle() } label: { track }
                .buttonStyle(.plain)
                .accessibilityRepresentation {
                    Toggle(isOn: configuration.$isOn) { configuration.label }
                }
        }

        private var track: some View {
            Capsule()
                .fill(OMWColor.fillPrimary)
                .frame(width: 38, height: 22)
                .overlay { Capsule().fill(accent).opacity(configuration.isOn ? 1 : 0) }
                .overlay(alignment: .leading) { knob }
                .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.22), value: configuration.isOn)
        }

        private var knob: some View {
            Circle()
                .fill(.white)
                .frame(width: 18, height: 18)
                .overlay { Circle().strokeBorder(.black.opacity(0.04), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                .offset(x: configuration.isOn ? 18 : 2)
        }
    }
}

extension ToggleStyle where Self == OMWSwitchToggleStyle {
    /// The Tahoe `.mac-switch` pill — see ``OMWSwitchToggleStyle``.
    static var omwSwitch: OMWSwitchToggleStyle { OMWSwitchToggleStyle() }
}

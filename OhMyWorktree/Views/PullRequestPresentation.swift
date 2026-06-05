import SwiftUI

// View-layer formatting for PR review + check status (detail card).

extension ReviewDecision {
    /// Human summary for the PR card; nil hides the line.
    var summary: String? {
        switch self {
        case .approved: "approved"
        case .changesRequested: "changes requested"
        case .reviewRequired: "review required"
        case .none: nil
        }
    }
}

extension CheckStatus {
    /// Label for the "checks …" line; nil hides it.
    var label: String? {
        switch self {
        case .passing: "passing"
        case .failing: "failing"
        case .pending: "running"
        case .none: nil
        }
    }

    var color: Color {
        switch self {
        case .passing: OMWColor.sysGreen
        case .failing: OMWColor.sysRed
        case .pending: OMWColor.sysOrange
        case .none: OMWColor.labelTertiary
        }
    }

    var systemImage: String {
        switch self {
        case .passing: "checkmark"
        case .failing: "xmark"
        case .pending: "circle.dotted"
        case .none: "circle"
        }
    }
}

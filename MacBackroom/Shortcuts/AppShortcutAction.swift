enum AppShortcutAction: String, CaseIterable, Hashable, Identifiable {
    case switchLeft
    case switchRight
    case pasteTicketDate
    case pasteCompactDate

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .switchLeft:
            return "Switch Left"
        case .switchRight:
            return "Switch Right"
        case .pasteTicketDate:
            return "Paste 0410-🚧-"
        case .pasteCompactDate:
            return "Paste 260410"
        }
    }

    var systemImage: String {
        switch self {
        case .switchLeft:
            return "arrow.left.circle"
        case .switchRight:
            return "arrow.right.circle"
        case .pasteTicketDate:
            return "text.insert"
        case .pasteCompactDate:
            return "calendar"
        }
    }

    var detailText: String {
        switch self {
        case .switchLeft:
            return "Trigger a one-step switch to the previous Space."
        case .switchRight:
            return "Trigger a one-step switch to the next Space."
        case .pasteTicketDate:
            return "Pastes today's date as `MMdd-🚧-`."
        case .pasteCompactDate:
            return "Pastes today's date as `yyMMdd`."
        }
    }

    var defaultShortcut: HotKeyCenter.Shortcut {
        switch self {
        case .switchLeft:
            return .switchLeft
        case .switchRight:
            return .switchRight
        case .pasteTicketDate:
            return .pasteTicketDate
        case .pasteCompactDate:
            return .pasteCompactDate
        }
    }

    var defaultsKey: String {
        "shortcut.\(rawValue)"
    }
}

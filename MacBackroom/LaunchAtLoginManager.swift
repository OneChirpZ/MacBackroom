import Foundation
import ServiceManagement

struct LaunchAtLoginState {
    let isEnabled: Bool
    let detailMessage: String
}

final class LaunchAtLoginManager {
    private let service = SMAppService.mainApp

    func currentState() -> LaunchAtLoginState {
        let installedInApplications = Self.isInstalledInApplicationsFolder

        switch service.status {
        case .enabled:
            if installedInApplications {
                return LaunchAtLoginState(
                    isEnabled: true,
                    detailMessage: "MacBackroom will launch automatically when you log in."
                )
            }

            return LaunchAtLoginState(
                isEnabled: true,
                detailMessage: "Enabled for the current app path. Install the app in Applications for a stable login item."
            )

        case .requiresApproval:
            return LaunchAtLoginState(
                isEnabled: true,
                detailMessage: "Pending approval in System Settings > General > Login Items."
            )

        case .notRegistered:
            if installedInApplications {
                return LaunchAtLoginState(
                    isEnabled: false,
                    detailMessage: "MacBackroom will not launch at login until you enable it."
                )
            }

            return LaunchAtLoginState(
                isEnabled: false,
                detailMessage: "Install the app in Applications before enabling launch at login."
            )

        case .notFound:
            return LaunchAtLoginState(
                isEnabled: false,
                detailMessage: "macOS could not resolve this app in Login Items."
            )

        @unknown default:
            return LaunchAtLoginState(
                isEnabled: false,
                detailMessage: "Launch at login status is unavailable on this macOS build."
            )
        }
    }

    func setEnabled(_ isEnabled: Bool) throws -> LaunchAtLoginState {
        if isEnabled {
            try service.register()
        } else {
            try service.unregister()
        }

        return currentState()
    }

    static var isInstalledInApplicationsFolder: Bool {
        let bundlePath = URL(fileURLWithPath: Bundle.main.bundlePath)
            .resolvingSymlinksInPath()
            .path
        let userApplicationsPath = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Applications")
            .path

        return bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix(userApplicationsPath + "/")
    }
}

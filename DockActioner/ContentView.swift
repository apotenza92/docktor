import SwiftUI
import AppKit

struct PreferencesView: View {
    @ObservedObject var coordinator: DockExposeCoordinator
    @ObservedObject var preferences = Preferences.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            appSettingsSection
            Divider()
            actionsSection
            Divider()
            permissionsSection
        }
        .padding(14)
        .frame(minWidth: 420, idealWidth: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var shouldShowPermissionsBanner: Bool {
        !coordinator.accessibilityGranted || !coordinator.inputMonitoringGranted
    }

    private var permissionsBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Permissions Needed")
                .font(.headline)
            Text("DockActioner needs Accessibility and Input Monitoring to detect Dock gestures.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                if !coordinator.accessibilityGranted {
                    Button("Grant Accessibility", action: openAccessibilitySettings)
                        .controlSize(.small)
                }
                if !coordinator.inputMonitoringGranted {
                    Button("Grant Input Monitoring", action: openInputMonitoringSettings)
                        .controlSize(.small)
                }
                Spacer()
            }
            Text("Tip: when developing, sign the app with a consistent identity (Xcode: Signing & Capabilities -> Team) so macOS doesn't treat each rebuild as a new app.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .background(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
        .cornerRadius(8)
    }
    
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "rectangle.dock")
                .font(.system(size: 28, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("DockActioner")
                    .font(.title3).fontWeight(.semibold)
            }
            Spacer()
        }
    }
    
    private var permissionsSection: some View {
        sectionBox {
            VStack(alignment: .leading, spacing: 22) {
                if shouldShowPermissionsBanner {
                    permissionsBanner
                }
                permissionRow(
                    title: "Accessibility",
                    detail: "Required to hit-test Dock icons and control other apps.",
                    granted: coordinator.accessibilityGranted,
                    actionTitle: coordinator.accessibilityGranted ? "Open Accessibility Settings" : "Grant Accessibility",
                    action: openAccessibilitySettings
                )
                permissionRow(
                    title: "Input Monitoring",
                    detail: "Required for the global event tap (clicks and scrolls).",
                    granted: coordinator.inputMonitoringGranted,
                    actionTitle: coordinator.inputMonitoringGranted ? "Open Input Monitoring Settings" : "Grant Input Monitoring",
                    action: openInputMonitoringSettings
                )
            }
        }
    }
    
    private func permissionRow(title: String,
                               detail: String,
                               granted: Bool,
                               actionTitle: String?,
                               action: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.body).fontWeight(.semibold)
                Spacer()
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .foregroundColor(granted ? .green : .orange)
            }
            Text(detail)
                .font(.body)
                .foregroundColor(.secondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
    }
    
    private var actionsSection: some View {
        sectionBox {
            VStack(alignment: .leading, spacing: 12) {
                actionRow(label: "Click", selection: $preferences.clickAction)
                actionRow(label: "Scroll Up", selection: $preferences.scrollUpAction)
                actionRow(label: "Scroll Down", selection: $preferences.scrollDownAction)
            }
        }
    }
    
    private var appSettingsSection: some View {
        sectionBox {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show settings on startup", isOn: $preferences.showOnStartup)
                Toggle("Start DockActioner at login", isOn: $preferences.startAtLogin)
                HStack(spacing: 12) {
                    Button("Restart App", action: restartApp)
                        .buttonStyle(.bordered)
                    Button("Quit", action: { NSApp.terminate(nil) })
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    private func sectionBox<T: View>(@ViewBuilder content: () -> T) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private func actionRow(label: String, selection: Binding<DockAction>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Picker("", selection: selection) {
                    ForEach(DockAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 170)
            }
            if let hint = hint(for: selection.wrappedValue) {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func hint(for action: DockAction) -> String? {
        switch action {
        case .hideApp:
            return "Option: Hide Others · Shift: Bring All to Front"
        case .hideOthers:
            return "Option: Hide App · Shift: Bring All to Front"
        case .bringAllToFront:
            return "Option: Hide Others · Shift: Hide App"
        case .appExpose:
            return "Uses Dock notification trigger"
        default:
            return nil
        }
    }
    
    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        coordinator.requestAccessibilityPermission()
        coordinator.startWhenPermissionAvailable()
    }

    private func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        coordinator.requestInputMonitoringPermission()
        coordinator.startWhenPermissionAvailable()
    }
    
    private func restartApp() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [bundleURL.path]
        do {
            try task.run()
        } catch {
            Logger.log("Failed to relaunch app: \(error.localizedDescription)")
        }
        NSApp.terminate(nil)
    }
}

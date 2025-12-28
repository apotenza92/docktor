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
            Divider()
            controlSection
        }
        .padding(14)
        .frame(minWidth: 420, idealWidth: 420)
        .fixedSize(horizontal: false, vertical: true)
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
                permissionRow(
                    title: "Accessibility",
                    detail: "Required to detect Dock clicks and scrolls.",
                    granted: coordinator.accessibilityGranted,
                    actionTitle: coordinator.accessibilityGranted ? "Open Accessibility Settings" : "Grant Accessibility",
                    action: openAccessibilitySettings
                )
                permissionRow(
                    title: "Automation (Apple Events)",
                    detail: "Needed to send the App Exposé shortcut via System Events.",
                    granted: true,
                    actionTitle: "Open Automation Settings",
                    action: openAutomationSettings
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
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Show settings on startup", isOn: $preferences.showOnStartup)
                Toggle("Start DockActioner at login", isOn: $preferences.startAtLogin)
            }
        }
    }
    
    private var controlSection: some View {
        sectionBox {
            HStack(spacing: 12) {
                Button("Restart App", action: restartApp)
                    .buttonStyle(.bordered)
                Button("Quit", action: { NSApp.terminate(nil) })
                    .buttonStyle(.borderedProminent)
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
    
    private func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
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

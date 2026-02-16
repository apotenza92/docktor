import SwiftUI
import AppKit

struct PreferencesView: View {
    @ObservedObject var coordinator: DockExposeCoordinator
    @ObservedObject var preferences = Preferences.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                appSettingsSection
                Divider()
                actionsSection
                Divider()
                permissionsSection
            }
            .padding(16)
            .frame(minWidth: 560, idealWidth: 560, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: false)
    }

    private var appSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("General")
                .font(.headline)
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

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Action Mappings")
                .font(.headline)

            HStack(spacing: 12) {
                Text("Input")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 220, alignment: .leading)
                Text("Action")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }

            Divider()

            mappingRow(label: "Click", selection: $preferences.clickAction)
            mappingRow(label: "Shift + Click", selection: $preferences.shiftClickAction)
            mappingRow(label: "Option + Click", selection: $preferences.optionClickAction)
            mappingRow(label: "Shift + Option + Click", selection: $preferences.shiftOptionClickAction)

            Divider()

            mappingRow(label: "Scroll Up", selection: $preferences.scrollUpAction)
            mappingRow(label: "Shift + Scroll Up", selection: $preferences.shiftScrollUpAction)
            mappingRow(label: "Option + Scroll Up", selection: $preferences.optionScrollUpAction)
            mappingRow(label: "Shift + Option + Scroll Up", selection: $preferences.shiftOptionScrollUpAction)

            Divider()

            mappingRow(label: "Scroll Down", selection: $preferences.scrollDownAction)
            mappingRow(label: "Shift + Scroll Down", selection: $preferences.shiftScrollDownAction)
            mappingRow(label: "Option + Scroll Down", selection: $preferences.optionScrollDownAction)
            mappingRow(label: "Shift + Option + Scroll Down", selection: $preferences.shiftOptionScrollDownAction)
        }
    }

    private func mappingRow(label: String, selection: Binding<DockAction>) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 220, alignment: .leading)
            Picker("", selection: selection) {
                ForEach(DockAction.allCases, id: \.self) { action in
                    Text(action.displayName).tag(action)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 220)
            Spacer()
        }
    }

    private var shouldShowPermissionsBanner: Bool {
        !coordinator.accessibilityGranted || !coordinator.inputMonitoringGranted
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Permissions")
                .font(.headline)

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
            Text("Tip: when developing, sign the app with a consistent identity (Xcode: Signing & Capabilities -> Team) so macOS does not treat each rebuild as a new app.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func permissionRow(title: String,
                               detail: String,
                               granted: Bool,
                               actionTitle: String?,
                               action: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.body.weight(.semibold))
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

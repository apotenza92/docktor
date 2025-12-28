import SwiftUI
import AppKit

struct OnboardingView: View {
    @ObservedObject var coordinator: DockExposeCoordinator
    
    var body: some View {
        VStack(spacing: 0) {
            // Title
            Text("DockActioner")
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.top, 30)
                .padding(.bottom, 20)
            
            // Permissions
            VStack(alignment: .leading, spacing: 20) {
                // Accessibility
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Accessibility")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        if coordinator.accessibilityGranted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                    Text("Required to detect Dock icon clicks and scrolls")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !coordinator.accessibilityGranted {
                        Button("Open System Settings") {
                            coordinator.requestAccessibilityPermission()
                            coordinator.startWhenPermissionAvailable()
                        }
                        .controlSize(.small)
                    }
                }
                
                // Automation
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Automation")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                    }
                    Text("Required to trigger App Exposé and manage windows")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open System Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
            
            Spacer()
            
            // Buttons
            HStack(spacing: 12) {
                Button("Done") {
                    completeOnboarding()
                }
                
                Button("Show Settings") {
                    openSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.bottom, 25)
        }
        .frame(width: 360, height: 280)
    }
    
    private func openSettings() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        NotificationCenter.default.post(name: NSNotification.Name("OnboardingCompleted"), object: nil)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            if let mainWindow = NSApp.windows.first(where: { $0.contentView is NSHostingView<PreferencesView> }) {
                mainWindow.makeKeyAndOrderFront(nil)
            }
        }
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        NotificationCenter.default.post(name: NSNotification.Name("OnboardingCompleted"), object: nil)
    }
}

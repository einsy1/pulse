import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    @Published var menuDisplay: String {
        didSet { UserDefaults.standard.set(menuDisplay, forKey: "menuDisplay") }
    }
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    @Published var errorMessage: String?
    var launchRequested: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }
    init() {
        let saved = UserDefaults.standard.string(forKey: "menuDisplay") ?? "cpu"
        menuDisplay = ["cpu", "memory", "icon"].contains(saved) ? saved : "cpu"
    }
    func refreshLoginStatus() { loginStatus = SMAppService.mainApp.status }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { errorMessage = "无法更改登录项：\(error.localizedDescription)" }
        refreshLoginStatus()
    }
    var loginDescription: String {
        switch loginStatus {
        case .enabled: return "已开启，下次登录 Mac 时自动启动 Pulse。"
        case .requiresApproval: return "等待授权，请在系统登录项中允许 Pulse。"
        case .notRegistered: return "关闭时，需手动启动 Pulse。"
        case .notFound: return "无法找到应用，请将 Pulse 放入“应用程序”后重试。"
        @unknown default: return "请在系统设置中检查登录项状态。"
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var preferences: Preferences
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pulse 设置").font(.title2.weight(.semibold))
                    Text("让系统监控更合你的习惯").foregroundStyle(.secondary)
                }
            }
            Form {
                Section("启动") {
                    Toggle("登录时自动启动", isOn: Binding(
                        get: { preferences.launchRequested },
                        set: { preferences.setLaunchAtLogin($0) }))
                    Text(preferences.loginDescription).font(.caption).foregroundStyle(.secondary)
                    Button("打开系统登录项…") { SMAppService.openSystemSettingsLoginItems() }
                }
                Section("菜单栏") {
                    Picker("显示内容", selection: $preferences.menuDisplay) {
                        Text("图标和 CPU 使用率").tag("cpu")
                        Text("图标和内存使用率").tag("memory")
                        Text("仅图标").tag("icon")
                    }
                    Text("选择后立即生效，设置会自动保存。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Text("Pulse · 本机系统监控").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("关于 Pulse") { NSApp.orderFrontStandardAboutPanel(nil) }
            }
        }
        .padding(24).frame(width: 450, height: 500)
        .onAppear { preferences.refreshLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            preferences.refreshLoginStatus()
        }
        .alert("登录项设置失败", isPresented: Binding(
            get: { preferences.errorMessage != nil },
            set: { if !$0 { preferences.errorMessage = nil } })) {
                Button("好", role: .cancel) { preferences.errorMessage = nil }
            } message: { Text(preferences.errorMessage ?? "") }
    }
}

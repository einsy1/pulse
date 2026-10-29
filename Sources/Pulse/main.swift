import AppKit
import SwiftUI
import Darwin
import MachO
import Combine
import ServiceManagement

@main
struct PulseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { PreferencesView(preferences: .shared) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = ResourceMonitor()
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var statusTimer: Timer?
    private var settingsWindow: NSWindow?
    private var preferencesObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenuBarItem()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: DashboardView(monitor: monitor, onClose: { [weak self] in
                self?.popover.performClose(nil)
            }, onSettings: { [weak self] in self?.showSettings() })
        )
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateStatusItem() }
        }
        preferencesObserver = Preferences.shared.$menuDisplay.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem() }
        }
        updateStatusItem()
    }


    private func buildMenuBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.path", accessibilityDescription: "Pulse 系统监控")
        item.button?.imagePosition = .imageLeading
        item.button?.toolTip = "Pulse 系统监控"
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        switch Preferences.shared.menuDisplay {
        case "memory": button.title = "内存 \(Int(monitor.memory.rounded()))%"
        case "icon": button.title = ""
        default: button.title = "CPU \(Int(monitor.cpu.rounded()))%"
        }
        button.toolTip = "Pulse · CPU \(Int(monitor.cpu.rounded()))% · 内存 \(Int(monitor.memory.rounded()))%"
    }

    private func showSettings() {
        popover.performClose(nil)
        Preferences.shared.refreshLoginStatus()
        if let nativeSettings = NSApp.windows.first(where: { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }) {
            NSApp.activate(ignoringOtherApps: true)
            nativeSettings.makeKeyAndOrderFront(nil)
            return
        }
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Pulse 设置"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: PreferencesView(preferences: .shared))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettingsMenu() { showSettings() }
    @objc private func toggleLoginMenu() { Preferences.shared.setLaunchAtLogin(!Preferences.shared.launchRequested) }
    @objc private func aboutPulse() { NSApp.activate(ignoringOtherApps: true); NSApp.orderFrontStandardAboutPanel(nil) }
    @objc private func quitPulse() { NSApp.terminate(nil) }

    private func showContextMenu() {
        popover.performClose(nil)
        Preferences.shared.refreshLoginStatus()
        let menu = NSMenu()
        for (title, action, key) in [("设置…", #selector(openSettingsMenu), ","),
                                     ("登录时自动启动", #selector(toggleLoginMenu), ""),
                                     ("关于 Pulse", #selector(aboutPulse), ""),
                                     ("退出 Pulse", #selector(quitPulse), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            if action == #selector(toggleLoginMenu) { item.state = Preferences.shared.launchRequested ? .on : .off }
            menu.addItem(item)
        }
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
        if let message = Preferences.shared.errorMessage {
            let alert = NSAlert(); alert.messageText = "登录项设置失败"; alert.informativeText = message
            NSApp.activate(ignoringOtherApps: true); alert.runModal(); Preferences.shared.errorMessage = nil
        }
    }

    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu(); return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

}

struct DashboardView: View {
    @ObservedObject var monitor: ResourceMonitor
    let onClose: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 15), GridItem(.flexible(), spacing: 15)], spacing: 13) {
                MetricTile(title: "CPU", value: "\(Int(monitor.cpu.rounded()))%", progress: monitor.cpu,
                           symbol: "cpu", tint: .cyan)
                MetricTile(title: "内存", value: "\(Int(monitor.memory.rounded()))%", progress: monitor.memory,
                           symbol: "memorychip", tint: .purple)
                MetricTile(title: "GPU", value: monitor.gpu.map { "\(Int($0.rounded()))%" } ?? "—",
                           progress: monitor.gpu, symbol: "gpu", tint: .pink,
                           detail: monitor.gpu == nil ? "不可用" : nil)
                MetricTile(title: "CPU 温度", value: monitor.cpuTemperature.map { "\(Int($0.rounded()))" } ?? "—",
                           progress: monitor.cpuTemperature, symbol: "thermometer.medium", tint: .orange,
                           detail: monitor.cpuTemperature == nil ? "传感器不可用" : "°C")
            }
            .padding(14)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            DiskSection(used: monitor.diskUsed, total: monitor.diskTotal, percent: monitor.diskPercent)
            ExternalDisksSection(disks: monitor.externalDisks)
            NetworkSection(download: monitor.downloadRate, upload: monitor.uploadRate)
            footer
        }
        .padding(18)
        .frame(width: 360, height: 560)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(.black.opacity(0.18)))
        }
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "waveform.path")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 34, height: 34)
                .background(.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("系统概览").font(.system(size: 17, weight: .semibold))
                Text(monitor.machineName).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.68))
            }
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("LIVE").font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.6)
            }
            .foregroundStyle(.white.opacity(0.72))
            Menu {
                Button("设置…") { onSettings() }
                Button("关于 Pulse") { NSApp.activate(ignoringOtherApps: true); NSApp.orderFrontStandardAboutPanel(nil) }
                Divider()
                Button("收起面板") { onClose() }
                Divider()
                Button("退出 Pulse") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.08), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .help("更多选项")
        }
    }

    private var footer: some View {
        HStack {
            Circle().fill(.green.opacity(0.8)).frame(width: 5, height: 5)
            Text("每秒刷新").font(.system(size: 10, weight: .medium))
            Spacer()
            Text(Date.now, format: .dateTime.hour().minute())
                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
        }
        .foregroundStyle(.white.opacity(0.64))
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let progress: Double?
    let symbol: String
    let tint: Color
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(value)
                    .font(.system(size: 23, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Spacer(minLength: 3)
                if let detail {
                    Text(detail).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.52))
                }
            }
            if let progress {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule().fill(tint.gradient).frame(width: max(3, proxy.size.width * min(progress / 100, 1)))
                    }
                }
                .frame(height: 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DiskSection: View {
    let used: Double
    let total: Double
    let percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive").font(.system(size: 12, weight: .medium)).foregroundStyle(.orange)
                Text("内置存储").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                Spacer()
                Text("\(Int(percent))% 已用").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(.white.opacity(0.88))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.11))
                    Capsule().fill(.orange.gradient).frame(width: max(3, proxy.size.width * min(percent / 100, 1)))
                }
            }
            .frame(height: 5)
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int64(used).formatted(.byteCount(style: .file))) 已用")
                Spacer()
                Text("共 \(Int64(total).formatted(.byteCount(style: .file)))")
            }
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.62))
        }
        .padding(13)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ExternalDisk: Identifiable {
    let id: String
    let name: String
    let used: Int64
    let total: Int64
    var percent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
}

struct ExternalDisksSection: View {
    let disks: [ExternalDisk]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive").font(.system(size: 11, weight: .medium)).foregroundStyle(.cyan)
                Text("外置磁盘").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                Spacer()
                Text(disks.isEmpty ? "未连接" : "\(disks.count) 个卷")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.56))
            }
            if disks.isEmpty {
                Text("连接外置硬盘后会显示容量使用情况")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.52))
            } else {
                ForEach(disks.prefix(3)) { disk in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(disk.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(Int(disk.percent))%")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        }
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.82))
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.11))
                                Capsule().fill(.cyan.gradient).frame(width: max(3, proxy.size.width * min(disk.percent / 100, 1)))
                            }
                        }
                        .frame(height: 3)
                    }
                }
                if disks.count > 3 {
                    Text("另有 \(disks.count - 3) 个磁盘卷")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .padding(12)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct NetworkSection: View {
    let download: Double
    let upload: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "network").font(.system(size: 11, weight: .medium)).foregroundStyle(.green)
                Text("网络速率").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.72))
                Spacer()
                Text("当前").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.54))
            }
            HStack(spacing: 0) {
                rate(symbol: "arrow.down", value: download, color: .cyan)
                Spacer()
                Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 30)
                Spacer()
                rate(symbol: "arrow.up", value: upload, color: .mint)
            }
        }
        .padding(13)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func rate(symbol: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                Text(Int64(value).formatted(.byteCount(style: .memory)))
                    .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("/s").font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.56))
            }
            Text(symbol == "arrow.down" ? "下载" : "上传")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.55))
        }
    }
}

@MainActor
final class ResourceMonitor: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var memory: Double = 0
    @Published private(set) var diskUsed: Double = 0
    @Published private(set) var diskTotal: Double = 1
    @Published private(set) var downloadRate: Double = 0
    @Published private(set) var uploadRate: Double = 0
    @Published private(set) var gpu: Double?
    @Published private(set) var cpuTemperature: Double?
    @Published private(set) var externalDisks: [ExternalDisk] = []
    let machineName = Host.current().localizedName ?? "Mac"

    private var timer: Timer?
    private var lastCPU: (UInt64, UInt64)?
    private var lastNetwork: (UInt64, UInt64)?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var diskPercent: Double { diskUsed / max(diskTotal, 1) * 100 }

    private func refresh() {
        cpu = readCPU()
        memory = readMemory()
        readDisk()
        externalDisks = readExternalDisks()
        gpu = HardwareMetrics.gpuUtilization()
        cpuTemperature = HardwareMetrics.cpuTemperatureCelsius()
        readNetwork()
    }

    private func readCPU() -> Double {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return cpu }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let current = (user + system + idle + nice, idle)
        defer { lastCPU = current }
        guard let previous = lastCPU else { return 0 }
        let totalDelta = current.0 &- previous.0
        let idleDelta = current.1 &- previous.1
        guard totalDelta > 0 else { return 0 }
        return min(100, Double(totalDelta - min(idleDelta, totalDelta)) / Double(totalDelta) * 100)
    }

    private func readMemory() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return memory }
        let total = ProcessInfo.processInfo.physicalMemory
        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(stats.free_count + stats.inactive_count + stats.purgeable_count) * pageSize
        return Double(total - min(free, total)) / Double(total) * 100
    }

    private func readDisk() {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage else { return }
        diskTotal = Double(total)
        diskUsed = Double(max(0, Int64(total) - available))
    }

    private func readExternalDisks() -> [ExternalDisk] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeIsInternalKey, .volumeIsLocalKey,
                                         .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeAvailableCapacityKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys),
                                                            options: [.skipHiddenVolumes]) ?? []
        return volumes.compactMap { url in
            guard url.path.hasPrefix("/Volumes/"),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.volumeIsInternal == false,
                  values.volumeIsLocal != false,
                  let total = values.volumeTotalCapacity,
                  total > 0 else { return nil }
            let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
            let used = max(0, Int64(total) - available)
            return ExternalDisk(id: url.path, name: values.volumeName ?? url.lastPathComponent,
                                used: used, total: Int64(total))
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func readNetwork() {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return }
        defer { freeifaddrs(addresses) }
        var received: UInt64 = 0, sent: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let data = current.pointee.ifa_data,
                  let name = current.pointee.ifa_name,
                  String(cString: name) != "lo0",
                  Int32(current.pointee.ifa_addr.pointee.sa_family) == AF_LINK else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(stats.ifi_ibytes)
            sent += UInt64(stats.ifi_obytes)
        }
        defer { lastNetwork = (received, sent) }
        guard let previous = lastNetwork else { return }
        downloadRate = Double(received &- previous.0)
        uploadRate = Double(sent &- previous.1)
    }
}

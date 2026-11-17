import AppKit
import CoreGraphics
import SwiftUI
import ServiceManagement
import IOKit
import IOKit.hid

// MARK: - Preferences

enum P {
    static let onColor = "onColor"
    static let offColor = "offColor"
    static let iconStyle = "iconStyle"
    static let iconSize = "iconSize"
    static let showHUD = "showHUD"
    static let hudDuration = "hudDuration"
    static let hudPosition = "hudPosition"
    static let playSound = "playSound"
    static let launchAtLogin = "launchAtLogin"

    static let defOnColor = "#FF3B30"
    static let defOffColor = "#8E8E93"

    static func string(_ key: String, _ def: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? def
    }
    static func bool(_ key: String, _ def: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? def
    }
    static func double(_ key: String, _ def: Double) -> Double {
        UserDefaults.standard.object(forKey: key) as? Double ?? def
    }
    static func int(_ key: String, _ def: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? def
    }
    static func registerDefaults() {
        UserDefaults.standard.registerdefaults([
            P.onColor: P.defOnColor,
            P.offColor: P.defOffColor,
            P.iconStyle: 0,
            P.iconSize: 18.0,
            P.showHUD: true,
            P.hudDuration: 1.4,
            P.hudPosition: 0,
            P.playSound: true,
            P.launchAtLogin: false,
        ])
    }
}

extension UserDefaults {
    func registerdefaults(_ values: [String: Any]) {
        register(defaults: values)
    }
}

// MARK: - Color helpers

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 {
            s = String(s.map { "\($0)\($0)" }.joined())
        }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }
}

extension Color {
    init(hex: String) {
        let c = NSColor(hex: hex).usingColorSpace(.sRGB) ?? NSColor.gray
        self.init(.sRGB, red: Double(c.redComponent), green: Double(c.greenComponent),
                  blue: Double(c.blueComponent), opacity: Double(c.alphaComponent))
    }

    var hexString: String { NSColor(self).hexString }
}

// MARK: - Caps Lock detection

enum CapsReader {
    static let capsKeyCode = CGKeyCode(57) // kVK_CapsLock

    /// Reads the real Caps Lock latch from the HID system (the same state as the
    /// keyboard LED). No Accessibility or Input Monitoring permission required.
    static func isOn() -> Bool {
        guard let matching = IOServiceMatching(kIOHIDSystemClass) else { return fallback }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return fallback }

        var connection: io_connect_t = 0
        let opened = IOServiceOpen(service, mach_task_self_,
                                   UInt32(kIOHIDParamConnectType), &connection)
        IOObjectRelease(service)
        guard opened == KERN_SUCCESS else { return fallback }

        var state = false
        let result = IOHIDGetModifierLockState(connection,
                                               Int32(kIOHIDCapsLockState), &state)
        IOServiceClose(connection)
        return result == KERN_SUCCESS ? state : fallback
    }

    private static var fallback: Bool {
        CGEventSource.keyState(.hidSystemState, key: capsKeyCode)
            || NSEvent.modifierFlags.contains(.capsLock)
    }
}

// MARK: - Menu bar icon

enum IconFactory {
    static func image(active: Bool) -> NSImage {
        let pt = CGFloat(P.int(P.iconSize, 18))
        let color = NSColor(hex: P.string(active ? P.onColor : P.offColor,
                                        active ? P.defOnColor : P.defOffColor))
        let style = P.int(P.iconStyle, 0)
        let scale: CGFloat = 2  // retina

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: Int(pt * scale), pixelsHigh: Int(pt * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let gctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gctx
        gctx.shouldAntialias = true
        gctx.cgContext.scaleBy(x: scale, y: scale)

        // The bitmap context uses a bottom-left origin. AppKit text drawing keeps
        // glyphs upright in that coordinate system, so all positions are converted.
        func baseline(forTop top: CGFloat, font: NSFont) -> CGFloat {
            pt - top - font.ascender
        }
        func barRect(top: CGFloat, height: CGFloat) -> NSRect {
            NSRect(x: pt * 0.28, y: pt - top - height, width: pt * 0.44, height: height)
        }

        let box = NSRect(x: 1.5, y: 1.5, width: pt - 3, height: pt - 3)

        switch style {
        case 1: // letter only
            let font = NSFont.boldSystemFont(ofSize: pt * 0.72)
            let str = "A" as NSString
            let tw = str.size(withAttributes: [.font: font]).width
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            str.draw(at: NSPoint(x: (pt - tw) / 2, y: baseline(forTop: pt * 0.08, font: font)),
                     withAttributes: attrs)
            if active {
                let bar = NSBezierPath(roundedRect: NSRect(x: (pt - tw) / 2, y: 0.3,
                                                           width: tw, height: 1.2),
                                       xRadius: 0.6, yRadius: 0.6)
                color.setFill()
                bar.fill()
            }

        case 2: // filled circle
            let path = NSBezierPath(ovalIn: box.insetBy(dx: 0.5, dy: 0.5))
            if active {
                color.setFill(); path.fill()
            } else {
                color.setStroke(); path.lineWidth = 1.6; path.stroke()
            }
            let font = NSFont.boldSystemFont(ofSize: pt * 0.55)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: active ? NSColor.white : color,
            ]
            let str = "A" as NSString
            let tw = str.size(withAttributes: [.font: font]).width
            str.draw(at: NSPoint(x: (pt - tw) / 2, y: baseline(forTop: pt * 0.18, font: font)),
                     withAttributes: attrs)

        default: // classic keycap
            let radius: CGFloat = pt * 0.20
            let path = NSBezierPath(roundedRect: box, xRadius: radius, yRadius: radius)
            if active {
                color.setFill(); path.fill()
            } else {
                color.setStroke(); path.lineWidth = 1.5; path.stroke()
            }
            let font = NSFont.boldSystemFont(ofSize: pt * 0.56)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: active ? NSColor.white : color,
            ]
            let str = "A" as NSString
            let tw = str.size(withAttributes: [.font: font]).width
            str.draw(at: NSPoint(x: (pt - tw) / 2, y: baseline(forTop: pt * 0.18, font: font)),
                     withAttributes: attrs)

            // small bar under the letter = caps lock symbol
            let bar = NSBezierPath(roundedRect: barRect(top: pt * 0.78, height: 1.5),
                                   xRadius: 0.7, yRadius: 0.7)
            (active ? NSColor.white : color).setFill()
            bar.fill()
        }

        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: pt, height: pt))
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }
}

// MARK: - HUD near the text cursor

final class HUDView: NSView {
    let active: Bool

    init(active: Bool) {
        self.active = active
        super.init(frame: NSRect(x: 0, y: 0, width: 224, height: 64))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor(hex: P.string(active ? P.onColor : P.offColor,
                                           active ? P.defOnColor : P.defOffColor))
        let bg = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 14, yRadius: 14)
        bg.setFill(); r.fill()
        accent.setStroke(); r.lineWidth = 2; r.stroke()

        let title = active ? "CAPS LOCK AKTIF" : "CAPS LOCK NONAKTIF"
        let font = NSFont.boldSystemFont(ofSize: 13)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: accent]
        let str = title as NSString
        let tw = str.size(withAttributes: attrs).width
        str.draw(at: NSPoint(x: (bounds.width - tw) / 2, y: 15), withAttributes: attrs)

        let sub = active ? "Huruf besar aktif saat mengetik" : "Ketikan kembali normal"
        let f2 = NSFont.systemFont(ofSize: 10.5)
        let a2: [NSAttributedString.Key: Any] = [.font: f2,
                                                 .foregroundColor: NSColor.secondaryLabelColor]
        let s2 = sub as NSString
        let w2 = s2.size(withAttributes: a2).width
        s2.draw(at: NSPoint(x: (bounds.width - w2) / 2, y: 36), withAttributes: a2)
    }
}

final class HUDController {
    static let shared = HUDController()
    private var panel: NSPanel?
    private var hideTimer: Timer?

    func show(active: Bool) {
        guard P.bool(P.showHUD, true) else { return }
        hide(animated: false)

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 224, height: 64),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = HUDView(active: active)
        panel.alphaValue = 0

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first
        let w: CGFloat = 224, h: CGFloat = 64
        var x: CGFloat, y: CGFloat
        if P.int(P.hudPosition, 0) == 0, let screen = screen {
            // near the pointer / typing location
            x = mouse.x + 20
            y = screen.frame.maxY - (screen.frame.maxY - mouse.y) - 22 - h
            x = min(max(x, screen.frame.minX + 8), screen.frame.maxX - w - 8)
            y = min(max(y, screen.frame.minY + 8), screen.frame.maxY - h - 8)
        } else if let screen = screen {
            x = screen.frame.midX - w / 2
            y = screen.frame.maxY - 92
        } else {
            x = 0; y = 0
        }
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        hideTimer = Timer.scheduledTimer(withTimeInterval: P.double(P.hudDuration, 1.4),
                                         repeats: false) { [weak self] _ in
            self?.hide(animated: true)
        }
    }

    func hide(animated: Bool) {
        hideTimer?.invalidate(); hideTimer = nil
        guard let panel = panel else { return }
        self.panel = nil
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        } else {
            panel.orderOut(nil)
        }
    }
}

// MARK: - Settings UI

struct SettingsView: View {
    @AppStorage(P.onColor) private var onColor = P.defOnColor
    @AppStorage(P.offColor) private var offColor = P.defOffColor
    @AppStorage(P.iconStyle) private var style = 0
    @AppStorage(P.iconSize) private var size = 18.0
    @AppStorage(P.showHUD) private var showHUD = true
    @AppStorage(P.hudDuration) private var duration = 1.4
    @AppStorage(P.hudPosition) private var position = 0
    @AppStorage(P.playSound) private var sound = true
    @AppStorage(P.launchAtLogin) private var login = false

    @State private var loginMessage = ""

    var body: some View {
        Form {
            Section("Ikon Menu Bar") {
                Picker("Gaya ikon", selection: $style) {
                    Text("Tombol Caps Lock klasik").tag(0)
                    Text("Huruf A saja").tag(1)
                    Text("Lingkaran").tag(2)
                }
                ColorPicker("Warna saat AKTIF", selection: Binding(
                    get: { Color(hex: onColor) },
                    set: { onColor = $0.hexString }))
                ColorPicker("Warna saat NONAKTIF", selection: Binding(
                    get: { Color(hex: offColor) },
                    set: { offColor = $0.hexString }))
                HStack {
                    Text("Ukuran ikon")
                    Slider(value: $size, in: 14...24, step: 1)
                    Text("\(Int(size)) pt").monospacedDigit().frame(width: 42, alignment: .trailing)
                }
            }

            Section("Notifikasi dekat kursor") {
                Toggle("Tampilkan HUD saat Caps Lock berubah", isOn: $showHUD)
                Picker("Posisi HUD", selection: $position) {
                    Text("Dekat kursor / tempat mengetik").tag(0)
                    Text("Tengah atas layar").tag(1)
                }
                HStack {
                    Text("Lama tampil")
                    Slider(value: $duration, in: 0.5...4.0, step: 0.1)
                    Text(String(format: "%.1f dtk", duration)).monospacedDigit().frame(width: 58)
                }
                Toggle("Bunyi suara saat berubah", isOn: $sound)
                Button("Pratinjau HUD") {
                    HUDController.shared.show(active: true)
                }
            }

            Section("Umum") {
                Toggle("Jalankan otomatis saat login", isOn: $login)
                    .onChange(of: login) { newValue in
                        setLogin(newValue)
                    }
                if !loginMessage.isEmpty {
                    Text(loginMessage).font(.caption).foregroundColor(.secondary)
                }
                HStack {
                    Text("Versi 1.0 · macOS 13 Ventura atau lebih baru")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Keluar") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
        .onAppear {
            if #available(macOS 13.0, *) {
                login = (SMAppService.mainApp.status == .enabled)
            }
        }
    }

    private func setLogin(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
                loginMessage = "Aktif: CapLock akan jalan otomatis saat login."
            } else {
                try SMAppService.mainApp.unregister()
                loginMessage = "Auto-start dimatikan."
            }
        } catch {
            loginMessage = "Gagal mengubah auto-start: \(error.localizedDescription)"
            login = (SMAppService.mainApp.status == .enabled)
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var timer: Timer?
    private var lastState = false
    private var didInit = false
    private var pendingHits = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        P.registerDefaults()
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        let status = NSMenuItem(title: "Caps Lock: —", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Pratinjau notifikasi", action: #selector(previewHUD),
                                keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings),
                                keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Keluar CapLock", action: #selector(quit),
                                keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        status.isEnabled = false
        statusItem.menu = menu

        lastState = CapsReader.isOn()
        didInit = false
        refresh(announce: false)

        timer = Timer.scheduledTimer(timeInterval: 0.12, target: self,
                                     selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(defaultsChanged),
                                               name: UserDefaults.didChangeNotification,
                                               object: nil)
    }

    @objc private func tick() {
        let current = CapsReader.isOn()
        guard current != lastState else {
            pendingHits = 0
            return
        }
        // Two consecutive reads avoid reacting to the brief "tentative" state
        // macOS reports during a Caps Lock press.
        pendingHits += 1
        if pendingHits >= 2 {
            lastState = current
            pendingHits = 0
            refresh(announce: true)
        }
    }

    private func refresh(announce: Bool) {
        statusItem.button?.image = IconFactory.image(active: lastState)
        statusItem.button?.toolTip = lastState ? "Caps Lock: AKTIF" : "Caps Lock: nonaktif"
        statusItem.menu?.item(at: 0)?.title = lastState
            ? "Caps Lock: AKTIF (huruf besar)"
            : "Caps Lock: nonaktif"

        if announce && didInit {
            HUDController.shared.show(active: lastState)
            if P.bool(P.playSound, true) {
                NSSound(named: NSSound.Name(lastState ? "Tink" : "Pop"))?.play()
            }
        }
        didInit = true
    }

    @objc private func defaultsChanged() {
        refresh(announce: false)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "CapLock Settings"
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func previewHUD() {
        HUDController.shared.show(active: lastState)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Entry point

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()

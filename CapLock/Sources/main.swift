import AppKit
import ApplicationServices
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
    static let showBadge = "showBadge"
    static let showHUD = "showHUD"          // legacy key, migrated to showBadge
    static let hudDuration = "hudDuration"  // kept for old preferences
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
        let defaults = UserDefaults.standard
        // Users of the previous build may have disabled the old HUD. Carry that
        // choice over to the new anchored indicator.
        if defaults.object(forKey: P.showBadge) == nil,
           let legacy = defaults.object(forKey: P.showHUD) as? Bool {
            defaults.set(legacy, forKey: P.showBadge)
        }
        // v1.0 used tag 1 for "top center"; v1.1 uses tag 0 for the new
        // anchored indicator, so reset the old choice once.
        if defaults.object(forKey: "badgePositionMigrated") == nil {
            defaults.set(0, forKey: P.hudPosition)
            defaults.set(true, forKey: "badgePositionMigrated")
        }
        defaults.registerdefaults([
            P.onColor: P.defOnColor,
            P.offColor: P.defOffColor,
            P.iconStyle: 0,
            P.iconSize: 18.0,
            P.showBadge: true,
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

// MARK: - Focused text box + anchored badge

enum TextBoxLocator {
    /// Roles that represent an editable text field in the Accessibility tree.
    static let textRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSecureTextField", "AXSearchField",
        "AXComboBox", "AXTextView", "AXText",
    ]

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openPrivacySettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    static func frame(for element: AXUIElement) -> NSRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString,
                                            &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString,
                                            &sizeRef) == .success,
              let posRef = posRef, let sizeRef = sizeRef else { return nil }
        let posValue = posRef as! AXValue
        let sizeValue = sizeRef as! AXValue
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue, .cgPoint, &point),
              AXValueGetValue(sizeValue, .cgSize, &size),
              size.width >= 24, size.height >= 10 else { return nil }
        return NSRect(x: point.x, y: point.y, width: size.width, height: size.height)
    }

    /// Frame of the text field focused by the frontmost app.
    ///
    /// Accessibility coordinates use the top-left of the primary display as the
    /// origin and increase downwards; AppKit windows use a bottom-left origin.
    static func focusedTextFieldFrame() -> NSRect? {
        guard isTrusted, let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focusedRef) == .success,
              let focusedRef = focusedRef else { return nil }
        let element = focusedRef as! AXUIElement

        var roleRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        if let role = roleRef as? String, textRoles.contains(role) {
            return frame(for: element)
        }

        // Some containers expose their real editor one level deeper.
        var childRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &childRef) == .success,
              let childRef = childRef else { return nil }
        let child = childRef as! AXUIElement
        var childRoleRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(child, kAXRoleAttribute as CFString, &childRoleRef)
        guard let childRole = childRoleRef as? String, textRoles.contains(childRole) else {
            return nil
        }
        return frame(for: child)
    }
}

/// Small pill drawn directly above the focused text field.
final class BadgeView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let accent = NSColor(hex: P.string(P.onColor, P.defOnColor))
        let body = NSBezierPath(roundedRect: NSRect(x: bounds.minX, y: bounds.minY + 5,
                                                    width: bounds.width,
                                                    height: bounds.height - 5),
                                xRadius: 9, yRadius: 9)
        accent.setFill(); body.fill()

        // Pointer aimed at the text field below.
        let pointer = NSBezierPath()
        let mid = bounds.midX
        pointer.move(to: NSPoint(x: mid - 5, y: 6))
        pointer.line(to: NSPoint(x: mid + 5, y: 6))
        pointer.line(to: NSPoint(x: mid, y: 0))
        pointer.close()
        accent.setFill(); pointer.fill()

        let key = NSBezierPath(roundedRect: NSRect(x: 6, y: 11, width: 18, height: 14),
                               xRadius: 4, yRadius: 4)
        NSColor.white.setFill(); key.fill()
        let letter = "A" as NSString
        let letterFont = NSFont.boldSystemFont(ofSize: 11)
        let letterAttrs: [NSAttributedString.Key: Any] = [
            .font: letterFont, .foregroundColor: accent,
        ]
        let letterWidth = letter.size(withAttributes: letterAttrs).width
        letter.draw(at: NSPoint(x: 6 + (18 - letterWidth) / 2, y: 13),
                    withAttributes: letterAttrs)

        let title = "CAPS LOCK AKTIF" as NSString
        let font = NSFont.boldSystemFont(ofSize: 11)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.white,
        ]
        title.draw(at: NSPoint(x: 30, y: 13), withAttributes: attrs)
    }
}

final class BadgeController {
    static let shared = BadgeController()
    private var panel: NSPanel?
    private var previewTimer: Timer?
    private var hasAnchoredFrame = false
    private let width: CGFloat = 168
    private let height: CGFloat = 35

    /// Keeps the badge in sync with Caps Lock and the currently focused field.
    /// Safe to call on every polling tick; positioning is cheap.
    func update(active: Bool) {
        guard active else { hide(); return }
        guard P.bool(P.showBadge, true) else { hide(); return }
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            p.contentView = BadgeView()
            p.alphaValue = 0
            panel = p
        }
        guard let panel = panel else { return }
        place(panel)
        if !panel.isVisible {
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    private func place(_ panel: NSPanel) {
        let gap: CGFloat = 8
        let globalTop = NSScreen.screens.first?.frame.maxY ?? 0

        // Anchor above the focused text field and stay there. The pointer is
        // never consulted, so moving the mouse cannot drag the badge away.
        guard let field = TextBoxLocator.focusedTextFieldFrame() else {
            if !hasAnchoredFrame {
                // No field detected yet (e.g. Accessibility not granted): use a
                // fixed neutral spot instead of following the cursor.
                if let screen = NSScreen.main ?? NSScreen.screens.first {
                    let x = min(max(screen.frame.midX - width / 2,
                                    screen.frame.minX + 8),
                                screen.frame.maxX - width - 8)
                    let y = screen.frame.maxY - height - 44
                    panel.setFrame(NSRect(x: x, y: y, width: width, height: height),
                                   display: true)
                }
            }
            return
        }

        hasAnchoredFrame = true
        let fieldMidCocoa = NSPoint(x: field.midX, y: globalTop - field.midY)
        let screen = NSScreen.screens.first {
            NSMouseInRect(fieldMidCocoa, $0.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first

        // Top of the field, measured downward from the primary display top.
        // In AppKit coordinates the badge bottom sits `gap` above that edge.
        var y = globalTop - field.minY + gap
        if let screen = screen, y + height > screen.frame.maxY - 4 {
            // Not enough room above: flip below the field.
            y = globalTop - field.maxY - gap - height
        }
        var x = field.midX - width / 2
        if let screen = screen {
            x = min(max(x, screen.frame.minX + 8),
                    screen.frame.maxX - width - 8)
            y = min(max(y, screen.frame.minY + 8),
                    screen.frame.maxY - height - 8)
        }
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    func preview() {
        update(active: true)
        previewTimer?.invalidate()
        previewTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func hide() {
        previewTimer?.invalidate(); previewTimer = nil
        hasAnchoredFrame = false
        guard let panel = panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

// MARK: - Settings UI

struct SettingsView: View {
    @AppStorage(P.onColor) private var onColor = P.defOnColor
    @AppStorage(P.offColor) private var offColor = P.defOffColor
    @AppStorage(P.iconStyle) private var style = 0
    @AppStorage(P.iconSize) private var size = 18.0
    @AppStorage(P.showBadge) private var showBadge = true
    @AppStorage(P.playSound) private var sound = true
    @AppStorage(P.launchAtLogin) private var login = false

    @State private var loginMessage = ""
    @State private var trusted = TextBoxLocator.isTrusted

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

            Section("Indikator Caps Lock aktif") {
                Toggle("Tampilkan saat Caps Lock aktif", isOn: $showBadge)
                Text("Indikator selalu menempel di atas text box yang fokus dan tidak mengikuti kursor.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Toggle("Bunyi suara saat berubah", isOn: $sound)
                Button("Pratinjau indikator") {
                    BadgeController.shared.preview()
                }

                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(trusted ? .green : .orange)
                    Text(trusted ? "Akses Accessibility: aktif"
                                 : "Akses Accessibility: belum diberikan")
                        .font(.caption)
                    Spacer()
                    Button("Perbarui") { trusted = TextBoxLocator.isTrusted }
                        .controlSize(.small)
                }
                if !trusted {
                    Text("Izinkan CapLock di Privacy & Security › Accessibility agar indikator bisa menempel tepat di atas text box. Tanpa izin, indikator diam di posisi tetap tengah atas.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Button("Minta Izin") {
                            TextBoxLocator.requestAccess()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                trusted = TextBoxLocator.isTrusted
                            }
                        }
                        Button("Buka Pengaturan") {
                            TextBoxLocator.openPrivacySettings()
                        }
                    }
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
            trusted = TextBoxLocator.isTrusted
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

        // Placement needs Accessibility. Ask once on launch when missing so the
        // user does not have to dig into Settings to discover the requirement.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if !TextBoxLocator.isTrusted {
                TextBoxLocator.requestAccess()
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        let status = NSMenuItem(title: "Caps Lock: —", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Pratinjau indikator", action: #selector(previewBadge),
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
            // Follow the focused text field while Caps Lock stays on.
            BadgeController.shared.update(active: lastState)
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

        if lastState {
            BadgeController.shared.update(active: true)
        } else {
            BadgeController.shared.hide()
        }
        if announce && didInit, P.bool(P.playSound, true) {
            NSSound(named: NSSound.Name(lastState ? "Tink" : "Pop"))?.play()
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

    @objc private func previewBadge() {
        BadgeController.shared.preview()
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

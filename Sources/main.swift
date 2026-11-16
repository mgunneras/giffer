import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var window: NSWindow!

    func applicationWillFinishLaunching(_ notification: Notification) {
        buildMenu()
        let host = NSHostingController(rootView: ContentView(model: model))
        host.sizingOptions = [.preferredContentSize]
        window = NSWindow(contentViewController: host)
        window.title = "Giffer"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startSnapshots()
    }

    /// Debug aid: GIFFER_SNAPSHOT=<dir> saves a PNG of the window per phase,
    /// and GIFFER_AUTOCONVERT=1 presses Convert once the options appear.
    private func startSnapshots() {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["GIFFER_SNAPSHOT"] else { return }
        var seen = Set<String>(), autoConverted = false
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            let name = "\(self.model.phase)".prefix(12).filter(\.isLetter)
            guard let view = self.window.contentView, seen.insert(String(name)).inserted,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "\(dir)/\(seen.count)-\(name).png"))
            if self.model.phase == .options, env["GIFFER_AUTOCONVERT"] != nil, !autoConverted {
                autoConverted = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.model.convert() }
            }
        }
    }

    // Files dropped on the Dock icon (or opened with the app) arrive here.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.open(url)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) { model.cancelConversion() }

    @objc func openDocument(_ sender: Any?) { model.chooseFile() }

    private func buildMenu() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About Giffer", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Giffer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Giffer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o")
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        for menu in [app, file, edit] {
            let item = NSMenuItem()
            item.submenu = menu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }
}

// Headless check of the real pipeline: Giffer --selftest <video>
if let i = CommandLine.arguments.firstIndex(of: "--selftest"), CommandLine.arguments.count > i + 1 {
    let url = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    guard let tools = FFmpeg.locate() else { print("ffmpeg not found"); exit(2) }
    print("using \(tools.ffmpeg)")
    do {
        let info = try FFmpeg.probe(url, tools: tools)
        var settings = Settings()
        let hard = CommandLine.arguments.contains("--hard")
        if hard { settings.speed = 2; settings.colors = 64; settings.dither = .none; settings.width = 480 }
        let plan = Plan(info: info, settings: settings, trimStart: hard ? 1 : 0, trimEnd: info.duration - (hard ? 1 : 0))
        let out = url.deletingPathExtension().appendingPathExtension("gif")
        var updates = 0, images = 0
        try Conversion(plan: plan, tools: tools).run(to: out) { _, _, image in
            updates += 1
            if image != nil { images += 1 }
        }
        let size = (try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
        print("ok \(info.width)x\(info.height) \(info.fps)fps \(info.duration)s -> \(plan.outW)x\(plan.outH) \(plan.frames) frames")
        print("updates \(updates) images \(images) size \(size) rawEstimate \(Int(plan.rawEstimate))")
        exit(0)
    } catch {
        print("failed: \(error.localizedDescription)")
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

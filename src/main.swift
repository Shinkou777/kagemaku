import AppKit

/// NSApplication.delegate 是 weak，这里留一份强引用
enum DelegateHolder {
    nonisolated(unsafe) static var delegate: AppDelegate?
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    DelegateHolder.delegate = delegate
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

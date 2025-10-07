import SwiftUI
#if os(macOS)
import AppKit
import Core

/// A helper view that captures the NSWindow instance for the view hierarchy
struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?
    let onWindowSet: () -> Void
    private let logger = Logger.shared

    init(window: Binding<NSWindow?>, onWindowSet: @escaping () -> Void = {}) {
        self._window = window
        self.onWindowSet = onWindowSet
    }

    func makeNSView(context: Context) -> NSView {
        let view = WindowCaptureView()
        view.onWindowChange = { [weak view] in
            guard let window = view?.window else { return }
            DispatchQueue.main.async {
                self.window = window
                self.logger.log("🪟 WindowAccessor captured window: \(window)", category: "WindowAccessor")
                self.onWindowSet()
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if nsView.window != nil && window == nil {
            DispatchQueue.main.async {
                self.window = nsView.window
                self.logger.log("🪟 WindowAccessor updated window: \(String(describing: nsView.window))", category: "WindowAccessor")
                self.onWindowSet()
            }
        }
    }
}

private class WindowCaptureView: NSView {
    var onWindowChange: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?()
    }
}
#endif

import AppKit
import SwiftUI

extension View {
    /// La fenêtre de `MenuBarExtra` grandit avec son contenu mais ne rétrécit jamais :
    /// on la recale sur la taille du contenu, en gardant le haut collé à la barre des menus.
    func fitsMenuWindow() -> some View {
        fixedSize().background(GeometryReader { g in FitWindow(size: g.size) })
    }
}

private struct FitWindow: NSViewRepresentable {
    let size: CGSize

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let size = size
        DispatchQueue.main.async {
            guard let window = view.window, size.height > 0 else { return }
            let content = window.contentRect(forFrameRect: window.frame)
            guard abs(content.height - size.height) > 0.5 || abs(content.width - size.width) > 0.5 else { return }
            let target = NSRect(x: content.minX, y: content.maxY - size.height, width: size.width, height: size.height)
            window.setFrame(window.frameRect(forContentRect: target), display: true)
        }
    }
}

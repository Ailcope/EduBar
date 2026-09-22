import AppKit

// AppKit pur : une scène SwiftUI (même `Settings`) ouvrirait une fenêtre vide au lancement.
Snapshot.runIfRequested()
let app = NSApplication.shared
// Utile hors bundle (`swift run`) ; dans le .app, LSUIElement fait déjà le travail.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

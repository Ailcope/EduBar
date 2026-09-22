#!/bin/sh
# Régénère Resources/AppIcon.icns à partir de Resources/AppIcon.svg (AppKit + iconutil, sans Xcode).
# Usage : scripts/make-icon.sh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$SET"

swift - "$ROOT/Resources/AppIcon.svg" "$SET" <<'EOF'
import AppKit

let args = CommandLine.arguments
guard let svg = NSImage(contentsOfFile: args[1]) else { fatalError("SVG illisible : \(args[1])") }
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = size * scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        svg.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]).appendingPathComponent(name))
    }
}
EOF

iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"
rm -rf "$(dirname "$SET")"
echo "OK : $ROOT/Resources/AppIcon.icns"

import AppKit

let destination = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/clear-notifications-master.png"

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let side: CGFloat = 1024
let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
    NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: 48, dy: 48), xRadius: 200, yRadius: 200).fill()

    guard let symbol = NSImage(systemSymbolName: "bell.slash.fill", accessibilityDescription: nil) else {
        return false
    }
    let config = NSImage.SymbolConfiguration(pointSize: 560, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let rendered = symbol.withSymbolConfiguration(config) ?? symbol
    let length: CGFloat = 560
    rendered.draw(in: NSRect(
        x: (side - length) / 2,
        y: (side - length) / 2 - 16,
        width: length,
        height: length
    ))
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Could not render icon\n", stderr)
    exit(1)
}

let url = URL(fileURLWithPath: destination)
try png.write(to: url)

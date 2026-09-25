import AppKit

let destination = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/mackey-master.png"

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let side: CGFloat = 1024
let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
    NSColor(calibratedWhite: 0.11, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: 48, dy: 48), xRadius: 200, yRadius: 200).fill()

    let mark = "M" as NSString
    let font = NSFont.systemFont(ofSize: 640, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
    ]
    let markSize = mark.size(withAttributes: attributes)
    mark.draw(
        at: NSPoint(x: (side - markSize.width) / 2, y: (side - markSize.height) / 2 - 24),
        withAttributes: attributes
    )
    return true
}

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fputs("Could not render icon\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: destination))

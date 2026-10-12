// Renders the GitHub social preview card (1280×640). Usage: swift scripts/make-social-preview.swift <icon.png> <out.png>
import AppKit

let args = CommandLine.arguments
let icon = NSImage(contentsOfFile: args[1])!
let out = URL(fileURLWithPath: args[2])
let W: CGFloat = 1280, H: CGFloat = 640

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: deep navy with a soft blue glow behind the icon.
NSGradient(colors: [NSColor(srgbRed: 0.05, green: 0.08, blue: 0.18, alpha: 1),
                    NSColor(srgbRed: 0.02, green: 0.03, blue: 0.08, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.45, blue: 1, alpha: 0.35), .clear])!
    .draw(fromCenter: NSPoint(x: 330, y: 320), radius: 0, toCenter: NSPoint(x: 330, y: 320), radius: 360, options: [])

icon.draw(in: NSRect(x: 150, y: 140, width: 360, height: 360))

/// Draws `s` with its top edge at `top` (y measured from the bottom of the canvas). Returns the block's height.
@discardableResult
func text(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
    let style = NSMutableParagraphStyle(); style.lineSpacing = 2
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    let h = ceil(str.boundingRect(with: NSSize(width: width, height: 1000), options: [.usesLineFragmentOrigin]).height)
    str.draw(with: NSRect(x: x, y: top - h, width: width, height: h), options: [.usesLineFragmentOrigin])
    return h
}
let x: CGFloat = 570
var top: CGFloat = 486
top -= text("Cove", .systemFont(ofSize: 96, weight: .bold), .white, x: x, top: top, width: 660) + 6
top -= text("A Mac of their own,\nfor your AI agents.", .systemFont(ofSize: 44, weight: .semibold),
            NSColor(srgbRed: 0.55, green: 0.75, blue: 1, alpha: 1), x: x, top: top, width: 660) + 24
text("Agent-first macOS virtual machines for Apple silicon.\nOne-click install · snapshots · ssh cove-<name>",
     .systemFont(ofSize: 24, weight: .regular), NSColor(white: 0.72, alpha: 1), x: x, top: top, width: 680)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")

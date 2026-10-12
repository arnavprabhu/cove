// Renders the Cove app icon. Usage: swift scripts/make-icon.swift <out.png> [size]
// Follows the macOS icon grid: 1024 canvas, 824 pt rounded-square body, soft drop shadow.
import AppKit

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "icon.png")
let S = CGFloat(args.count > 2 ? Double(args[2])! : 1024)
let k = S / 1024

func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Apple-style continuous-corner rounded square (superellipse, n = 5).
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
        let y = cy + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func linear(_ ctx: CGContext, _ colors: [CGColor], _ locs: [CGFloat], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locs)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: k, y: k)   // draw in 1024-pt design space; y grows upward

// MARK: Body
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
// macOS app icons: rounded square with ~22% corner radius.
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: c(0x000000, 0.35))
ctx.addPath(bodyPath); ctx.setFillColor(c(0x0B2A66)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
// Deep ocean gradient: bright azure at the top fading to navy.
linear(ctx, [c(0x3FA0FF), c(0x1764E8), c(0x0A2C7A)], [0, 0.45, 1], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
// Soft glow behind the display.
let glow = CGGradient(colorsSpace: cs, colors: [c(0x9FD3FF, 0.45), c(0x9FD3FF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 560), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 560), endRadius: 430, options: [])

// MARK: Display (frosted glass bezel)
let bezel = CGRect(x: 212, y: 330, width: 600, height: 420)
let bezelPath = CGPath(roundedRect: bezel, cornerWidth: 54, cornerHeight: 54, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: c(0x031540, 0.55))
ctx.addPath(bezelPath); ctx.setFillColor(c(0xF4F8FF, 0.96)); ctx.fillPath()
ctx.restoreGState()

// Screen
let screen = bezel.insetBy(dx: 26, dy: 26)
let screenPath = CGPath(roundedRect: screen, cornerWidth: 32, cornerHeight: 32, transform: nil)
ctx.saveGState()
ctx.addPath(screenPath); ctx.clip()
// Dusk sky
linear(ctx, [c(0xFFC79A), c(0xFF8FA3), c(0x7B6CF0), c(0x2B3FA8)], [0, 0.28, 0.62, 1],
       from: CGPoint(x: 512, y: screen.minY + screen.height * 0.35), to: CGPoint(x: 512, y: screen.maxY))
// Sun setting into the cove
let sun = CGPoint(x: 512, y: screen.minY + screen.height * 0.40)
let sunG = CGGradient(colorsSpace: cs, colors: [c(0xFFF4D6), c(0xFFD08A, 0.9), c(0xFFB27A, 0)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawRadialGradient(sunG, startCenter: sun, startRadius: 0, endCenter: sun, endRadius: 120, options: [])

// Headlands: land rises from both screen edges and slopes into the bay, framing the sunset.
let base = screen.minY
let horizon = screen.minY + screen.height * 0.40
func land(_ edgeX: CGFloat, _ peak: CGFloat, _ shoulder: CGPoint, _ toe: CGFloat, _ color: CGColor) {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: edgeX, y: base))
    p.addLine(to: CGPoint(x: edgeX, y: peak))
    p.addCurve(to: CGPoint(x: toe, y: horizon - 2), control1: shoulder,
               control2: CGPoint(x: toe + (edgeX < toe ? -40 : 40), y: horizon + 26))
    p.addLine(to: CGPoint(x: toe, y: base)); p.closeSubpath()
    ctx.addPath(p); ctx.setFillColor(color); ctx.fillPath()
}
land(screen.minX, horizon + 96, CGPoint(x: screen.minX + 120, y: horizon + 104), screen.minX + 200, c(0x2A3A8F))
land(screen.maxX, horizon + 168, CGPoint(x: screen.maxX - 70, y: horizon + 176), screen.maxX - 236, c(0x1E2A78))
// Water
ctx.saveGState()
let water = CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: horizon - screen.minY)
ctx.clip(to: water)
linear(ctx, [c(0x6FD3F7), c(0x2A8BE0), c(0x1450B0)], [0, 0.55, 1], from: CGPoint(x: 512, y: horizon), to: CGPoint(x: 512, y: screen.minY))
// Soft sun glints on the water
for (i, (w, a)) in [(150.0, 0.55), (104.0, 0.42), (66.0, 0.3)].enumerated() {
    let y = horizon - 22 - CGFloat(i) * 26
    let r = CGRect(x: 512 - w / 2, y: y, width: w, height: 8)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil))
    ctx.setFillColor(c(0xFFF0CF, a)); ctx.fillPath()
}
ctx.restoreGState()
// Beach curving around the cove: warm sand with a thin line of foam.
let beachTop: (CGFloat) -> CGMutablePath = { lift in
    let b = CGMutablePath()
    b.move(to: CGPoint(x: screen.minX, y: screen.minY + 58 + lift))
    b.addCurve(to: CGPoint(x: screen.maxX, y: screen.minY + 40 + lift),
               control1: CGPoint(x: screen.minX + 200, y: screen.minY + 104 + lift),
               control2: CGPoint(x: screen.maxX - 220, y: screen.minY - 6 + lift))
    b.addLine(to: CGPoint(x: screen.maxX, y: screen.minY)); b.addLine(to: CGPoint(x: screen.minX, y: screen.minY)); b.closeSubpath()
    return b
}
ctx.addPath(beachTop(7)); ctx.setFillColor(c(0xFFFFFF, 0.9)); ctx.fillPath()
ctx.addPath(beachTop(0)); ctx.saveGState(); ctx.clip()
linear(ctx, [c(0xFBE3C2), c(0xF2CB98)], [0, 1], from: CGPoint(x: 512, y: screen.minY + 90), to: CGPoint(x: 512, y: screen.minY))
ctx.restoreGState()
ctx.restoreGState()

// Screen inner edge
ctx.addPath(screenPath); ctx.setStrokeColor(c(0x0B1F55, 0.18)); ctx.setLineWidth(2); ctx.strokePath()

// MARK: Stand
let neck = CGMutablePath()
neck.move(to: CGPoint(x: 452, y: 330)); neck.addLine(to: CGPoint(x: 572, y: 330))
neck.addLine(to: CGPoint(x: 590, y: 250)); neck.addLine(to: CGPoint(x: 434, y: 250)); neck.closeSubpath()
ctx.addPath(neck)
ctx.saveGState(); ctx.clip()
linear(ctx, [c(0xDCE6F7), c(0xAFC0E0)], [0, 1], from: CGPoint(x: 512, y: 330), to: CGPoint(x: 512, y: 250))
ctx.restoreGState()
let foot = CGPath(roundedRect: CGRect(x: 380, y: 226, width: 264, height: 30), cornerWidth: 15, cornerHeight: 15, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: c(0x031540, 0.45))
ctx.addPath(foot); ctx.setFillColor(c(0xE8EEF9)); ctx.fillPath()
ctx.restoreGState()

// Top sheen on the body for that glassy Apple finish.
ctx.saveGState()
let sheen = CGMutablePath()
sheen.move(to: CGPoint(x: 100, y: 924)); sheen.addLine(to: CGPoint(x: 924, y: 924))
sheen.addLine(to: CGPoint(x: 924, y: 700))
sheen.addCurve(to: CGPoint(x: 100, y: 780), control1: CGPoint(x: 700, y: 760), control2: CGPoint(x: 400, y: 820))
sheen.closeSubpath()
ctx.addPath(sheen); ctx.clip()
linear(ctx, [c(0xFFFFFF, 0.16), c(0xFFFFFF, 0)], [0, 1], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 720))
ctx.restoreGState()
ctx.restoreGState()

// Hairline edge
ctx.addPath(bodyPath); ctx.setStrokeColor(c(0xFFFFFF, 0.12)); ctx.setLineWidth(3); ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path) (\(Int(S))px)")

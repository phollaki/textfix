import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowBlurRadius = 28
shadow.set()
NSColor.black.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(
    starting: NSColor(red: 0.36, green: 0.42, blue: 1.0, alpha: 1),
    ending: NSColor(red: 0.55, green: 0.24, blue: 0.93, alpha: 1)
)?.draw(in: shape, angle: -90)

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let font = NSFont.systemFont(ofSize: 430, weight: .heavy)
let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 430) } ?? font
let text = NSAttributedString(string: "Aa", attributes: [
    .font: rounded,
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
])
text.draw(in: NSRect(x: 80, y: 390, width: 824, height: 520))

let line = NSBezierPath()
line.lineWidth = 34
line.lineCapStyle = .round
line.move(to: NSPoint(x: 230, y: 370))
line.curve(to: NSPoint(x: 540, y: 370), controlPoint1: NSPoint(x: 330, y: 330), controlPoint2: NSPoint(x: 440, y: 410))
NSColor.white.withAlphaComponent(0.85).setStroke()
line.stroke()

let badge = NSRect(x: 620, y: 160, width: 240, height: 240)
NSColor(red: 0.2, green: 0.8, blue: 0.45, alpha: 1).setFill()
NSBezierPath(ovalIn: badge).fill()
NSColor.white.setStroke()
let ring = NSBezierPath(ovalIn: badge.insetBy(dx: 6, dy: 6))
ring.lineWidth = 12
ring.stroke()

let check = NSBezierPath()
check.lineWidth = 34
check.lineCapStyle = .round
check.lineJoinStyle = .round
check.move(to: NSPoint(x: 680, y: 285))
check.line(to: NSPoint(x: 727, y: 238))
check.line(to: NSPoint(x: 803, y: 327))
check.stroke()

image.unlockFocus()

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))

import AppKit
import CoreGraphics

func generateAppIcon(symbolName: String, outputPath: String, size: CGFloat = 1024) {
    let imageSize = NSSize(width: size, height: size)
    let iconImage = NSImage(size: imageSize)
    
    iconImage.lockFocus()
    
    // Draw background solid color
    let context = NSGraphicsContext.current!.cgContext
    
    // Premium Solid Color (Deep macOS Indigo)
    let backgroundColor = NSColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1.0)
    backgroundColor.setFill()
    
    // Draw Squircle (standard macOS icon shape)
    let rect = NSRect(origin: .zero, size: imageSize)
    let radius = size * 0.225
    let path = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.05, dy: size * 0.05), xRadius: radius, yRadius: radius)
    
    context.saveGState()
    path.fill() // Fill with solid color
    context.restoreGState()
    
    // Render SF Symbol
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.45, weight: .semibold)
    if let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let symbolSize = symbolImage.size
        let drawRect = NSRect(
            x: (size - symbolSize.width) / 2,
            y: (size - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )
        
        // Use semi-transparent white for a more premium look or pure white
        let symbolColor = NSColor.white
        
        context.saveGState()
        // Subtle glow/shadow
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: size * 0.01, color: NSColor.black.withAlphaComponent(0.2).cgColor)
        symbolImage.lockFocus()
        symbolColor.set()
        let imageRect = NSRect(origin: .zero, size: symbolSize)
        __NSRectFillUsingOperation(imageRect, .sourceAtop)
        symbolImage.unlockFocus()
        
        symbolImage.draw(in: drawRect, from: NSRect(origin: .zero, size: symbolSize), operation: .sourceOver, fraction: 1.0)
        context.restoreGState()
    }
    
    iconImage.unlockFocus()
    
    // Save to PNG
    if let tiffData = iconImage.tiffRepresentation,
       let bitmapImage = NSBitmapImageRep(data: tiffData),
       let pngData = bitmapImage.representation(using: .png, properties: [:]) {
        try? pngData.write(to: URL(fileURLWithPath: outputPath))
        print("Successfully generated icon at \(outputPath)")
    } else {
        print("Failed to generate icon data")
    }
}

let arguments = CommandLine.arguments
let symbol = arguments.count > 1 ? arguments[1] : "computermouse.fill"
let output = arguments.count > 2 ? arguments[2] : "icon_1024.png"

generateAppIcon(symbolName: symbol, outputPath: output)

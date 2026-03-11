#!/usr/bin/swift
import AppKit
import CoreGraphics

let size: CGFloat = 1024
let rect = NSRect(x: 0, y: 0, width: size, height: size)
let image = NSImage(size: rect.size)

image.lockFocus()
let context = NSGraphicsContext.current!.cgContext

// Draw rounded rect background with gradient
let path = NSBezierPath(roundedRect: rect.insetBy(dx: 50, dy: 50), xRadius: 200, yRadius: 200)
context.saveGState()
path.addClip()

let colors = [NSColor.systemOrange.cgColor, NSColor.orange.cgColor] as CFArray
let colorSpace = CGColorSpaceCreateDeviceRGB()
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
context.restoreGState()

// Draw stopwatch pictogram
let center = CGPoint(x: size/2, y: size/2)
let radius: CGFloat = 250
context.setStrokeColor(NSColor.white.cgColor)
context.setLineWidth(40)
context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius*2, height: radius*2))

// Draw hands
context.move(to: center)
context.addLine(to: CGPoint(x: center.x, y: center.y + radius - 60))
context.strokePath()

context.move(to: center)
context.addLine(to: CGPoint(x: center.x + 100, y: center.y + 100))
context.strokePath()

// Draw button
let buttonWidth: CGFloat = 120
let buttonHeight: CGFloat = 40
context.setFillColor(NSColor.white.cgColor)
context.fill(CGRect(x: center.x - buttonWidth/2, y: center.y + radius + 20, width: buttonWidth, height: buttonHeight))

image.unlockFocus()

let outputPath = "AppIcon.png"
if let tiffData = image.tiffRepresentation,
   let bitmap = NSBitmapImageRep(data: tiffData),
   let pngData = bitmap.representation(using: .png, properties: [:]) {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
    print("Generated \(outputPath)")
}

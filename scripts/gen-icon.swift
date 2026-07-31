// gen-icon.swift — renders the SessionHawk app icon (hawk emoji on a rounded
// gradient tile, macOS Big Sur icon style) to assets/icon_1024.png.
// Run: swift scripts/gen-icon.swift
import AppKit

let canvas: CGFloat = 1024
// macOS icons leave ~10% transparent margin around the rounded tile
let inset: CGFloat = 100
let tileRect = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)

let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

let tile = NSBezierPath(roundedRect: tileRect, xRadius: 185, yRadius: 185)
let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.35, alpha: 1.0),
    ending: NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.13, alpha: 1.0)
)
gradient?.draw(in: tile, angle: -90)

// Flat single-color white hawk silhouette (MAMP-style): render the eagle
// emoji for its shape, then flatten every pixel to pure white.
let hawk = "🦅" as NSString
let font = NSFont.systemFont(ofSize: 560)
let attrs: [NSAttributedString.Key: Any] = [.font: font]
let textSize = hawk.size(withAttributes: attrs)
let silhouette = NSImage(size: textSize)
silhouette.lockFocus()
hawk.draw(at: .zero, withAttributes: attrs)
NSColor.white.set()
NSRect(origin: .zero, size: textSize).fill(using: .sourceAtop)
silhouette.unlockFocus()
silhouette.draw(
    in: NSRect(
        x: (canvas - textSize.width) / 2,
        y: (canvas - textSize.height) / 2 + 15,
        width: textSize.width,
        height: textSize.height
    )
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to render icon")
}
try! FileManager.default.createDirectory(atPath: "assets", withIntermediateDirectories: true)
try! png.write(to: URL(fileURLWithPath: "assets/icon_1024.png"))
print("wrote assets/icon_1024.png")

// Menu bar template image: same hawk silhouette in black (template images are
// recolored by the system for light/dark menu bars). 36px = 18pt @2x.
let menubarSize: CGFloat = 36
let menubarImage = NSImage(size: NSSize(width: menubarSize, height: menubarSize))
menubarImage.lockFocus()
let mbFont = NSFont.systemFont(ofSize: 30)
let mbAttrs: [NSAttributedString.Key: Any] = [.font: mbFont]
let mbTextSize = hawk.size(withAttributes: mbAttrs)
let mbSilhouette = NSImage(size: mbTextSize)
mbSilhouette.lockFocus()
hawk.draw(at: .zero, withAttributes: mbAttrs)
NSColor.black.set()
NSRect(origin: .zero, size: mbTextSize).fill(using: .sourceAtop)
mbSilhouette.unlockFocus()
mbSilhouette.draw(in: NSRect(
    x: (menubarSize - mbTextSize.width) / 2,
    y: (menubarSize - mbTextSize.height) / 2,
    width: mbTextSize.width,
    height: mbTextSize.height
))
menubarImage.unlockFocus()
guard let mbTiff = menubarImage.tiffRepresentation,
      let mbRep = NSBitmapImageRep(data: mbTiff),
      let mbPng = mbRep.representation(using: .png, properties: [:]) else {
    fatalError("failed to render menubar image")
}
try! mbPng.write(to: URL(fileURLWithPath: "assets/menubar-hawk.png"))
print("wrote assets/menubar-hawk.png")

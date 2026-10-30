import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// 用法: swift compose_icon.swift <hammer.jpg> <dst.png>
// 1) 去掉右下角水印（白底直接填白）
// 2) 合成到 macOS 风格圆角方块（白色渐变底板，锤子居中缩放）

let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("usage: compose_icon <src> <dst>") }
let srcURL = URL(fileURLWithPath: args[1])
let dstURL = URL(fileURLWithPath: args[2])

guard let srcRef = CGImageSourceCreateWithURL(srcURL as CFURL, nil),
      let hammer = CGImageSourceCreateImageAtIndex(srcRef, 0, nil) else {
    fatalError("cannot load \(srcURL.path)")
}

// ── 第一步：水印区域填白 ──
let hw = hammer.width, hh = hammer.height
let patchCtx = CGContext(
    data: nil, width: hw, height: hh, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
patchCtx.draw(hammer, in: CGRect(x: 0, y: 0, width: hw, height: hh))
patchCtx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
// 右下角水印区域（图坐标左下系：y 0..90，x 右侧 60%）
patchCtx.fill(CGRect(x: Int(Double(hw) * 0.55), y: 0, width: Int(Double(hw) * 0.45), height: 95))
let cleaned = patchCtx.makeImage()!

// ── 第二步：合成到圆角方块 ──
let S = 1024
let ctx = CGContext(
    data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
ctx.interpolationQuality = .high

// 圆角方块底板（浅色渐变）
let radius: CGFloat = 230
let tile = CGRect(x: 0, y: 0, width: S, height: S)
let path = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)
ctx.addPath(path)
ctx.clip()
let colors = [
    CGColor(srgbRed: 1.00, green: 1.00, blue: 1.00, alpha: 1),
    CGColor(srgbRed: 0.94, green: 0.94, blue: 0.97, alpha: 1),
] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

// 锤子居中，占 88%
let target: CGFloat = CGFloat(S) * 0.88
let scale = target / CGFloat(hw)
let drawW = CGFloat(hw) * scale, drawH = CGFloat(hh) * scale
let origin = CGPoint(x: (CGFloat(S) - drawW) / 2, y: (CGFloat(S) - drawH) / 2)
ctx.draw(cleaned, in: CGRect(origin: origin, size: CGSize(width: drawW, height: drawH)))

let out = ctx.makeImage()!
let dstRef = CGImageDestinationCreateWithURL(dstURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dstRef, out, nil)
CGImageDestinationFinalize(dstRef)
print("saved \(dstURL.path)")

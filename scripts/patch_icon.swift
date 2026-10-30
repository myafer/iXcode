import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// 用法: swift patch_icon.swift <src.png> <dst.png>
// 用水印上方 110px 的干净背景区域，覆盖右下角水印

let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("usage: patch_icon <src> <dst>") }
let srcURL = URL(fileURLWithPath: args[1])
let dstURL = URL(fileURLWithPath: args[2])

guard let srcRef = CGImageSourceCreateWithURL(srcURL as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(srcRef, 0, nil) else {
    fatalError("cannot load \(srcURL.path)")
}

let w = img.width, h = img.height
let ctx = CGContext(
    data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
ctx.interpolationQuality = .high
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

// 水印区域（CG 坐标，原点左下）：x 840..1024, y 0..95
// 用同一 x 区域、上方 110px 的干净背景覆盖
let dest = CGRect(x: 835, y: 0, width: w - 835, height: 100)
ctx.saveGState()
ctx.clip(to: dest)
ctx.draw(img, in: CGRect(x: 0, y: -110, width: w, height: h))
ctx.restoreGState()

let out = ctx.makeImage()!
let dstRef = CGImageDestinationCreateWithURL(dstURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dstRef, out, nil)
CGImageDestinationFinalize(dstRef)
print("saved \(dstURL.path)")

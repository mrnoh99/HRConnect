#!/usr/bin/env swift
// 앱 아이콘(1024×1024, 불투명) 생성: 어두운 배경 + 빨간 하트 + 전파 호.
// 사용: swift scripts/generate_app_icons.swift   (저장소 루트에서)
import AppKit

let size = 1024
// 알파 채널 없는(불투명) 비트맵에 직접 그린다.
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

// 하트(원점 좌하단 좌표계)
let red = CGColor(red: 1.0, green: 0.30, blue: 0.27, alpha: 1)
let cx: CGFloat = 512, top: CGFloat = 640, bottom: CGFloat = 250, w: CGFloat = 300
let heart = CGMutablePath()
heart.move(to: CGPoint(x: cx, y: bottom))
heart.addCurve(to: CGPoint(x: cx - w, y: top),
               control1: CGPoint(x: cx - 120, y: bottom + 110), control2: CGPoint(x: cx - w, y: top - 190))
heart.addArc(center: CGPoint(x: cx - w / 2, y: top), radius: w / 2, startAngle: .pi, endAngle: 0, clockwise: true)
heart.addArc(center: CGPoint(x: cx + w / 2, y: top), radius: w / 2, startAngle: .pi, endAngle: 0, clockwise: true)
heart.addCurve(to: CGPoint(x: cx, y: bottom),
               control1: CGPoint(x: cx + w, y: top - 190), control2: CGPoint(x: cx + 120, y: bottom + 110))
heart.closeSubpath()
ctx.addPath(heart)
ctx.setFillColor(red)
ctx.fillPath()

// 좌우 전파 호
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
ctx.setLineWidth(26)
ctx.setLineCap(.round)
let center = CGPoint(x: cx, y: 520)
for radius in [400.0, 465.0] {
    ctx.addArc(center: center, radius: radius, startAngle: -.pi / 7, endAngle: .pi / 7, clockwise: false)
    ctx.strokePath()
    ctx.addArc(center: center, radius: radius, startAngle: .pi - .pi / 7, endAngle: .pi + .pi / 7, clockwise: false)
    ctx.strokePath()
}

let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
for path in ["HRConnect/Assets.xcassets/AppIcon.appiconset/AppIcon.png",
             "HRConnectWatch/Assets.xcassets/AppIcon.appiconset/AppIcon.png"] {
    try png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

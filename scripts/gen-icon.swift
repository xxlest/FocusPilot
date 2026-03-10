#!/usr/bin/env swift
// gen-icon.swift
// 生成与悬浮球一致的 Enso 品牌 Logo .icns 文件
// 用法: swift scripts/gen-icon.swift <output-dir>

import AppKit
import Foundation

// MARK: - Enso 品牌 Logo 绘制（与 FloatingBallView.createBrandLogoImage 一致）

func createBrandLogo(size: CGFloat, gradientColors: (light: NSColor, medium: NSColor, dark: NSColor)) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let circleRect = NSRect(x: 0, y: 0, width: size, height: size)
    let circlePath = NSBezierPath(ovalIn: circleRect)
    let center = CGPoint(x: size / 2, y: size / 2)

    // 1. 径向渐变背景
    let bgGradient = NSGradient(colorsAndLocations:
        (gradientColors.light, 0.0),
        (gradientColors.medium, 0.5),
        (gradientColors.dark, 1.0)
    )
    bgGradient?.draw(in: circlePath, relativeCenterPosition: NSPoint(x: -0.15, y: 0.2))

    // 2. 球形高光
    NSGraphicsContext.saveGraphicsState()
    circlePath.addClip()
    let highlightRect = NSRect(x: size * 0.08, y: size * 0.45, width: size * 0.55, height: size * 0.50)
    let highlightPath = NSBezierPath(ovalIn: highlightRect)
    let highlightGradient = NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0.22), 0.0),
        (NSColor.white.withAlphaComponent(0.06), 0.6),
        (NSColor.clear, 1.0)
    )
    highlightGradient?.draw(in: highlightPath, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // 3. 底部暗区
    NSGraphicsContext.saveGraphicsState()
    circlePath.addClip()
    let shadowRect = NSRect(x: size * 0.1, y: -size * 0.15, width: size * 0.8, height: size * 0.45)
    let shadowPath = NSBezierPath(ovalIn: shadowRect)
    let shadowGradient = NSGradient(colorsAndLocations:
        (NSColor.black.withAlphaComponent(0.12), 0.0),
        (NSColor.clear, 1.0)
    )
    shadowGradient?.draw(in: shadowPath, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    // 4. 内边缘光
    let innerGlow = NSBezierPath(ovalIn: NSRect(x: 0.5, y: 0.5, width: size - 1, height: size - 1))
    NSColor.white.withAlphaComponent(0.15).setStroke()
    innerGlow.lineWidth = 0.5
    innerGlow.stroke()

    // 5. 禅圆 Enso
    NSGraphicsContext.saveGraphicsState()
    circlePath.addClip()

    let ensoRadius = size * 0.30
    let segments = 28
    let arcDegrees: CGFloat = 300
    let startAngle: CGFloat = 120
    let maxWidth = size * 0.09
    let minWidth = size * 0.02

    let startRad = startAngle * .pi / 180

    let arcPerSegment = arcDegrees / CGFloat(segments)

    // 5a. 弧线主体
    for i in 0..<segments {
        let t = CGFloat(i) / CGFloat(segments)
        let angle0 = startAngle + arcPerSegment * CGFloat(i)
        let angle1 = startAngle + arcPerSegment * CGFloat(i + 1)

        let rad0 = angle0 * .pi / 180
        let rad1 = angle1 * .pi / 180

        let seg = NSBezierPath()
        seg.move(to: NSPoint(
            x: center.x + ensoRadius * cos(rad0),
            y: center.y + ensoRadius * sin(rad0)
        ))
        seg.line(to: NSPoint(
            x: center.x + ensoRadius * cos(rad1),
            y: center.y + ensoRadius * sin(rad1)
        ))

        let easedT = 1.0 - pow(1.0 - t, 2.0)
        let lineWidth = maxWidth - (maxWidth - minWidth) * easedT
        let alpha = 0.88 - 0.15 * easedT
        NSColor.white.withAlphaComponent(alpha).setStroke()

        seg.lineWidth = lineWidth
        seg.lineCapStyle = .round
        seg.stroke()
    }

    // 5b. 起笔墨滴
    let inkDropCenter = NSPoint(
        x: center.x + ensoRadius * cos(startRad),
        y: center.y + ensoRadius * sin(startRad)
    )
    let inkDropRadius = size * 0.07
    let inkDropPath = NSBezierPath(ovalIn: NSRect(
        x: inkDropCenter.x - inkDropRadius,
        y: inkDropCenter.y - inkDropRadius,
        width: inkDropRadius * 2,
        height: inkDropRadius * 2
    ))
    NSColor.white.withAlphaComponent(0.92).setFill()
    inkDropPath.fill()

    // 5c. 收笔渐隐散点
    let tailAngles: [CGFloat] = [5.0, 13.0, 22.0]
    let tailRadii: [CGFloat] = [0.042, 0.030, 0.020]
    let tailAlphas: [CGFloat] = [0.65, 0.42, 0.22]

    for j in 0..<tailAngles.count {
        let dotAngle = (startAngle + arcDegrees + tailAngles[j]) * .pi / 180
        let dotCenter = NSPoint(
            x: center.x + ensoRadius * cos(dotAngle),
            y: center.y + ensoRadius * sin(dotAngle)
        )
        let dotR = size * tailRadii[j]
        let dotPath = NSBezierPath(ovalIn: NSRect(
            x: dotCenter.x - dotR,
            y: dotCenter.y - dotR,
            width: dotR * 2,
            height: dotR * 2
        ))
        NSColor.white.withAlphaComponent(tailAlphas[j]).setFill()
        dotPath.fill()
    }

    NSGraphicsContext.restoreGraphicsState()

    image.unlockFocus()
    return image
}

/// 生成带白色圆角正方形背景的完整 app icon
func createAppIcon(canvasSize: CGFloat, gradientColors: (light: NSColor, medium: NSColor, dark: NSColor)) -> NSImage {
    let icon = NSImage(size: NSSize(width: canvasSize, height: canvasSize))
    icon.lockFocus()

    // -- 参数 --
    let squirclePadding = canvasSize * 0.08          // squircle 距画布边缘
    let squircleSize = canvasSize - squirclePadding * 2
    let cornerRadius = squircleSize * 0.2237         // Apple 标准连续圆角比例
    let logoPadding = squircleSize * 0.18            // 球体距 squircle 内边距
    let logoSize = squircleSize - logoPadding * 2

    let squircleRect = NSRect(
        x: squirclePadding, y: squirclePadding,
        width: squircleSize, height: squircleSize
    )
    let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // 1. Squircle 外部微阴影
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -1)
    shadow.shadowBlurRadius = max(canvasSize * 0.01, 1.5)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.set()
    NSColor.white.setFill()
    squirclePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // 2. 白色 Squircle 背景（无阴影再绘一次确保干净）
    NSColor.white.setFill()
    squirclePath.fill()

    // 3. Squircle 极细描边（防止亮色壁纸上边界模糊）
    NSColor.black.withAlphaComponent(0.06).setStroke()
    squirclePath.lineWidth = max(canvasSize * 0.002, 0.5)
    squirclePath.stroke()

    // 4. 球体 Logo 居中绘制
    let logo = createBrandLogo(size: logoSize, gradientColors: gradientColors)
    let logoX = squirclePadding + logoPadding
    let logoY = squirclePadding + logoPadding
    let logoRect = NSRect(x: logoX, y: logoY, width: logoSize, height: logoSize)
    logo.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    icon.unlockFocus()
    return icon
}

/// 将 NSImage 保存为 PNG
func savePNG(_ image: NSImage, to url: URL) {
    guard let tiffData = image.tiffRepresentation,
          let bitmapRep = NSBitmapImageRep(data: tiffData),
          let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to create PNG data")
    }
    try! pngData.write(to: url)
}

// MARK: - Main

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift gen-icon.swift <output-dir>")
    exit(1)
}

let outputDir = CommandLine.arguments[1]

// 默认主题 accent 色（#2563EB 蓝色，与 lightBlue 主题一致）
let accent = NSColor(calibratedRed: 0.145, green: 0.388, blue: 0.922, alpha: 1.0)
let light = accent.blended(withFraction: 0.3, of: .white) ?? accent
let dark = accent.blended(withFraction: 0.4, of: .black) ?? accent
let gradientColors = (light: light, medium: accent, dark: dark)

// .icns 需要的尺寸（iconutil 要求的 iconset 内容）
let sizes: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

let iconsetDir = "\(outputDir)/AppIcon.iconset"
try! FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

for (name, px) in sizes {
    let icon = createAppIcon(canvasSize: px, gradientColors: gradientColors)
    let url = URL(fileURLWithPath: "\(iconsetDir)/\(name).png")
    savePNG(icon, to: url)
}

print("iconset generated at \(iconsetDir)")

// 使用 iconutil 转换为 .icns
let icnsPath = "\(outputDir)/AppIcon.icns"
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetDir, "-o", icnsPath]
try! process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    // 清理 iconset 临时目录
    try? FileManager.default.removeItem(atPath: iconsetDir)
    print("AppIcon.icns generated at \(icnsPath)")
} else {
    print("iconutil failed with status \(process.terminationStatus)")
    exit(1)
}

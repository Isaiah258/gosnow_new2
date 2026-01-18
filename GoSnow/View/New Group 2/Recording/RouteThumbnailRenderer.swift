//
//  RouteThumbnailRenderer.swift
//  雪兔滑行
//
//  Created by federico Liu on 2026/1/6.
//

import UIKit
import CoreLocation

enum RouteThumbnailRenderer {

    struct Segment {
        let coords: [CLLocationCoordinate2D]
        let bucket: Int // 0=green, 1=orange
    }

    /// 离线渲染一张抽象轨迹图（不依赖 Mapbox / 网络）
    static func render(
        size: CGSize,
        segments: [Segment],
        padding: CGFloat = 26,
        cornerRadius: CGFloat = 22
    ) -> UIImage {

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        return renderer.image { ctx in
            let cg = ctx.cgContext
            let rect = CGRect(origin: .zero, size: size)

            // 背景：纯白（不透底）
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(rect)

            // 圆角裁切
            let clipPath = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            clipPath.addClip()

            // 轻微网格（Apple Fitness 那种硬朗干净的“纸感”）
            drawGrid(in: cg, rect: rect)

            // 没轨迹就画占位
            guard let fitted = fitPoints(segments: segments, in: rect.insetBy(dx: padding, dy: padding)) else {
                drawEmptyState(in: cg, rect: rect)
                return
            }

            // 先画描边（黑色粗线）
            drawSegments(
                in: cg,
                fitted: fitted,
                colorProvider: { _ in UIColor.black.withAlphaComponent(0.45) },
                lineWidth: 8.0
            )

            // 再画主线（绿/橙）
            drawSegments(
                in: cg,
                fitted: fitted,
                colorProvider: { bucket in
                    bucket == 1 ? UIColor.systemOrange.withAlphaComponent(0.95)
                                : UIColor.systemGreen.withAlphaComponent(0.95)
                },
                lineWidth: 4.5
            )

            // 轻微“浮起”高光边（可选，增强层次）
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.06).cgColor)
            cg.setLineWidth(1)
            cg.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    // MARK: - Drawing helpers

    private static func drawGrid(in cg: CGContext, rect: CGRect) {
        let step: CGFloat = 26
        cg.saveGState()
        cg.setStrokeColor(UIColor.black.withAlphaComponent(0.045).cgColor)
        cg.setLineWidth(1)

        // vertical lines
        var x = rect.minX
        while x <= rect.maxX {
            cg.move(to: CGPoint(x: x, y: rect.minY))
            cg.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += step
        }

        // horizontal lines
        var y = rect.minY
        while y <= rect.maxY {
            cg.move(to: CGPoint(x: rect.minX, y: y))
            cg.addLine(to: CGPoint(x: rect.maxX, y: y))
            y += step
        }

        cg.strokePath()
        cg.restoreGState()
    }

    private static func drawEmptyState(in cg: CGContext, rect: CGRect) {
        cg.saveGState()
        let text = "暂无轨迹"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let p = CGPoint(x: rect.midX - size.width/2, y: rect.midY - size.height/2)
        (text as NSString).draw(at: p, withAttributes: attrs)
        cg.restoreGState()
    }

    private static func drawSegments(
        in cg: CGContext,
        fitted: [(points: [CGPoint], bucket: Int)],
        colorProvider: (Int) -> UIColor,
        lineWidth: CGFloat
    ) {
        cg.saveGState()
        cg.setLineJoin(.round)
        cg.setLineCap(.round)
        cg.setLineWidth(lineWidth)

        for seg in fitted {
            guard seg.points.count >= 2 else { continue }
            cg.setStrokeColor(colorProvider(seg.bucket).cgColor)

            cg.beginPath()
            cg.move(to: seg.points[0])
            for p in seg.points.dropFirst() {
                cg.addLine(to: p)
            }
            cg.strokePath()
        }

        cg.restoreGState()
    }

    /// 把经纬度段转成画布内点，并做 fit（保持比例居中）
    private static func fitPoints(
        segments: [Segment],
        in rect: CGRect
    ) -> [(points: [CGPoint], bucket: Int)]? {

        // 收集全部坐标
        let all = segments.flatMap { $0.coords }
        guard all.count >= 2 else { return nil }

        // 简化投影：x = lon * cos(lat0), y = lat（对滑雪这种小范围足够）
        let lat0 = all.map(\.latitude).reduce(0, +) / Double(all.count)
        let k = cos(lat0 * .pi / 180)

        func proj(_ c: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(x: c.longitude * k, y: c.latitude)
        }

        let projectedAll = all.map(proj)

        var minX = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        for p in projectedAll {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }

        let spanX = max(maxX - minX, 1e-9)
        let spanY = max(maxY - minY, 1e-9)

        let scale = min(rect.width / spanX, rect.height / spanY)

        // 居中偏移
        let contentW = spanX * scale
        let contentH = spanY * scale
        let offsetX = rect.minX + (rect.width - contentW) / 2
        let offsetY = rect.minY + (rect.height - contentH) / 2

        func mapToRect(_ p: CGPoint) -> CGPoint {
            // 注意：UIKit y 轴向下，所以把纬度方向翻转一下会更“正常”
            let x = offsetX + (p.x - minX) * scale
            let y = offsetY + (maxY - p.y) * scale
            return CGPoint(x: x, y: y)
        }

        // 输出每段 points
        var out: [(points: [CGPoint], bucket: Int)] = []
        out.reserveCapacity(segments.count)

        for seg in segments {
            let pts = seg.coords.map { mapToRect(proj($0)) }
            out.append((points: pts, bucket: seg.bucket))
        }
        return out
    }
}


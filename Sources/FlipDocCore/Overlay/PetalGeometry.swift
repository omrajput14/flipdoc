import Foundation
import CoreGraphics
import SwiftUI

/// Exact geometric petal layout and polar hit-testing for FlipDoc's radial fan wheel.
/// Coordinate space: `(0, 0)` is the wheel center; `+X` points right; `+Y` points down (matches SwiftUI & flipped NSView).
public enum PetalGeometry {
    public static let innerRadius: CGFloat = 46.0
    public static let outerRadius: CGFloat = 126.0
    public static let backdropRadius: CGFloat = 134.0
    public static let gap: CGFloat = 4.4
    public static let cornerRadius: CGFloat = 22.0
    public static let labelInnerRadius: CGFloat = 44.0
    public static let wheelDiameter: CGFloat = 276.0

    /// Center angle (in radians, where `-pi/2` is 12 o'clock / straight up, increasing clockwise) for `index` in `0..<count`.
    public static func centerAngle(index: Int, count: Int) -> CGFloat {
        guard count > 1 else {
            return -.pi / 2.0
        }
        let step = (2.0 * .pi) / CGFloat(count)
        return (-.pi / 2.0) + CGFloat(index) * step
    }

    /// Angular span of a single sector before subtracting inter-petal gap.
    public static func sectorSpan(count: Int) -> CGFloat {
        if count <= 1 {
            // Single option renders as a generous sculpted top arc (220°) rather than a degenerate seamless ring
            return (11.0 * .pi) / 9.0
        }
        return (2.0 * .pi) / CGFloat(count)
    }

    /// Position of the label/icon centroid inside a petal relative to `(0, 0)` wheel center.
    public static func labelPosition(index: Int, count: Int) -> CGPoint {
        let angle = centerAngle(index: index, count: count)
        let r = labelInnerRadius + (outerRadius - labelInnerRadius) * 0.54
        return CGPoint(x: cos(angle) * r, y: sin(angle) * r)
    }

    /// Builds a smooth rounded-corner annular wedge `CGPath` centered at `origin`.
    public static func makePetalPath(index: Int, count: Int, origin: CGPoint = .zero) -> CGPath {
        let path = CGMutablePath()
        guard count >= 1, index >= 0, index < count else { return path }

        let mid = centerAngle(index: index, count: count)
        let span = sectorSpan(count: count)
        let startAngle = mid - span / 2.0
        let endAngle = mid + span / 2.0

        func halfGapAngle(at radius: CGFloat) -> CGFloat {
            let safeR = max(radius, gap / 2.0 + 0.1)
            let ratio = min(0.92, Double((gap / 2.0) / safeR))
            return CGFloat(asin(ratio))
        }

        func pt(_ r: CGFloat, _ theta: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + cos(theta) * r, y: origin.y + sin(theta) * r)
        }

        let outerA0 = startAngle + halfGapAngle(at: outerRadius)
        let outerA1 = endAngle - halfGapAngle(at: outerRadius)
        let innerA0 = startAngle + halfGapAngle(at: innerRadius)
        let innerA1 = endAngle - halfGapAngle(at: innerRadius)

        guard outerA1 > outerA0, innerA1 > innerA0 else { return path }

        let outerCornerAngular = min(0.15, (outerA1 - outerA0) * 0.24)
        let innerCornerAngular = min(0.18, (innerA1 - innerA0) * 0.18)

        let innerCtrlR = innerRadius / max(0.05, cos(innerCornerAngular))
        let innerStartR = innerCtrlR + innerRadius * tan(innerCornerAngular)
        let outerShoulderR = outerRadius - min(cornerRadius, (outerRadius - innerRadius) * 0.35)

        let pStart = pt(innerStartR, startAngle + halfGapAngle(at: innerStartR))
        let pOuterLeftShoulder = pt(outerShoulderR, startAngle + halfGapAngle(at: outerShoulderR))
        let pOuterLeftCtrl = pt(outerRadius, outerA0)
        let pOuterArcStart = pt(outerRadius, outerA0 + outerCornerAngular)

        let pOuterRightCtrl = pt(outerRadius, outerA1)
        let pOuterRightShoulder = pt(outerShoulderR, endAngle - halfGapAngle(at: outerShoulderR))

        let pInnerRightShoulder = pt(innerStartR, endAngle - halfGapAngle(at: innerStartR))
        let pInnerRightCtrl = pt(innerCtrlR, endAngle - halfGapAngle(at: innerCtrlR))
        let pInnerArcStart = pt(innerRadius, innerA1 - innerCornerAngular)

        let pInnerLeftCtrl = pt(innerCtrlR, startAngle + halfGapAngle(at: innerCtrlR))

        path.move(to: pStart)
        path.addLine(to: pOuterLeftShoulder)
        path.addQuadCurve(to: pOuterArcStart, control: pOuterLeftCtrl)

        // Note: In +Y-down coordinates, clockwise on screen corresponds to `clockwise: false` in CoreGraphics `addArc`!
        path.addArc(
            center: origin,
            radius: outerRadius,
            startAngle: outerA0 + outerCornerAngular,
            endAngle: outerA1 - outerCornerAngular,
            clockwise: false
        )

        path.addQuadCurve(to: pOuterRightShoulder, control: pOuterRightCtrl)
        path.addLine(to: pInnerRightShoulder)
        path.addQuadCurve(to: pInnerArcStart, control: pInnerRightCtrl)

        // Counter-clockwise back along inner radius (`clockwise: true` in +Y-down CoreGraphics)
        path.addArc(
            center: origin,
            radius: innerRadius,
            startAngle: innerA1 - innerCornerAngular,
            endAngle: innerA0 + innerCornerAngular,
            clockwise: true
        )

        path.addQuadCurve(to: pStart, control: pInnerLeftCtrl)
        path.closeSubpath()
        return path
    }

    /// Exact petal hit-testing for pointer delta `(dx, dy)` from wheel center `(0, 0)` in +Y-down coordinates.
    public static func hitTest(dx: CGFloat, dy: CGFloat, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let dist = hypot(dx, dy)
        guard dist >= innerRadius && dist <= outerRadius else { return nil }

        let pt = CGPoint(x: dx, y: dy)
        // Fast exact check against each petal's CGPath (count is typically 1...9, takes < 5 microseconds!)
        for idx in 0..<count {
            let path = makePetalPath(index: idx, count: count, origin: .zero)
            if path.contains(pt) {
                return idx
            }
        }
        return nil
    }
}

public struct PetalShape: Shape {
    public let index: Int
    public let count: Int

    public init(index: Int, count: Int) {
        self.index = index
        self.count = count
    }

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return Path(PetalGeometry.makePetalPath(index: index, count: count, origin: center))
    }
}

public struct DonutBackdropShape: Shape {
    public let innerRadius: CGFloat
    public let outerRadius: CGFloat

    public init(
        innerRadius: CGFloat = PetalGeometry.innerRadius - 3.5,
        outerRadius: CGFloat = PetalGeometry.backdropRadius
    ) {
        self.innerRadius = innerRadius
        self.outerRadius = outerRadius
    }

    public func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.addArc(center: center, radius: outerRadius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        p.addArc(center: center, radius: innerRadius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: true)
        return p
    }
}


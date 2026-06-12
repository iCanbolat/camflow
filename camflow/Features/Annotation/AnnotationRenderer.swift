import SwiftUI

/// Draws annotation shapes into a `GraphicsContext`. Shared by the editor,
/// the photo viewer overlay, and (later) export baking — one source of truth
/// for how every shape looks.
enum AnnotationRenderer {
    static func draw(_ shapes: [AnnotationShape], in context: inout GraphicsContext, size: CGSize) {
        for shape in shapes {
            draw(shape, in: &context, size: size)
        }
    }

    static func draw(_ shape: AnnotationShape, in context: inout GraphicsContext, size: CGSize) {
        let color = Color(hex: shape.colorHex)
        let lineWidth = max(1.5, shape.lineWidth * size.width)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let points = shape.points.map { denormalize($0, in: size) }

        switch shape.kind {
        case .freehand:
            guard points.count > 1 else { return }
            var path = Path()
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            context.stroke(path, with: .color(color), style: style)

        case .arrow:
            guard points.count == 2 else { return }
            let (start, end) = (points[0], points[1])
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)

            // Arrowhead: two strokes splayed back from the tip.
            let angle = Double(atan2(end.y - start.y, end.x - start.x))
            let headLength = Double(max(14, lineWidth * 4))
            let spread = Double.pi / 7
            for side in [angle + .pi - spread, angle + .pi + spread] {
                path.move(to: end)
                path.addLine(to: CGPoint(
                    x: Double(end.x) + headLength * Darwin.cos(side),
                    y: Double(end.y) + headLength * Darwin.sin(side)
                ))
            }
            context.stroke(path, with: .color(color), style: style)

        case .rectangle:
            guard points.count == 2 else { return }
            let rect = CGRect(corner: points[0], opposite: points[1])
            context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(color), style: style)

        case .ellipse:
            guard points.count == 2 else { return }
            let rect = CGRect(corner: points[0], opposite: points[1])
            context.stroke(Path(ellipseIn: rect), with: .color(color), style: style)

        case .text:
            guard let anchor = points.first, let string = shape.text, !string.isEmpty else { return }
            let fontSize = max(12, shape.fontScale * size.width)
            let text = Text(string)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundStyle(color)
            let resolved = context.resolve(text)
            let textSize = resolved.measure(in: size)

            // Subtle scrim behind the text for readability on busy photos.
            let padding = fontSize * 0.18
            let background = CGRect(
                x: anchor.x - padding,
                y: anchor.y - padding,
                width: textSize.width + padding * 2,
                height: textSize.height + padding * 2
            )
            context.fill(
                Path(roundedRect: background, cornerRadius: padding),
                with: .color(.black.opacity(0.35))
            )
            context.draw(resolved, at: anchor, anchor: .topLeading)
        }
    }

    private static func denormalize(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: point.x * size.width, y: point.y * size.height)
    }
}

private extension CGRect {
    init(corner: CGPoint, opposite: CGPoint) {
        self.init(
            x: min(corner.x, opposite.x),
            y: min(corner.y, opposite.y),
            width: abs(opposite.x - corner.x),
            height: abs(opposite.y - corner.y)
        )
    }
}

import SwiftUI

struct PieChartSegment: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let color: Color
}

struct PieChart: View {
    let segments: [PieChartSegment]
    let selectedName: String?
    let onSelect: (PieChartSegment) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let explodeMax: CGFloat = 10
            let radius = max(0, size / 2 - explodeMax - 2)
            let innerRadius = radius * 0.56
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let total = segments.map { $0.value }.reduce(0, +)

            Canvas { context, _ in
                var startAngle = Angle.degrees(-90)
                for segment in segments {
                    let fraction = total == 0 ? 0 : segment.value / total
                    let endAngle = startAngle + Angle.degrees(fraction * 360)

                    let isSelected = segment.name == selectedName
                    let midAngle = Angle.degrees((startAngle.degrees + endAngle.degrees) / 2)
                    let explodeDistance: CGFloat = isSelected ? explodeMax : 0
                    let segmentCenter = CGPoint(
                        x: center.x + CGFloat(cos(midAngle.radians)) * explodeDistance,
                        y: center.y + CGFloat(sin(midAngle.radians)) * explodeDistance
                    )
                    let path = donutPath(
                        center: segmentCenter,
                        outerRadius: radius,
                        innerRadius: innerRadius,
                        startAngle: startAngle,
                        endAngle: endAngle
                    )

                    let fillColor = isSelected ? segment.color.opacity(0.95) : segment.color.opacity(0.75)
                    context.fill(path, with: .color(fillColor))

                    startAngle = endAngle
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        guard total > 0 else { return }
                        let location = value.location
                        let dx = location.x - center.x
                        let dy = center.y - location.y
                        let distance = sqrt(dx * dx + dy * dy)
                        guard distance <= radius, distance >= innerRadius else { return }

                        var degrees = atan2(dy, dx) * 180 / .pi
                        if degrees < 0 { degrees += 360 }
                        var chartAngle = 90 - degrees
                        if chartAngle < 0 { chartAngle += 360 }

                        var accumulator: Double = 0
                        for segment in segments {
                            let fraction = total == 0 ? 0 : segment.value / total
                            let segmentAngle = fraction * 360
                            if chartAngle >= accumulator && chartAngle < accumulator + segmentAngle {
                                onSelect(segment)
                                break
                            }
                            accumulator += segmentAngle
                        }
                    }
            )
        }
    }

    private func donutPath(
        center: CGPoint,
        outerRadius: CGFloat,
        innerRadius: CGFloat,
        startAngle: Angle,
        endAngle: Angle
    ) -> Path {
        var path = Path()
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

import SwiftUI

struct GenreGalaxySegment: Identifiable {
    let name: String
    let value: Double
    let color: Color

    var id: String { name }
}

struct GenreGalaxy: View {
    let segments: [GenreGalaxySegment]
    let selectedName: String?
    let onSelect: (GenreGalaxySegment) -> Void

    var body: some View {
        GeometryReader { geo in
            let nodes = layoutNodes(segments: segments, size: geo.size)

            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.06, green: 0.08, blue: 0.12),
                                Color(red: 0.10, green: 0.12, blue: 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                ForEach(nodes) { node in
                    let isSelected = node.segment.name == selectedName

                    Button {
                        onSelect(node.segment)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            node.segment.color.opacity(isSelected ? 0.95 : 0.88),
                                            node.segment.color.opacity(isSelected ? 0.62 : 0.48)
                                        ],
                                        center: .topLeading,
                                        startRadius: 4,
                                        endRadius: node.radius
                                    )
                                )

                            Circle()
                                .stroke(Color.white.opacity(isSelected ? 0.7 : 0.35), lineWidth: isSelected ? 2.0 : 1.0)

                            if node.radius >= 28 {
                                VStack(spacing: 2) {
                                    Text(node.segment.name)
                                        .font(.system(size: labelFontSize(for: node.radius), weight: .semibold))
                                        .foregroundColor(.white.opacity(0.96))
                                        .multilineTextAlignment(.center)
                                        .lineLimit(2)

                                    if isSelected, node.radius >= 40 {
                                        Text("\(Int(node.segment.value))")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                                .padding(.horizontal, 6)
                            }
                        }
                        .frame(width: node.radius * 2, height: node.radius * 2)
                        .shadow(color: node.segment.color.opacity(isSelected ? 0.45 : 0.18), radius: isSelected ? 14 : 8, x: 0, y: 4)
                        .scaleEffect(isSelected ? 1.06 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .position(node.center)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func layoutNodes(segments: [GenreGalaxySegment], size: CGSize) -> [GalaxyNode] {
        guard !segments.isEmpty else { return [] }

        let sorted = segments.sorted { $0.value > $1.value }
        let maxValue = max(sorted.first?.value ?? 1, 1)
        let minDimension = min(size.width, size.height)
        let minRadius: CGFloat = max(18, minDimension * 0.07)
        let maxRadius: CGFloat = max(38, minDimension * 0.16)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxOrbit = minDimension / 2 - maxRadius - 8

        var placed: [GalaxyNode] = []
        placed.reserveCapacity(sorted.count)

        for (index, segment) in sorted.enumerated() {
            let normalized = sqrt(segment.value / maxValue)
            let radius = minRadius + CGFloat(normalized) * (maxRadius - minRadius)

            var point: CGPoint
            if index == 0 {
                point = center
            } else {
                let baseAngle = Double(index) * 137.508
                let baseDistance = min(maxOrbit, CGFloat(sqrt(Double(index))) * (maxRadius * 0.9))
                point = pointOnCircle(center: center, radius: baseDistance, angleDegrees: baseAngle)
            }
            point = clamped(point: point, radius: radius, size: size, padding: 6)

            var candidate = point
            var attempt = 0
            while overlaps(point: candidate, radius: radius, existing: placed), attempt < 120 {
                attempt += 1
                let angle = Double(index * 41 + attempt * 23)
                let distance = min(maxOrbit, CGFloat(attempt) * 3.6 + CGFloat(sqrt(Double(index))) * (maxRadius * 0.7))
                candidate = pointOnCircle(center: center, radius: distance, angleDegrees: angle)
                candidate = clamped(point: candidate, radius: radius, size: size, padding: 6)
            }

            placed.append(GalaxyNode(segment: segment, center: candidate, radius: radius))
        }

        return placed
    }

    private func pointOnCircle(center: CGPoint, radius: CGFloat, angleDegrees: Double) -> CGPoint {
        let radians = angleDegrees * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }

    private func clamped(point: CGPoint, radius: CGFloat, size: CGSize, padding: CGFloat) -> CGPoint {
        CGPoint(
            x: min(max(point.x, radius + padding), size.width - radius - padding),
            y: min(max(point.y, radius + padding), size.height - radius - padding)
        )
    }

    private func overlaps(point: CGPoint, radius: CGFloat, existing: [GalaxyNode]) -> Bool {
        for node in existing {
            let dx = point.x - node.center.x
            let dy = point.y - node.center.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance < (radius + node.radius + 7) {
                return true
            }
        }
        return false
    }

    private func labelFontSize(for radius: CGFloat) -> CGFloat {
        if radius < 30 { return 9 }
        if radius < 38 { return 10 }
        if radius < 48 { return 11 }
        return 12
    }
}

private struct GalaxyNode: Identifiable {
    let segment: GenreGalaxySegment
    let center: CGPoint
    let radius: CGFloat

    var id: String { segment.id }
}

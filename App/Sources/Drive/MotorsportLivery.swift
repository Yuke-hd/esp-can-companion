import SwiftUI
import DesignSystem

/// Decorative racing livery behind the Motorsport Drive gauges: twin slanted
/// stripes through the centre and a chequered band in the bottom-left corner.
///
/// Purely ornamental: kept low in contrast so it never competes with a
/// reading, and hidden from accessibility. `parted` slides the stripes apart
/// to frame the enlarged G-meter when it takes the centre.
struct MotorsportLivery: View {
    /// Horizontal shift per point of height, matching the brand mark's slant.
    static let slant: CGFloat = 0.35

    var parted = false

    var body: some View {
        ZStack {
            MotorsportLiveryStripes(parted: parted)
            // Clear of the display's rounded corner and the home indicator.
            MotorsportChequer()
                .padding(.horizontal, 44)
                .padding(.bottom, 6)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Two broad bands with a narrow gap, edged in red pinstripes, leaning like
/// the italic numerals and centred behind the gear.
///
/// When `parted`, each half slides outward until its inner edge clears the
/// centred G-meter ring, so the stripes no longer cut through the dial.
private struct MotorsportLiveryStripes: View {
    let parted: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let band = (size.height * 0.16).rounded()
            let gap = (band * 0.22).rounded()
            let pinstripe: CGFloat = 2
            let pinGap: CGFloat = 4
            let centre = size.width / 2
            let outer = gap / 2 + band + pinGap + pinstripe / 2
            // The centred ring is roughly 0.56 of the height across; a slanted
            // edge clears it once it sits ~1.06 radii (1 / cos of the lean)
            // from the centre.
            let spread = parted ? (size.height * 0.3 - gap / 2).rounded() : 0
            ZStack {
                ZStack {
                    stripe(in: size, centre: centre - (gap + band) / 2, width: band)
                        .fill(Theme.Colors.textPrimary.opacity(0.035))
                    stripe(in: size, centre: centre - outer, width: pinstripe)
                        .fill(Theme.Colors.accent.opacity(0.35))
                }
                .offset(x: -spread)
                ZStack {
                    stripe(in: size, centre: centre + (gap + band) / 2, width: band)
                        .fill(Theme.Colors.textPrimary.opacity(0.035))
                    stripe(in: size, centre: centre + outer, width: pinstripe)
                        .fill(Theme.Colors.accent.opacity(0.35))
                }
                .offset(x: spread)
            }
        }
    }

    /// A full-height parallelogram whose midline crosses `centre` halfway down.
    private func stripe(in size: CGSize, centre: CGFloat, width: CGFloat) -> Path {
        let lean = size.height * MotorsportLivery.slant / 2
        var path = Path()
        path.move(to: CGPoint(x: centre - width / 2 + lean, y: 0))
        path.addLine(to: CGPoint(x: centre + width / 2 + lean, y: 0))
        path.addLine(to: CGPoint(x: centre + width / 2 - lean, y: size.height))
        path.addLine(to: CGPoint(x: centre - width / 2 - lean, y: size.height))
        path.closeSubpath()
        return path
    }
}

/// Two rows of chequers along the bottom edge under the RPM column, fading
/// out toward the centre. The right corner is left clear for the g-meter.
private struct MotorsportChequer: View {
    private static let square: CGFloat = 7
    private static let rows = 2
    private static let reach: CGFloat = 0.24

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let columns = Int((size.width / Self.square).rounded(.up))
                for row in 0..<Self.rows {
                    for column in 0..<columns where (row + column).isMultiple(of: 2) {
                        let rect = CGRect(
                            x: CGFloat(column) * Self.square,
                            y: CGFloat(row) * Self.square,
                            width: Self.square,
                            height: Self.square
                        )
                        context.fill(Path(rect), with: .color(Theme.Colors.textPrimary.opacity(0.14)))
                    }
                }
            }
            .frame(width: (proxy.size.width * Self.reach).rounded(), height: Self.square * CGFloat(Self.rows))
            .mask(LinearGradient(colors: [.black, .black.opacity(0)], startPoint: .leading, endPoint: .trailing))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}

/// The brand mark's three slanted red bars, set beside a Drive label.
struct MotorsportHashes: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle()
                    .fill(Theme.Colors.accent)
                    .frame(width: 3, height: 9)
                    .transformEffect(CGAffineTransform(a: 1, b: 0, c: -MotorsportLivery.slant, d: 1, tx: 3, ty: 0))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A livery-style backplate behind a large Drive numeral: a slanted panel
/// with a stepped body, a red accent bar, hash ticks and fine pinstripes.
///
/// `mirrored` puts the stepped end on the right for the speed column; the
/// slant still leans forward so it matches the italic numerals.
struct MotorsportNumeralPlate: View {
    var mirrored = false

    var body: some View {
        GeometryReader { proxy in
            let plate = PlateGeometry(size: proxy.size, mirrored: mirrored)
            ZStack {
                plate.panel.fill(Theme.Colors.textPrimary.opacity(0.03))
                plate.body.fill(Theme.Colors.textPrimary.opacity(0.07))
                plate.pinstripes.fill(Theme.Colors.textPrimary.opacity(0.12))
                plate.accent.fill(Theme.Colors.accent.opacity(0.85))
                plate.ticks.fill(Theme.Colors.accent.opacity(0.85))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The plate's parts in unit coordinates, where x 0 is the stepped (outer)
/// end, sheared forward by the livery slant.
private struct PlateGeometry {
    let size: CGSize
    let mirrored: Bool

    private func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        let lean = (0.5 - y) * size.height * MotorsportLivery.slant
        return CGPoint(x: (mirrored ? 1 - x : x) * size.width + lean, y: y * size.height)
    }

    private func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
        var path = Path()
        path.addLines(points.map { point($0.0, $0.1) })
        path.closeSubpath()
        return path
    }

    private func bar(_ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> Path {
        polygon([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])
    }

    /// The pale outline panel the whole graphic sits on.
    var panel: Path {
        polygon([(0, 0.04), (1, 0.04), (1, 0.98), (0, 0.98)])
    }

    /// A long upper band that steps down to a deeper block at the outer end.
    var body: Path {
        polygon([
            (0.30, 0.10), (0.94, 0.10), (0.94, 0.26), (0.42, 0.26),
            (0.34, 0.80), (0.04, 0.80), (0.04, 0.58), (0.20, 0.58)
        ])
    }

    var accent: Path {
        bar(0.20, 0.70, 0.89, 0.93)
    }

    /// Five short slanted ticks leading into the accent bar at the outer end.
    var ticks: Path {
        var path = Path()
        for index in 0..<5 {
            let x = 0.03 + CGFloat(index) * 0.032
            path.addPath(bar(x, x + 0.014, 0.88, 0.94))
        }
        return path
    }

    var pinstripes: Path {
        var path = bar(0.46, 0.92, 0.32, 0.34)
        path.addPath(bar(0.04, 0.26, 0.50, 0.52))
        path.addPath(bar(0.74, 0.90, 0.95, 0.965))
        return path
    }
}

/// A faded team logo in the empty corner under the RPM, above the chequers.
struct MotorsportTeamBadge: View {
    var body: some View {
        Image("MazdaSpiritRacing")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 140, alignment: .leading)
            .opacity(0.18)
            // Clear of the chequered band along the bottom edge.
            .padding(.bottom, Theme.Spacing.lg)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

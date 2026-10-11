import SwiftUI
import UIKit

/// A solid shape filled brighter than SDR white on displays with HDR
/// headroom. On other displays it falls back to the colour scaled into SDR,
/// since clipping each channel separately would shift its hue.
///
/// SwiftUI colours only gain HDR headroom from iOS 26, so this draws through
/// a Core Animation layer that opts into extended range, which iOS 17 allows.
/// Opacity and scale still come from SwiftUI, so it animates with its parent.
struct HDRFill<S: Shape>: UIViewRepresentable {
    /// Extended linear sRGB components; values above 1 exceed SDR white.
    var linearRed: CGFloat
    var linearGreen: CGFloat
    var linearBlue: CGFloat
    var shape: S

    func makeUIView(context: Context) -> HDRFillView {
        let view = HDRFillView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: HDRFillView, context: Context) {
        view.components = [linearRed, linearGreen, linearBlue]
        view.path = { shape.path(in: $0).cgPath }
    }
}

/// A linear gradient of one colour fading through the given opacities,
/// brighter than SDR white on displays with HDR headroom, like ``HDRFill``.
struct HDRGradient: UIViewRepresentable {
    /// Extended linear sRGB components; values above 1 exceed SDR white.
    var linearRed: CGFloat
    var linearGreen: CGFloat
    var linearBlue: CGFloat
    /// Opacity at each evenly spaced stop from `startPoint` to `endPoint`.
    var opacities: [CGFloat]
    var startPoint: UnitPoint
    var endPoint: UnitPoint

    func makeUIView(context: Context) -> HDRGradientView {
        let view = HDRGradientView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: HDRGradientView, context: Context) {
        view.gradientLayer.startPoint = CGPoint(x: startPoint.x, y: startPoint.y)
        view.gradientLayer.endPoint = CGPoint(x: endPoint.x, y: endPoint.y)
        view.opacities = opacities
        view.components = [linearRed, linearGreen, linearBlue]
    }
}

final class HDRFillView: UIView {
    private let shapeLayer = CAShapeLayer()

    var components: [CGFloat] = [0, 0, 0] {
        didSet { updateColor() }
    }

    var path: ((CGRect) -> CGPath)? {
        didSet { setNeedsLayout() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        shapeLayer.allowsExtendedDynamicRange()
        layer.addSublayer(shapeLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateColor()
    }

    private func updateColor() {
        shapeLayer.fillColor = extendedColor(components, opacity: 1, on: window)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        shapeLayer.frame = bounds
        shapeLayer.path = path?(bounds)
    }
}

final class HDRGradientView: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }
    var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

    var components: [CGFloat] = [0, 0, 0] {
        didSet { updateColors() }
    }

    var opacities: [CGFloat] = [1, 0]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        gradientLayer.allowsExtendedDynamicRange()
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateColors()
    }

    private func updateColors() {
        gradientLayer.colors = opacities.map { extendedColor(components, opacity: $0, on: window) }
    }
}

private extension CALayer {
    func allowsExtendedDynamicRange() {
        if #available(iOS 26.0, *) {
            preferredDynamicRange = .high
        } else {
            wantsExtendedDynamicRangeContent = true
        }
    }
}

/// The colour as given where the screen has HDR headroom; otherwise scaled
/// so its brightest channel is SDR white, keeping the hue.
private func extendedColor(_ components: [CGFloat], opacity: CGFloat, on window: UIWindow?) -> CGColor {
    let headroom = window?.screen.potentialEDRHeadroom ?? 1
    let brightest = components.max() ?? 1
    let scale = headroom > 1 || brightest <= 1 ? 1 : 1 / brightest
    return CGColor(
        colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
        components: components.map { $0 * scale } + [opacity]
    )!
}

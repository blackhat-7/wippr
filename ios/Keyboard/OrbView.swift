import UIKit

/// The keyboard's orb, after the watercolour voice orb in ask-ndtv: a pale blue body whose pigment
/// pools under three churning waterlines. It breathes at rest, swells and churns faster while recording,
/// and swirls while processing. Everything runs as Core Animation on the render server.
final class OrbView: UIView {
    var phase = KeyboardHandoff.Phase.off {
        didSet { if phase != oldValue { apply(animated: true) } }
    }

    private let scaler = CALayer()
    private let pulse = CALayer()
    private let glow = CALayer()
    private let body = CALayer()
    private let swirl = CALayer()
    private let water = CALayer()
    private let tide = CALayer()
    private let waves = (0..<3).map { _ in (fill: CAGradientLayer(), line: CAShapeLayer()) }
    private var side: CGFloat = 0

    /// Height of the waterline from the bottom, waves across the body, seconds per churn, pigment, alpha.
    private static let waterlines: [(height: CGFloat, cycles: CGFloat, seconds: Double, color: UInt32, alpha: CGFloat)] = [
        (0.28, 1.1, 10, 0x0B84F5, 0.72),
        (0.45, 1.8, 8, 0xA6EDFF, 0.5),
        (0.66, 2.7, 6, 0xFDFCEF, 0.45),
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        let pigment = color(0x0B84F5).cgColor
        glow.backgroundColor = pigment
        glow.shadowColor = pigment
        glow.shadowOffset = .zero
        glow.shadowRadius = 3.5
        glow.shadowOpacity = 1
        body.backgroundColor = color(0xDCF5FF).cgColor
        body.masksToBounds = true
        for ((fill, line), spec) in zip(waves, Self.waterlines) {
            fill.colors = [color(spec.color, spec.alpha * 0.8).cgColor, color(spec.color, spec.alpha).cgColor]
            fill.compositingFilter = "multiplyBlendMode"
            fill.mask = line
            tide.addSublayer(fill)
        }
        water.addSublayer(tide)
        swirl.addSublayer(water)
        body.addSublayer(swirl)
        pulse.addSublayer(glow)
        pulse.addSublayer(body)
        scaler.addSublayer(pulse)
        layer.addSublayer(scaler)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: 30, height: 30) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s = min(bounds.width, bounds.height)
        guard s > 0, s != side else { return }
        side = s
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let square = CGRect(x: 0, y: 0, width: s, height: s)
        place(scaler, CGRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s))
        for layer in [pulse, glow, body, swirl, water] { place(layer, square) }
        glow.cornerRadius = s / 2
        glow.shadowPath = UIBezierPath(ovalIn: square).cgPath
        body.cornerRadius = s / 2
        // Twice the body, so the water still covers it when it swirls or rises.
        place(tide, square.insetBy(dx: -s / 2, dy: -s / 2))
        for ((fill, line), spec) in zip(waves, Self.waterlines) {
            place(fill, tide.bounds)
            line.frame = tide.bounds
            fill.startPoint = CGPoint(x: 0.5, y: 0.15 + (1 - spec.height) / 2)
            fill.endPoint = CGPoint(x: 0.5, y: 0.75)
        }
        CATransaction.commit()
        resume()
    }

    /// Re-adds every animation. Core Animation drops them while the keyboard is hidden.
    func resume() {
        guard side > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [scaler, pulse, glow, swirl, water] { layer.removeAllAnimations() }
        for ((_, line), spec) in zip(waves, Self.waterlines) {
            let frames = paths(height: spec.height, cycles: spec.cycles)
            let churn = CAKeyframeAnimation(keyPath: "path")
            churn.values = frames
            churn.duration = spec.seconds
            churn.repeatCount = .infinity
            churn.isRemovedOnCompletion = false
            line.path = frames[0]
            line.add(churn, forKey: "churn")
        }
        apply(animated: false)
        CATransaction.commit()
    }

    /// A quick swell and glow, for text arriving.
    func flash() {
        let swell = CAKeyframeAnimation(keyPath: "transform.scale")
        swell.values = [0, 0.18, 0]
        let shine = CAKeyframeAnimation(keyPath: "opacity")
        shine.values = [0, 0.8, 0]
        for (layer, animation) in [(pulse, swell), (glow, shine)] {
            animation.isAdditive = true
            animation.duration = 0.45
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "flash")
        }
    }

    /// A small no.
    func shake() {
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -4, 4, -3, 3, -1.5, 0]
        shake.duration = 0.4
        shake.isAdditive = true
        scaler.add(shake, forKey: "shake")
    }

    private func apply(animated: Bool) {
        guard side > 0 else { return }
        let (scale, opacity, glowing, level, tempo): (CGFloat, CGFloat, CGFloat, CGFloat, Float) = switch phase {
        case .off: (0.62, 0.45, 0, 0.04, 0.5)
        case .ready: (0.74, 1, 0.3, 0, 1)
        case .recording: (1.15, 1, 0.9, -0.12, 3.2)
        case .processing: (0.88, 1, 0.55, -0.04, 2)
        }
        let growing = scale > scaler.value(forKeyPath: "transform.scale") as? CGFloat ?? 1
        move(scaler, "transform.scale", to: scale, animated: animated, spring: growing)
        move(scaler, "opacity", to: opacity, animated: animated)
        move(glow, "opacity", to: glowing, animated: animated)
        move(water, "transform.translation.y", to: level * side, animated: animated, spring: true)
        setSpeed(tide, tempo)
        breathe(animated: animated)
        spin(phase == .processing, animated: animated)
    }

    /// Sets a value and, when animated, eases there from wherever it is on screen.
    /// Growing uses the source's damped spring (1 − e^−5.5t·cos 9t); shrinking is a plain 0.4 s ease.
    private func move(_ layer: CALayer, _ keyPath: String, to value: CGFloat, animated: Bool, spring: Bool = false) {
        let from = (layer.presentation() ?? layer).value(forKeyPath: keyPath)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: keyPath)
        CATransaction.commit()
        guard animated else { return }
        let animation: CABasicAnimation
        if spring {
            let bounce = CASpringAnimation(keyPath: keyPath)
            bounce.stiffness = 111
            bounce.damping = 11
            bounce.duration = bounce.settlingDuration
            animation = bounce
        } else {
            animation = CABasicAnimation(keyPath: keyPath)
            animation.duration = 0.4
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        animation.fromValue = from
        animation.toValue = value
        layer.add(animation, forKey: keyPath)
    }

    /// Changes how fast a layer's animations play without jumping them to a different frame.
    private func setSpeed(_ layer: CALayer, _ speed: Float) {
        guard layer.speed != speed else { return }
        let now = CACurrentMediaTime()
        let local = layer.convertTime(now, from: nil)
        layer.beginTime = layer.superlayer?.convertTime(now, from: nil) ?? now
        layer.timeOffset = local
        layer.speed = speed
    }

    /// Slow breathing at rest, an uneven speech-like pulse while recording. The old pulse settles out
    /// additively instead of snapping back to 1.
    private func breathe(animated: Bool) {
        let keyPath = "transform.scale"
        if animated, let now = pulse.presentation()?.value(forKeyPath: keyPath) as? CGFloat {
            let settle = CABasicAnimation(keyPath: keyPath)
            settle.isAdditive = true
            settle.fromValue = now - 1
            settle.toValue = 0
            settle.duration = 0.5
            settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
            pulse.add(settle, forKey: "settle")
        }
        let breath: CAPropertyAnimation
        if phase == .recording {
            let chatter = CAKeyframeAnimation(keyPath: keyPath)
            chatter.values = [0, 0.07, 0.03, 0.09, 0.02, 0.06, 0.04, 0.08, 0]
            chatter.calculationMode = .cubic
            chatter.duration = 1.8
            breath = chatter
        } else {
            let calm = CABasicAnimation(keyPath: keyPath)
            calm.fromValue = 0
            calm.toValue = phase == .processing ? 0.03 : 0.04
            calm.duration = (phase == .off ? 7 : phase == .processing ? 3.2 : 5) / 2
            calm.autoreverses = true
            calm.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breath = calm
        }
        breath.isAdditive = true
        breath.repeatCount = .infinity
        breath.isRemovedOnCompletion = false
        pulse.add(breath, forKey: "breath")
    }

    /// Processing swirls the water around: it winds up into a steady turn and, after, runs on to the
    /// next full turn and stops, so the pigment settles back at the bottom.
    private func spin(_ on: Bool, animated: Bool) {
        let keyPath = "transform.rotation.z"
        let turn: CGFloat = 2 * .pi
        let seconds = 2.0
        var angle = swirl.presentation()?.value(forKeyPath: keyPath) as? CGFloat ?? 0
        if angle < 0 { angle += turn }
        let left = Double((turn - angle) / turn)
        swirl.removeAllAnimations()
        var start = CACurrentMediaTime()
        if on {
            if animated {
                // Ease-in ends at 1.72× its average speed, which here meets the steady turn.
                let windUp = CABasicAnimation(keyPath: keyPath)
                windUp.fromValue = angle
                windUp.toValue = turn
                windUp.duration = max(0.3, 1.72 * seconds * left)
                windUp.timingFunction = CAMediaTimingFunction(name: .easeIn)
                swirl.add(windUp, forKey: "windUp")
                start += windUp.duration
            }
            let steady = CABasicAnimation(keyPath: keyPath)
            steady.fromValue = 0
            steady.toValue = turn
            steady.duration = seconds
            steady.beginTime = start
            steady.repeatCount = .infinity
            steady.isRemovedOnCompletion = false
            swirl.add(steady, forKey: "spin")
        } else if animated, angle > 0.01, angle < turn - 0.01 {
            let windDown = CABasicAnimation(keyPath: keyPath)
            windDown.fromValue = angle
            windDown.toValue = turn
            windDown.duration = max(0.2, 1.72 * seconds * left)
            windDown.timingFunction = CAMediaTimingFunction(name: .easeOut)
            swirl.add(windDown, forKey: "windDown")
        }
    }

    /// One churn cycle of a waterline: two sine waves travelling against each other, so the line
    /// churns in place instead of scrolling. Filled down to the bottom of the tide layer.
    private func paths(height: CGFloat, cycles: CGFloat) -> [CGPath] {
        let s = side, size = 2 * side, frames = 12, points = 24
        return (0...frames).map { frame in
            let t = CGFloat(frame % frames) / CGFloat(frames) * 2 * .pi
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: size))
            var previous: CGPoint?
            for i in 0...points {
                let x = size * CGFloat(i) / CGFloat(points)
                let u = x / s * cycles * 2 * .pi
                let wobble = 0.6 * sin(u + t) + 0.4 * sin(1.7 * u - 2 * t + 1.3)
                let point = CGPoint(x: x, y: s / 2 + (1 - height) * s + wobble * 0.1 * s)
                if let previous {
                    path.addQuadCurve(to: CGPoint(x: (previous.x + x) / 2, y: (previous.y + point.y) / 2), controlPoint: previous)
                } else {
                    path.addLine(to: point)
                }
                previous = point
            }
            path.addLine(to: previous!)
            path.addLine(to: CGPoint(x: size, y: size))
            path.close()
            return path.cgPath
        }
    }

    private func place(_ layer: CALayer, _ frame: CGRect) {
        layer.bounds = CGRect(origin: .zero, size: frame.size)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
    }

    private func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

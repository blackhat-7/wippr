import MetalKit
import UIKit

/// The keyboard's orb: ask-ndtv's watercolour voice orb (`orb.frag.glsl`), ported to Metal in `Orb.metal`
/// and drawn into a small `MTKView`. At rest it is a pulsing dot of the vivid pigment; recording springs it
/// open into a pale blue body whose pigment pools under three churning waterlines that rise with the voice;
/// processing keeps it open and churns the water 1.6× faster. The shader does the choreography from state
/// flip timestamps (spring 1 − e^−5.5t·cos 9t in, 0.4 s linear out); this view only flips flags, smooths the
/// mic level exactly as ask-ndtv's `useShaderOrb` does, and breathes the whole orb (5 s, 7 s at rest).
final class OrbView: UIView {
    var phase = KeyboardHandoff.Phase.off {
        didSet { if phase != oldValue { renderer?.setPhase(phase) } }
    }

    private let canvas = MTKView()
    private let renderer: OrbRenderer?
    /// Set by `pauseRendering()`, cleared by `resume()`; rendering also stops while out of a window.
    private var suspended = false

    /// The drawing is larger than the orb's layout box: the open body fills ~66–75 % of the canvas, as in
    /// the source, so the open body spans ~88–100 % of the orb's box (the box is as tall as the keyboard's button).
    private static let canvasRatio: CGFloat = 4 / 3

    override init(frame: CGRect) {
        renderer = OrbRenderer.make()
        super.init(frame: frame)
        isUserInteractionEnabled = false
        canvas.isUserInteractionEnabled = false
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.layer.isOpaque = false
        canvas.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        canvas.colorPixelFormat = .bgra8Unorm
        canvas.enableSetNeedsDisplay = false
        canvas.isPaused = true
        // The glow `flash()` shows; free while its opacity is 0.
        canvas.layer.shadowColor = UIColor(red: 0x0B / 255, green: 0x84 / 255, blue: 0xF5 / 255, alpha: 1).cgColor
        canvas.layer.shadowOffset = .zero
        canvas.layer.shadowRadius = 3.5
        canvas.layer.shadowOpacity = 0
        if let renderer {
            canvas.device = renderer.device
            canvas.delegate = renderer
            renderer.setPhase(phase)
            renderer.apply(to: canvas)
            addSubview(canvas)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: 30, height: 30) }

    override func layoutSubviews() {
        super.layoutSubviews()
        // bounds/center rather than frame: `flash()` and `shake()` transform the canvas.
        let side = min(bounds.width, bounds.height) * Self.canvasRatio
        canvas.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        canvas.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updatePaused()
    }

    /// Starts rendering again after `pauseRendering()` (call when the keyboard appears). Re-bases the
    /// shader clock so float time stays small however long the keyboard process lives.
    func resume() {
        suspended = false
        renderer?.rebase()
        updatePaused()
    }

    /// Stops the render loop (call when the keyboard disappears); the last frame stays on screen.
    func pauseRendering() {
        suspended = true
        updatePaused()
    }

    /// A quick swell and glow, for text arriving.
    func flash() {
        let swell = CAKeyframeAnimation(keyPath: "transform.scale")
        swell.values = [0, 0.18, 0]
        swell.isAdditive = true
        let shine = CAKeyframeAnimation(keyPath: "shadowOpacity")
        shine.values = [0, 0.8, 0]
        for animation in [swell, shine] {
            animation.duration = 0.45
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            canvas.layer.add(animation, forKey: animation.keyPath)
        }
    }

    /// A small no.
    func shake() {
        let shake = CAKeyframeAnimation(keyPath: "transform.translation.x")
        shake.values = [0, -4, 4, -3, 3, -1.5, 0]
        shake.duration = 0.4
        shake.isAdditive = true
        canvas.layer.add(shake, forKey: "shake")
    }

    private func updatePaused() {
        let paused = suspended || window == nil || renderer == nil
        guard canvas.isPaused != paused else { return }
        canvas.isPaused = paused
    }
}

/// Drives `Orb.metal`: the uniforms of ask-ndtv's `useShaderOrb` + `orbShader`, one draw call per frame.
private final class OrbRenderer: NSObject, MTKViewDelegate {
    /// Mirrors `OrbUniforms` in Orb.metal.
    private struct Uniforms {
        var bands = SIMD4<Float>.zero
        var cumulative = SIMD4<Float>.zero
        /// Listen / think / speak / captured flags. The keyboard only ever uses the first two.
        var stateOn = SIMD4<Float>.zero
        var stateChangedAt = SIMD4<Float>(repeating: -10)
        var colorBase = OrbRenderer.rgb(0xDCF5FF)
        var colorLow = OrbRenderer.rgb(0x0B84F5)
        var colorMid = OrbRenderer.rgb(0xA6EDFF)
        var colorHigh = OrbRenderer.rgb(0xFDFCEF)
        var size = SIMD2<Float>(1, 1)
        var time: Float = 0
        var level: Float = 0
        var alpha: Float = 1
        var dotRadius: Float = OrbRenderer.dotRadius
        var scale: Float = 1
        var unused: Float = 0
    }

    /// Shared across keyboard instances: the GPU objects and grain are built once per process.
    private struct Resources {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipeline: MTLRenderPipelineState
        let grain: MTLTexture
    }

    private static let resources: Resources? = {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary() else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "orbVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "orbFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor),
              let grain = makeGrain(device) else { return nil }
        return Resources(device: device, queue: queue, pipeline: pipeline, grain: grain)
    }()

    /// The source's resting dot is 0.17 of the canvas, a 7 pt speck here; this reads at keyboard size.
    private static let dotRadius: Float = 0.3
    /// Envelope smoothing per 60 Hz frame (useShaderOrb): quick to answer a syllable, unhurried letting go.
    private static let attack: Float = 0.4
    private static let release: Float = 0.06
    /// How fast the cumulative phase advances at full band energy.
    private static let cumulativeRate: Float = 0.9
    /// The analyser's own smoothing of the level before useShaderOrb sees it (useAnalyserLevel).
    private static let levelSmoothing: Float = 0.25
    private static let maxFrame = 1.0 / 30
    /// The app writes the level ~20×/s; reading the file faster buys nothing.
    private static let pollInterval = 1.0 / 30

    let device: MTLDevice
    private let resources: Resources
    private var uniforms = Uniforms()
    private var phase = KeyboardHandoff.Phase.off
    private var start = CACurrentMediaTime()
    private var last = CACurrentMediaTime()
    private var changedAt = -Double.infinity
    private var lastPoll = -Double.infinity
    private var rawLevel: Float = 0
    private var envelope: Float = 0
    private var breath: Double = 0
    private var alphaFrom: Float = 1
    private var alphaTo: Float = 1

    /// nil without Metal (never on a supported iPhone); the orb then stays blank.
    static func make() -> OrbRenderer? { resources.map(OrbRenderer.init) }

    private init(_ resources: Resources) {
        self.resources = resources
        device = resources.device
        super.init()
    }

    /// Flips the state flags; the shader springs from the timestamps.
    func setPhase(_ phase: KeyboardHandoff.Phase) {
        let now = CACurrentMediaTime()
        let time = Float(now - start)
        let targets = SIMD4<Float>(phase == .recording ? 1 : 0, phase == .processing ? 1 : 0, 0, 0)
        for i in 0..<4 where targets[i] != uniforms.stateOn[i] {
            uniforms.stateOn[i] = targets[i]
            uniforms.stateChangedAt[i] = time
        }
        alphaFrom = currentAlpha(now)
        alphaTo = Self.alpha(phase)
        self.phase = phase
        changedAt = now
    }

    /// Moves the clock's zero to now, keeping every in-flight transition where it is.
    func rebase() {
        let now = CACurrentMediaTime()
        let shift = Float(now - start)
        start = now
        last = now
        for i in 0..<4 { uniforms.stateChangedAt[i] = max(uniforms.stateChangedAt[i] - shift, -10) }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let elapsed = now - last
        let dt = Float(min(elapsed, Self.maxFrame))
        last = now
        let frames = dt * 60

        if phase == .recording {
            if now - lastPoll >= Self.pollInterval {
                lastPoll = now
                rawLevel = min(max(KeyboardHandoff.level(), 0), 1)
            }
        } else {
            rawLevel = 0
        }
        // useAnalyserLevel's smoothing, then useShaderOrb's attack/release envelope and its integral. The
        // keyboard only has one level, so all four bands carry it (as readSignals does without bands).
        uniforms.level += (rawLevel - uniforms.level) * (1 - pow(1 - Self.levelSmoothing, frames))
        let rate = uniforms.level > envelope ? Self.attack : Self.release
        envelope += (uniforms.level - envelope) * (1 - pow(1 - rate, frames))
        uniforms.bands = SIMD4(repeating: envelope)
        uniforms.cumulative += SIMD4(repeating: envelope * dt * Self.cumulativeRate)

        // The whole-orb CSS breathing, scale 1 → 1.04 and back; the period follows the phase without a jump.
        breath += elapsed / Self.breathPeriod(phase)
        breath -= breath.rounded(.down)
        uniforms.scale = Float(1 + 0.04 * (0.5 - 0.5 * cos(2 * .pi * breath)))

        uniforms.time = Float(now - start)
        uniforms.alpha = currentAlpha(now)
        uniforms.size = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        apply(to: view)

        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = resources.queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(resources.pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentTexture(resources.grain, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    /// Full rate while the body is open or moving; the idle dot pulses fine at 30, and dimmed at 20.
    func apply(to view: MTKView) {
        let settling = CACurrentMediaTime() - changedAt < 1.5
        let fps = switch phase {
        case .recording, .processing: 60
        case _ where settling: 60
        case .ready: 30
        case .off: 20
        }
        if view.preferredFramesPerSecond != fps { view.preferredFramesPerSecond = fps }
    }

    /// The source's resting orb sits at 0.82 opacity; off (mic unavailable) dims it further.
    private static func alpha(_ phase: KeyboardHandoff.Phase) -> Float {
        switch phase {
        case .off: 0.4
        case .ready: 0.82
        case .recording, .processing: 1
        }
    }

    /// Seconds per breath: 5 s by default, 3.2 s while thinking, 7 s at rest.
    private static func breathPeriod(_ phase: KeyboardHandoff.Phase) -> Double {
        switch phase {
        case .off, .ready: 7
        case .recording: 5
        case .processing: 3.2
        }
    }

    /// The CSS `transition: opacity 0.3s` (ease), from wherever the fade was.
    private func currentAlpha(_ now: CFTimeInterval) -> Float {
        let t = Float(min(max((now - changedAt) / 0.3, 0), 1))
        return alphaFrom + (alphaTo - alphaFrom) * t * t * (3 - 2 * t)
    }

    private static func rgb(_ hex: UInt32) -> SIMD4<Float> {
        SIMD4(Float(hex >> 16 & 0xFF) / 255, Float(hex >> 8 & 0xFF) / 255, Float(hex & 0xFF) / 255, 1)
    }

    /// The prebaked grain (useShaderOrb's makeNoiseTexture): 32×32 white noise upscaled 8× bilinear, plus
    /// 40 % of one quadrant upscaled 16×, all blurred with a 3 px Gaussian into broad soft blobs. Two
    /// decorrelated channels (r, g). Wraps at the edges so it tiles under the shader's repeat sampler.
    private static func makeGrain(_ device: MTLDevice) -> MTLTexture? {
        let small = 32, size = 256
        var generator = SystemRandomNumberGenerator()
        let seed = (0..<2).map { _ in (0..<small * small).map { _ in Float.random(in: 0...1, using: &generator) } }

        func bilinear(_ channel: [Float], _ x: Float, _ y: Float) -> Float {
            let fx = x.rounded(.down), fy = y.rounded(.down)
            let tx = x - fx, ty = y - fy
            func at(_ i: Int, _ j: Int) -> Float { channel[((j % small + small) % small) * small + (i % small + small) % small] }
            let i = Int(fx), j = Int(fy)
            let top = at(i, j) + (at(i + 1, j) - at(i, j)) * tx
            let bottom = at(i, j + 1) + (at(i + 1, j + 1) - at(i, j + 1)) * tx
            return top + (bottom - top) * ty
        }

        let sigma: Float = 3, radius = 9
        let kernel: [Float] = {
            let raw = (-radius...radius).map { exp(-Float($0 * $0) / (2 * sigma * sigma)) }
            let sum = raw.reduce(0, +)
            return raw.map { $0 / sum }
        }()

        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for (c, channel) in seed.enumerated() {
            var image = [Float](repeating: 0, count: size * size)
            for y in 0..<size {
                for x in 0..<size {
                    let a = bilinear(channel, (Float(x) + 0.5) / 8 - 0.5, (Float(y) + 0.5) / 8 - 0.5)
                    let b = bilinear(channel, (Float(x + size) + 0.5) / 16 - 0.5, (Float(y + size) + 0.5) / 16 - 0.5)
                    image[y * size + x] = a * 0.6 + b * 0.4
                }
            }
            var pass = [Float](repeating: 0, count: size * size)
            for y in 0..<size {
                for x in 0..<size {
                    var sum: Float = 0
                    for k in -radius...radius { sum += image[y * size + (x + k + size) % size] * kernel[k + radius] }
                    pass[y * size + x] = sum
                }
            }
            for y in 0..<size {
                for x in 0..<size {
                    var sum: Float = 0
                    for k in -radius...radius { sum += pass[((y + k + size) % size) * size + x] * kernel[k + radius] }
                    pixels[(y * size + x) * 4 + c] = UInt8(min(max(sum * 255, 0), 255).rounded())
                }
            }
        }
        for i in stride(from: 2, to: pixels.count, by: 4) { pixels[i] = 0 }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: pixels, bytesPerRow: size * 4)
        return texture
    }
}

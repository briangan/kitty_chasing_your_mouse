// KittyChasingYourMouse.swift
// A tiny animated 2D kitty that lives on top of your desktop and chases the mouse pointer.
//
//  - Runs after the pointer while it is moving and catches it.
//  - On catch: bites the pointer, holds it in its mouth for 3 seconds, then fades away.
//  - If the pointer is idle for 60s+, the kitty curls up and naps next to it.
//  - The kitty comes back a few seconds after it vanishes.
//
// Art style: white kitty, peach patches, big round eyes, soft blue-grey shading, dark plum outline.
// Everything is drawn in code, in "cat units" (origin = between the kitty's feet, 1 unit ≈ 1.25 px).
//
// Build:  ./build.sh      (needs Xcode command line tools)

import Cocoa

// MARK: - Palette & geometry

private let ink      = NSColor(srgbRed: 0.255, green: 0.200, blue: 0.247, alpha: 1)   // outline / eyes
private let snow     = NSColor(srgbRed: 1.000, green: 1.000, blue: 1.000, alpha: 1)
private let peach    = NSColor(srgbRed: 0.992, green: 0.788, blue: 0.722, alpha: 1)
private let peachMid = NSColor(srgbRed: 0.976, green: 0.749, blue: 0.702, alpha: 1)
private let peachDk  = NSColor(srgbRed: 0.878, green: 0.616, blue: 0.565, alpha: 1)
private let shade    = NSColor(srgbRed: 0.780, green: 0.816, blue: 0.827, alpha: 1)   // blue-grey shadow
private let noseCol  = NSColor(srgbRed: 0.957, green: 0.714, blue: 0.741, alpha: 1)
private let mouthCol = NSColor(srgbRed: 0.260, green: 0.070, blue: 0.100, alpha: 1)

/// One "cat unit" is this many screen points.
private let unitScale: CGFloat = 1.25
/// Size of the transparent, click-through window that carries the kitty sprite.
private let spriteSize = CGSize(width: 170, height: 140)
/// The kitty's position is the point between its feet; this is where that sits inside the sprite.
private let feetAnchor = CGPoint(x: 85, y: 14)
/// Where the mouth is, relative to the feet, when the kitty faces right (screen points).
/// Run/hold pose: head centre is at unit (18, 27); the mouth is 9.2 units below it.
private let mouthRel = CGPoint(x: 18 * unitScale, y: 17.8 * unitScale)

private let lineW: CGFloat = 1.7

// MARK: - Drawing helpers

private enum Eyes { case open, sleepy, happy }

@inline(__always) private func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

private func inkStroke(_ p: NSBezierPath, _ w: CGFloat = lineW) {
    p.lineWidth = w
    p.lineCapStyle = .round
    p.lineJoinStyle = .round
    ink.setStroke()
    p.stroke()
}

private func line(_ a: CGPoint, _ b: CGPoint, width: CGFloat, color: NSColor) {
    let p = NSBezierPath()
    p.move(to: a)
    p.line(to: b)
    p.lineWidth = width
    p.lineCapStyle = .round
    color.setStroke()
    p.stroke()
}

private func blob(_ ctx: CGContext, _ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat,
                  angle: CGFloat = 0, fill: NSColor, stroke: Bool = true, width: CGFloat = lineW) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angle)
    let p = NSBezierPath(ovalIn: NSRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
    fill.setFill()
    p.fill()
    if stroke { inkStroke(p, width) }
    ctx.restoreGState()
}

/// Runs `body` with drawing clipped to `path`.
private func clipped(_ ctx: CGContext, to path: NSBezierPath, _ body: () -> Void) {
    ctx.saveGState()
    path.addClip()
    body()
    ctx.restoreGState()
}

/// Thick limb with outline (used for the stubby legs).
private func stub(_ a: CGPoint, _ b: CGPoint, width: CGFloat, color: NSColor) {
    line(a, b, width: width + lineW * 2, color: ink)
    line(a, b, width: width, color: color)
}

// A cubic Bézier, used for striped tails.
private struct Cubic {
    let a, b, c, d: CGPoint
    func at(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u*u*u*a.x + 3*u*u*t*b.x + 3*u*t*t*c.x + t*t*t*d.x,
                       y: u*u*u*a.y + 3*u*u*t*b.y + 3*u*t*t*c.y + t*t*t*d.y)
    }
    func normal(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let dx = 3*u*u*(b.x-a.x) + 6*u*t*(c.x-b.x) + 3*t*t*(d.x-c.x)
        let dy = 3*u*u*(b.y-a.y) + 6*u*t*(c.y-b.y) + 3*t*t*(d.y-c.y)
        let l = max(0.0001, hypot(dx, dy))
        return CGPoint(x: -dy / l, y: dx / l)
    }
}

/// Peach tail with white bands and a darker base, like the reference icon.
private func drawStripedTail(_ ctx: CGContext, _ cu: Cubic, width w: CGFloat) {
    let path = NSBezierPath()
    path.move(to: cu.a)
    path.curve(to: cu.d, controlPoint1: cu.b, controlPoint2: cu.c)
    path.lineCapStyle = .round
    path.lineWidth = w + lineW * 2
    ink.setStroke()
    path.stroke()
    path.lineWidth = w
    peach.setStroke()
    path.stroke()

    ctx.saveGState()
    let cg = CGMutablePath()
    cg.move(to: cu.a)
    cg.addCurve(to: cu.d, control1: cu.b, control2: cu.c)
    ctx.addPath(cg)
    ctx.setLineWidth(w)
    ctx.setLineCap(.round)
    ctx.replacePathWithStrokedPath()
    ctx.clip()

    // darker base
    let base = NSBezierPath()
    base.move(to: cu.at(0))
    for i in 1...10 { base.line(to: cu.at(0.30 * CGFloat(i) / 10)) }
    base.lineWidth = w + 2
    base.lineCapStyle = .butt
    peachDk.setStroke()
    base.stroke()

    // white bands
    for t: CGFloat in [0.50, 0.72] {
        let p = cu.at(t), n = cu.normal(t)
        line(P(p.x - n.x * w, p.y - n.y * w), P(p.x + n.x * w, p.y + n.y * w), width: 1.9, color: snow)
    }
    ctx.restoreGState()
}

/// The kawaii head. Centre of the head is `c`; the mouth is 9.2 units below it, and
/// when `pointer` is true the captured mouse pointer's tip sits exactly there.
private func drawHead(_ ctx: CGContext, at c: CGPoint, tilt: CGFloat, eyes: Eyes,
                      mouthOpen: CGFloat, pointer: Bool, fangs: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: tilt)

    // Silhouette: head + ears in one outline. `outlinePath` stays open at the chin so the
    // neck shadow flows into the body without a line, exactly like the reference.
    let shape = NSBezierPath()
    shape.move(to: P(-17.6, -12.5))
    shape.curve(to: P(-21.9, -4.5), controlPoint1: P(-19.8, -11), controlPoint2: P(-21.8, -8))
    shape.curve(to: P(-19.5, 5.7),  controlPoint1: P(-22.0, -1),  controlPoint2: P(-21.0, 2.5))
    shape.curve(to: P(-17.7, 21.8), controlPoint1: P(-18.6, 9),   controlPoint2: P(-19.5, 17))
    shape.curve(to: P(-7.2, 15.9),  controlPoint1: P(-15, 21),    controlPoint2: P(-11, 18.5))
    shape.curve(to: P(0, 17.5),     controlPoint1: P(-5, 16.9),   controlPoint2: P(-2.4, 17.5))
    shape.curve(to: P(7.2, 15.9),   controlPoint1: P(2.4, 17.5),  controlPoint2: P(5, 16.9))
    shape.curve(to: P(17.5, 21.8),  controlPoint1: P(11, 18.5),   controlPoint2: P(15, 21))
    shape.curve(to: P(19.5, 5.7),   controlPoint1: P(19.5, 17),   controlPoint2: P(18.6, 9))
    shape.curve(to: P(21.9, -4.5),  controlPoint1: P(21.0, 2.5),  controlPoint2: P(22.0, -1))
    shape.curve(to: P(17.6, -12.5), controlPoint1: P(21.8, -8),   controlPoint2: P(19.8, -11))
    let outlinePath = shape.copy() as! NSBezierPath
    shape.curve(to: P(0, -17.8),    controlPoint1: P(16, -15.5),  controlPoint2: P(8, -17.8))
    shape.curve(to: P(-17.6, -12.5), controlPoint1: P(-8, -17.8), controlPoint2: P(-16, -15.5))
    shape.close()

    snow.setFill()
    shape.fill()

    clipped(ctx, to: shape) {
        // big peach patch on one side of the face
        let patch = NSBezierPath()
        patch.move(to: P(0.2, 19))
        patch.line(to: P(0.2, 17.2))
        patch.curve(to: P(-1.6, 9.7), controlPoint1: P(-2.6, 14),  controlPoint2: P(-2.4, 12))
        patch.curve(to: P(-0.9, 5),   controlPoint1: P(-1.2, 8),   controlPoint2: P(-1.2, 6.5))
        patch.curve(to: P(4.5, -0.7), controlPoint1: P(0.5, 2.5),  controlPoint2: P(2.5, 0.5))
        patch.curve(to: P(13.4, -2.9), controlPoint1: P(7, -2.2),  controlPoint2: P(10.5, -2.2))
        patch.curve(to: P(19, -7),    controlPoint1: P(16, -3.5),  controlPoint2: P(18, -5.5))
        patch.line(to: P(26, -7))
        patch.line(to: P(26, 19))
        patch.close()
        peach.setFill()
        patch.fill()

        // glossy white streak + shine in the patch
        let streak = NSBezierPath()
        streak.move(to: P(1.9, 16.2))
        streak.curve(to: P(5.6, 5.6), controlPoint1: P(0.5, 11), controlPoint2: P(2.4, 7.6))
        streak.lineWidth = 1.7
        streak.lineCapStyle = .round
        snow.setStroke()
        streak.stroke()
        blob(ctx, P(12.9, 2.8), 1.3, 0.7, fill: snow, stroke: false)

        // small peach mark on the other cheek/forehead
        blob(ctx, P(-14.9, 1.3), 1.8, 0.8, angle: 0.25, fill: peach, stroke: false)

        // soft shadow along the chin
        let chin = NSBezierPath()
        chin.move(to: P(-24, -8.5))
        chin.curve(to: P(24, -8.5), controlPoint1: P(-12, -17.5), controlPoint2: P(12, -17.5))
        chin.line(to: P(24, -24))
        chin.line(to: P(-24, -24))
        chin.close()
        shade.setFill()
        chin.fill()
    }

    inkStroke(outlinePath)

    // Inner ears
    for s: CGFloat in [-1, 1] {
        let inner = NSBezierPath()
        inner.move(to: P(s * 16.4, 18.9))
        inner.curve(to: P(s * 13.0, 12.9), controlPoint1: P(s * 14.8, 17), controlPoint2: P(s * 13.6, 14.5))
        inner.curve(to: P(s * 17.9, 8.0),  controlPoint1: P(s * 15.5, 11.2), controlPoint2: P(s * 17, 9.5))
        inner.curve(to: P(s * 16.4, 18.9), controlPoint1: P(s * 18.6, 12), controlPoint2: P(s * 18, 16))
        inner.close()
        (s < 0 ? peachMid : peachDk).setFill()
        inner.fill()
        inkStroke(inner, 0.9)
    }

    // Eyes
    for ex: CGFloat in [-10.8, 10.8] {
        let ey: CGFloat = -4
        switch eyes {
        case .open:
            blob(ctx, P(ex, ey), 3.7, 3.7, fill: ink, stroke: false)
            blob(ctx, P(ex + 1.2, ey + 1.5), 1.0, 1.3, fill: snow, stroke: false)
            blob(ctx, P(ex - 1.5, ey - 1.4), 0.6, 0.8, fill: snow, stroke: false)
        case .sleepy, .happy:
            let bend: CGFloat = (eyes == .happy) ? 3.2 : -3.2        // ∩ happy, ∪ sleepy
            let p = NSBezierPath()
            p.move(to: P(ex - 3.6, ey - 0.8))
            p.curve(to: P(ex + 3.6, ey - 0.8),
                    controlPoint1: P(ex - 2.2, ey - 0.8 + bend * 1.3),
                    controlPoint2: P(ex + 2.2, ey - 0.8 + bend * 1.3))
            inkStroke(p, 1.6)
        }
    }

    // Nose
    let nose = NSBezierPath()
    nose.move(to: P(-2.0, -4.7))
    nose.line(to: P(2.0, -4.7))
    nose.line(to: P(0, -6.9))
    nose.close()
    noseCol.setFill()
    nose.fill()
    inkStroke(nose, 1.2)

    // Mouth
    if mouthOpen > 0.05 {
        let ry = 0.8 + 3.6 * mouthOpen
        let cy: CGFloat = -9.6
        let m = NSBezierPath(ovalIn: NSRect(x: -3.3, y: cy - ry, width: 6.6, height: ry * 2))
        mouthCol.setFill()
        m.fill()
        clipped(ctx, to: m) {
            blob(ctx, P(0, cy - ry), 2.6, ry * 0.7, fill: noseCol, stroke: false)
        }
        inkStroke(m, 1.2)
        line(P(0, -6.9), P(0, cy + ry), width: 1.2, color: ink)
        if fangs {
            for fx: CGFloat in [-2.6, 1.0] {
                let f = NSBezierPath()
                let top = cy + ry - 0.2
                f.move(to: P(fx, top))
                f.line(to: P(fx + 1.6, top))
                f.line(to: P(fx + 0.8, top - 2.4))
                f.close()
                snow.setFill()
                f.fill()
            }
        }
    } else {
        let m = NSBezierPath()
        m.move(to: P(0, -6.9)); m.line(to: P(0, -9.1))
        m.move(to: P(-4.1, -8.4))
        m.curve(to: P(0, -9.1), controlPoint1: P(-4.1, -11.4), controlPoint2: P(-0.2, -11.4))
        m.move(to: P(4.1, -8.4))
        m.curve(to: P(0, -9.1), controlPoint1: P(4.1, -11.4), controlPoint2: P(0.2, -11.4))
        inkStroke(m, 1.4)
    }

    // Whiskers (they cross the face edge, like the reference)
    for s: CGFloat in [-1, 1] {
        line(P(s * 14.1, -5.0), P(s * 28.8, -5.0), width: 1.5, color: ink)
        line(P(s * 14.1, -7.7), P(s * 26.8, -7.7), width: 1.5, color: ink)
    }

    // Captured mouse pointer, tip exactly at the mouth
    if pointer {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: -9.2)
        let a = NSBezierPath()
        a.move(to: .zero)
        a.line(to: P(0, -16))
        a.line(to: P(3.6, -12.6))
        a.line(to: P(6.4, -18.6))
        a.line(to: P(9, -17.4))
        a.line(to: P(6.2, -11.6))
        a.line(to: P(11, -11.6))
        a.close()
        NSColor.black.setFill()
        a.fill()
        NSColor.white.setStroke()
        a.lineWidth = 1.2
        a.lineJoinStyle = .round
        a.stroke()
        ctx.restoreGState()
    }

    ctx.restoreGState()
}

// MARK: - Cat view

enum Pose { case run, hold, sit, sleep }

final class CatView: NSView {
    var pose: Pose = .sit
    var facing: CGFloat = 1          // +1 = right, -1 = left
    var phase: CGFloat = 0           // run-cycle phase
    var time: CGFloat = 0            // free-running animation clock
    var gait: CGFloat = 1            // 0…1 leg swing amplitude
    var mouthOpen: CGFloat = 0
    var showPointer = false

    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        if facing < 0 {
            ctx.translateBy(x: bounds.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        ctx.translateBy(x: feetAnchor.x, y: feetAnchor.y)
        ctx.scaleBy(x: unitScale, y: unitScale)
        switch pose {
        case .run:   drawRunner(ctx, holding: false)
        case .hold:  drawRunner(ctx, holding: true)
        case .sit:   drawSit(ctx)
        case .sleep: drawSleep(ctx)
        }
        ctx.restoreGState()
        if pose == .sleep { drawZs() }
    }

    // MARK: Running / walking / standing with the pointer in its mouth

    private func drawRunner(_ ctx: CGContext, holding: Bool) {
        let biting = holding && showPointer
        let g: CGFloat = holding ? 0 : gait
        let b = abs(sin(phase)) * 3 * g

        // Tail (curls up behind)
        let lash: CGFloat = biting ? sin(time * 14) * 3 : sin(phase) * 3 * g + sin(time * 4)
        drawStripedTail(ctx, Cubic(a: P(-26, 16 + b), b: P(-41, 15 + b),
                                   c: P(-43 + lash, 32 + b), d: P(-32 + lash, 34 + b)), width: 8)

        // Legs (stubby, white; the far pair is shaded) – behind the body
        func leg(_ x: CGFloat, _ off: CGFloat, far: Bool) {
            let a = sin(phase + off) * 0.9 * g
            let lift = max(0, cos(phase + off)) * 3 * g
            let hip = P(x, 8 + b)
            let paw = P(x + sin(a) * 8.5, 8 + b - cos(a) * 8.5 + lift)
            let col = far ? shade : snow
            stub(hip, paw, width: 4.4, color: col)
            blob(ctx, paw, 3.6, 2.7, fill: col)
        }
        leg(1, .pi * 0.35, far: true)
        leg(-14, .pi * 1.25, far: true)

        // Body
        let bodyRect = NSRect(x: -31, y: 4 + b, width: 44, height: 24)
        let body = NSBezierPath(ovalIn: bodyRect)
        snow.setFill()
        body.fill()
        clipped(ctx, to: body) {
            blob(ctx, P(-9, 5 + b), 21, 6, fill: shade, stroke: false)                 // belly shade
            blob(ctx, P(-15, 26 + b), 11, 5.5, fill: peach, stroke: false)             // peach saddle
            blob(ctx, P(-11, 28 + b), 3.4, 0.8, angle: -0.5, fill: snow, stroke: false)
        }
        inkStroke(body)

        leg(7, 0, far: false)
        leg(-20, .pi * 0.9, far: false)

        // Head faces the camera at the front
        let tilt: CGFloat = biting ? sin(time * 25) * 0.06 : sin(phase) * 0.05 * g
        let mouth: CGFloat = biting ? 0.3 + 0.2 * sin(time * 18) : (g > 0.6 ? 0.3 : 0)
        drawHead(ctx, at: P(18, 27 + b), tilt: tilt,
                 eyes: holding ? .happy : .open,
                 mouthOpen: mouth, pointer: biting, fangs: biting)
    }

    // MARK: Sitting and watching (also the yawn when waking up)

    private func drawSit(_ ctx: CGContext) {
        let wag = sin(time * 3)
        drawStripedTail(ctx, Cubic(a: P(17, 2.5), b: P(40 + wag * 1.5, 4),
                                   c: P(37 + wag * 2, 26), d: P(25 + wag * 2, 19.5 + wag)), width: 8.5)

        // Body
        let body = NSBezierPath()
        body.move(to: P(-15.0, 27))
        body.curve(to: P(-15.6, 3), controlPoint1: P(-19.5, 18), controlPoint2: P(-19.5, 9))
        body.curve(to: P(-12, 0),   controlPoint1: P(-15.6, 1),  controlPoint2: P(-14, 0))
        body.line(to: P(14.5, 0))
        body.curve(to: P(17.7, 3),  controlPoint1: P(16.3, 0),   controlPoint2: P(17.7, 1))
        body.curve(to: P(17.2, 27), controlPoint1: P(22.5, 8),   controlPoint2: P(20.5, 19))
        snow.setFill()
        body.fill()
        clipped(ctx, to: body) {
            let band = NSBezierPath()
            band.move(to: P(-22, 34))
            band.line(to: P(-22, 21.3))
            band.curve(to: P(22, 25.5), controlPoint1: P(-6, 17.2), controlPoint2: P(12, 19.5))
            band.line(to: P(22, 34))
            band.close()
            shade.setFill()
            band.fill()
            blob(ctx, P(-17, -1), 11, 12, fill: shade, stroke: false)
            blob(ctx, P(20, 1), 10, 11, fill: shade, stroke: false)
        }
        inkStroke(body)

        // Front legs (just the soft lines between them, like the reference)
        let legs = NSBezierPath()
        legs.move(to: P(-8.4, 15));  legs.curve(to: P(-6.3, 1.6), controlPoint1: P(-8.9, 10), controlPoint2: P(-7.5, 5))
        legs.move(to: P(-2.1, 14.7)); legs.curve(to: P(-0.2, 1.6), controlPoint1: P(-0.4, 12), controlPoint2: P(-0.3, 6))
        legs.move(to: P(2.0, 14.7));  legs.curve(to: P(0.2, 1.6),  controlPoint1: P(0.8, 12),  controlPoint2: P(0.5, 6))
        legs.move(to: P(8.2, 14.9));  legs.curve(to: P(6.3, 2.3),  controlPoint1: P(8.6, 10),  controlPoint2: P(7.4, 5))
        inkStroke(legs, 1.4)

        // Paws with toe lines
        for cx: CGFloat in [-11.4, 13.0] {
            blob(ctx, P(cx, 2.8), 4.9, 3.3, fill: snow)
            for dx: CGFloat in [-2, 0, 2] {
                line(P(cx + dx - 0.6, 4.3), P(cx + dx + 0.6, 2.0), width: 0.8, color: ink.withAlphaComponent(0.8))
            }
        }

        // Head
        let blink = time.truncatingRemainder(dividingBy: 3.4) > 3.25
        let eyes: Eyes = mouthOpen > 0.3 ? .happy : (blink ? .sleepy : .open)
        drawHead(ctx, at: P(0, 41), tilt: sin(time * 0.9) * 0.05,
                 eyes: eyes, mouthOpen: mouthOpen, pointer: false, fangs: false)
    }

    // MARK: Curled up asleep

    private func drawSleep(_ ctx: CGContext) {
        let breath = sin(time * 1.8) * 0.04
        let ry = 12.5 * (1 + breath)

        let body = NSBezierPath(ovalIn: NSRect(x: -34, y: 0.5, width: 56, height: ry * 2))
        snow.setFill()
        body.fill()
        clipped(ctx, to: body) {
            blob(ctx, P(-6, 0), 30, 6, fill: shade, stroke: false)
            blob(ctx, P(-16, 0.5 + ry * 2 - 1), 12, 5.5, fill: peach, stroke: false)
            blob(ctx, P(-12, 0.5 + ry * 2 - 1.6), 3.4, 0.8, angle: -0.3, fill: snow, stroke: false)
        }
        inkStroke(body)

        // Tail wrapped around the front
        drawStripedTail(ctx, Cubic(a: P(-30, 10), b: P(-26, -4), c: P(16, -5), d: P(36, 4)), width: 7.5)

        // Head resting on top
        drawHead(ctx, at: P(22, 18), tilt: -0.12, eyes: .sleepy,
                 mouthOpen: 0, pointer: false, fangs: false)
    }

    // Floating "Z"s (drawn unmirrored so the letters never flip)
    private func drawZs() {
        for i in 0..<3 {
            let t = (time * 0.45 + CGFloat(i) / 3).truncatingRemainder(dividingBy: 1)
            var x = 118 + t * 16
            if facing < 0 { x = bounds.width - x }
            let y = 50 + t * 45
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9 + t * 11, weight: .heavy),
                .foregroundColor: NSColor(srgbRed: 0.35, green: 0.45, blue: 0.85, alpha: sin(t * .pi))
            ]
            ("Z" as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
        }
    }
}

// MARK: - Behaviour

final class CatController: NSObject {
    private enum State { case gone, chasing, goingToNap, sleeping, waking, biting, fading }

    private let window: NSWindow
    private let view: CatView
    private var timer: Timer?

    private var state: State = .gone
    private var stateStart = CACurrentMediaTime()
    private var respawnDelay: Double = 1.0

    private var pos = CGPoint.zero            // between the kitty's feet, global Cocoa coordinates
    private var vel = CGPoint.zero
    private var facing: CGFloat = 1
    private var alpha: CGFloat = 1
    private var sitting = false
    private var napSide: CGFloat = 1

    private var lastTick = CACurrentMediaTime()
    private var lastPointer = NSEvent.mouseLocation
    private var lastMoveTime = CACurrentMediaTime()
    private var cursorHeld = false

    /// When true, the real pointer is frozen in the kitty's mouth during the 3-second hold.
    var freezeCursor = true

    override init() {
        let v = CatView(frame: NSRect(origin: .zero, size: spriteSize))
        let w = NSWindow(contentRect: v.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.contentView = v
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        view = v
        window = w
        super.init()

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Public

    func callCat() {
        guard state == .gone || state == .fading else { return }
        releaseCursor()
        spawn(near: NSEvent.mouseLocation)
    }

    func releaseCursor() {
        if cursorHeld {
            _ = CGAssociateMouseAndMouseCursorPosition(1)
            cursorHeld = false
        }
    }

    // MARK: Helpers

    private func enter(_ s: State) {
        state = s
        stateStart = CACurrentMediaTime()
    }

    private func spawn(near ptr: CGPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(ptr, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let f = screen.frame
        let fromLeft = Bool.random()
        pos = CGPoint(x: fromLeft ? f.minX - 80 : f.maxX + 80,
                      y: CGFloat.random(in: (f.minY + 60)...(f.maxY - 120)))
        vel = .zero
        alpha = 1
        facing = fromLeft ? 1 : -1
        sitting = false
        view.mouthOpen = 0
        view.showPointer = false
        window.alphaValue = 1
        window.orderFrontRegardless()
        enter(.chasing)
    }

    private func steer(to target: CGPoint, maxSpeed: CGFloat, dt: CGFloat) {
        let dx = target.x - pos.x, dy = target.y - pos.y
        let dist = hypot(dx, dy)
        var desired = CGPoint.zero
        if dist > 0.5 {
            let s = min(maxSpeed, dist * 6)
            desired = CGPoint(x: dx / dist * s, y: dy / dist * s)
        }
        let k = min(1, dt * 9)
        vel.x += (desired.x - vel.x) * k
        vel.y += (desired.y - vel.y) * k
        pos.x += vel.x * dt
        pos.y += vel.y * dt
    }

    private func mouthPoint() -> CGPoint {
        CGPoint(x: pos.x + facing * mouthRel.x, y: pos.y + mouthRel.y)
    }

    private func startBite(pointer ptr: CGPoint) {
        // Lunge so the mouth is exactly on the pointer
        pos = CGPoint(x: ptr.x - facing * mouthRel.x, y: ptr.y - mouthRel.y)
        vel = .zero
        view.showPointer = true
        if freezeCursor {
            _ = CGAssociateMouseAndMouseCursorPosition(0)   // pointer stops obeying the mouse
            cursorHeld = true
        }
        enter(.biting)
    }

    // MARK: Main loop

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(now - lastTick, 0.05))
        lastTick = now

        let ptr = NSEvent.mouseLocation
        if !cursorHeld, hypot(ptr.x - lastPointer.x, ptr.y - lastPointer.y) > 1.5 {
            lastPointer = ptr
            lastMoveTime = now
        }
        let moving = now - lastMoveTime < 0.6
        let idleFor = now - lastMoveTime
        let t = now - stateStart
        view.time += dt

        switch state {
        case .gone:
            if t > respawnDelay { spawn(near: ptr) }
            return

        case .chasing:
            view.mouthOpen = 0
            if moving {
                sitting = false
                if ptr.x > pos.x + 12 { facing = 1 } else if ptr.x < pos.x - 12 { facing = -1 }
                steer(to: CGPoint(x: ptr.x - facing * mouthRel.x, y: ptr.y - mouthRel.y),
                      maxSpeed: 800, dt: dt)
                let m = mouthPoint()
                if hypot(m.x - ptr.x, m.y - ptr.y) < 28 {
                    startBite(pointer: ptr)
                    break
                }
                view.pose = .run
            } else if idleFor >= 60 {
                napSide = pos.x >= ptr.x ? 1 : -1
                enter(.goingToNap)
            } else {
                // Pointer is still: wander over to a spot beside it and sit, watching.
                let side: CGFloat = pos.x >= ptr.x ? 1 : -1
                let spot = CGPoint(x: ptr.x + side * 100, y: ptr.y - 20)
                let d = hypot(spot.x - pos.x, spot.y - pos.y)
                if sitting && d < 30 {
                    vel = .zero
                    facing = -side
                    view.pose = .sit
                } else {
                    sitting = false
                    steer(to: spot, maxSpeed: 300, dt: dt)
                    if abs(spot.x - pos.x) > 3 { facing = spot.x > pos.x ? 1 : -1 }
                    view.pose = .run
                    if d < 4 { sitting = true }
                }
            }

        case .goingToNap:
            if moving { enter(.chasing); break }
            let spot = CGPoint(x: ptr.x + napSide * 90, y: ptr.y - 20)
            steer(to: spot, maxSpeed: 220, dt: dt)
            if abs(spot.x - pos.x) > 3 { facing = spot.x > pos.x ? 1 : -1 }
            view.pose = .run
            if hypot(spot.x - pos.x, spot.y - pos.y) < 3 {
                vel = .zero
                facing = -napSide
                enter(.sleeping)
            }

        case .sleeping:
            vel = .zero
            view.pose = .sleep
            if moving { enter(.waking) }

        case .waking:
            view.pose = .sit
            view.mouthOpen = 0.9
            if t > 0.9 {
                view.mouthOpen = 0
                enter(.chasing)
            }

        case .biting:
            vel = .zero
            view.pose = .hold
            view.showPointer = true
            if t >= 3.0 {
                releaseCursor()
                lastPointer = NSEvent.mouseLocation
                lastMoveTime = now
                view.showPointer = false
                enter(.fading)
            }

        case .fading:
            view.pose = .hold
            view.showPointer = false
            alpha = max(0, 1 - CGFloat(t) / 1.2)
            pos.y += dt * 25
            if alpha <= 0 {
                window.orderOut(nil)
                respawnDelay = 8
                enter(.gone)
                return
            }
        }

        // Sync sprite
        let speed = hypot(vel.x, vel.y)
        view.gait = min(1, max(0.3, speed / 300))
        view.phase += dt * (5 + speed / 35)
        view.facing = facing
        window.alphaValue = alpha
        window.setFrameOrigin(NSPoint(x: pos.x - feetAnchor.x, y: pos.y - feetAnchor.y))
        view.needsDisplay = true
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var kitty: CatController!
    private var statusItem: NSStatusItem!
    private var freezeItem: NSMenuItem!
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        kitty = CatController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐱"

        let menu = NSMenu()
        let call = NSMenuItem(title: "Call the Cat", action: #selector(callCat), keyEquivalent: "")
        call.target = self
        menu.addItem(call)

        freezeItem = NSMenuItem(title: "Hold Pointer in Mouth When Caught",
                                action: #selector(toggleFreeze), keyEquivalent: "")
        freezeItem.target = self
        freezeItem.state = .on
        menu.addItem(freezeItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Cat Chaser", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu

        // Never leave the pointer frozen if we get killed from a terminal
        for sig in [SIGINT, SIGTERM] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler {
                _ = CGAssociateMouseAndMouseCursorPosition(1)
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = CGAssociateMouseAndMouseCursorPosition(1)
    }

    @objc private func callCat() { kitty.callCat() }

    @objc private func toggleFreeze() {
        kitty.freezeCursor.toggle()
        freezeItem.state = kitty.freezeCursor ? .on : .off
    }

    @objc private func quit() {
        kitty.releaseCursor()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)      // no Dock icon; control it from the 🐱 menu bar item
app.run()

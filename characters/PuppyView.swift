// PuppyView.swift  —  "Kitty Chasing Your Mouse"
// A shiba-inu puppy drawn in the same "kitty units" as KittyView (origin = between the feet,
// 1 unit ≈ 1.25 px), as a subclass of KittyView.
//
// Experiment: how much of KittyView's drawing code carries over to a different animal?
//   REUSED as-is ........ blob, line, stub, clipped, inkStroke, KittyView.Cubic, the unit system,
//                         the mouth/pointer anchor (head centre + (0, -9.2)), the pose/animation
//                         logic of drawRunner / drawSit / drawSleep (same skeleton, new parts)
//   PARAMETERISED ....... outlineColor (plum for the kitty, red-brown for the puppy)
//   PUPPY-SPECIFIC ...... head silhouette (broad fluffy ears, cheek tufts), cream muzzle mask,
//                         forehead spots, open "D" mouth with tongue, collar + tag, cream bib,
//                         bushy cream-tipped tail with fur spikes, separate front legs / haunch
//
// To try it, change the one line in KittyController where the sprite view is created:
//     let v = PuppyView(frame: NSRect(origin: .zero, size: spriteSize))

import Cocoa

// MARK: Puppy palette (picked by eye from the reference illustration)

private let pFur      = NSColor(srgbRed: 0.941, green: 0.659, blue: 0.439, alpha: 1)
private let pFurDark  = NSColor(srgbRed: 0.851, green: 0.549, blue: 0.380, alpha: 1)
private let pRose     = NSColor(srgbRed: 0.788, green: 0.459, blue: 0.420, alpha: 1)
private let pCream    = NSColor(srgbRed: 1.000, green: 0.937, blue: 0.820, alpha: 1)
private let pLine     = NSColor(srgbRed: 0.604, green: 0.267, blue: 0.239, alpha: 1)
private let pCollar   = NSColor(srgbRed: 0.894, green: 0.282, blue: 0.251, alpha: 1)
private let pCollarHi = NSColor(srgbRed: 0.965, green: 0.463, blue: 0.408, alpha: 1)
private let pNose     = NSColor(srgbRed: 0.620, green: 0.267, blue: 0.282, alpha: 1)
private let pMouth    = NSColor(srgbRed: 0.361, green: 0.098, blue: 0.169, alpha: 1)
private let pTongue   = NSColor(srgbRed: 0.941, green: 0.420, blue: 0.361, alpha: 1)
private let pEye      = NSColor(srgbRed: 0.169, green: 0.098, blue: 0.137, alpha: 1)
private let pBlush    = NSColor(srgbRed: 0.929, green: 0.600, blue: 0.580, alpha: 1)
private let pTag      = NSColor(srgbRed: 0.918, green: 0.686, blue: 0.760, alpha: 1)
private let pBuckle   = NSColor(srgbRed: 0.992, green: 0.898, blue: 0.878, alpha: 1)

final class PuppyView: KittyView {

    /// Same outline helpers as the kitty, different ink.
    var outlineColor: NSColor { pLine }

    // MARK: - Running / walking / standing with the pointer in its mouth

    override func drawRunner(_ ctx: CGContext, holding: Bool) {
        let biting = holding && showPointer
        let g: CGFloat = holding ? 0 : gait
        let b = abs(sin(phase)) * 3 * g

        // Bushy tail curling up behind
        let lash: CGFloat = biting ? sin(time * 14) * 3 : sin(phase) * 3 * g + sin(time * 4)
        puppyTail(ctx, KittyView.Cubic(a: P(-26, 16 + b), b: P(-42, 12 + b),
                                       c: P(-47 + lash, 30 + b), d: P(-36 + lash, 36 + b)), width: 9)

        // Legs: identical rig to the kitty (stubby limbs + paw blobs), orange instead of white
        func leg(_ x: CGFloat, _ off: CGFloat, far: Bool) {
            let a = sin(phase + off) * 0.9 * g
            let lift = max(0, cos(phase + off)) * 3 * g
            let hip = P(x, 8 + b)
            let paw = P(x + sin(a) * 8.5, 8 + b - cos(a) * 8.5 + lift)
            let col = far ? pFurDark : pFur
            stub(hip, paw, width: 4.8, color: col)
            blob(ctx, paw, 3.8, 2.8, fill: col)
        }
        leg(1, .pi * 0.35, far: true)
        leg(-14, .pi * 1.25, far: true)

        // Body: same bean as the kitty, with a cream chest
        let body = NSBezierPath(ovalIn: NSRect(x: -31, y: 4 + b, width: 44, height: 24))
        pFur.setFill()
        body.fill()
        clipped(ctx, to: body) {
            blob(ctx, P(-9, 4 + b), 21, 6, fill: pFurDark, stroke: false)      // belly shade
            blob(ctx, P(10, 13 + b), 7, 9, fill: pCream, stroke: false)        // cream chest
        }
        inkStroke(body)

        leg(7, 0, far: false)
        leg(-20, .pi * 0.9, far: false)

        // Head: same position as the kitty's, so the mouth lands exactly on the pointer
        let tilt: CGFloat = biting ? sin(time * 25) * 0.06 : sin(phase) * 0.05 * g
        let mouth: CGFloat = biting ? 0.3 + 0.2 * sin(time * 18) : (g > 0.6 ? 0.45 : 0)
        drawPuppyHead(ctx, at: P(18, 27 + b), tilt: tilt, eyes: holding ? .happy : .open,
                      mouthOpen: mouth, pointer: biting)
    }

    // MARK: - Sitting and watching (also the yawn when waking up, and the happy howl)

    override func drawSit(_ ctx: CGContext) {
        let wag = sin(time * 4)

        // Tail
        puppyTail(ctx, KittyView.Cubic(a: P(13, 8), b: P(36, 3 + wag),
                                       c: P(41 + wag, 27), d: P(23 + wag, 33)), width: 10)

        // Rear-left paw peeking out behind the body
        blob(ctx, P(-17, 2.8), 3.8, 2.7, fill: pFur)
        toes(-17, 1.4)

        // Body (open at the top: the head and collar cover the neck)
        let body = NSBezierPath()
        body.move(to: P(-15.5, 26))
        body.curve(to: P(-18.4, 11),  controlPoint1: P(-19.5, 21),  controlPoint2: P(-20.5, 15.5))
        body.curve(to: P(-12.5, 1.4), controlPoint1: P(-16.6, 6.5), controlPoint2: P(-15.5, 2.4))
        body.line(to: P(14.5, 1.2))
        body.curve(to: P(19.6, 11),   controlPoint1: P(18.6, 2),    controlPoint2: P(20.6, 6))
        body.curve(to: P(9, 27.5),    controlPoint1: P(19.2, 21),   controlPoint2: P(15, 26.5))
        pFur.setFill()
        body.fill()
        clipped(ctx, to: body) {
            blob(ctx, P(-4, 0), 15, 4.2, fill: pFurDark, stroke: false)           // shadow near the floor

            // cream bib with ragged fur tips
            let bib = NSBezierPath()
            bib.move(to: P(-16.5, 22))
            bib.curve(to: P(-11.5, 14), controlPoint1: P(-16, 18), controlPoint2: P(-14, 16))
            bib.line(to: P(-9.3, 10.8))
            bib.line(to: P(-8.6, 13.2))
            bib.line(to: P(-7.2, 9.6))
            bib.line(to: P(-5.6, 12.6))
            bib.line(to: P(-3.2, 10.2))
            bib.curve(to: P(3.5, 18),   controlPoint1: P(-1.5, 13), controlPoint2: P(2.5, 15.5))
            bib.curve(to: P(11, 26.5),  controlPoint1: P(6, 20.5),  controlPoint2: P(10, 24))
            let edge = bib.copy() as! NSBezierPath
            bib.line(to: P(11, 34))
            bib.line(to: P(-17, 34))
            bib.close()
            pCream.setFill()
            bib.fill()
            edge.lineWidth = 0.9
            edge.lineJoinStyle = .round
            pLine.withAlphaComponent(0.7).setStroke()
            edge.stroke()
        }
        inkStroke(body)

        // Hind leg / haunch on the far side
        let haunch = NSBezierPath(ovalIn: NSRect(x: 6.2, y: 0.6, width: 14.8, height: 17.6))
        pFur.setFill()
        haunch.fill()
        clipped(ctx, to: haunch) {
            blob(ctx, P(9, 3), 7, 7, fill: pFurDark, stroke: false)
        }
        inkStroke(haunch)
        blob(ctx, P(14.2, 2.4), 5.4, 2.9, fill: pFur)
        toes(14.2, 1.0)

        // Front legs
        frontLeg(-11.8, top: 12.5, width: 7.4)
        frontLeg(3.5, top: 12.5, width: 7.8)

        // Collar and tag sit under the chin
        drawCollar(ctx)

        // Head (turned a little, like the reference). While howling it tips back further.
        let blink = time.truncatingRemainder(dividingBy: 3.4) > 3.25
        let eyes: Eyes = blink ? .sleepy : .open
        let tilt = 0.12 + sin(time * 0.9) * 0.03 + lookUp * 0.12
        drawPuppyHead(ctx, at: P(-4.5, 43 + lookUp * 1.5), tilt: tilt, eyes: eyes,
                      mouthOpen: mouthOpen, pointer: false, lookUp: lookUp)
    }

    // MARK: - Curled up asleep

    override func drawSleep(_ ctx: CGContext) {
        let breath = sin(time * 1.8) * 0.04
        let ry = 12.5 * (1 + breath)

        let body = NSBezierPath(ovalIn: NSRect(x: -34, y: 0.5, width: 56, height: ry * 2))
        pFur.setFill()
        body.fill()
        clipped(ctx, to: body) {
            blob(ctx, P(-6, 0), 30, 6, fill: pFurDark, stroke: false)
            blob(ctx, P(14, 6), 8, 9, fill: pCream, stroke: false)
        }
        inkStroke(body)

        // Tail wrapped around the front
        puppyTail(ctx, KittyView.Cubic(a: P(-30, 10), b: P(-26, -4), c: P(16, -5), d: P(36, 4)), width: 8)

        drawPuppyHead(ctx, at: P(22, 18), tilt: -0.12, eyes: .sleepy, mouthOpen: 0, pointer: false)
    }

    // MARK: - Puppy-only parts ------------------------------------------------

    /// Small toe lines on a paw.
    private func toes(_ cx: CGFloat, _ y: CGFloat) {
        for dx: CGFloat in [-1.4, 1.4] {
            line(P(cx + dx, y + 1.9), P(cx + dx * 0.9, y), width: 0.8, color: pLine.withAlphaComponent(0.8))
        }
    }

    /// A front leg: open at the top (it grows out of the chest), flared at the paw.
    private func frontLeg(_ x: CGFloat, top: CGFloat, width w: CGFloat) {
        let h = w / 2
        let p = NSBezierPath()
        p.move(to: P(x - h, top))
        p.line(to: P(x - h, 4.5))
        p.curve(to: P(x - h - 0.8, 1.2), controlPoint1: P(x - h, 3), controlPoint2: P(x - h - 0.8, 2.2))
        p.line(to: P(x + h + 0.8, 1.2))
        p.curve(to: P(x + h, 4.5), controlPoint1: P(x + h + 0.8, 2.2), controlPoint2: P(x + h, 3))
        p.line(to: P(x + h, top))
        pFur.setFill()
        p.fill()
        inkStroke(p)
        toes(x, 1.4)
    }

    /// Red collar, buckles and the little round tag.
    private func drawCollar(_ ctx: CGContext) {
        let cu = KittyView.Cubic(a: P(-18, 25.5), b: P(-13, 16.5), c: P(0, 15.5), d: P(10.5, 27.5))
        let path = NSBezierPath()
        path.move(to: cu.a)
        path.curve(to: cu.d, controlPoint1: cu.b, controlPoint2: cu.c)
        path.lineCapStyle = .butt
        path.lineWidth = 7.4
        pLine.setStroke()
        path.stroke()
        path.lineWidth = 4.8
        pCollar.setStroke()
        path.stroke()

        // highlight along the top edge of the band
        let hi = path.copy() as! NSBezierPath
        hi.transform(using: AffineTransform(translationByX: 0, byY: 1.2))
        hi.lineWidth = 1.0
        pCollarHi.setStroke()
        hi.stroke()

        // buckle + strap loop
        for t: CGFloat in [0.2, 0.55] {
            let p = cu.at(t)
            let r = NSBezierPath(roundedRect: NSRect(x: p.x - 1.7, y: p.y - 2.8, width: 3.4, height: 5.6),
                                 xRadius: 1.2, yRadius: 1.2)
            pBuckle.setFill()
            r.fill()
            inkStroke(r, 0.8)
        }

        // tag
        let tagC = P(-5.4, 13.6)
        line(P(tagC.x, 17.6), P(tagC.x, tagC.y + 2.4), width: 0.9, color: pLine)
        blob(ctx, tagC, 2.6, 2.8, fill: pTag)
        blob(ctx, tagC, 1.2, 1.4, fill: pCream)
    }

    /// Bushy tail: orange core, cream tip, rose underside and fur spikes on the outer edge.
    private func puppyTail(_ ctx: CGContext, _ cu: KittyView.Cubic, width w: CGFloat) {
        // Which side is "outside" of the curl?
        let turn = (cu.b.x - cu.a.x) * (cu.d.y - cu.c.y) - (cu.b.y - cu.a.y) * (cu.d.x - cu.c.x)
        let o: CGFloat = turn > 0 ? -1 : 1

        // Fur spikes first, so the tail core overlaps their roots
        let spikes: [(CGFloat, NSColor)] = [(0.42, pRose), (0.58, pRose), (0.74, pFur), (0.90, pCream)]
        for (t, col) in spikes {
            let p = cu.at(t), n = cu.normal(t)
            let out = P(n.x * o, n.y * o)
            let tan = P(n.y, -n.x)
            let root = P(p.x + out.x * w * 0.42, p.y + out.y * w * 0.42)
            let tip = P(root.x + out.x * 3.6 + tan.x * 1.6, root.y + out.y * 3.6 + tan.y * 1.6)
            let s = NSBezierPath()
            s.move(to: P(root.x - tan.x * 2.2, root.y - tan.y * 2.2))
            s.line(to: tip)
            s.line(to: P(root.x + tan.x * 2.2, root.y + tan.y * 2.2))
            s.close()
            col.setFill()
            s.fill()
            inkStroke(s, 1.0)
        }

        // Core
        let path = NSBezierPath()
        path.move(to: cu.a)
        path.curve(to: cu.d, controlPoint1: cu.b, controlPoint2: cu.c)
        path.lineCapStyle = .round
        path.lineWidth = w + 3.4
        pLine.setStroke()
        path.stroke()
        path.lineWidth = w
        pFur.setStroke()
        path.stroke()

        // Decorations, clipped to the tail
        func poly(_ from: CGFloat, _ to: CGFloat, offset: CGFloat) -> NSBezierPath {
            let p = NSBezierPath()
            for i in 0...12 {
                let t = from + (to - from) * CGFloat(i) / 12
                let q = cu.at(t), n = cu.normal(t)
                let pt = P(q.x + n.x * offset, q.y + n.y * offset)
                if i == 0 { p.move(to: pt) } else { p.line(to: pt) }
            }
            return p
        }
        ctx.saveGState()
        let cg = CGMutablePath()
        cg.move(to: cu.a)
        cg.addCurve(to: cu.d, control1: cu.b, control2: cu.c)
        ctx.addPath(cg)
        ctx.setLineWidth(w)
        ctx.setLineCap(.round)
        ctx.replacePathWithStrokedPath()
        ctx.clip()

        let under = poly(0.0, 0.88, offset: o * w * 0.30)          // rose underside
        under.lineWidth = w * 0.55
        under.lineCapStyle = .butt
        pRose.setStroke()
        under.stroke()

        let tipCream = poly(0.80, 1.0, offset: 0)                  // cream tip
        tipCream.lineWidth = w + 2
        tipCream.lineCapStyle = .butt
        pCream.setStroke()
        tipCream.stroke()
        ctx.restoreGState()
    }

    /// The captured mouse pointer, tip at head-local (0, -9.2) — same anchor as the kitty.
    private func drawPointer(_ ctx: CGContext) {
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

    /// The puppy head. Same 44-unit width and the same "mouth 9.2 units below centre" anchor as
    /// the kitty head, but a different silhouette and face.
    private func drawPuppyHead(_ ctx: CGContext, at c: CGPoint, tilt: CGFloat, eyes: Eyes,
                               mouthOpen: CGFloat, pointer: Bool, lookUp: CGFloat = 0) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: tilt)

        // Silhouette: broad ears, fluffy tuft on top, two fur spikes on each cheek
        let shape = NSBezierPath()
        shape.move(to: P(-4.3, 17.3))
        shape.line(to: P(-1.6, 19.4))
        shape.line(to: P(-0.7, 17.7))
        shape.line(to: P(1.4, 19.8))
        shape.line(to: P(4.5, 17.3))
        // right ear
        shape.curve(to: P(14.6, 26.0), controlPoint1: P(6.8, 21.5),  controlPoint2: P(11, 26.5))
        shape.curve(to: P(19.8, 10.5), controlPoint1: P(17.6, 25),   controlPoint2: P(19.6, 17.5))
        shape.curve(to: P(22.0, 0.5),  controlPoint1: P(20.0, 7),    controlPoint2: P(21.5, 4))
        // right cheek tufts
        shape.line(to: P(25.0, -5.6))
        shape.line(to: P(21.8, -5.8))
        shape.line(to: P(23.4, -10.8))
        shape.line(to: P(20.4, -9.8))
        // chin
        shape.curve(to: P(0, -18.8),   controlPoint1: P(17, -17.5),  controlPoint2: P(8, -18.8))
        shape.curve(to: P(-20.4, -9.8), controlPoint1: P(-8, -18.8), controlPoint2: P(-17, -17.5))
        // left cheek tufts
        shape.line(to: P(-23.4, -10.8))
        shape.line(to: P(-21.8, -5.8))
        shape.line(to: P(-25.0, -5.6))
        shape.line(to: P(-22.0, 0.5))
        // left ear
        shape.curve(to: P(-19.8, 10.5), controlPoint1: P(-21.5, 4),   controlPoint2: P(-20.0, 7))
        shape.curve(to: P(-14.6, 26.0), controlPoint1: P(-19.6, 17.5), controlPoint2: P(-17.6, 25))
        shape.curve(to: P(-4.3, 17.3),  controlPoint1: P(-11, 26.5),   controlPoint2: P(-6.8, 21.5))
        shape.close()

        pFur.setFill()
        shape.fill()

        clipped(ctx, to: shape) {
            // cream muzzle/cheek mask: dips under the eyes, rises to the nose bridge between them
            let mask = NSBezierPath()
            mask.move(to: P(-27, -2))
            mask.curve(to: P(-9.5, -5.6), controlPoint1: P(-20, -1),   controlPoint2: P(-15, -5.6))
            mask.curve(to: P(0, -1.8),    controlPoint1: P(-5.5, -5.6), controlPoint2: P(-3, -1.8))
            mask.curve(to: P(9.5, -5.6),  controlPoint1: P(3, -1.8),   controlPoint2: P(5.5, -5.6))
            mask.curve(to: P(27, -1),     controlPoint1: P(15, -5.6),  controlPoint2: P(21, 3))
            mask.line(to: P(27, -30))
            mask.line(to: P(-27, -30))
            mask.close()
            pCream.setFill()
            mask.fill()

            // the two cream "eyebrow" spots
            blob(ctx, P(-5.4, 6.8), 2.3, 1.9, angle: 0.35, fill: pCream, stroke: false)
            blob(ctx, P(3.8, 7.8), 2.5, 2.0, angle: 0.2, fill: pCream, stroke: false)
        }
        inkStroke(shape)

        // Inner ears (dusty rose)
        for s: CGFloat in [-1, 1] {
            let inner = NSBezierPath()
            inner.move(to: P(s * 7.8, 18.0))
            inner.curve(to: P(s * 14.4, 23.2), controlPoint1: P(s * 9.6, 21),    controlPoint2: P(s * 12.6, 23.6))
            inner.curve(to: P(s * 17.3, 11.6), controlPoint1: P(s * 16.2, 21.5), controlPoint2: P(s * 17.4, 16))
            inner.curve(to: P(s * 7.8, 18.0),  controlPoint1: P(s * 14, 13),     controlPoint2: P(s * 10.5, 15.5))
            inner.close()
            pRose.setFill()
            inner.fill()
            inkStroke(inner, 0.8)
        }

        // Face slides up when the head is tipped back (howl)
        ctx.translateBy(x: 0, y: lookUp * 3.2)

        // Blush lines
        let blushSpots: [(CGFloat, CGFloat)] = [(-14.5, -6.2), (14.0, -5.8)]
        for (bx, by) in blushSpots {
            for k: CGFloat in [-0.8, 0.8] {
                line(P(bx - 1.2, by + k - 0.5), P(bx + 1.2, by + k + 0.5), width: 0.55, color: pBlush)
            }
        }

        // Eyes
        for ex: CGFloat in [-8.6, 8.6] {
            let ey: CGFloat = 0.2
            switch eyes {
            case .open:
                blob(ctx, P(ex, ey), 3.0, 3.3, fill: pEye, stroke: false)
                blob(ctx, P(ex + 0.9, ey + 1.4), 0.95, 1.1, fill: snow, stroke: false)
                blob(ctx, P(ex - 1.0, ey - 1.2), 0.45, 0.5, fill: snow, stroke: false)
            case .sleepy, .happy:
                let bend: CGFloat = (eyes == .happy) ? 3.2 : -3.2
                let p = NSBezierPath()
                p.move(to: P(ex - 3.2, ey - 0.8))
                p.curve(to: P(ex + 3.2, ey - 0.8),
                        controlPoint1: P(ex - 2.0, ey - 0.8 + bend * 1.3),
                        controlPoint2: P(ex + 2.0, ey - 0.8 + bend * 1.3))
                p.lineWidth = 1.5
                p.lineCapStyle = .round
                pEye.setStroke()
                p.stroke()
            }
        }

        // Nose
        blob(ctx, P(0, -4.2), 2.1, 1.5, fill: pNose)
        blob(ctx, P(-0.7, -3.7), 0.7, 0.35, fill: pBlush, stroke: false)

        // Mouth
        let mo = min(1, max(0, mouthOpen))
        if mo > 0.05 {
            let d = 1.2 + 8.6 * mo
            let m = NSBezierPath()
            m.move(to: P(-5.4, -6.2))
            m.curve(to: P(5.6, -6.0),        controlPoint1: P(-2, -7.4),             controlPoint2: P(2.6, -7.2))
            m.curve(to: P(0.3, -6.2 - d),    controlPoint1: P(6.8, -6.0 - d * 0.55), controlPoint2: P(4.6, -6.2 - d))
            m.curve(to: P(-5.4, -6.2),       controlPoint1: P(-4.2, -6.2 - d),       controlPoint2: P(-6.8, -6.0 - d * 0.55))
            m.close()
            pMouth.setFill()
            m.fill()
            clipped(ctx, to: m) {
                blob(ctx, P(0.2, -6.2 - d + 1.4), 4.4, max(1.2, d * 0.42), fill: pTongue, stroke: false)
            }
            inkStroke(m, 1.2)
            if mo > 0.25 {                                            // two little fangs
                for fx: CGFloat in [-3.7, 2.4] {
                    let f = NSBezierPath()
                    f.move(to: P(fx, -6.9))
                    f.line(to: P(fx + 1.5, -6.7))
                    f.line(to: P(fx + 0.7, -8.8))
                    f.close()
                    pCream.setFill()
                    f.fill()
                }
            }
        } else {
            let m = NSBezierPath()
            m.move(to: P(0, -5.2)); m.line(to: P(0, -6.8))
            m.move(to: P(-4.4, -6.2))
            m.curve(to: P(0, -6.8), controlPoint1: P(-4.4, -9.4), controlPoint2: P(-0.3, -9.4))
            m.move(to: P(4.4, -6.2))
            m.curve(to: P(0, -6.8), controlPoint1: P(4.4, -9.4), controlPoint2: P(0.3, -9.4))
            inkStroke(m, 1.3)
        }

        if pointer { drawPointer(ctx) }

        ctx.restoreGState()
    }
}

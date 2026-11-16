// CatChaser.swift
// A tiny animated 2D cat that lives on top of your desktop and chases the mouse pointer.
//
//  - Runs after the pointer while it is moving and catches it.
//  - On catch: bites the pointer, holds it in its mouth for 3 seconds, then fades away.
//  - If the pointer is idle for 60s+, the cat curls up and naps next to it.
//  - The cat comes back a few seconds after it vanishes.
//
// Build:  ./build.sh      (needs Xcode command line tools)

import Cocoa

// MARK: - Palette & geometry

private let fur      = NSColor(srgbRed: 0.93, green: 0.60, blue: 0.25, alpha: 1)
private let furDark  = NSColor(srgbRed: 0.76, green: 0.40, blue: 0.12, alpha: 1)
private let cream    = NSColor(srgbRed: 1.00, green: 0.94, blue: 0.84, alpha: 1)
private let outline  = NSColor(srgbRed: 0.30, green: 0.15, blue: 0.06, alpha: 1)
private let pink     = NSColor(srgbRed: 1.00, green: 0.55, blue: 0.62, alpha: 1)
private let eyeGreen = NSColor(srgbRed: 0.35, green: 0.78, blue: 0.40, alpha: 1)

/// Size of the (transparent, click-through) window that carries the cat sprite.
private let spriteSize = CGSize(width: 140, height: 110)
/// The cat's "position" is the point between its feet; this is where that sits inside the sprite.
private let feetAnchor = CGPoint(x: 70, y: 14)
/// Where the mouth is, relative to the feet, when the cat faces right.
private let mouthRel = CGPoint(x: 35, y: 26)

// MARK: - Drawing helpers

private enum Eyes { case open, sleepy, happy }

private func blob(_ ctx: CGContext, _ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat,
                  angle: CGFloat = 0, fill: NSColor, stroke: Bool = true) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: angle)
    let p = NSBezierPath(ovalIn: NSRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
    fill.setFill()
    p.fill()
    if stroke {
        outline.setStroke()
        p.lineWidth = 2.2
        p.stroke()
    }
    ctx.restoreGState()
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

private func limb(_ a: CGPoint, _ b: CGPoint, width: CGFloat, color: NSColor) {
    line(a, b, width: width + 3.5, color: outline)
    line(a, b, width: width, color: color)
}

private func strokeTail(_ ctx: CGContext, _ path: NSBezierPath, tip: CGPoint) {
    path.lineCapStyle = .round
    path.lineWidth = 10
    outline.setStroke()
    path.stroke()
    path.lineWidth = 6.5
    fur.setStroke()
    path.stroke()
    blob(ctx, tip, 3.4, 3.4, fill: furDark, stroke: false)
}

/// Draws the head centred on `c`. Facial features are shifted right a little for a 3/4 look.
/// The mouth sits at local (5, -8); the pointer (when held) has its tip exactly there.
private func drawHead(_ ctx: CGContext, at c: CGPoint, tilt: CGFloat, eyes: Eyes,
                      mouthOpen: CGFloat, pointer: Bool, fangs: Bool) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y)
    ctx.rotate(by: tilt)

    // Ears
    for s: CGFloat in [-1, 1] {
        let ear = NSBezierPath()
        ear.move(to: CGPoint(x: s * 14, y: 4))
        ear.line(to: CGPoint(x: s * 10, y: 25))
        ear.line(to: CGPoint(x: s * 1, y: 12))
        ear.close()
        fur.setFill()
        ear.fill()
        outline.setStroke()
        ear.lineWidth = 2.2
        ear.lineJoinStyle = .round
        ear.stroke()

        let inner = NSBezierPath()
        inner.move(to: CGPoint(x: s * 11.5, y: 8))
        inner.line(to: CGPoint(x: s * 9.5, y: 20))
        inner.line(to: CGPoint(x: s * 4.5, y: 12))
        inner.close()
        pink.setFill()
        inner.fill()
    }

    // Head + forehead stripes + muzzle
    blob(ctx, .zero, 16, 14, fill: fur)
    for dx: CGFloat in [-4, 0, 4] {
        line(CGPoint(x: dx + 2, y: 13), CGPoint(x: dx + 2, y: dx == 0 ? 8 : 9.5), width: 2, color: furDark)
    }
    blob(ctx, CGPoint(x: 5, y: -6), 8.5, 6, fill: cream, stroke: false)

    // Eyes
    for ex: CGFloat in [-1, 11] {
        switch eyes {
        case .open:
            blob(ctx, CGPoint(x: ex, y: 2), 3.8, 4.6, fill: eyeGreen)
            blob(ctx, CGPoint(x: ex + 0.5, y: 2), 1.6, 3.8, fill: .black, stroke: false)
            blob(ctx, CGPoint(x: ex + 1.4, y: 4.2), 1, 1, fill: .white, stroke: false)
        case .sleepy, .happy:
            let up: CGFloat = (eyes == .happy) ? 7 : -2      // ∩ for happy, ∪ for sleepy
            let p = NSBezierPath()
            p.move(to: CGPoint(x: ex - 3.8, y: 2.5))
            p.curve(to: CGPoint(x: ex + 3.8, y: 2.5),
                    controlPoint1: CGPoint(x: ex - 2, y: up),
                    controlPoint2: CGPoint(x: ex + 2, y: up))
            p.lineWidth = 2
            p.lineCapStyle = .round
            outline.setStroke()
            p.stroke()
        }
    }

    // Nose
    let nose = NSBezierPath()
    nose.move(to: CGPoint(x: 2.5, y: -2))
    nose.line(to: CGPoint(x: 7.5, y: -2))
    nose.line(to: CGPoint(x: 5, y: -4.8))
    nose.close()
    pink.setFill()
    nose.fill()
    outline.setStroke()
    nose.lineWidth = 1.2
    nose.stroke()

    // Mouth
    if mouthOpen > 0.05 {
        let h = 1.5 + 6 * mouthOpen
        let m = NSBezierPath(ovalIn: NSRect(x: 0.5, y: -8 - h / 2, width: 9, height: h))
        NSColor(srgbRed: 0.28, green: 0.05, blue: 0.08, alpha: 1).setFill()
        m.fill()
        outline.setStroke()
        m.lineWidth = 1.2
        m.stroke()
        if h > 4 {
            blob(ctx, CGPoint(x: 5, y: -8 - h / 2 + 2), 3, 1.6, fill: pink, stroke: false)
        }
        if fangs {
            for fx: CGFloat in [2, 6.6] {
                let f = NSBezierPath()
                f.move(to: CGPoint(x: fx, y: -7.4))
                f.line(to: CGPoint(x: fx + 1.5, y: -7.4))
                f.line(to: CGPoint(x: fx + 0.75, y: -10.2))
                f.close()
                NSColor.white.setFill()
                f.fill()
            }
        }
    } else {
        let m = NSBezierPath()
        m.move(to: CGPoint(x: 5, y: -4.8)); m.line(to: CGPoint(x: 5, y: -7))
        m.move(to: CGPoint(x: 5, y: -7))
        m.curve(to: CGPoint(x: 1.5, y: -7.5), controlPoint1: CGPoint(x: 4, y: -9), controlPoint2: CGPoint(x: 2.5, y: -9))
        m.move(to: CGPoint(x: 5, y: -7))
        m.curve(to: CGPoint(x: 8.5, y: -7.5), controlPoint1: CGPoint(x: 6, y: -9), controlPoint2: CGPoint(x: 7.5, y: -9))
        m.lineWidth = 1.3
        m.lineCapStyle = .round
        outline.setStroke()
        m.stroke()
    }

    // Whiskers
    let wc = outline.withAlphaComponent(0.55)
    for s: CGFloat in [-1, 1] {
        line(CGPoint(x: 5 + s * 8, y: -4.5), CGPoint(x: 5 + s * 20, y: -2), width: 1, color: wc)
        line(CGPoint(x: 5 + s * 8, y: -6.5), CGPoint(x: 5 + s * 19, y: -8.5), width: 1, color: wc)
    }

    // The captured mouse pointer, tip exactly at the mouth
    if pointer {
        ctx.saveGState()
        ctx.translateBy(x: 5, y: -8)
        let a = NSBezierPath()
        a.move(to: .zero)
        a.line(to: CGPoint(x: 0, y: -16))
        a.line(to: CGPoint(x: 3.6, y: -12.6))
        a.line(to: CGPoint(x: 6.4, y: -18.6))
        a.line(to: CGPoint(x: 9, y: -17.4))
        a.line(to: CGPoint(x: 6.2, y: -11.6))
        a.line(to: CGPoint(x: 11, y: -11.6))
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
        switch pose {
        case .run:   drawRunner(ctx, holding: false)
        case .hold:  drawRunner(ctx, holding: true)
        case .sit:   drawSit(ctx)
        case .sleep: drawSleep(ctx)
        }
        ctx.restoreGState()
        if pose == .sleep { drawZs() }
    }

    // Running / walking / standing-with-pointer-in-mouth
    private func drawRunner(_ ctx: CGContext, holding: Bool) {
        let biting = holding && showPointer
        let g: CGFloat = holding ? 0 : gait
        let bob = abs(sin(phase)) * 5 * g
        let by: CGFloat = 38 + bob
        let hipY = by - 8

        // Tail
        let lash: CGFloat = biting ? sin(time * 14) * 5 : sin(phase) * 5 * g + sin(time * 4) * 2
        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: 38, y: by + 2))
        let tip = CGPoint(x: 20 + lash, y: by + 36)
        tail.curve(to: tip,
                   controlPoint1: CGPoint(x: 18, y: by - 2),
                   controlPoint2: CGPoint(x: 12 + lash, y: by + 20))
        strokeTail(ctx, tail, tip: tip)

        // Legs (drawn behind the body)
        func leg(_ x: CGFloat, _ off: CGFloat, _ color: NSColor) {
            let a = sin(phase + off) * 0.95 * g
            let lift = max(0, cos(phase + off)) * 5 * g
            let top = CGPoint(x: x, y: hipY)
            let paw = CGPoint(x: x + sin(a) * 18, y: hipY - cos(a) * 18 + lift)
            limb(top, paw, width: 6.5, color: color)
            blob(ctx, paw, 4.6, 3.6, fill: cream)
        }
        leg(80, .pi * 0.35, furDark)
        leg(52, .pi * 1.25, furDark)
        leg(86, 0, fur)
        leg(46, .pi * 0.9, fur)

        // Body
        blob(ctx, CGPoint(x: 66, y: by), 30, 15, angle: sin(phase) * 0.05 * g, fill: fur)
        blob(ctx, CGPoint(x: 68, y: by - 9), 22, 5, fill: cream, stroke: false)
        for i in 0..<3 {
            let x = 50 + CGFloat(i) * 12
            line(CGPoint(x: x, y: by + 13), CGPoint(x: x + 2, y: by + 5), width: 3, color: furDark)
        }

        // Head
        let tilt: CGFloat = biting ? sin(time * 25) * 0.06 : sin(phase) * 0.05 * g
        let mouth: CGFloat = biting ? 0.3 + 0.2 * sin(time * 18) : (g > 0.6 ? 0.25 : 0)
        drawHead(ctx, at: CGPoint(x: 100, y: by + 10), tilt: tilt,
                 eyes: holding ? .happy : .open,
                 mouthOpen: mouth, pointer: biting, fangs: biting)
    }

    // Sitting and watching (also used for the yawn when waking up)
    private func drawSit(_ ctx: CGContext) {
        let wag = sin(time * 3)
        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: 46, y: 20))
        let tip = CGPoint(x: 14 + wag * 3, y: 38 + wag * 4)
        tail.curve(to: tip, controlPoint1: CGPoint(x: 20, y: 12), controlPoint2: CGPoint(x: 8, y: 26))
        strokeTail(ctx, tail, tip: tip)

        blob(ctx, CGPoint(x: 52, y: 28), 20, 15, fill: fur)                  // haunch
        blob(ctx, CGPoint(x: 64, y: 46), 16, 26, angle: -0.12, fill: fur)    // torso
        blob(ctx, CGPoint(x: 73, y: 44), 8, 17, fill: cream, stroke: false)  // chest
        for x: CGFloat in [74, 83] {                                         // front legs
            limb(CGPoint(x: x, y: 36), CGPoint(x: x, y: 17), width: 6.5, color: fur)
            blob(ctx, CGPoint(x: x, y: 15), 5.2, 3.6, fill: cream)
        }

        let blink = time.truncatingRemainder(dividingBy: 3.4) > 3.25
        let eyes: Eyes = mouthOpen > 0.3 ? .happy : (blink ? .sleepy : .open)
        drawHead(ctx, at: CGPoint(x: 76, y: 78), tilt: sin(time * 0.9) * 0.07,
                 eyes: eyes, mouthOpen: mouthOpen, pointer: false, fangs: false)
    }

    // Curled up asleep
    private func drawSleep(_ ctx: CGContext) {
        let breath = sin(time * 1.8) * 0.04
        let ry = 17 * (1 + breath)
        let c = CGPoint(x: 64, y: 13 + ry)
        blob(ctx, c, 36, ry, fill: fur)
        for i in 0..<3 {
            let x = 46 + CGFloat(i) * 13
            line(CGPoint(x: x, y: c.y + ry - 1), CGPoint(x: x + 3, y: c.y + ry - 8), width: 3, color: furDark)
        }

        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: 30, y: 22))
        let tip = CGPoint(x: 112, y: 12)
        tail.curve(to: tip, controlPoint1: CGPoint(x: 40, y: 2), controlPoint2: CGPoint(x: 96, y: 0))
        strokeTail(ctx, tail, tip: tip)

        drawHead(ctx, at: CGPoint(x: 98, y: 26), tilt: -0.25, eyes: .sleepy,
                 mouthOpen: 0, pointer: false, fangs: false)
        blob(ctx, CGPoint(x: 114, y: 15), 7, 4, fill: cream)
    }

    // Floating "Z"s (drawn unmirrored so the letters never flip)
    private func drawZs() {
        for i in 0..<3 {
            let t = (time * 0.45 + CGFloat(i) / 3).truncatingRemainder(dividingBy: 1)
            var x = 92 + t * 18
            if facing < 0 { x = bounds.width - x }
            let y = 40 + t * 40
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9 + t * 11, weight: .heavy),
                .foregroundColor: NSColor(srgbRed: 0.25, green: 0.40, blue: 0.90, alpha: sin(t * .pi))
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

    private var pos = CGPoint.zero            // between the cat's feet, global Cocoa coordinates
    private var vel = CGPoint.zero
    private var facing: CGFloat = 1
    private var alpha: CGFloat = 1
    private var sitting = false
    private var napSide: CGFloat = 1

    private var lastTick = CACurrentMediaTime()
    private var lastPointer = NSEvent.mouseLocation
    private var lastMoveTime = CACurrentMediaTime()
    private var cursorHeld = false

    /// When true, the real pointer is frozen in the cat's mouth during the 3-second hold.
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
                let spot = CGPoint(x: ptr.x + side * 90, y: ptr.y - 20)
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
            let spot = CGPoint(x: ptr.x + napSide * 75, y: ptr.y - 20)
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
    private var cat: CatController!
    private var statusItem: NSStatusItem!
    private var freezeItem: NSMenuItem!
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        cat = CatController()

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

    @objc private func callCat() { cat.callCat() }

    @objc private func toggleFreeze() {
        cat.freezeCursor.toggle()
        freezeItem.state = cat.freezeCursor ? .on : .off
    }

    @objc private func quit() {
        cat.releaseCursor()
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)      // no Dock icon; control it from the 🐱 menu bar item
app.run()

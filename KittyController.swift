// KittyController.swift  —  "Kitty Chasing Your Mouse"
// The kitty's brain: owns the transparent overlay window, runs the 60 fps loop and the
// state machine (chasing, biting, waiting, petting, napping, fading) using KittyView for drawing.

import Cocoa

// MARK: - Behaviour

final class KittyController: NSObject {
    private enum State { case gone, chasing, goingToNap, sleeping, waking, biting, petting, fading }

    private let window: NSWindow
    private let view: KittyView
    private var timer: Timer?

    private var state: State = .gone
    private var stateStart = CACurrentMediaTime()
    private var respawnDelay: Double = 1.0

    private var pos = CGPoint.zero            // between the kitty's feet, global Cocoa coordinates
    private var vel = CGPoint.zero
    private var facing: CGFloat = 1
    private var alpha: CGFloat = 1
    private var sitting = false               // true while the kitty is seated and waiting
    private var sitInPlace = false            // sit right where it is instead of walking to a spot
    private var napSide: CGFloat = 1
    private var noChaseUntil: Double = 0      // short pause after biting / petting before chasing again

    // Petting: scrub the pointer left-right over the seated kitty
    private var scrubDir: CGFloat = 0
    private var scrubExtreme: CGFloat = 0
    private var scrubReversals = 0
    private var scrubActive: Double = 0
    private let petReversalsNeeded = 5        // 5 direction changes = 3 full left-right scrubs
    private let petSweepDistance: CGFloat = 20

    private var lastTick = CACurrentMediaTime()
    private var lastPointer = NSEvent.mouseLocation
    private var lastMoveTime = CACurrentMediaTime()
    private var cursorHeld = false

    var respawnLater = true

    /// When true, the real pointer is frozen in the kitty's mouth during the 3-second hold.
    var freezeCursor = true
    private var handShown = false          // we have switched the cursor to the pointing hand

    override init() {
        let v = KittyView(frame: NSRect(origin: .zero, size: spriteSize))
        // A non-activating panel lets you click the kitty without stealing focus from your app.
        let w = NSPanel(contentRect: v.frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        w.contentView = v
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true           // switched off only while the pointer is over a clickable kitty
        w.acceptsMouseMovedEvents = true
        w.level = .screenSaver
        w.isFloatingPanel = true
        w.hidesOnDeactivate = false
        w.becomesKeyOnlyIfNeeded = true
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        view = v
        window = w
        super.init()

        v.onClick = { [weak self] in self?.kittyClicked() }

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: Public

    func callKitty() {
        guard state == .gone || state == .fading else { return }
        releaseCursor()
        spawn(near: NSEvent.mouseLocation)
    }

    // Resets respawnDelay and callKitty
    func recallKitty() {
        respawnDelay = 8
        callKitty()
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
        sitInPlace = false
        noChaseUntil = 0
        resetScrub(ptr.x)
        view.mouthOpen = 0
        view.lookUp = 0
        view.petting = false
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
        sitting = false
        sitInPlace = false
        view.showPointer = true
        if freezeCursor {
            _ = CGAssociateMouseAndMouseCursorPosition(0)   // pointer stops obeying the mouse
            cursorHeld = true
        }
        enter(.biting)
    }

    // MARK: Clicking

    /// Rect (screen coordinates) the seated kitty occupies. Also the area where petting works.
    private func seatedRect() -> CGRect {
        CGRect(x: pos.x - 40, y: pos.y - 4, width: 80, height: 88)
    }

    /// Rect covered by the kitty in its current pose.
    private func bodyRect() -> CGRect {
        let s = unitScale
        switch view.pose {
        case .sit:
            return seatedRect()
        case .sleep:
            let x0 = -36 * s, x1 = 46 * s
            let lo = facing > 0 ? x0 : -x1
            return CGRect(x: pos.x + lo, y: pos.y - 6, width: x1 - x0, height: 46 * s)
        case .run, .hold:
            let x0 = -40 * s, x1 = 42 * s
            let lo = facing > 0 ? x0 : -x1
            return CGRect(x: pos.x + lo, y: pos.y - 4, width: x1 - x0, height: 62 * s)
        }
    }

    /// Clicking the kitty only does something while it is eating, waiting, being petted or sleeping.
    private var isClickable: Bool {
        switch state {
        case .biting, .sleeping, .waking, .petting: return true
        case .chasing: return sitting
        default: return false
        }
    }

    private func kittyClicked() {
        guard isClickable else { return }
        releaseCursor()
        lastPointer = NSEvent.mouseLocation
        lastMoveTime = CACurrentMediaTime()
        view.showPointer = false
        view.petting = false
        view.lookUp = 0
        view.mouthOpen = 0
        enter(.fading)
    }

    // MARK: Petting (scrubbing the pointer left and right over the seated kitty)

    private func resetScrub(_ x: CGFloat) {
        scrubDir = 0
        scrubExtreme = x
        scrubReversals = 0
    }

    private func trackScrub(_ x: CGFloat, now: Double) {
        if scrubDir != 0 && now - scrubActive > 1.5 { resetScrub(x) }     // too slow: start over
        if scrubDir == 0 {
            if abs(x - scrubExtreme) > 6 {
                scrubDir = x > scrubExtreme ? 1 : -1
                scrubExtreme = x
                scrubActive = now
            }
            return
        }
        if scrubDir * (x - scrubExtreme) > 0 {                 // still travelling the same way
            scrubExtreme = x
            scrubActive = now
        } else if abs(x - scrubExtreme) > petSweepDistance {   // turned around: one sweep done
            scrubDir = -scrubDir
            scrubExtreme = x
            scrubReversals += 1
            scrubActive = now
        }
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
            if respawnDelay > 0 && t > respawnDelay { spawn(near: ptr) }
            return

        case .chasing:
            view.mouthOpen = 0
            view.lookUp = 0
            view.petting = false

            let onKitty = sitting && seatedRect().contains(ptr)
            if !onKitty { resetScrub(ptr.x) }

            if onKitty && idleFor < 30 {
                // Pointer is over the waiting kitty: it can be petted, but it won't be chased.
                vel = .zero
                view.pose = .sit
                trackScrub(ptr.x, now: now)

                if scrubReversals >= petReversalsNeeded {
                    resetScrub(ptr.x)
                    enter(.petting)
                    break
                }
            } else if now < noChaseUntil {
                // Just finished biting/petting: sit tight for a moment.
                vel = .zero
                sitting = true
                view.pose = .sit
            } else if moving {
                sitting = false
                sitInPlace = false
                if ptr.x > pos.x + 12 { facing = 1 } else if ptr.x < pos.x - 12 { facing = -1 }
                steer(to: CGPoint(x: ptr.x - facing * mouthRel.x, y: ptr.y - mouthRel.y),
                    maxSpeed: 800, dt: dt)
                let m = mouthPoint()
                if hypot(m.x - ptr.x, m.y - ptr.y) < 28 {
                    startBite(pointer: ptr)
                    break
                }
                view.pose = .run
            } else if idleFor >= 30 {
                napSide = pos.x >= ptr.x ? 1 : -1
                sitting = false
                sitInPlace = false
                enter(.goingToNap)
            } else if sitInPlace {
                // After a bite (or a nap) the kitty simply sits where it is and waits.
                vel = .zero
                sitting = true
                view.pose = .sit
            } else {
                // Pointer is still: wander over to a spot beside it and sit, waiting.
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
                sitting = true
                sitInPlace = true
                enter(.chasing)
            }

        case .biting:
            vel = .zero
            view.pose = .hold
            view.showPointer = true
            if t >= 3.0 {
                // Done eating: let go of the pointer and sit down (no more fading away).
                releaseCursor()
                lastPointer = NSEvent.mouseLocation
                lastMoveTime = now
                view.showPointer = false
                sitting = true
                sitInPlace = true
                noChaseUntil = now + 1.5
                resetScrub(lastPointer.x)
                enter(.chasing)
            }

        case .petting:
            // Happy howl: head tips back, mouth open, hearts float up.
            vel = .zero
            sitting = true
            view.pose = .sit
            view.petting = true
            let tt = CGFloat(t)
            let k = min(1, tt * 4)                                  // head tips back quickly
            let settle: CGFloat = tt > 2.2 ? max(0, 1 - (tt - 2.2) / 0.4) : 1
            view.lookUp = k * settle
            view.mouthOpen = (0.6 + 0.35 * sin(tt * 4)) * settle
            if t > 2.6 {
                view.petting = false
                view.lookUp = 0
                view.mouthOpen = 0
                sitInPlace = true
                noChaseUntil = now + 0.8
                resetScrub(ptr.x)
                enter(.chasing)
            }

        case .fading:
            // Clicked: fade away in whatever pose the kitty was in.
            view.showPointer = false
            view.mouthOpen = 0
            alpha = max(0, 1 - CGFloat(t) / 1.2)
            pos.y += dt * 25
            if alpha <= 0 {
                window.orderOut(nil)
                window.ignoresMouseEvents = true
                NSApp.terminate(nil)
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
        // The window only catches clicks while the pointer is over a clickable kitty.
        let hover = isClickable && bodyRect().contains(ptr)
        window.ignoresMouseEvents = !hover
        // Pointing hand over the waiting/sleeping kitty (not while it holds the pointer: the drawn
        // arrow in its mouth should match the real one).
        let wantHand = hover && state != .biting
        view.wantsHand = wantHand
        if wantHand {
            NSCursor.pointingHand.set()
            handShown = true
        } else if handShown {
            NSCursor.arrow.set()
            handShown = false
        }
        view.needsDisplay = true
    }
}

//
//  CharacterView.swift
//  chasing_your_mouse
//
//  Created by brian on 11/24/26.
//

import Cocoa

// Common constants

enum Pose { case run, hold, sit, sleep }
enum Eyes { case open, sleepy, happy }

let ink = NSColor(srgbRed: 0.255, green: 0.200, blue: 0.247, alpha: 1)   // outline / eyes

// Dimensions
let lineW: CGFloat = 1.7

@inline(__always) func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

class CharacterView: NSView {
    
    var pose: Pose = .sit
    var facing: CGFloat = 1          // +1 = right, -1 = left
    var phase: CGFloat = 0           // run-cycle phase
    var time: CGFloat = 0            // free-running animation clock
    var gait: CGFloat = 1            // 0…1 leg swing amplitude
    var mouthOpen: CGFloat = 0
    var showPointer = false
    var lookUp: CGFloat = 0          // 0…1, head tipped back for the happy howl
    var petting = false              // shows floating hearts
    var onClick: (() -> Void)?

    // MARK: Hand cursor
    /// Set by the controller each frame: true while the pointer is over a clickable/pettable kitty.
    var wantsHand = false
    
    // MARK: Overriding parent methods --------------------------
    
    override var isFlipped: Bool { false }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }

    
    // A tracking area with .activeAlways is what lets this (never-active) overlay window
    // receive enter/move/cursorUpdate events and change the cursor.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited,
                                                 .mouseMoved, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }
    override func cursorUpdate(with event: NSEvent) { if wantsHand { NSCursor.pointingHand.set() } }
    override func mouseMoved(with event: NSEvent)   { if wantsHand { NSCursor.pointingHand.set() } }
    override func mouseEntered(with event: NSEvent) { if wantsHand { NSCursor.pointingHand.set() } }
    override func mouseExited(with event: NSEvent)  { NSCursor.arrow.set() }

    
    // MARK: Inherited UI methods ------------------------------------
    
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
        if petting { drawHearts() }
    }
    
    // MARK: Common helper drawing
    public func inkStroke(_ p: NSBezierPath, _ w: CGFloat = lineW) {
        p.lineWidth = w
        p.lineCapStyle = .round
        p.lineJoinStyle = .round
        ink.setStroke()
        p.stroke()
    }

    func line(_ a: CGPoint, _ b: CGPoint, width: CGFloat, color: NSColor) {
        let p = NSBezierPath()
        p.move(to: a)
        p.line(to: b)
        p.lineWidth = width
        p.lineCapStyle = .round
        color.setStroke()
        p.stroke()
    }

    
    
    // MARK: Common actions ------------------------------------
    
    // Floating "Z"s (drawn unmirrored so the letters never flip)
    func drawZs() {
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
    
    // Floating hearts while being petted (drawn unmirrored, in sprite coordinates)
    func drawHearts() {
        let xs: [CGFloat] = [-26, 22, -8, 34]
        for i in 0..<4 {
            let t = (time * 0.8 + CGFloat(i) * 0.25).truncatingRemainder(dividingBy: 1)
            let cx = bounds.width / 2 + xs[i] + sin(time * 4 + CGFloat(i)) * 3
            let cy = 92 + t * 38
            let s = 3.5 + 1.5 * CGFloat(i % 2)
            let h = NSBezierPath()
            h.move(to: P(cx, cy - s))
            h.curve(to: P(cx - s, cy + s * 0.25), controlPoint1: P(cx - s * 0.5, cy - s * 0.55), controlPoint2: P(cx - s, cy - s * 0.2))
            h.curve(to: P(cx, cy + s * 0.45),     controlPoint1: P(cx - s, cy + s * 0.95),       controlPoint2: P(cx - s * 0.15, cy + s * 0.95))
            h.curve(to: P(cx + s, cy + s * 0.25), controlPoint1: P(cx + s * 0.15, cy + s * 0.95), controlPoint2: P(cx + s, cy + s * 0.95))
            h.curve(to: P(cx, cy - s),            controlPoint1: P(cx + s, cy - s * 0.2),        controlPoint2: P(cx + s * 0.5, cy - s * 0.55))
            h.close()
            let a = sin(t * .pi)
            NSColor(srgbRed: 1.0, green: 0.42, blue: 0.56, alpha: a).setFill()
            h.fill()
            ink.withAlphaComponent(a).setStroke()
            h.lineWidth = 0.9
            h.lineJoinStyle = .round
            h.stroke()
        }
    }
    
    // To be implemented -------------------------------

    // MARK: Running / walking / standing with the pointer in its mouth

    func drawRunner(_ ctx: CGContext, holding: Bool) {
    }

    // MARK: Sitting and watching (also the yawn when waking up)

    func drawSit(_ ctx: CGContext) {
        
    }

    // MARK: Curled up asleep

    func drawSleep(_ ctx: CGContext) {
    }

}

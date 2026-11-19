/* A demo application to test how a window program can have cursor changed dynamically.
*/
import Cocoa

class ViewController: NSViewController {
    
    var cursor: NSCursor?
    let subframe = CGRect(x: 100, y: 100, width: 300, height: 100)
  
    override func loadView() {
        let subview = NSView(frame: subframe)
        subview.wantsLayer = true
        subview.layer!.backgroundColor = NSColor.red.cgColor
        view = NSView(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        view.addSubview(subview)
        view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .cursorUpdate, .mouseMoved], owner: self))
    }
    
    override func mouseMoved(with event: NSEvent) {
        if subframe.contains(view.convert(event.locationInWindow, from: nil)) {
            if cursor == nil {
                cursor = .openHand
                cursor!.push()
                print("set cursor")
            }
        } else if let cursor = cursor {
            cursor.pop()
            cursor = nil
            print("unset cursor")
        }
    }
    
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "My App"
        window.makeKeyAndOrderFront(nil)
        
        // Set up your view controller
        let viewController = ViewController()
        viewController.view.autoresizingMask = [.width, .height]
        window.contentViewController = viewController
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)      // no Dock icon; control it from the 🐱 menu bar item
app.run()


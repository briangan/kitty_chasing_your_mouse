//
//  ChasingYourMouse.swift
//  chasing_your_mouse
//
//  Created by brian on 11/23/26.
//

import Cocoa
import SwiftUI

let VERSION = "0.1"
let APP_NAME = "Chasing Your Mouse"

// A background (accessory) app is normally not allowed to change the cursor: the window server
// keeps resetting it to the active app's cursor, which is why NSCursor.set()/push() did nothing.
// This private CoreGraphics connection property lifts that restriction.
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(_ cid: Int32, _ targetCID: Int32, _ key: CFString, _ value: CFTypeRef) -> Int32

private func allowCursorChangesInBackground() {
    let cid = CGSMainConnectionID()
    _ = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var characterCtrl: CharacterController!
    private var statusItem: NSStatusItem!
    private var charactersMenu: NSMenu!
    private var respawnLaterItem: NSMenuItem!
    private var freezeItem: NSMenuItem!
    private var signalSources: [DispatchSourceSignal] = []
    private var aboutWindow: NSWindow?   // <-- keep a reference so it doesn’t de‑allocate

    func applicationDidFinishLaunching(_ notification: Notification) {
        allowCursorChangesInBackground()
        characterCtrl = CharacterController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐱"

        let menu = NSMenu()
        let aboutVersion = NSMenuItem(title: "About \(APP_NAME)", action: #selector(aboutDialog), keyEquivalent: "")
        menu.addItem(aboutVersion)

        let call = NSMenuItem(title: "Call the Character", action: #selector(callCharacter), keyEquivalent: "")
        call.target = self
        menu.addItem(call)

        // Characters submenu
        charactersMenu = NSMenu()
        let kittyItem = NSMenuItem(title: "Kitty", action: #selector(switchToKitty), keyEquivalent: "")
        kittyItem.target = self
        kittyItem.state = .on
        
        let puppyItem = NSMenuItem(title: "Puppy", action: #selector(switchToPuppy), keyEquivalent: "")
        puppyItem.target = self
        charactersMenu.addItem(kittyItem)
        charactersMenu.addItem(puppyItem)
        let menuItemForSubmenu = NSMenuItem(title: "Which Character", action: nil, keyEquivalent: "")
        menuItemForSubmenu.submenu = charactersMenu
        menu.addItem(menuItemForSubmenu)

        respawnLaterItem = NSMenuItem(title: "Respawn Character Later?",
                                action: #selector(toggleRespawnLater), keyEquivalent: "")
        respawnLaterItem.target = self
        syncRespawnLaterToMenu()
        menu.addItem(respawnLaterItem)

        freezeItem = NSMenuItem(title: "Hold Pointer in Mouth When Caught?",
                                action: #selector(toggleFreezeCursor), keyEquivalent: "")
        freezeItem.target = self
        freezeItem.state = .on // will toggle
        syncFreezeCursorToMenu()
        menu.addItem(freezeItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit \(APP_NAME)", action: #selector(quit), keyEquivalent: "q")
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

    @objc private func aboutDialog() {
        if let window = aboutWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 410, height: 260),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.center()
        window.title = "About \(APP_NAME)"
        window.level = .floating                // keep it above other windows
        window.collectionBehavior = [.canJoinAllSpaces]
        window.contentView = NSHostingView(rootView: AboutView())
        window.makeKeyAndOrderFront(nil)
        aboutWindow = window
    }
    
    @objc public func closeAboutWindow() {
        self.aboutWindow = nil
    }

    @objc private func callCharacter() { characterCtrl.callCharacter() }

    @objc private func toggleRespawnLater() {
        characterCtrl.respawnLater.toggle()
        syncRespawnLaterToMenu()
    }
    
    @objc private func syncRespawnLaterToMenu() {
        respawnLaterItem.state = characterCtrl.respawnLater ? .on : .off
        if characterCtrl.respawnLater {
            characterCtrl.recallCharacter()
        }
    }

    @objc private func toggleFreezeCursor() {
        characterCtrl.freezeCursor.toggle()
        syncFreezeCursorToMenu()
    }
    
    @objc private func syncFreezeCursorToMenu() {
        freezeItem.state = characterCtrl.freezeCursor ? .on : .off
    }

    @objc private func quit() {
        print(".. Quiting ..")
        characterCtrl.releaseCursor()
        NSApp.terminate(nil)
    }
    
    @objc private func selectInCharactersSubmenu(_ character: String) {
        for item in charactersMenu.items {
            item.state = item.title == character ? .on : .off
        }
    }
    
    @objc private func switchToKitty() {
        selectInCharactersSubmenu("Kitty")
        characterCtrl.switchToCharacter(.kitty)
    }
    
    @objc private func switchToPuppy() {
        selectInCharactersSubmenu("Puppy")
        characterCtrl.switchToCharacter(.puppy)
    }
}

@main
struct ChasingYourMouseApp: App {

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)      // no Dock icon; control it from the 🐱 menu bar item
        app.run()
    }

    var body: some Scene {
        WindowGroup {
        }
    }
}

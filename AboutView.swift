import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text(APP_NAME)
                .font(.largeTitle)
                .bold()

            Text("Version \(VERSION)")
                .font(.title3)

            Spacer()

            Text("© 2026 Brian Gan — A charming kitty adventure.")
                .font(.footnote)

            Button("Close") {
                // Close the about window
                NSApp.keyWindow?.close()
                // Clear the cached reference
                if let delegate = NSApplication.shared.delegate as? AppDelegate {
                    delegate.closeAboutWindow()
                }
            }
            .padding(.top, 10)
        }
        .padding(30)
        .frame(minWidth: 380, minHeight: 240)
    }
}

import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // One window only: this also removes "Show Tab Bar" / "Show All Tabs" from the View menu.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MidiPassthroughApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A single-instance window scene has no "New Window" command.
        Window("Midi Passthrough", id: "main") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

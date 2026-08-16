import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // Kinetag is desktop-first. Give the window an explicit default size and
    // a minimum that keeps the court readable next to the setup inspector,
    // rather than inheriting whatever frame the nib or a stale autosaved
    // position supplies (which can land off-screen on multi-display Macs).
    self.minSize = NSSize(width: 900, height: 600)
    self.setContentSize(NSSize(width: 1440, height: 900))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    // Ensure the window actually reaches the active Space on launch.
    self.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }
}

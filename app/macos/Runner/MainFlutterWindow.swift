import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame

    // Пока Flutter не нарисовал первый кадр, окно должно быть цвета фона
    // главного экрана (K.bgTop), а не белым.
    let background = NSColor(srgbRed: 12 / 255, green: 16 / 255, blue: 22 / 255, alpha: 1)
    self.backgroundColor = background
    flutterViewController.backgroundColor = background

    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

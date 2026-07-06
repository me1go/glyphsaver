// Loads the built .saver the way the system would (NSBundle + NSPrincipalClass),
// instantiates the view, animates it briefly, and checks pixels actually render.
// Usage: swift scripts/verify-bundle.swift build/GlyphSaver.saver

import AppKit
import ScreenSaver

func fail(_ msg: String) -> Never {
    print("VERIFY FAILED: \(msg)")
    exit(1)
}

guard CommandLine.arguments.count > 1 else { fail("usage: verify-bundle.swift <path.saver>") }
let path = CommandLine.arguments[1]

guard let bundle = Bundle(path: path) else { fail("Bundle(path:) returned nil for \(path)") }
guard bundle.load() else { fail("bundle.load() failed — Mach-O type or signing problem") }
guard let principal = bundle.principalClass else { fail("no principal class — NSPrincipalClass mismatch") }
print("principal class: \(principal)")

guard let saverClass = principal as? ScreenSaverView.Type else {
    fail("principal class is not a ScreenSaverView subclass")
}
guard let view = saverClass.init(frame: NSRect(x: 0, y: 0, width: 800, height: 500),
                                 isPreview: false) else {
    fail("init(frame:isPreview:) returned nil")
}
print("instantiated: \(view)")
guard view.hasConfigureSheet else { fail("hasConfigureSheet is false") }

view.startAnimation()
RunLoop.main.run(until: Date(timeIntervalSinceNow: 2.0))

guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
    fail("could not create bitmap rep")
}
view.cacheDisplay(in: view.bounds, to: rep)
view.stopAnimation()

// After 2s of matrix/decrypt/overflow, the frame must contain non-background pixels.
var litPixels = 0
for _ in 0..<2000 {
    let x = Int.random(in: 0..<rep.pixelsWide)
    let y = Int.random(in: 0..<rep.pixelsHigh)
    if let color = rep.colorAt(x: x, y: y),
       color.redComponent + color.greenComponent + color.blueComponent > 0.25 {
        litPixels += 1
    }
}
print("lit pixel samples: \(litPixels)/2000")
guard litPixels > 10 else { fail("rendered frame looks empty — animation not drawing") }

print("VERIFY OK — bundle loads, animates, and draws")
exit(0)

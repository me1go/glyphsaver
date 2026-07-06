import AppKit
import ImageIO
import UniformTypeIdentifiers
import GlyphSaverCore
import GlyphSaverKit

// Dev harness for GlyphSaver. Modes:
//   glyphsaver-preview                      window (n=next effect, t=next theme, q=quit)
//   glyphsaver-preview --snapshot <dir> [--effect NAME] [--theme ID] [--size WxH]
//                      [--times 1,3,5,...]  headless PNG frames for visual checks
//   glyphsaver-preview --bench [--size WxH] [--seconds N] [--scale 2]
//                                           frame-time report (step vs draw)
//   glyphsaver-preview --soak <seconds>     headless run, prints RSS growth

let args = CommandLine.arguments

func argValue(_ flag: String) -> String? {
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func parseSize(_ s: String?) -> CGSize {
    guard let s, let x = s.firstIndex(of: "x"),
          let w = Double(s[..<x]), let h = Double(s[s.index(after: x)...]) else {
        return CGSize(width: 1600, height: 900)
    }
    return CGSize(width: w, height: h)
}

func makeConfig() -> Config {
    var config = Config.default
    if let effect = argValue("--effect") { config.enabledEffects = [effect] }
    if let theme = argValue("--theme") { config.theme = theme }
    if let speed = argValue("--speed").flatMap(Double.init) { config.speed = speed }
    if let font = argValue("--font").flatMap(Double.init) { config.fontSize = font }
    if let text = argValue("--text") { config.artTexts = [text] }
    if args.contains("--reduced-motion") { config.reducedMotion = true }
    return config.sanitized
}

// MARK: - Headless rendering shared by snapshot/bench/soak

struct HeadlessRig {
    let controller: AnimationController
    let renderer: GlyphRenderer
    let ctx: CGContext
    let pointSize: CGSize
    let scale: CGFloat

    init(config: Config, pixelSize: CGSize, scale: CGFloat, seed: UInt64) {
        self.scale = scale
        self.pointSize = CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
        let fontSize = GlyphSaverContentView.fittedFontSize(for: pointSize, config: config)
        self.renderer = GlyphRenderer(fontSize: fontSize)
        let cols = max(Int(pointSize.width / renderer.metrics.cellWidth), 1)
        let rows = max(Int(pointSize.height / renderer.metrics.cellHeight), 1)
        self.controller = AnimationController(cols: cols, rows: rows, config: config, seed: seed)
        guard let ctx = CGContext(
            data: nil,
            width: Int(pixelSize.width), height: Int(pixelSize.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("could not create bitmap context")
        }
        ctx.scaleBy(x: scale, y: scale)
        self.ctx = ctx
        print("grid \(cols)x\(rows) @ font \(String(format: "%.1f", fontSize))pt, " +
              "\(Int(pixelSize.width))x\(Int(pixelSize.height))px scale \(Int(scale))x")
    }

    func drawFrame() {
        renderer.draw(canvas: controller.canvas, background: controller.background,
                      in: ctx, size: pointSize)
    }

    func writePNG(to url: URL) {
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("could not create PNG at \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}

func residentMemoryMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    guard kr == KERN_SUCCESS else { return -1 }
    return Double(info.phys_footprint) / 1_048_576
}

// MARK: - Snapshot mode

if let dir = argValue("--snapshot") {
    let outDir = URL(fileURLWithPath: dir, isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let config = makeConfig()
    let times = (argValue("--times") ?? "1,2.5,4.5,6.5,8,10,12,14")
        .split(separator: ",").compactMap { Double($0) }.sorted()
    let rig = HeadlessRig(config: config, pixelSize: parseSize(argValue("--size")),
                          scale: CGFloat(argValue("--scale").flatMap(Double.init) ?? 1),
                          seed: UInt64(argValue("--seed").flatMap(Int.init) ?? 42))
    let dt = 1.0 / 60.0
    var t = 0.0
    let label = "\(config.enabledEffects.joined(separator: "+"))-\(config.theme)"
    for target in times {
        while t < target {
            rig.controller.step(dt: dt)
            t += dt
        }
        rig.drawFrame()
        let name = String(format: "%@-t%04.1f.png", label, target)
        rig.writePNG(to: outDir.appendingPathComponent(name))
        print("wrote \(name)  (effect: \(rig.controller.currentEffect?.name ?? "-"))")
    }
    exit(0)
}

// MARK: - Bench mode

if args.contains("--bench") {
    let config = makeConfig()
    let seconds = argValue("--seconds").flatMap(Double.init) ?? 12
    let scale = CGFloat(argValue("--scale").flatMap(Double.init) ?? 2)
    let pixelSize = parseSize(argValue("--size") ?? "3840x2160")
    let rig = HeadlessRig(config: config, pixelSize: pixelSize, scale: scale, seed: 42)
    let dt = 1.0 / 60.0
    let frames = Int(seconds / dt)
    var stepTimes: [Double] = []
    var drawTimes: [Double] = []
    stepTimes.reserveCapacity(frames)
    drawTimes.reserveCapacity(frames)
    for _ in 0..<frames {
        let t0 = CACurrentMediaTime()
        rig.controller.step(dt: dt)
        let t1 = CACurrentMediaTime()
        rig.drawFrame()
        let t2 = CACurrentMediaTime()
        stepTimes.append((t1 - t0) * 1000)
        drawTimes.append((t2 - t1) * 1000)
    }
    func stats(_ xs: [Double]) -> String {
        let sorted = xs.sorted()
        let avg = xs.reduce(0, +) / Double(xs.count)
        let p95 = sorted[Int(Double(xs.count) * 0.95)]
        let worst = sorted.last ?? 0
        return String(format: "avg %6.2fms  p95 %6.2fms  max %6.2fms", avg, p95, worst)
    }
    let totals = zip(stepTimes, drawTimes).map(+)
    print("frames: \(frames) simulated at 60fps")
    print("step:  \(stats(stepTimes))")
    print("draw:  \(stats(drawTimes))")
    print("total: \(stats(totals))  (budget 16.67ms)")
    let over = totals.filter { $0 > 16.67 }.count
    print("frames over budget: \(over) (\(String(format: "%.2f", 100 * Double(over) / Double(frames)))%)")
    exit(0)
}

// MARK: - Soak mode

if let secs = argValue("--soak").flatMap(Double.init) {
    let config = makeConfig()
    let rig = HeadlessRig(config: config, pixelSize: parseSize(argValue("--size")),
                          scale: 1, seed: 42)
    let dt = 1.0 / 60.0
    var t = 0.0
    var nextReport = 0.0
    let start = residentMemoryMB()
    print(String(format: "start RSS %.1f MB", start))
    while t < secs {
        rig.controller.step(dt: dt)
        rig.drawFrame()
        t += dt
        if t >= nextReport {
            print(String(format: "t=%5.0fs  RSS %.1f MB", t, residentMemoryMB()))
            nextReport += 30
        }
    }
    let end = residentMemoryMB()
    print(String(format: "end RSS %.1f MB (delta %+.1f MB)", end, end - start))
    exit(0)
}

// MARK: - Window mode

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var contentView: GlyphSaverContentView!
    var themeIndex = 0
    var config = makeConfig()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rect = NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = NSWindow(contentRect: rect,
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "GlyphSaver Preview — n: effect, t: theme, q: quit"
        rebuildContent()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            switch event.charactersIgnoringModifiers {
            case "n":
                self.contentView.skipToNextEffect()
                return nil
            case "t":
                self.themeIndex = (self.themeIndex + 1) % Theme.all.count
                self.config.theme = Theme.all[self.themeIndex].id
                self.rebuildContent()
                return nil
            case "q":
                NSApp.terminate(nil)
                return nil
            default:
                return event
            }
        }
    }

    func rebuildContent() {
        contentView?.stopDriving()
        contentView = GlyphSaverContentView(
            frame: window.contentView!.bounds,
            config: config,
            seed: UInt64.random(in: 0...UInt64.max)
        )
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView
        contentView.startDriving()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

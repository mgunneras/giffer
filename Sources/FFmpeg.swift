import AppKit
import Foundation

struct VideoInfo {
    let url: URL
    let width: Int
    let height: Int
    let duration: Double
    let fps: Double
    let fileSize: Int64
}

enum Dither: String, Codable, CaseIterable, Identifiable {
    case smooth, pattern, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .smooth: return "Smooth"
        case .pattern: return "Pattern"
        case .none: return "None"
        }
    }
    var filter: String {
        switch self {
        case .smooth: return "sierra2_4a"
        case .pattern: return "bayer:bayer_scale=5"
        case .none: return "none"
        }
    }
    var sizeFactor: Double {
        switch self {
        case .smooth: return 1.3
        case .pattern: return 1.0
        case .none: return 0.7
        }
    }
}

enum Format: String, Codable, CaseIterable, Identifiable {
    case gif, webp, avif, apng
    var id: String { rawValue }
    var label: String {
        switch self {
        case .gif: return "GIF"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        case .apng: return "APNG"
        }
    }
    /// APNG files use .png so that every app and upload form accepts them.
    var fileExtension: String { self == .apng ? "png" : rawValue }
    var mimeType: String { "image/\(rawValue)" }
    var hasQuality: Bool { self == .webp || self == .avif }
    /// Rough bytes per pixel per frame before calibration.
    var bytesPerPixel: Double {
        switch self {
        case .gif: return 0.06
        case .webp: return 0.025
        case .avif: return 0.008
        case .apng: return 0.3
        }
    }
}

enum Quality: String, Codable, CaseIterable, Identifiable {
    case low, medium, high, best
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var webp: Int { [.low: 45, .medium: 65, .high: 80, .best: 92][self]! }
    var crf: Int { [.low: 48, .medium: 40, .high: 32, .best: 24][self]! }
    var sizeFactor: Double { [.low: 0.6, .medium: 1.0, .high: 1.6, .best: 2.6][self]! }
}

struct Settings: Codable, Equatable {
    var format = Format.gif
    var fps = 15
    var width = 960          // 0 = original
    var colors = 256
    var dither = Dither.pattern
    var quality = Quality.medium
    var speed = 1.0

    init() {}

    // Tolerates settings saved by older versions that lack newer keys.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = (try? c.decode(Format.self, forKey: .format)) ?? format
        fps = (try? c.decode(Int.self, forKey: .fps)) ?? fps
        width = (try? c.decode(Int.self, forKey: .width)) ?? width
        colors = (try? c.decode(Int.self, forKey: .colors)) ?? colors
        dither = (try? c.decode(Dither.self, forKey: .dither)) ?? dither
        quality = (try? c.decode(Quality.self, forKey: .quality)) ?? quality
        speed = (try? c.decode(Double.self, forKey: .speed)) ?? speed
    }
}

/// Everything ffmpeg needs, resolved from settings + the source video.
struct Plan {
    let source: URL
    let start: Double
    let length: Double       // seconds of source used
    let trimsEnd: Bool
    let fps: Int
    let outW: Int
    let outH: Int
    let previewW: Int
    let previewH: Int
    let frames: Int
    let colors: Int
    let speed: Double
    let dither: Dither
    let format: Format
    let quality: Quality

    init(info: VideoInfo, settings: Settings, trimStart: Double, trimEnd: Double) {
        source = info.url
        let s = min(max(0, trimStart), max(0, info.duration - 0.05))
        let e = min(max(s + 0.05, trimEnd), info.duration)
        start = s
        length = e - s
        trimsEnd = e < info.duration - 0.01
        speed = settings.speed
        // No point emitting more frames than the source has.
        let cap = max(1, Int((info.fps * settings.speed).rounded()))
        fps = max(1, min(settings.fps, cap))
        let w = (settings.width == 0 || settings.width >= info.width) ? info.width : settings.width
        format = settings.format
        quality = settings.quality
        var ow = max(2, w)
        var oh = max(2, Int((Double(info.height) * Double(ow) / Double(info.width)).rounded()))
        if format == .avif { ow = max(2, ow & ~1); oh = max(2, oh & ~1) }   // AV1 4:2:0 needs even sizes
        outW = ow
        outH = oh
        let k = min(1, 400.0 / Double(outW), 300.0 / Double(outH))
        previewW = max(2, Int(Double(outW) * k))
        previewH = max(2, Int(Double(outH) * k))
        frames = max(1, Int((length / speed * Double(fps)).rounded(.up)))
        colors = settings.colors
        dither = settings.dither
    }

    var outputDuration: Double { length / speed }

    /// Uncalibrated guess at the output size in bytes.
    var rawEstimate: Double {
        var bytesPerPixel = format.bytesPerPixel
        if format == .gif { bytesPerPixel *= (log2(Double(colors)) / 8.0) * dither.sizeFactor }
        if format.hasQuality { bytesPerPixel *= quality.sizeFactor }
        return Double(outW * outH) * Double(frames) * bytesPerPixel
    }

    private var inputArgs: [String] {
        var a = ["-hide_banner", "-loglevel", "error", "-nostdin", "-y"]
        if start > 0.001 { a += ["-ss", String(format: "%.3f", start)] }
        if trimsEnd { a += ["-t", String(format: "%.3f", length)] }
        return a + ["-i", source.path]
    }

    private var chain: String {
        var f = "[0:v:0]"
        if speed != 1 { f += String(format: "setpts=PTS/%.3f,", speed) }
        return f + "fps=\(fps),scale=\(outW):\(outH):flags=lanczos"
    }

    private var previewOut: [String] {
        ["-map", "[v]", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"]
    }

    struct Pass {
        let stage: String
        let weight: Double
        let args: [String]
    }

    /// The ffmpeg runs needed to produce `output`. `workDir` holds intermediates.
    func passes(workDir: URL, output: URL) -> [Pass] {
        if format == .gif {
            let palette = workDir.appendingPathComponent("palette.png")
            let analyse = "\(chain),split[a][b];"
                + "[a]palettegen=max_colors=\(colors):stats_mode=diff[p];"
                + "[b]scale=\(previewW):\(previewH)[v]"
            let encode = "\(chain)[x];"
                + "[x][1:v]paletteuse=dither=\(dither.filter):diff_mode=rectangle,split[g][q];"
                + "[q]scale=\(previewW):\(previewH):flags=neighbor[v]"
            return [
                Pass(stage: "Analysing colours", weight: 0.35,
                     args: inputArgs + ["-filter_complex", analyse,
                                        "-map", "[p]", "-update", "1", "-frames:v", "1", palette.path]
                         + previewOut),
                Pass(stage: "Encoding GIF", weight: 0.65,
                     args: inputArgs + ["-i", palette.path, "-filter_complex", encode,
                                        "-map", "[g]", "-loop", "0", "-f", "gif", output.path]
                         + previewOut),
            ]
        }
        let encoder: [String]
        switch format {
        case .webp:
            encoder = ["-c:v", "libwebp_anim", "-pix_fmt", "yuv420p", "-lossless", "0",
                       "-q:v", "\(quality.webp)", "-compression_level", "4", "-loop", "0", "-f", "webp"]
        case .avif:
            encoder = ["-c:v", "libsvtav1", "-pix_fmt", "yuv420p", "-crf", "\(quality.crf)",
                       "-preset", "8", "-loop", "0", "-f", "avif"]
        default:
            encoder = ["-c:v", "apng", "-pix_fmt", "rgb24", "-plays", "0", "-f", "apng"]
        }
        let graph = "\(chain),split[g][q];[q]scale=\(previewW):\(previewH)[v]"
        return [Pass(stage: "Encoding \(format.label)", weight: 1,
                     args: inputArgs + ["-filter_complex", graph, "-map", "[g]"] + encoder + [output.path]
                         + previewOut)]
    }
}

struct GifferError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct Cancelled: Error {}

enum FFmpeg {
    struct Tools {
        let ffmpeg: String
        let ffprobe: String
    }

    static func locate() -> Tools? {
        // Debug aid: pretend ffmpeg is missing to see the install instructions.
        if ProcessInfo.processInfo.environment["GIFFER_NO_FFMPEG"] != nil { return nil }
        let home = NSHomeDirectory()
        // The copy shipped inside the app comes first, so everyone runs the same version.
        var dirs = [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers").path,
                    "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
                    "\(home)/.local/bin", "\(home)/bin"]
        dirs += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let fm = FileManager.default
        for dir in dirs {
            let a = "\(dir)/ffmpeg", b = "\(dir)/ffprobe"
            if fm.isExecutableFile(atPath: a), fm.isExecutableFile(atPath: b) {
                return Tools(ffmpeg: a, ffprobe: b)
            }
        }
        return nil
    }

    private static func capture(_ exe: String, _ args: [String]) throws -> (Int32, Data, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        var errData = Data()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            errData = err.fileHandleForReading.readDataToEndOfFile()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        group.wait()
        return (p.terminationStatus, data, String(decoding: errData, as: UTF8.self))
    }

    static func probe(_ url: URL, tools: Tools) throws -> VideoInfo {
        let (status, data, err) = try capture(tools.ffprobe, [
            "-v", "error", "-select_streams", "v:0",
            "-show_streams", "-show_format", "-of", "json", url.path,
        ])
        guard status == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stream = (json["streams"] as? [[String: Any]])?.first,
              var w = stream["width"] as? Int, var h = stream["height"] as? Int, w > 0, h > 0
        else {
            let detail = err.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GifferError(message: detail.isEmpty ? "No video track found in this file." : detail)
        }
        // ffmpeg auto-rotates, so report the displayed orientation.
        if let side = stream["side_data_list"] as? [[String: Any]] {
            for item in side {
                if let r = (item["rotation"] as? NSNumber)?.intValue, abs(r) % 180 == 90 { swap(&w, &h) }
            }
        }
        func rate(_ key: String) -> Double? {
            guard let s = stream[key] as? String else { return nil }
            let parts = s.split(separator: "/").compactMap { Double($0) }
            if parts.count == 2, parts[1] > 0, parts[0] > 0 { return parts[0] / parts[1] }
            return nil
        }
        var fps = rate("avg_frame_rate") ?? rate("r_frame_rate") ?? 30
        if fps > 240 || fps < 1 { fps = rate("r_frame_rate") ?? 30 }
        if fps > 240 || fps < 1 { fps = 30 }
        let format = json["format"] as? [String: Any]
        let duration = Double(format?["duration"] as? String ?? "")
            ?? Double(stream["duration"] as? String ?? "") ?? 0
        guard duration > 0 else { throw GifferError(message: "Could not read the video's duration.") }
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        return VideoInfo(url: url, width: w, height: h, duration: duration, fps: fps, fileSize: size)
    }

    static func poster(_ url: URL, tools: Tools) -> NSImage? {
        guard let (status, data, _) = try? capture(tools.ffmpeg, [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-i", url.path,
            "-frames:v", "1", "-vf", "scale=320:-2", "-f", "image2pipe", "-c:v", "png", "pipe:1",
        ]), status == 0 else { return nil }
        return NSImage(data: data)
    }
}

/// One two-pass conversion. `run` blocks; call it off the main thread.
final class Conversion {
    let plan: Plan
    let tools: FFmpeg.Tools
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    init(plan: Plan, tools: FFmpeg.Tools) {
        self.plan = plan
        self.tools = tools
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let p = process
        lock.unlock()
        p?.terminate()
    }

    /// progress(fraction 0...1, stage, latest preview frame or nil)
    func run(to destination: URL, progress: @escaping (Double, String, CGImage?) -> Void) throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("giffer-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let out = tmp.appendingPathComponent("out.\(plan.format.fileExtension)")

        var done = 0.0
        for step in plan.passes(workDir: tmp, output: out) {
            let base = done
            try pass(step.args) { f, img in progress(base + f * step.weight, step.stage, img) }
            done += step.weight
        }

        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: out, to: destination)
    }

    private func pass(_ args: [String], onFrame: (Double, CGImage?) -> Void) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tools.ffmpeg)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err

        lock.lock()
        if cancelled { lock.unlock(); throw Cancelled() }
        process = p
        lock.unlock()
        try p.run()

        var errData = Data()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            errData = err.fileHandleForReading.readDataToEndOfFile()
        }

        // The preview stream is raw RGB at a known size, so frames are fixed-length chunks.
        let frameBytes = plan.previewW * plan.previewH * 3
        var buffer = [UInt8]()
        var count = 0
        var lastUpdate = Date.distantPast
        while true {
            let chunk = out.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(contentsOf: chunk)
            let whole = buffer.count / frameBytes
            guard whole > 0 else { continue }
            count += whole
            let now = Date()
            if now.timeIntervalSince(lastUpdate) > 0.06 {
                lastUpdate = now
                let lastStart = (whole - 1) * frameBytes
                let image = makeImage(Array(buffer[lastStart ..< lastStart + frameBytes]))
                onFrame(min(1, Double(count) / Double(plan.frames)), image)
            }
            buffer.removeFirst(whole * frameBytes)
        }
        p.waitUntilExit()
        group.wait()

        lock.lock()
        let wasCancelled = cancelled
        process = nil
        lock.unlock()
        if wasCancelled { throw Cancelled() }
        guard p.terminationStatus == 0 else {
            let text = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = text.split(separator: "\n").suffix(4).joined(separator: "\n")
            throw GifferError(message: tail.isEmpty ? "ffmpeg exited with status \(p.terminationStatus)." : tail)
        }
        onFrame(1, nil)
    }

    private func makeImage(_ bytes: [UInt8]) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: plan.previewW, height: plan.previewH,
                       bitsPerComponent: 8, bitsPerPixel: 24, bytesPerRow: plan.previewW * 3,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }
}

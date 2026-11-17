import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private func bytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

private func seconds(_ t: Double) -> String {
    t < 60 ? String(format: "%.1f s", t) : String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var targeted = false

    var body: some View {
        Group {
            switch model.phase {
            case .missingFFmpeg: MissingFFmpegView(model: model)
            case .idle: DropZone(model: model, targeted: targeted)
            case .probing: ProgressView("Reading video…").padding(50)
            case .options: OptionsView(model: model)
            case .converting: ConvertingView(model: model)
            case .done: DoneView(model: model)
            case .failed(let message): FailedView(model: model, message: message)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { model.open(url) } }
            }
            return true
        }
    }
}

struct DropZone: View {
    @ObservedObject var model: AppModel
    let targeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Poster().frame(height: PosterView.height)
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1).padding(.top, 30)
            HStack(spacing: 12) {
                Button("Choose File…") { model.chooseFile() }
                Text("or drop it on the Dock icon.\nThe result is saved next to the video.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(Color(red: 0.90, green: 0.08, blue: 0.11)).frame(width: 12, height: 12)
            }
            .padding(.top, 16)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(targeted ? Color.accentColor : Color.secondary.opacity(0.4),
                              style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
        )
    }
}

struct OptionsView: View {
    @ObservedObject var model: AppModel
    private let widths = [1600, 1280, 960, 800, 640, 480, 320]

    var body: some View {
        if let info = model.info, let plan = model.plan {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Group {
                        if let poster = model.poster {
                            Image(nsImage: poster).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Rectangle().fill(.quaternary)
                        }
                    }
                    .frame(width: 96, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(info.url.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
                        Text(verbatim: "\(info.width) × \(info.height) · \(Int(info.fps.rounded())) fps · \(seconds(info.duration)) · \(bytes(info.fileSize))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        label("Format")
                        Picker("", selection: $model.settings.format) {
                            ForEach(Format.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden()
                    }
                    GridRow {
                        label("Frame rate")
                        Picker("", selection: $model.settings.fps) {
                            ForEach([5, 8, 10, 12, 15, 20, 24, 30], id: \.self) { Text("\($0) fps").tag($0) }
                        }.labelsHidden().fixedSize()
                    }
                    GridRow {
                        label("Width")
                        Picker("", selection: widthBinding(info)) {
                            Text(verbatim: "Original (\(info.width) px)").tag(0)
                            ForEach(widths.filter { $0 < info.width }, id: \.self) { Text(verbatim: "\($0) px").tag($0) }
                        }.labelsHidden().fixedSize()
                    }
                    if model.settings.format == .gif {
                        GridRow {
                            label("Colours")
                            Picker("", selection: $model.settings.colors) {
                                ForEach([256, 128, 64, 32], id: \.self) { Text(verbatim: "\($0)").tag($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                        }
                        GridRow {
                            label("Dithering")
                            Picker("", selection: $model.settings.dither) {
                                ForEach(Dither.allCases) { Text($0.label).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                                .help("Smooth looks best on footage. None is smallest and suits screen recordings.")
                        }
                    } else if model.settings.format.hasQuality {
                        GridRow {
                            label("Quality")
                            Picker("", selection: $model.settings.quality) {
                                ForEach(Quality.allCases) { Text($0.label).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                        }
                    } else {
                        GridRow {
                            label("Quality")
                            Text("Lossless. Files are large; lower the width and frame rate.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    GridRow {
                        label("Speed")
                        Picker("", selection: $model.settings.speed) {
                            Text("1×").tag(1.0); Text("1.5×").tag(1.5); Text("2×").tag(2.0); Text("4×").tag(4.0)
                        }.pickerStyle(.segmented).labelsHidden()
                    }
                    GridRow {
                        label("Trim")
                        HStack(spacing: 6) {
                            timeField($model.trimStart)
                            Text("to").foregroundStyle(.secondary).fixedSize()
                            timeField($model.trimEnd)
                            Text(verbatim: "of \(String(format: "%.1f", info.duration)) s").foregroundStyle(.secondary).fixedSize()
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: "\(plan.outW) × \(plan.outH) · \(plan.fps) fps · \(seconds(plan.outputDuration)) · \(plan.frames) frames · about \(bytes(model.estimatedBytes))")
                        .font(.callout.weight(.medium))
                    Text((model.destination?.path ?? "").replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))

                HStack {
                    Spacer()
                    Button("Cancel") { model.reset() }.keyboardShortcut(.cancelAction)
                    Button("Convert") { model.convert() }.keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    private func timeField(_ value: Binding<Double>) -> some View {
        TextField("", value: value, format: .number.precision(.fractionLength(0 ... 2)))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 64)
    }

    private func widthBinding(_ info: VideoInfo) -> Binding<Int> {
        Binding(
            get: { widths.contains(model.settings.width) && model.settings.width < info.width ? model.settings.width : 0 },
            set: { model.settings.width = $0 }
        )
    }
}

struct ConvertingView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            Group {
                if let image = model.preview {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 260)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            ProgressView(value: model.progress)
            HStack {
                Text(model.stage).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(model.progress * 100)) %").monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.callout)
            HStack {
                Spacer()
                Button("Cancel") { model.cancelConversion() }.keyboardShortcut(.cancelAction)
            }
        }
    }
}

struct DoneView: View {
    @ObservedObject var model: AppModel
    @State private var toast = false
    @State private var toastToken = 0

    var body: some View {
        let px = model.resultPixels
        let k = min(1, 420 / max(1, px.width), 300 / max(1, px.height))
        VStack(spacing: 14) {
            if let data = model.resultData {
                AnimatedImage(data: data, mimeType: model.resultFormat.mimeType)
                    .frame(width: px.width * k, height: px.height * k)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .overlay { if toast { ClipboardToast().transition(.scale(scale: 0.9).combined(with: .opacity)) } }
            }
            VStack(spacing: 2) {
                Text(model.resultURL?.lastPathComponent ?? "").font(.headline).lineLimit(1).truncationMode(.middle)
                Text(verbatim: "\(bytes(Int64(model.resultData?.count ?? 0))) · \(Int(px.width)) × \(Int(px.height))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Change Settings…") { model.backToOptions() }
                Spacer()
                Button("Copy") { model.copyResult(); showToast() }
                Button("Reveal in Finder") { model.reveal() }.keyboardShortcut(.defaultAction)
            }
            Text("Drop another video to convert it.").font(.caption).foregroundStyle(.secondary)
        }
        // The result is copied automatically when the conversion finishes.
        .onAppear { showToast() }
    }

    /// Pops the card in, holds it, then lets it fade.
    private func showToast() {
        toastToken += 1
        let token = toastToken
        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { toast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            guard token == toastToken else { return }
            withAnimation(.easeOut(duration: 0.7)) { toast = false }
        }
    }
}

/// A dark, high-contrast card, like the system's volume and brightness overlays.
struct ClipboardToast: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard.fill").font(.title2).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Copied to your clipboard").font(.body.weight(.semibold)).foregroundStyle(.white)
                Text("Paste it into your slides with ⌘V").font(.callout).foregroundStyle(.white.opacity(0.82))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
    }
}

struct FailedView: View {
    @ObservedObject var model: AppModel
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 32)).foregroundStyle(.orange)
            Text("Conversion failed").font(.title3.weight(.medium))
            Text(message).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).textSelection(.enabled)
            HStack {
                if model.info != nil { Button("Back to Settings") { model.backToOptions() } }
                Button("Choose Another File…") { model.chooseFile() }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 20)
    }
}

struct MissingFFmpegView: View {
    @ObservedObject var model: AppModel
    private let brewInstall = #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("ffmpeg is not installed", systemImage: "wrench.and.screwdriver").font(.title3.weight(.medium))
            Text("Giffer uses ffmpeg to do the conversion. Install it once with Homebrew, then come back here.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            step("1. If you don't have Homebrew yet, paste this in Terminal:", brewInstall)
            step("2. Then install ffmpeg:", "brew install ffmpeg")
            HStack {
                Button("Open Terminal") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                }
                Link("brew.sh", destination: URL(string: "https://brew.sh")!)
                Spacer()
                Button("Check Again") { if !model.checkTools() { NSSound.beep() } }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func step(_ title: String, _ command: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout)
            HStack(spacing: 8) {
                Text(command).font(.system(.caption, design: .monospaced))
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.6)))
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
            }
        }
    }
}

struct AboutView: View {
    private let artwork: NSImage = Bundle.main.url(forResource: "Artwork", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) } ?? NSApp.applicationIconImage
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    private let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? ""
    private let bundled = Bundle.main.url(forResource: "bundled-versions", withExtension: "txt")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    var body: some View {
        VStack(spacing: 16) {
            // The square artwork itself, not the rounded Dock icon.
            Image(nsImage: artwork)
                .resizable().interpolation(.high)
                .frame(width: 288, height: 288)
                .overlay(Rectangle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            VStack(spacing: 3) {
                Text("Giffer").font(.title2.weight(.semibold))
                Text(verbatim: "Version \(version)").font(.callout).foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                Text("Get Giffer and its source code at").font(.callout)
                Link("github.com/mgunneras/giffer", destination: URL(string: "https://github.com/mgunneras/giffer")!)
                    .font(.callout)
            }
            Text(verbatim: "Includes FFmpeg (LGPL 2.1 or later), libwebp and SVT-AV1 (BSD 3-Clause), built from the official sources"
                + (bundled.map { ": \($0)" } ?? "")
                + ". The icon is set in Jost (SIL Open Font License). Licence texts are inside the app at Contents/Resources/licenses.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Text(verbatim: copyright).font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 336)
    }
}

/// Plays the result in a web view, which animates GIF, WebP, AVIF and APNG alike.
struct AnimatedImage: NSViewRepresentable {
    let data: Data
    let mimeType: String

    /// Never accepts drags, so a video dropped on the preview still reaches the app.
    final class PassiveWebView: WKWebView {
        override func registerForDraggedTypes(_ newTypes: [NSPasteboard.PasteboardType]) {}
    }

    static weak var current: WKWebView?   // for the debug snapshot hook

    func makeNSView(context: Context) -> WKWebView {
        let view = PassiveWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.setValue(false, forKey: "drawsBackground")
        view.unregisterDraggedTypes()
        Self.current = view
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.data != data else { return }
        context.coordinator.data = data
        let html = """
        <html><body style="margin:0;overflow:hidden;background:transparent">
        <img style="width:100vw;height:100vh;object-fit:contain;display:block"
             src="data:\(mimeType);base64,\(data.base64EncodedString())">
        </body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var data: Data? }
}

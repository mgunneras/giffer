import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
            Text("Drop a video here").font(.title3.weight(.medium))
            Text("or drop it on the Dock icon. The GIF is saved next to the video.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Choose File…") { model.chooseFile() }.padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 14)
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
                    GridRow {
                        label("Colours")
                        Picker("", selection: $model.settings.colors) {
                            ForEach([256, 128, 64, 32], id: \.self) { Text("\($0)").tag($0) }
                        }.pickerStyle(.segmented).labelsHidden()
                    }
                    GridRow {
                        label("Dithering")
                        Picker("", selection: $model.settings.dither) {
                            ForEach(Dither.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden()
                            .help("Smooth looks best on footage. None is smallest and suits screen recordings.")
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

    var body: some View {
        let px = model.resultPixels
        let k = min(1, 420 / max(1, px.width), 300 / max(1, px.height))
        VStack(spacing: 14) {
            if let data = model.resultData {
                AnimatedGIF(data: data)
                    .frame(width: px.width * k, height: px.height * k)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(spacing: 2) {
                Text(model.resultURL?.lastPathComponent ?? "").font(.headline).lineLimit(1).truncationMode(.middle)
                Text(verbatim: "\(bytes(Int64(model.resultData?.count ?? 0))) · \(Int(px.width)) × \(Int(px.height))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Change Settings…") { model.backToOptions() }
                Spacer()
                Button("Copy") { model.copyResult() }
                Button("Reveal in Finder") { model.reveal() }.keyboardShortcut(.defaultAction)
            }
            Text("Drop another video to convert it.").font(.caption).foregroundStyle(.secondary)
        }
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

struct AnimatedGIF: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if context.coordinator.data != data {
            context.coordinator.data = data
            view.image = NSImage(data: data)
            view.animates = true
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var data: Data? }
}

import AppKit
import Foundation

final class AppModel: ObservableObject {
    enum Phase: Equatable {
        case missingFFmpeg, idle, probing, options, converting, done, failed(String)
    }

    @Published var phase: Phase = .idle
    @Published var info: VideoInfo?
    @Published var poster: NSImage?
    @Published var settings = Settings() {
        didSet {
            if let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: "settings")
            }
        }
    }
    @Published var trimStart = 0.0
    @Published var trimEnd = 0.0

    @Published var progress = 0.0
    @Published var stage = ""
    @Published var preview: CGImage?

    @Published var resultURL: URL?
    @Published var resultData: Data?
    @Published var resultPixels = CGSize.zero
    @Published var resultFormat = Format.gif

    private var tools: FFmpeg.Tools?
    private var pendingURL: URL?
    private var job: Conversion?

    /// Running correction of the size estimate, learned from real results.
    private var calibrationKey: String { "calibration-\(settings.format.rawValue)" }
    private var calibration: Double {
        get { let v = UserDefaults.standard.double(forKey: calibrationKey); return v > 0 ? v : 1 }
        set { UserDefaults.standard.set(newValue, forKey: calibrationKey) }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "settings"),
           let saved = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = saved
        }
        checkTools()
    }

    var plan: Plan? {
        info.map { Plan(info: $0, settings: settings, trimStart: trimStart, trimEnd: trimEnd) }
    }

    var estimatedBytes: Int64 {
        Int64((plan?.rawEstimate ?? 0) * calibration)
    }

    var destination: URL? {
        info?.url.deletingPathExtension().appendingPathExtension(settings.format.fileExtension)
    }

    @discardableResult
    func checkTools() -> Bool {
        tools = FFmpeg.locate()
        if tools == nil {
            phase = .missingFFmpeg
            return false
        }
        if phase == .missingFFmpeg {
            phase = .idle
            if let url = pendingURL { pendingURL = nil; open(url) }
        }
        return true
    }

    func open(_ url: URL) {
        guard phase != .converting, phase != .probing else { NSSound.beep(); return }
        guard checkTools(), let tools else { pendingURL = url; return }
        phase = .probing
        poster = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try FFmpeg.probe(url, tools: tools) }
            DispatchQueue.main.async {
                switch result {
                case .success(let info):
                    self.info = info
                    self.trimStart = 0
                    self.trimEnd = (info.duration * 100).rounded(.down) / 100
                    self.phase = .options
                case .failure(let error):
                    self.phase = .failed("Couldn't read \(url.lastPathComponent).\n\(error.localizedDescription)")
                }
            }
            let image = FFmpeg.poster(url, tools: tools)
            DispatchQueue.main.async {
                if self.info?.url == url { self.poster = image }
            }
        }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .video]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func convert() {
        guard let plan, let tools, let destination else { return }
        if destination.standardizedFileURL == plan.source.standardizedFileURL {
            phase = .failed("The output would overwrite the source file.")
            return
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            let alert = NSAlert()
            alert.messageText = "Replace \(destination.lastPathComponent)?"
            alert.informativeText = "A file with this name already exists next to the video."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() != .alertFirstButtonReturn { return }
        }

        let job = Conversion(plan: plan, tools: tools)
        self.job = job
        progress = 0
        stage = "Starting"
        preview = poster?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        phase = .converting

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try job.run(to: destination) { fraction, stage, image in
                    DispatchQueue.main.async {
                        guard self.job === job else { return }
                        self.progress = fraction
                        self.stage = stage
                        if let image { self.preview = image }
                    }
                }
            }
            DispatchQueue.main.async {
                guard self.job === job else { return }
                self.job = nil
                switch result {
                case .success:
                    let data = try? Data(contentsOf: destination)
                    self.resultURL = destination
                    self.resultData = data
                    self.resultPixels = CGSize(width: plan.outW, height: plan.outH)
                    self.resultFormat = plan.format
                    if let size = data?.count, size > 0, plan.rawEstimate > 0 {
                        let ratio = min(8, max(0.125, Double(size) / plan.rawEstimate))
                        self.calibration = self.calibration * 0.5 + ratio * 0.5
                    }
                    self.phase = .done
                    NSApp.requestUserAttention(.informationalRequest)
                case .failure(let error):
                    if error is Cancelled {
                        self.phase = .options
                    } else {
                        self.phase = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    func cancelConversion() { job?.cancel() }

    func backToOptions() { phase = info == nil ? .idle : .options }

    func reset() {
        info = nil
        poster = nil
        phase = .idle
    }

    func reveal() {
        if let resultURL { NSWorkspace.shared.activateFileViewerSelecting([resultURL]) }
    }

    func copyResult() {
        guard let resultURL else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([resultURL as NSURL])
    }
}

import ImageIO
import PhotosUI
import SpektraCore
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var selection: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var original: UIImage?
    @State private var rendered: UIImage?
    @State private var isBusy = false
    @State private var status = "选择一张照片"
    @State private var exportURL: URL?

    @State private var packIDs: [String] = []
    @State private var showingSelfTest = false
    @State private var packID = BundledPack.defaultID
    @State private var exposureEV: Double = 0
    @State private var magentaShift: Double = 0
    @State private var yellowShift: Double = 0
    @State private var printExposure: Double = 1

    /// Rendering a 12 MP frame on the CPU is minutes of work; preview at this
    /// edge until the Metal path lands.
    private let previewEdge = 1600

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                ZStack {
                    Color(uiColor: .secondarySystemBackground)
                    if let image = rendered ?? original {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Text(status)
                            .foregroundStyle(.secondary)
                    }
                    if isBusy {
                        ProgressView().controlSize(.large)
                    }
                }
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                controls
            }
            .padding()
            .navigationTitle("Spektra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSelfTest = true
                    } label: {
                        Image(systemName: "checkmark.seal")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selection, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSelfTest) {
                SelfTestView()
            }
        }
        .task(id: selection) {
            await loadSelection()
        }
        .onAppear {
            if packIDs.isEmpty { packIDs = BundledPack.availableIDs() }
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 8) {
            if packIDs.count > 1 {
                Picker("胶片", selection: $packID) {
                    ForEach(packIDs, id: \.self) { id in
                        Text(shortName(id)).tag(id)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Text("曝光")
                Slider(value: $exposureEV, in: -2...2, step: 0.1)
                Text(String(format: "%+.1f EV", exposureEV)).monospacedDigit()
            }

            HStack {
                Text("品红")
                Slider(value: $magentaShift, in: -20...20, step: 1)
                Text("\(Int(magentaShift)) CC").monospacedDigit()
            }

            HStack {
                Text("黄")
                Slider(value: $yellowShift, in: -20...20, step: 1)
                Text("\(Int(yellowShift)) CC").monospacedDigit()
            }

            HStack {
                Text("印相")
                Slider(value: $printExposure, in: 0.5...2, step: 0.05)
                Text(String(format: "×%.2f", printExposure)).monospacedDigit()
            }

            HStack(spacing: 10) {
                Button {
                    Task { await render() }
                } label: {
                    Label("渲染", systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(photoData == nil || isBusy)

                Button {
                    Task { await renderFullResolution() }
                } label: {
                    Label("全尺寸", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.bordered)
                .disabled(photoData == nil || isBusy)

                // Bypasses the photo decode entirely: if this renders and a
                // photo does not, the problem is ImageBridge, not the pipeline.
                Button {
                    Task { await renderSample() }
                } label: {
                    Image(systemName: "testtube.2")
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)
            }

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func shortName(_ id: String) -> String {
        let film = id.components(separatedBy: "__").first ?? id
        let trimmed = film
            .replacingOccurrences(of: "kodak_", with: "")
            .replacingOccurrences(of: "fujifilm_", with: "")
        return trimmed.replacingOccurrences(of: "_", with: " ").capitalized
    }

    @MainActor
    private func loadSelection() async {
        guard let selection else { return }
        guard let data = try? await selection.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            status = "无法读取这张照片"
            return
        }
        photoData = data
        original = image
        rendered = nil
        exportURL = nil
        await render()
    }

    /// A synthetic frame straight into the simulator: no file, no Core Graphics
    /// decode. It separates "the port is wrong" from "the photo import is wrong".
    @MainActor
    private func renderSample() async {
        isBusy = true
        status = "示例渲染中…"
        defer { isBusy = false }

        let pack = packID
        let ev = Float(exposureEV)
        let magenta = Float(magentaShift)
        let yellow = Float(yellowShift)
        let printExp = Float(printExposure)
        let width = 512
        let height = 384

        let outputURL: URL? = await Task.detached(priority: .userInitiated) {
            guard let bundle = try? BundledPack.load(id: pack) else { return nil }

            var pixels = [Float](repeating: 0, count: width * height * 3)
            for y in 0..<height {
                let v = Float(y) / Float(height - 1)
                for x in 0..<width {
                    let u = Float(x) / Float(width - 1)
                    let i = (y * width + x) * 3
                    // linear Display P3-ish: a hue sweep over an exposure ramp
                    pixels[i] = 0.02 + 0.9 * u * v
                    pixels[i + 1] = 0.02 + 0.9 * (1 - u) * v
                    pixels[i + 2] = 0.02 + 0.9 * (1 - v) * (0.4 + 0.6 * u)
                }
            }

            var simulator = bundle.simulator
            simulator.exposureCompensationEV = ev
            simulator.filterShift = SIMD3(0, magenta, yellow)
            simulator.printExposure = printExp

            let rgb = simulator.render(linearRGB: pixels, width: width, height: height)
            guard let out = ImageBridge.makeImage(fromRGB: rgb, width: width, height: height)
            else { return nil }
            return Self.writePNG(out)
        }.value

        guard let outputURL, let output = UIImage(contentsOfFile: outputURL.path) else {
            status = "示例渲染失败"
            return
        }
        rendered = output
        exportURL = outputURL
        status = "示例完成"
    }

    static func writePNG(_ image: CGImage) -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spektra-\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                 "public.png" as CFString,
                                                                 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }

    @MainActor
    private func render() async {
        await renderFrame(maxEdge: previewEdge, stripHeight: 0, updatePreview: true)
    }

    /// Full resolution, in 128-row strips: the peak memory becomes a few strips
    /// instead of a few frames, which is what makes a 12 MP export fit.
    @MainActor
    private func renderFullResolution() async {
        await renderFrame(maxEdge: 0, stripHeight: 128, updatePreview: false)
    }

    @MainActor
    private func renderFrame(maxEdge: Int, stripHeight: Int, updatePreview: Bool) async {
        guard let photoData else { return }
        isBusy = true
        status = updatePreview ? "渲染中…" : "全尺寸渲染中，约需数十秒…"
        defer { isBusy = false }

        let pack = packID
        let ev = Float(exposureEV)
        let magenta = Float(magentaShift)
        let yellow = Float(yellowShift)
        let printExp = Float(printExposure)

        // Only `URL` crosses the task boundary: UIImage and CGImage are not
        // Sendable, so decode, render and encode all happen inside the task.
        let outputURL: URL? = await Task.detached(priority: .userInitiated) {
            guard let bundle = try? BundledPack.load(id: pack),
                  let frame = ImageBridge.linearRGB(from: photoData, maxEdge: maxEdge)
            else { return nil }

            var simulator = bundle.simulator
            simulator.exposureCompensationEV = ev
            simulator.filterShift = SIMD3(0, magenta, yellow)
            simulator.printExposure = printExp

            let rgb = simulator.render(linearRGB: frame.pixels,
                                       width: frame.width,
                                       height: frame.height,
                                       stripHeight: stripHeight)
            guard let out = ImageBridge.makeImage(fromRGB: rgb,
                                                  width: frame.width,
                                                  height: frame.height)
            else { return nil }
            return Self.writePNG(out)
        }.value

        guard let outputURL, let output = UIImage(contentsOfFile: outputURL.path) else {
            status = "渲染失败"
            return
        }
        if updatePreview {
            rendered = output
        }
        self.exportURL = outputURL
        status = updatePreview ? "完成" : "全尺寸完成（点右上角导出）"
    }
}

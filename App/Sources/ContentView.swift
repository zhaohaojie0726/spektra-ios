import ImageIO
import PhotosUI
import SpektraCore
import SwiftUI
import UIKit

/// The editor screen, laid out the way SpektraLab lays out its window:
/// the photograph fills the canvas on a neutral gray, and everything else is a
/// dense, dark rail of labelled rows with hairline separators.
///
/// On a phone the two rails cannot sit beside the canvas, so they become one
/// panel under it. The order of the sections follows the work: pick a stock,
/// then enlarge, then render.
struct ContentView: View {
    @State private var selection: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var original: UIImage?
    @State private var rendered: UIImage?
    @State private var isBusy = false
    @State private var status = "选择一张照片"
    @State private var exportURL: URL?

    @State private var packIDs: [String] = []
    @State private var packID = BundledPack.defaultID
    @State private var showingSelfTest = false

    @State private var exposureEV: Double = 0
    @State private var magentaShift: Double = 0
    @State private var yellowShift: Double = 0
    @State private var printExposure: Double = 1

    @State private var enlargerOpen = true
    @State private var cameraOpen = false

    /// Rendering a 12 MP frame on the CPU is minutes of work; preview at this
    /// edge until the Metal path lands.
    private let previewEdge = 1600

    var body: some View {
        ZStack {
            Theme.ground.ignoresSafeArea()
            VStack(spacing: 0) {
                headerBar
                stockStrip
                canvas
                panel
            }
        }
        .preferredColorScheme(.dark)
        .task(id: selection) { await loadSelection() }
        .onAppear {
            if packIDs.isEmpty { packIDs = BundledPack.availableIDs() }
        }
        .sheet(isPresented: $showingSelfTest) {
            SelfTestView().preferredColorScheme(.dark)
        }
    }

    // MARK: - header

    private var headerBar: some View {
        HStack(spacing: 2) {
            VStack(alignment: .leading, spacing: 1) {
                Text(filmName)
                    .font(Theme.Type_.navTitle)
                    .foregroundStyle(Theme.Ink.text)
                Text(paperName)
                    .font(Theme.Type_.caption)
                    .foregroundStyle(Theme.Ink.tertiary)
            }
            Spacer(minLength: 8)

            PhotosPicker(selection: $selection, matching: .images) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Ink.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            GlyphButton(systemImage: "testtube.2", help: "渲染示例") {
                Task { await renderSample() }
            }
            .disabled(isBusy)
            .opacity(isBusy ? Theme.disabledOpacity : 1)

            GlyphButton(systemImage: "checkmark.seal", help: "自检") {
                showingSelfTest = true
            }

            if let exportURL {
                ShareLink(item: exportURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Ink.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 46)
        .background(Theme.card)
    }

    private var stockStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(packIDs, id: \.self) { identifier in
                    Button {
                        guard packID != identifier else { return }
                        packID = identifier
                        if photoData != nil { Task { await render() } }
                    } label: {
                        StockChip(title: shortName(identifier), selected: packID == identifier)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Theme.card)
        .overlay(alignment: .bottom) { Hairline() }
    }

    // MARK: - canvas

    private var canvas: some View {
        ZStack {
            Theme.ground
            if let image = rendered ?? original {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.Ink.tertiary)
                    Text(status)
                        .font(Theme.Type_.caption)
                        .foregroundStyle(Theme.Ink.tertiary)
                }
            }
            if isBusy {
                ProgressView().controlSize(.large).tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottomLeading) {
            if !isBusy, rendered != nil {
                Text(status)
                    .font(Theme.Type_.caption)
                    .foregroundStyle(Theme.Ink.tertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    // MARK: - panel

    private var panel: some View {
        VStack(spacing: 0) {
            Hairline()
            VStack(spacing: 0) {
                SectionBlock(title: "放大机", expanded: $enlargerOpen, note: "CC") {
                    ScrubRow(label: "黄", sublabel: "→ 蓝", value: $yellowShift,
                             range: -20 ... 20, snap: 1,
                             gradient: [Color(hex: 0xB8A860), Color(hex: 0x8A8A8A),
                                        Color(hex: 0x6F7FB0)],
                             format: { String(format: "%+.0f", $0) })
                    ScrubRow(label: "品红", sublabel: "→ 绿", value: $magentaShift,
                             range: -20 ... 20, snap: 1,
                             gradient: [Color(hex: 0xB07CAE), Color(hex: 0x8A8A8A),
                                        Color(hex: 0x7CA87C)],
                             format: { String(format: "%+.0f", $0) })
                    ScrubRow(label: "印相", sublabel: "曝光倍数", value: $printExposure,
                             range: 0.5 ... 2, snap: 0.05,
                             format: { String(format: "×%.2f", $0) })
                }

                SectionBlock(title: "胶片曝光", expanded: $cameraOpen) {
                    ScrubRow(label: "曝光", sublabel: "档", value: $exposureEV,
                             range: -2 ... 2, snap: 0.1,
                             format: { String(format: "%+.1f", $0) })
                }
            }
            .padding(.horizontal, Theme.Metric.panelPadding)

            Hairline()
            actionBar
        }
        .background(Theme.card)
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await render() }
            } label: {
                Text("渲染")
                    .font(Theme.Type_.label)
                    .foregroundStyle(Theme.Ink.onSelection)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Theme.selection)
            }
            .buttonStyle(.plain)
            .disabled(photoData == nil || isBusy)
            .opacity(photoData == nil || isBusy ? Theme.disabledOpacity : 1)

            Button {
                Task { await renderFullResolution() }
            } label: {
                Text("全尺寸")
                    .font(Theme.Type_.label)
                    .foregroundStyle(Theme.Ink.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .overlay(Rectangle().stroke(Theme.rule, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(photoData == nil || isBusy)
            .opacity(photoData == nil || isBusy ? Theme.disabledOpacity : 1)
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.vertical, 10)
        .background(Theme.card)
    }

    // MARK: - names

    private var filmName: String {
        let parts = packID.components(separatedBy: "__")
        return Self.pretty(parts.first ?? packID)
    }

    private var paperName: String {
        let parts = packID.components(separatedBy: "__")
        return parts.count > 1 ? Self.pretty(parts[1]) : ""
    }

    private static func pretty(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "kodak_", with: "")
            .replacingOccurrences(of: "fujifilm_", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func shortName(_ identifier: String) -> String {
        let film = identifier.components(separatedBy: "__").first ?? identifier
        return Self.pretty(film)
    }

    // MARK: - actions

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
}

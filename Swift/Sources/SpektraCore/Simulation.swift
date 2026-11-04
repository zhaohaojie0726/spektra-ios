import Foundation

/// The whole simulation, end to end: linear scene RGB in, print scan out.
///
/// Every constant it needs is baked (see `Reference/export_goldens.py`): the
/// input colour matrix and the 192×192 chroma table are per (film, input
/// space); the enlarger and scanner setups are per (paper, output space).
/// Nothing here touches the file system — the app assembles a `Simulator` and
/// calls `render`.
public struct Simulator {
    public let film: Profile
    public let paper: Profile
    /// Linear input RGB → XYZ, adapted to the film's reference illuminant.
    public let inputMatrix: ColourMatrix
    /// Hanatos spectra contracted with the film's sensitivities, 192×192×3.
    public let chromaTable: ChromaTable
    /// DIR couplers with `amount` already folded in.
    public let couplers: Matrix3
    public let enlarger: EnlargerSetup
    public let scan: Scanning.Setup
    /// The negative's spectral density for an 18 % grey, baked by the pack.
    /// The reference derives it from a 0.184 **sRGB** grey (SpektraLab trap 21:
    /// the probe colour space is sRGB whatever the input space is).
    public let midgrayDensity: [Float]

    /// Enlarger filter pack offset in CC units (the UI sliders).
    public var filterShift: SIMD3<Float> = .zero
    /// Multiplier on the print exposure (1 = as balanced).
    public var printExposure: Float = 1

    /// Shifts the scene on the film's characteristic curve.
    ///
    /// Applied as a gain on the linear input, which the reference proves
    /// equivalent (`EV = +1` against a doubled frame: max diff 0.0) **as long
    /// as the enlarger does not re-time the print**. The baked packs set
    /// `print_exposure_compensation = false`, so this moves exposure, not
    /// print brightness — the desktop default (`true`) does the opposite.
    public var exposureCompensationEV: Float = 0

    /// Row blocks for the two spectral integrals. 0 = one per active processor.
    /// Rows are independent (nothing spatial), so the split cannot change a
    /// pixel — `RunRemoteTests` checks it bit for bit.
    public var threads: Int = 0

    public init(film: Profile,
                paper: Profile,
                inputMatrix: ColourMatrix,
                chromaTable: ChromaTable,
                couplers: Matrix3,
                enlarger: EnlargerSetup,
                scan: Scanning.Setup,
                midgrayDensity: [Float]) {
        self.film = film
        self.paper = paper
        self.inputMatrix = inputMatrix
        self.chromaTable = chromaTable
        self.couplers = couplers
        self.enlarger = enlarger
        self.scan = scan
        self.midgrayDensity = midgrayDensity
    }

    /// Renders `width × height` linear RGB (tightly packed) to encoded output
    /// RGB of the same size.
    ///
    /// `stripHeight > 0` renders in horizontal strips: every stage is
    /// per-pixel, so a strip's rows are the same rows the whole-image render
    /// would produce, and the peak memory becomes three strips instead of three
    /// frames. That is what makes a 12 MP export fit on a phone.
    public func render(linearRGB: [Float], width: Int, height: Int, stripHeight: Int = 0) -> [Float] {
        guard stripHeight > 0, stripHeight < height else {
            return renderImage(linearRGB: linearRGB, width: width, height: height)
        }
        var out = [Float](repeating: 0, count: linearRGB.count)
        var start = 0
        while start < height {
            let end = min(start + stripHeight, height)
            let lower = (start * width) * 3
            let upper = (end * width) * 3
            let slice = Array(linearRGB[lower..<upper])
            let rendered = renderImage(linearRGB: slice, width: width, height: end - start)
            out.replaceSubrange(lower..<upper, with: rendered)
            start = end
        }
        return out
    }

    /// One frame, in one piece.
    public func renderImage(linearRGB: [Float], width: Int, height: Int) -> [Float] {
        let curves = CharacteristicCurves(logExposure: film.logExposure,
                                          densityCurves: film.densityCurves)
        var input = linearRGB
        if exposureCompensationEV != 0 {
            let gain = powF(2, exposureCompensationEV)
            input = linearRGB.map { $0 * gain }
        }
        let logFilm = FilmExposure.logExposure(rgb: input,
                                               width: width,
                                               height: height,
                                               matrix: inputMatrix,
                                               table: chromaTable)
        let negative = FilmDevelopment.density(logExposure: logFilm,
                                               width: width,
                                               height: height,
                                               curves: curves,
                                               couplers: couplers)

        let filtered = enlarger.filteredIlluminant(cc: enlarger.ccNeutral, shift: filterShift)
        let sensitivity = PrintingExposure.linearSensitivity(paper.logSensitivity)
        let factor = PrintingExposure.midgrayFactor(
            midgrayDensity: midgrayDensity,
            filteredIlluminant: filtered,
            paperSensitivity: sensitivity)

        let logPrint = PrintingExposure.logExposure(cmy: negative,
                                                    width: width,
                                                    height: height,
                                                    filmChannelDensity: film.channelDensity,
                                                    filmBaseDensity: film.baseDensity,
                                                    paperSensitivity: sensitivity,
                                                    filteredIlluminant: filtered,
                                                    midgrayFactor: factor,
                                                    printExposure: printExposure,
                                                    threads: threads)

        guard let model = paper.densityModel else {
            // Without the fitted model a print cannot be developed faithfully;
            // returning the paper exposure keeps the failure visible rather
            // than silently substituting the sampled curves.
            return logPrint
        }
        let printDensity = PrintDevelopment.density(logExposure: logPrint,
                                                    width: width,
                                                    height: height,
                                                    exposureAxis: paper.logExposure,
                                                    model: model,
                                                    positive: paper.info.type == "positive")

        return Scanning.outputRGB(cmy: printDensity,
                                  width: width,
                                  height: height,
                                  channelDensity: paper.channelDensity,
                                  baseDensity: paper.baseDensity,
                                  viewingIlluminant: scan.viewingIlluminant,
                                  cmfs: scan.cmfs,
                                  normalization: scan.normalization,
                                  xyzToRGB: scan.xyzToRGB,
                                  roundtrip: scan.roundtrip,
                                  encode: scan.encode,
                                  threads: threads)
    }
}

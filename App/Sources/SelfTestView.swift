import SpektraCore
import SwiftUI

/// Runs the golden comparison on this device and shows one row per stage.
///
/// Styled like the editor's rails — dark well, hairlines, monospaced numbers —
/// because it is a diagnostic of the same instrument, not a settings page.
struct SelfTestView: View {
    @State private var results: [SelfTest.Result] = []
    @State private var benchmark: SelfTest.Benchmark?
    @State private var isRunning = true

    var body: some View {
        ZStack {
            Theme.card.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                Hairline()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                            row(result)
                            Hairline()
                        }
                        if let benchmark {
                            benchmarkRow(benchmark)
                            Hairline()
                        }
                    }
                }
                footer
            }
        }
        .task {
            let report = await Task.detached(priority: .userInitiated) {
                SelfTest.run()
            }.value
            results = report
            isRunning = false
            benchmark = await Task.detached(priority: .utility) {
                SelfTest.benchmark()
            }.value
        }
    }

    private var header: some View {
        HStack {
            Text("自检")
                .font(Theme.Type_.navTitle)
                .foregroundStyle(Theme.Ink.text)
            Spacer()
            if isRunning {
                ProgressView().controlSize(.small).tint(Theme.accent)
            } else {
                let passed = results.filter(\.passed).count
                Text("\(passed)/\(results.count)")
                    .font(Theme.Type_.value)
                    .foregroundStyle(passed == results.count ? Theme.accent : Theme.Ink.secondary)
            }
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .frame(height: 40)
    }

    private func row(_ result: SelfTest.Result) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(result.passed ? "OK" : "FAIL")
                .font(Theme.Type_.value)
                .foregroundStyle(result.passed ? Theme.accent : Color(hex: 0xE8524E))
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.name)
                    .font(Theme.Type_.label)
                    .foregroundStyle(Theme.Ink.text)
                Text(result.maxDiff.isFinite
                     ? String(format: "max |diff| %.2e   tol %.0e", result.maxDiff, result.tolerance)
                     : "did not run")
                    .font(Theme.Type_.sublabel)
                    .foregroundStyle(Theme.Ink.tertiary)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.vertical, 7)
    }

    private func benchmarkRow(_ benchmark: SelfTest.Benchmark) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("512")
                .font(Theme.Type_.value)
                .foregroundStyle(Theme.Ink.tertiary)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: "%.0f ms / frame", benchmark.milliseconds / 2))
                    .font(Theme.Type_.label)
                    .foregroundStyle(Theme.Ink.text)
                Text(String(format: "≈ %.2f s per megapixel",
                            benchmark.millisecondsPerMegapixel / 1000))
                    .font(Theme.Type_.sublabel)
                    .foregroundStyle(Theme.Ink.tertiary)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, Theme.Metric.panelPadding)
        .padding(.vertical, 7)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Hairline()
            Text("每条都在本机 CPU 上跑一遍，对照 Python 参考，阈值 2e-5。"
                 + "全绿说明这台设备上的数值与参考一致。")
                .font(Theme.Type_.sublabel)
                .foregroundStyle(Theme.Ink.tertiary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Metric.panelPadding)
                .padding(.vertical, 10)
        }
    }
}

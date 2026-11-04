import SpektraCore
import SwiftUI

/// Runs the golden comparison on this device and shows one row per stage.
///
/// This is the answer to "does it really run on iOS": the numbers are compared
/// against the Python reference, not against a picture that looks right.
struct SelfTestView: View {
    @State private var results: [SelfTest.Result] = []
    @State private var benchmark: SelfTest.Benchmark?
    @State private var isRunning = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if isRunning {
                        HStack {
                            ProgressView()
                            Text("比对中…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(result.passed ? Color.green : Color.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.name).font(.footnote)
                                Text(String(format: "max |diff| %.2e   (tol %.0e)", result.maxDiff, result.tolerance))
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("对照 Python 参考实现")
                } footer: {
                    Text("每条都在本机 CPU 上跑一遍，误差阈值 2e-5。"
                         + "全绿说明这台设备上的数值与参考一致。")
                }

                if let benchmark {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "512×512 渲染：%.0f ms / 帧", benchmark.milliseconds / 2))
                                .font(.footnote)
                            Text(String(format: "≈ %.2f 秒 / 百万像素",
                                        benchmark.millisecondsPerMegapixel / 1000))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("速度")
                    } footer: {
                        Text("乘上你的照片像素数，就是这个 App 单次渲染的大致耗时。")
                    }
                }
            }
            .navigationTitle("自检")
            .navigationBarTitleDisplayMode(.inline)
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
    }
}

import Dispatch
import Foundation

/// Splits a height into row blocks and runs them concurrently.
///
/// Rows are independent here: nothing in the pipeline is spatial (no grain, no
/// halation, no blur), so each block writes only its own output rows. That is
/// what makes the split safe without locks — and it is why the tiled Metal path
/// can be tiled at all.
enum Parallel {
    /// `threads == 0` means "one block per active processor".
    static func rows(_ height: Int, threads: Int, _ body: (Int, Int) -> Void) {
        guard height > 0 else { return }
        let requested = threads > 0 ? threads : ProcessInfo.processInfo.activeProcessorCount
        let blocks = min(height, max(1, requested))
        if blocks == 1 {
            body(0, height)
            return
        }
        let per = (height + blocks - 1) / blocks
        DispatchQueue.concurrentPerform(iterations: blocks) { block in
            let start = block * per
            let end = min(start + per, height)
            if start < end {
                body(start, end)
            }
        }
    }
}

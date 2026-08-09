#if os(macOS)
import AppKit

/// Swallows trackpad/Magic Mouse scroll events until the current gesture (and its
/// momentum) fully ends. Used after gallery dismiss so leftover two-finger motion
/// doesn't pull-to-refresh or scroll the feed underneath.
enum TrackpadScrollLock {
    private static var monitor: Any?
    private static var timeoutWork: DispatchWorkItem?

    static func beginUntilScrollGestureEnds(timeout: TimeInterval = 0.9) {
        end()

        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            let phase = event.phase
            let momentum = event.momentumPhase

            let fingersActive = phase.contains(.began)
                || phase.contains(.changed)
                || phase.contains(.mayBegin)
            let momentumActive = momentum.contains(.began)
                || momentum.contains(.changed)

            if fingersActive || momentumActive {
                return nil
            }

            // Consume terminal events, then release the lock on the next turn.
            if phase.contains(.ended) || phase.contains(.cancelled)
                || momentum.contains(.ended) || momentum.contains(.cancelled)
                || (phase.isEmpty && momentum.isEmpty) {
                DispatchQueue.main.async {
                    TrackpadScrollLock.end()
                }
            }
            return nil
        }

        let work = DispatchWorkItem {
            TrackpadScrollLock.end()
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    static func end() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        timeoutWork?.cancel()
        timeoutWork = nil
    }
}
#endif

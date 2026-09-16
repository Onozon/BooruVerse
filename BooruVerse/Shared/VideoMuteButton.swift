import SwiftUI
#if os(iOS)
import AVFoundation
#endif

/// Icon reflects the current mute state (muted by default), not the action.
struct VideoMuteButton: View {
    @Binding var isMuted: Bool

    var body: some View {
        Button {
            isMuted.toggle()
            GalleryAudioSession.activatePlaybackIfNeeded()
        } label: {
            Image(isMuted ? AppIcon.volumeMute : AppIcon.volumeUp)
                .appGlyph(size: 20)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMuted ? "Sound off" : "Sound on")
        .accessibilityHint("Toggles video sound")
    }
}

enum GalleryAudioSession {
    static func activatePlaybackIfNeeded() {
#if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {}
#endif
    }
}

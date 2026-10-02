import AVFoundation
import Foundation

#if os(iOS)
import UIKit
#endif

// Standalone diagnostic executable. No HearLift sources, fixtures, observers,
// dependencies or XCTest host are linked. Never included in either app target.
private final class AudioProbe: @unchecked Sendable {
    private let queue = DispatchQueue(label: "AudioProbe.output")
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var buffer: AVAudioPCMBuffer?
    private var sessionActive = false
    private var stage = "launch"
    private let mode: String

    init(mode: String) {
        self.mode = mode
    }

    func start() {
        queue.async {
            do {
                try self.run()
            } catch {
                self.emit("failure", detail: String(describing: error))
                exit(1)
            }
        }
    }

    private func emit(_ event: String, detail: String = "") {
        let record: [String: Any] = [
            "event": event,
            "stage": stage,
            "mode": mode,
            "mainThread": Thread.isMainThread,
            "detail": detail
        ]

        let json = try! JSONSerialization.data(
            withJSONObject: record,
            options: [.sortedKeys]
        )

        // Unbuffered checkpoints survive an abort inside the following Apple call.
        FileHandle.standardOutput.write(
            Data("AUDIO_PROBE ".utf8) + json + Data([10])
        )
    }

    private func checkpoint(_ next: String, detail: String = "") {
        stage = next
        emit("stage", detail: detail)
    }

    private func run() throws {
        dispatchPrecondition(condition: .onQueue(queue))

        guard mode == "playback" || mode == "mixer" else {
            emit("failure", detail: "Unknown probe mode")
            exit(2)
        }

        checkpoint(
            "environment",
            detail: ProcessInfo.processInfo.operatingSystemVersionString
        )

        #if os(iOS)
        // The mixer-only control deliberately omits explicit session activation.
        // Playback uses the same documented .playback setup as the M1 harness.
        if mode == "playback" {
            checkpoint("session-category")

            let session = AVAudioSession.sharedInstance()

            try session.setCategory(
                .playback,
                mode: .default,
                options: []
            )

            checkpoint("session-activate")

            try session.setActive(true)
            sessionActive = true

            checkpoint(
                "session-ready",
                detail: "rate=\(session.sampleRate), outputChannels=\(session.outputNumberOfChannels)"
            )
        }
        #endif

        checkpoint("engine-create")

        let engine = AVAudioEngine()
        self.engine = engine

        checkpoint("mixer-get")

        let mixer = engine.mainMixerNode

        checkpoint("mixer-ready")

        if mode == "mixer" {
            finish()
            return
        }

        // One second of quiet, identical stereo PCM at the CI device's 48 kHz.
        // This is an output transport control, not a test of HearLift's DSP.
        guard
            let format = AVAudioFormat(
                standardFormatWithSampleRate: 48_000,
                channels: 2
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: 48_000
            ),
            let channels = buffer.floatChannelData
        else {
            emit("failure", detail: "Could not allocate stereo PCM")
            exit(1)
        }

        buffer.frameLength = 48_000

        for frame in 0..<Int(buffer.frameLength) {
            let value = Float(
                sin(Double(frame) * 2 * .pi * 440 / 48_000) * 0.01
            )

            channels[0][frame] = value
            channels[1][frame] = value
        }

        self.buffer = buffer

        let player = AVAudioPlayerNode()
        self.player = player

        checkpoint("player-attach")
        engine.attach(player)

        checkpoint("player-connect")
        engine.connect(player, to: mixer, format: format)

        checkpoint("buffer-schedule")

        player.scheduleBuffer(
            buffer,
            completionCallbackType: .dataPlayedBack
        ) { _ in
            // Completion only enqueues teardown; no engine work on its callback.
            self.queue.async {
                self.checkpoint("played-back")
                self.finish()
            }
        }

        checkpoint("engine-start")
        try engine.start()

        checkpoint("player-play")
        player.play()

        checkpoint("playing")
    }

    private func finish() {
        checkpoint("stop")

        player?.stop()
        engine?.stop()

        player = nil
        engine = nil
        buffer = nil

        #if os(iOS)
        if sessionActive {
            checkpoint("session-deactivate")

            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
        #endif

        stage = "complete"
        emit("success")

        // Intentional only in this throwaway command-line/simulator probe.
        exit(0)
    }
}

#if os(iOS)
@main
@MainActor
final class AudioProbeAppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var probe: AudioProbe?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)

        let controller = UIViewController()
        controller.view.backgroundColor = .systemBackground

        window.rootViewController = controller
        window.makeKeyAndVisible()

        self.window = window

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        guard probe == nil else {
            return
        }

        let probe = AudioProbe(
            mode: CommandLine.arguments.last ?? "invalid"
        )

        self.probe = probe
        probe.start()
    }
}
#else
@main
struct AudioProbeMain {
    static func main() {
        let probe = AudioProbe(
            mode: CommandLine.arguments.last ?? "invalid"
        )

        probe.start()
        dispatchMain()
    }
}
#endif
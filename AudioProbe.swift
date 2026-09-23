import Foundation
import AVFoundation
import Darwin

private func log(_ message: String) {
    print(message)
    fflush(stdout)
}

private func logError(_ message: String) {
    fputs(message + "\n", stderr)
    fflush(stderr)
}

@main
struct AudioProbe {
    static func main() {
        let mode = CommandLine.arguments.dropFirst().first ?? "playback"

        log("AudioProbe starting")
        log("mode=\(mode)")
        log("arch=\(ProcessInfo.processInfo.machineHardwareName)")
        log("os=\(ProcessInfo.processInfo.operatingSystemVersionString)")

        guard mode == "playback" || mode == "mixer-only" else {
            logError("Unknown mode: \(mode)")
            logError("Usage: ./AudioProbe playback")
            exit(2)
        }

        let finished = DispatchSemaphore(value: 0)
        let queue = DispatchQueue(label: "com.codemagic.avaudio-probe")

        queue.async {
            log("engine-create")
            let engine = AVAudioEngine()
            log("engine-ready")

            // This is the call reported to hang on the Codemagic mac_mini_m2 host.
            log("mixer-get")
            let mixer = engine.mainMixerNode
            log("mixer-ready")

            let format = mixer.outputFormat(forBus: 0)
            log("mixer-format=\(format)")
            finished.signal()
        }

        let result = finished.wait(timeout: .now() + 25)

        if result == .timedOut {
            logError("probe-timeout: mainMixerNode did not return within 25 seconds")
            exit(124)
        }

        log("probe-complete")
        exit(0)
    }
}

private extension ProcessInfo {
    var machineHardwareName: String {
        var size: size_t = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)

        var machine = [CChar](repeating: 0, count: Int(size))
        sysctlbyname("hw.machine", &machine, &size, nil, 0)

        return String(cString: machine)
    }
}

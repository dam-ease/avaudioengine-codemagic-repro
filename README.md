# AVAudioEngine / Codemagic reproduction project

This is a minimal standalone Swift reproduction for the reported
`AVAudioEngine.mainMixerNode` hang on a Codemagic `mac_mini_m2` machine
using Xcode 26.6.

There is no iOS app, Flutter project, CocoaPods setup, or third-party
dependency in this repository.

## Files

- `AudioProbe.swift` — standalone Swift program using only Apple frameworks.
- `codemagic.yaml` — Codemagic workflow that compiles and runs the probe.

## How to run it in Codemagic

1. Create an empty GitHub or GitLab repository.
2. Upload `AudioProbe.swift` and `codemagic.yaml` to the repository root.
3. Add the repository to Codemagic.
4. Start the workflow named `AVAudioEngine mainMixerNode repro`.
5. Open the `Run AVAudioEngine playback probe` step.

## What to look for

A successful/non-reproducing run should contain:

```text
engine-create
engine-ready
mixer-get
mixer-ready
probe-complete
RESULT: NOT REPRODUCED
```

If the issue reproduces, the log should reach:

```text
mixer-get
```

but never print:

```text
mixer-ready
```

After 25 seconds the probe's watchdog will terminate it and the Codemagic
step will print:

```text
probe-timeout: mainMixerNode did not return within 25 seconds
RESULT: REPRODUCED
```

## Equivalent manual compile/run commands

```bash
xcrun --sdk macosx swiftc \
  -swift-version 5 \
  -parse-as-library \
  -target arm64-apple-macos13.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -framework AVFoundation \
  AudioProbe.swift \
  -o AudioProbe

./AudioProbe playback
```

## Useful control test

If the problem reproduces on Xcode 26.6, duplicate the workflow and change
only the Xcode version. Keep the same machine type and probe. That helps
separate an Xcode-specific behavior from a more general build-host behavior.
# avaudioengine-codemagic-repro

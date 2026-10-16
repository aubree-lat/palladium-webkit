# Palladium WebKitGTK

Palladium's Linux runtime, based on WebKitGTK 2.54.1. This branch keeps a small downstream patch set and builds a GTK 3 / libsoup 3 runtime for Arch Linux x86_64. It is not a replacement for the system WebKitGTK package.

## Changes

- Incoming tracks become ready independently of silent or delayed participants. Repeated track-ready notifications are ignored.
- Opus RTP payloads pass through encoded-transform workers on both sender and receiver. RTP identity and timing metadata are retained, changed payload sizes are supported, output is ordered on a serial queue, and queued frames are bounded. Closing a transform worker does not silently resume plaintext transmission. This is an initial audio implementation; encrypted video is not implemented.
- Device refresh clears stale speaker entries, and default-device changes emit device-change notifications.
- Display capture can request system audio; monitor devices stay out of normal microphone selection. Portal and PipeWire support remain enabled.
- Palladium can request a native memory-pressure release. Large Function.toString results are returned normally without keeping an extra long-lived cached copy.

## Build profile

Clang, Ninja unified builds, `-O2`, lld, ccache (2 GiB maximum), no LTO or debug symbols. Both X11 and Wayland, sandboxing, Skia/GPU acceleration, JavaScript JIT, WebAssembly, WebAudio, WebRTC, media recording, accessibility, spellcheck, WOFF2 and AVIF remain available.

Disabled: documentation, MiniBrowser, WebDriver, PDF.js, gamepad, speech synthesis, MHTML archives, native content filters, native browser extensions, WebXR, WebGPU and Vulkan. Some are already disabled upstream; pinning them prevents accidental expansion. Palladium uses injected JavaScript mods rather than native WebKit extension/content-filter APIs.

GObject introspection stays enabled for the native Python probes. Full WebKit development test suites are not compiled by this profile.

## CI and releases

`.github/workflows/palladium-runtime.yml` checks the source patch against the SHA-pinned official archive and builds inside a pinned Arch container. Package versions are recorded; Arch packages currently follow the distribution repositories, so a changed dependency set invalidates compiled objects. This is not a claim of bit-for-bit reproducibility.

Compiled objects and the private prefix survive between runs. The Rust toolchain and Cargo dependency build trees are not part of the checkpoint cache. A job checkpoints before the hosted-runner deadline and automatically queues the next attempt, up to six attempts. Compilation failures stop the workflow. No runtime is published until the sandboxed native probes pass:

1. Decoded synthetic Opus audio with multiple transceivers and renegotiation.
2. AES-GCM worker encryption/decryption, including changed payload lengths, metadata and worker progress checks.
3. An audible first participant alongside a worker that drops all frames, followed by the delayed participant becoming audible.
4. Microphone capture, explicit output switching, and device add/default-change/remove notifications using isolated virtual devices.

Tests use generated tones and an isolated PipeWire null sink, never a user's microphone or speakers. Native probes verify an offline media path, not Discord's DAVE protocol. Real two-party Discord calls, physical headset hotplug, and interactive screen sharing still require manual validation. Releases are prereleases until that validation is complete.

Each archive contains a source commit, input pins, dependency versions, native test results, licenses, the downstream source patch, and file hashes. Release assets also include SHA256SUMS. Build metrics record cumulative compile time and runtime size; compare the same runner and dependency versions before drawing performance conclusions.

Palladium app builds should download an explicitly pinned runtime release and checksum. They do not need to compile WebKit. A runtime built for Arch must not be advertised as compatible with Ubuntu or another glibc baseline.

## Updating upstream

Update `.palladium/pins.env`, rebase the native patches onto the matching tag, update version pins in the build/verification scripts, and run the source and native gates. Keep the Opus bridge separate from other changes: upstream is replacing the GStreamer WebRTC backend with LibWebRTC, and this bridge should be retired when the upstream backend passes Palladium's probes.

Source: https://webkitgtk.org/releases/webkitgtk-2.54.1.tar.xz plus the release's `palladium-source.patch`. The corresponding build scripts live on the release's source commit. Upstream and Rice licenses are included in the runtime; downstream edits retain the licenses of the files they modify.

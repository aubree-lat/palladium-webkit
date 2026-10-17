# Palladium WebKitGTK

Palladium's Linux runtime, based on WebKitGTK 2.54.1. This branch keeps a small downstream patch set and builds a GTK 3 / libsoup 3 runtime for Arch Linux x86_64. It is not a replacement for the system WebKitGTK package.

## Changes

- Incoming tracks become ready independently of silent or delayed participants. Repeated track-ready notifications are ignored.
- Opus RTP payloads pass through encoded-transform workers on both sender and receiver. RTP identity and timing metadata are retained, changed payload sizes are supported, output is ordered on a serial queue, and queued native callbacks and output buffers are bounded independently of JavaScript garbage collection. Closing a transform worker does not silently resume plaintext transmission. This is an initial audio implementation; encrypted video is not implemented and its payloads are blocked while a transform is attached.
- Backport upstream commit [ad718fae36e5](https://github.com/WebKit/WebKit/commit/ad718fae36e5b41ae7ebe55d6422d667e75a09fa), fixing WebAudio stream timestamps and durations so audio sinks do not discard the samples as gaps ([bug 325697](https://bugs.webkit.org/show_bug.cgi?id=325697)).
- Explicit Unix PulseAudio server addresses no longer trip a sandbox-launcher string assertion.
- GTK speaker enumeration and asynchronous output selection are enabled for Palladium, allowing Discord to restore a selected device without a fresh gesture. Permission policies remain enforced.
- Device refresh clears stale speaker entries, and default-device changes emit device-change notifications.
- Display capture can request system audio; monitor devices stay out of normal microphone selection. Portal and PipeWire support remain enabled.
- Palladium can request a native memory-pressure release. Large Function.toString results are returned normally without keeping an extra long-lived cached copy.

## Build profile

Clang, Ninja unified builds, `-O2`, lld, ccache (2 GiB maximum), no LTO or debug symbols. Both X11 and Wayland, sandboxing, Skia/GPU acceleration, JavaScript JIT, WebAssembly, WebAudio, WebRTC, media recording, accessibility, spellcheck, WOFF2 and AVIF remain available.

Disabled: documentation, MiniBrowser, WebDriver, PDF.js, gamepad, speech synthesis, MHTML archives, native content filters, native browser extensions, WebXR, WebGPU, Vulkan and Sysprof capture integration. Some are already disabled upstream; pinning them prevents accidental expansion. Palladium uses injected JavaScript mods rather than native WebKit extension/content-filter APIs.

GObject introspection stays enabled for the native Python probes. Full WebKit development test suites are not compiled by this profile.

## CI and releases

`.github/workflows/palladium-runtime.yml` checks the source patch against the SHA-pinned official archive and builds inside a pinned Arch container. Package versions are recorded; Arch packages currently follow the distribution repositories, so a changed dependency set invalidates compiled objects. This is not a claim of bit-for-bit reproducibility.

All native probes run again against the relocated package at `/usr/lib/palladium/runtime`, so helper paths and packaged libraries are tested before publication.

Compiled objects and the private prefix survive between runs. The Rust toolchain is downloaded per job. The cargo-c bootstrap build and crate registry are cached so interrupted setup can resume; its build tree is removed after the tool is installed. A job checkpoints before the hosted-runner deadline and automatically queues the next attempt, up to six attempts. Compilation failures stop the workflow. No runtime is published until the sandboxed native probes pass:

1. PNG, JPEG, GIF, WebP and AVIF decoding.
2. Decoded synthetic Opus audio with multiple transceivers and renegotiation, including measured tone energy at a virtual speaker output.
3. AES-GCM worker encryption/decryption, including changed payload lengths, metadata, worker replacement, explicit transform removal and worker progress checks.
4. An audible first participant alongside a worker that drops all frames, followed by the delayed participant becoming audible.
5. Microphone capture, explicit output switching with measured tone energy, and device add/default-change/remove notifications using isolated virtual devices.

Tests use generated tones and an isolated PipeWire null sink, never a user's microphone or speakers. Native probes verify an offline media path, not Discord's DAVE protocol. Real two-party Discord calls, physical headset hotplug, and interactive screen sharing still require manual validation. Releases are prereleases until that validation is complete.

Each archive contains a source commit, input pins, dependency versions, native test results, licenses, the downstream source patch, and file hashes. Release assets also include SHA256SUMS. Build metrics record cumulative compile time and runtime size; compare the same runner and dependency versions before drawing performance conclusions.

Palladium app builds should download an explicitly pinned runtime release and checksum. They do not need to compile WebKit. A runtime built for Arch must not be advertised as compatible with Ubuntu or another glibc baseline.

## Updating upstream

Update `.palladium/pins.env`, rebase the native patches onto the matching tag, update version pins in the build/verification scripts, run `bash .palladium/scripts/refresh-patch.sh`, and run the source and native gates. CI checks that the exported patch recreates the tracked native source files exactly. Keep the Opus bridge separate from other changes: upstream is replacing the GStreamer WebRTC backend with LibWebRTC, and this bridge should be retired when the upstream backend passes Palladium's probes.

Source: https://webkitgtk.org/releases/webkitgtk-2.54.1.tar.xz plus the release's `palladium-source.patch`. The corresponding build scripts live on the release's source commit. Upstream and Rice licenses are included in the runtime; downstream edits retain the licenses of the files they modify.

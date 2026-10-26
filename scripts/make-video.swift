// Builds the Perch intro video: dark, minimal motion design — 1920×1080, 30 fps, H.264 + AAC, ~62 s —
// with generated background music (four styles) and soft sound effects. No voiceover, no licensed audio.
//
//   build/Perch.app/Contents/MacOS/Perch --render-video-states build/video-states
//   swiftc -O -o build/make-video scripts/make-video.swift
//   build/make-video build/video-states ~/Downloads/Perch-intro.mp4 --music ambient   # ambient | lofi | cinematic | uplifting
//   build/make-video --music-preview lofi ~/Downloads/Perch-music-lofi.m4a          # 30 s music preview only
//   Voiceover: --voice "Zoe (Premium)" (any `say -v '?'` voice; default Samantha), or --no-voice
import AVFoundation
import AppKit

// MARK: - Arguments

let args = CommandLine.arguments
func option(_ name: String) -> String? { args.firstIndex(of: name).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
let previewStyle = option("--music-preview")
let voiceName = option("--voice") ?? "Samantha"
let useVoice = !args.contains("--no-voice") && previewStyle == nil
let positional = args.dropFirst().filter { !$0.hasPrefix("--") && $0 != option("--music") && $0 != previewStyle && $0 != option("--voice") }
let musicStyle = option("--music") ?? previewStyle ?? "ambient"

let W: CGFloat = 1920, H: CGFloat = 1080
let FPS = 30
let duration = previewStyle != nil ? 30.0 : 62.0

// MARK: - Easing

func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func prog(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
func inOut(_ p: Double) -> Double { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
func expoOut(_ p: Double) -> Double { p >= 1 ? 1 : 1 - pow(2, -10 * p) }
func quintOut(_ p: Double) -> Double { 1 - pow(1 - p, 5) }
func spring(_ p: Double) -> Double { p <= 0 ? 0 : (p >= 1 ? 1 : 1 - exp(-7 * p) * cos(7 * p)) }
func fade(_ t: Double, _ a: Double, _ b: Double, _ f: Double = 0.5) -> Double { min(prog(t, a, a + f), 1 - prog(t, b - f, b)) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ p: Double) -> CGFloat { a + (b - a) * CGFloat(p) }
func lerp(_ a: CGPoint, _ b: CGPoint, _ p: Double) -> CGPoint { CGPoint(x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p)) }

// MARK: - Sound

struct Cue { let at: Double; let kind: Sound; var gain: Float = 1 }
enum Sound { case click, key, whoosh, pop, chime }
var cues: [Cue] = []
func sfx(_ at: Double, _ kind: Sound, _ gain: Float = 1) { cues.append(Cue(at: at, kind: kind, gain: gain)) }

let SR = 48_000.0
let N = Int(duration * SR)
var L = [Float](repeating: 0, count: N)
var R = [Float](repeating: 0, count: N)
var rng = SystemRandomNumberGenerator()
func noise() -> Float { Float.random(in: -1...1, using: &rng) }
func midi(_ n: Double) -> Double { 440 * pow(2, (n - 69) / 12) }

/// A stereo bus that can be filtered and reverberated before it's mixed in.
struct Bus {
    var l = [Float](repeating: 0, count: N), r = [Float](repeating: 0, count: N)
    mutating func add(_ i: Int, _ s: Float, pan: Float = 0.5) {
        guard i >= 0 && i < N else { return }
        l[i] += s * (1 - pan) * 1.4; r[i] += s * pan * 1.4
    }
    /// One-pole low-pass; `amount` 0…1 (lower = darker).
    mutating func lowpass(_ amount: Float) {
        var a: Float = 0, b: Float = 0
        for i in 0..<N { a += (l[i] - a) * amount; b += (r[i] - b) * amount; l[i] = a; r[i] = b }
    }
    /// Small Schroeder reverb (parallel combs + allpasses), mixed in with `wet`.
    mutating func reverb(_ wet: Float, size: Double = 1) {
        let combs = [1557, 1617, 1491, 1422].map { Int(Double($0) * size * SR / 44_100) }
        let feedback: Float = 0.80
        var outL = [Float](repeating: 0, count: N), outR = [Float](repeating: 0, count: N)
        for d in combs {
            var bufL = [Float](repeating: 0, count: d), bufR = [Float](repeating: 0, count: d + 23)
            var pl = 0, pr = 0, lpL: Float = 0, lpR: Float = 0
            for i in 0..<N {
                let yl = bufL[pl]; lpL = yl * 0.6 + lpL * 0.4
                bufL[pl] = l[i] + lpL * feedback; pl = (pl + 1) % bufL.count
                let yr = bufR[pr]; lpR = yr * 0.6 + lpR * 0.4
                bufR[pr] = r[i] + lpR * feedback; pr = (pr + 1) % bufR.count
                outL[i] += yl * 0.25; outR[i] += yr * 0.25
            }
        }
        for d in [225, 556].map({ Int(Double($0) * SR / 44_100) }) {
            var bl = [Float](repeating: 0, count: d), br = [Float](repeating: 0, count: d)
            var p = 0
            for i in 0..<N {
                let yl = bl[p] - outL[i] * 0.5; bl[p] = outL[i] + bl[p] * 0.5; outL[i] = yl
                let yr = br[p] - outR[i] * 0.5; br[p] = outR[i] + br[p] * 0.5; outR[i] = yr
                p = (p + 1) % d
            }
        }
        for i in 0..<N { l[i] += outL[i] * wet; r[i] += outR[i] * wet }
    }
    func mix(_ gain: Float) { for i in 0..<N { L[i] += l[i] * gain; R[i] += r[i] * gain } }
}

/// Generic voice: additive partials with an attack/decay envelope.
func voice(_ bus: inout Bus, at t: Double, freq: Double, length: Double, amp: Double, attack: Double, decay: Double,
           partials: [(Double, Double)], pan: Float = 0.5, release: Double = 0.3, detune: Double = 0) {
    let start = Int(t * SR), n = Int((length + release) * SR)
    for i in 0..<n {
        let tt = Double(i) / SR
        var env = min(tt / attack, 1) * exp(-tt * decay)
        if tt > length { env *= max(0, 1 - (tt - length) / release) }
        var v = 0.0
        for (k, a) in partials { v += a * sin(2 * .pi * freq * k * tt * (1 + detune * (k - 1))) }
        bus.add(start + i, Float(v * env * amp), pan: pan)
    }
}
func kick(_ bus: inout Bus, at t: Double, amp: Double) {
    let start = Int(t * SR); var phase = 0.0
    for i in 0..<Int(0.4 * SR) {
        let tt = Double(i) / SR
        phase += 2 * .pi * (48 + 70 * exp(-tt * 28)) / SR
        bus.add(start + i, Float(sin(phase) * exp(-tt * 8) * amp))
    }
}
func hat(_ bus: inout Bus, at t: Double, amp: Double, pan: Float = 0.6) {
    let start = Int(t * SR); var prev: Float = 0
    for i in 0..<Int(0.05 * SR) {
        let n = noise(); let hp = n - prev; prev = n
        bus.add(start + i, hp * Float(exp(-Double(i) / SR * 80) * amp), pan: pan)
    }
}
func snare(_ bus: inout Bus, at t: Double, amp: Double) {
    let start = Int(t * SR); var lp: Float = 0
    for i in 0..<Int(0.25 * SR) {
        lp += (noise() - lp) * 0.4
        let tt = Double(i) / SR
        bus.add(start + i, (lp * Float(exp(-tt * 18)) + Float(sin(2 * .pi * 190 * tt) * exp(-tt * 30)) * 0.4) * Float(amp))
    }
}

// Partials (harmonic, amplitude) for a few timbres
let softPad: [(Double, Double)] = [(1, 1), (2, 0.18), (3, 0.05)]
let electricPiano: [(Double, Double)] = [(1, 1), (2, 0.35), (3, 0.06), (7, 0.04)]
let pianoTone: [(Double, Double)] = [(1, 1), (2, 0.45), (3, 0.2), (4, 0.1), (5, 0.05)]
let warmSaw: [(Double, Double)] = (1...10).map { (Double($0), 1 / Double($0)) }
let pluckTone: [(Double, Double)] = [(1, 1), (2, 0.5), (3, 0.25), (4, 0.12)]

func addMusic(_ style: String) {
    var pads = Bus(), keys = Bus(), drums = Bus(), bass = Bus()
    switch style {
    case "lofi":
        // Lo-fi chill: warm electric-piano chords, swung soft drums, vinyl hiss
        let bpm = 78.0, beat = 60 / bpm, bar = beat * 4
        let chords: [[Double]] = [[53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60], [48, 52, 55, 59]]
        let roots: [Double] = [41, 40, 38, 36]
        for b in 0..<Int(duration / bar) + 1 {
            let t0 = Double(b) * bar
            for (i, n) in chords[b % 4].enumerated() {
                voice(&keys, at: t0 + Double(i) * 0.018, freq: midi(n), length: bar * 0.95, amp: 0.05, attack: 0.01, decay: 0.55,
                      partials: electricPiano, pan: 0.35 + Float(i) * 0.1, release: 0.6)
            }
            if b % 2 == 1 { voice(&keys, at: t0 + beat * 2.5, freq: midi(chords[b % 4][3] + 12), length: 0.5, amp: 0.035, attack: 0.01, decay: 2, partials: electricPiano, pan: 0.6) }
            if b >= 1 { voice(&bass, at: t0, freq: midi(roots[b % 4]), length: bar * 0.9, amp: 0.10, attack: 0.02, decay: 0.4, partials: [(1, 1), (2, 0.15)]) }
            if b >= 2 {
                for k in 0..<4 {
                    let swing = k % 2 == 1 ? 0.06 : 0
                    if k == 0 || k == 2 { kick(&drums, at: t0 + Double(k) * beat, amp: 0.16) }
                    if k == 1 || k == 3 { snare(&drums, at: t0 + Double(k) * beat, amp: 0.05) }
                    hat(&drums, at: t0 + Double(k) * beat, amp: 0.012)
                    hat(&drums, at: t0 + Double(k) * beat + beat / 2 + swing, amp: 0.008)
                }
            }
        }
        for i in 0..<N where Int.random(in: 0..<2400, using: &rng) == 0 { drums.add(i, noise() * 0.05) } // crackle
        for i in 0..<N { drums.add(i, noise() * 0.0025) }                                                  // hiss
        keys.lowpass(0.25); keys.reverb(0.25, size: 0.8); drums.lowpass(0.4)
        keys.mix(1); bass.mix(1); drums.mix(1)
    case "cinematic":
        // Cinematic tech: pulsing arpeggio, wide pads, low swells, gentle build
        let bpm = 96.0, beat = 60 / bpm, bar = beat * 4
        let chords: [[Double]] = [[57, 60, 64, 69], [53, 57, 60, 65], [48, 55, 60, 64], [55, 59, 62, 67]]
        let roots: [Double] = [33, 29, 36, 31]
        for b in 0..<Int(duration / bar) + 1 {
            let t0 = Double(b) * bar
            for (i, n) in chords[b % 4].enumerated() {
                voice(&pads, at: t0, freq: midi(n), length: bar, amp: 0.022, attack: 1.2, decay: 0.05, partials: warmSaw,
                      pan: 0.3 + Float(i) * 0.13, release: 1.4, detune: 0.0008)
            }
            voice(&bass, at: t0, freq: midi(roots[b % 4]), length: bar, amp: 0.10, attack: 0.6, decay: 0.1, partials: [(1, 1), (2, 0.3)], release: 1)
            let level = min(1, Double(b) / 6)
            for s in 0..<16 {
                let note = chords[b % 4][[0, 1, 2, 3, 2, 1, 2, 3][s % 8]] + 12
                voice(&keys, at: t0 + Double(s) * beat / 4, freq: midi(note), length: 0.12, amp: 0.03 * (0.4 + 0.6 * level), attack: 0.004,
                      decay: 9, partials: pluckTone, pan: s % 2 == 0 ? 0.35 : 0.65, release: 0.1)
            }
            if b >= 4 { for k in 0..<4 { kick(&drums, at: t0 + Double(k) * beat, amp: 0.10) } }
        }
        pads.lowpass(0.12); pads.reverb(0.45, size: 1.2); keys.lowpass(0.3); keys.reverb(0.3)
        pads.mix(1); keys.mix(1); bass.mix(1); drums.mix(1)
    case "uplifting":
        // Light, upbeat electronic: off-beat chord stabs, soft four-on-the-floor, bright plucks
        let bpm = 112.0, beat = 60 / bpm, bar = beat * 4
        let chords: [[Double]] = [[60, 64, 67, 71], [59, 62, 67, 69], [57, 60, 64, 67], [53, 57, 60, 64]]
        let roots: [Double] = [36, 35, 33, 29]
        for b in 0..<Int(duration / bar) + 1 {
            let t0 = Double(b) * bar
            for k in 0..<4 {
                for (i, n) in chords[b % 4].enumerated() {
                    voice(&keys, at: t0 + Double(k) * beat + beat / 2, freq: midi(n), length: 0.18, amp: 0.028, attack: 0.005, decay: 6,
                          partials: pluckTone, pan: 0.35 + Float(i) * 0.1, release: 0.15)
                }
                if b >= 1 { voice(&bass, at: t0 + Double(k) * beat + beat / 2, freq: midi(roots[b % 4] + 12), length: 0.2, amp: 0.07, attack: 0.005, decay: 5, partials: [(1, 1), (2, 0.2)]) }
                if b >= 2 { kick(&drums, at: t0 + Double(k) * beat, amp: 0.14) }
                if b >= 4 { hat(&drums, at: t0 + Double(k) * beat + beat / 2, amp: 0.018) }
                if b >= 4 && (k == 1 || k == 3) { snare(&drums, at: t0 + Double(k) * beat, amp: 0.04) }
            }
            if b >= 3 {
                let melody: [Double] = [7, 4, 2, 4, 7, 9, 7, 4]
                for s in 0..<8 { voice(&pads, at: t0 + Double(s) * beat / 2, freq: midi(chords[b % 4][0] + 12 + melody[s]), length: 0.15, amp: 0.022, attack: 0.004, decay: 7, partials: pluckTone, pan: 0.6) }
            }
        }
        keys.reverb(0.25); pads.reverb(0.3); keys.lowpass(0.5)
        keys.mix(1); pads.mix(1); bass.mix(1); drums.mix(1)
    default: // "ambient"
        // Ambient piano: soft pads and a sparse, gentle piano melody with a long reverb
        let bpm = 70.0, beat = 60 / bpm, bar = beat * 4
        let chords: [[Double]] = [[50, 57, 61, 64, 66], [47, 54, 57, 62, 64], [43, 50, 54, 59, 62], [45, 52, 57, 61, 64]]
        let melody: [[Double]] = [[78, 76, 73], [74, 73, 71], [74, 71, 69], [73, 76, 73]]
        for b in 0..<Int(duration / bar) + 1 {
            let t0 = Double(b) * bar
            for (i, n) in chords[b % 4].enumerated() {
                voice(&pads, at: t0, freq: midi(n), length: bar, amp: 0.018, attack: 1.6, decay: 0.02, partials: softPad,
                      pan: 0.3 + Float(i) * 0.1, release: 2.2, detune: 0.0006)
            }
            if b >= 1 {
                for (k, n) in melody[b % 4].enumerated() {
                    voice(&keys, at: t0 + Double(k) * beat * 1.33 + 0.03, freq: midi(n), length: 1.8, amp: 0.05, attack: 0.006, decay: 1.4,
                          partials: pianoTone, pan: 0.45 + Float(k) * 0.05, release: 0.8)
                }
            }
            if b >= 3 { voice(&bass, at: t0, freq: midi(chords[b % 4][0] - 12), length: bar, amp: 0.06, attack: 0.8, decay: 0.05, partials: [(1, 1)], release: 1.2) }
        }
        pads.lowpass(0.15); pads.reverb(0.4, size: 1.3); keys.lowpass(0.4); keys.reverb(0.45, size: 1.3)
        pads.mix(1); keys.mix(1); bass.mix(1)
    }
}

func addEffects() {
    var fx = Bus()
    for cue in cues {
        let start = Int(cue.at * SR), g = cue.gain * 0.6
        switch cue.kind {
        case .click:
            var prev: Float = 0
            for i in 0..<Int(0.025 * SR) {
                let tt = Double(i) / SR; let n = noise(); let hp = n - prev * 0.6; prev = n
                fx.add(start + i, (Float(sin(2 * .pi * 2400 * tt) * exp(-tt * 300)) * 0.22 + hp * Float(exp(-tt * 450)) * 0.16) * g)
            }
        case .key:
            let f = Double.random(in: 230...290, using: &rng); var lp: Float = 0
            for i in 0..<Int(0.05 * SR) {
                let tt = Double(i) / SR; lp += (noise() - lp) * 0.5
                fx.add(start + i, (Float(sin(2 * .pi * f * tt) * exp(-tt * 80)) * 0.25 + lp * Float(exp(-tt * 170)) * 0.2) * g, pan: 0.45)
            }
        case .whoosh:
            var lp: Float = 0; let n = Int(0.7 * SR)
            for i in 0..<n {
                let p = Double(i) / Double(n); lp += (noise() - lp) * Float(0.015 + 0.12 * sin(p * .pi))
                fx.add(start + i, lp * Float(sin(p * .pi) * 0.16) * g, pan: Float(0.3 + 0.4 * p))
            }
        case .pop:
            for i in 0..<Int(0.1 * SR) {
                let tt = Double(i) / SR
                let f: Double = 600 + 500 * min(tt / 0.03, 1)
                let v: Double = sin(2 * Double.pi * f * tt) * exp(-tt * 45) * 0.16
                fx.add(start + i, Float(v) * g)
            }
        case .chime:
            for (o, n) in [(0.0, 84.0), (0.15, 88.0)] {
                for i in 0..<Int(1.4 * SR) {
                    let tt = Double(i) / SR, f = midi(n)
                    fx.add(start + Int(o * SR) + i, Float((sin(2 * .pi * f * tt) + 0.35 * sin(2 * .pi * f * 2.76 * tt)) * exp(-tt * 3) * 0.09) * g)
                }
            }
        }
    }
    fx.reverb(0.15, size: 0.7)
    fx.mix(1)
}

// MARK: - Voiceover

/// Narration, one line per scene: (start time, text).
let voiceLines: [(Double, String)] = [
    (3.8, "Meet Perch. A shelf that lives at the top of your Mac."),
    (8.6, "Hover over it, and everything you need is right there."),
    (12.9, "Screenshots and screen recordings land on it, automatically."),
    (18.6, "Drag anything out, straight into any app."),
    (24.2, "Select a few, and drag them all at once."),
    (29.6, "Press space to preview. Option, command, F, to find anything."),
    (34.8, "And it's built for Claude Code."),
    (38.8, "See every session at a glance, and jump straight to the one that needs you."),
    (45.0, "Keep an eye on your plan limits, live."),
    (48.9, "Make it yours. A notch, a floating capsule, or an orb."),
    (53.9, "Private, by design."),
    (58.0, "Perch. Everything you need, right where you look."),
]

/// Speaks each line with macOS's `say`, places it on the timeline, and ducks the music under it.
func addVoice() {
    var vo = [Float](repeating: 0, count: N)
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("perch-vo-\(UUID().uuidString).aiff")
    defer { try? FileManager.default.removeItem(at: tmp) }
    for (start, line) in voiceLines {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        p.arguments = ["-v", voiceName, "-r", "172", "-o", tmp.path, line]
        try? p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0, let file = try? AVAudioFile(forReading: tmp),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil, let data = buffer.floatChannelData?[0] else {
            print("Couldn't speak with voice '\(voiceName)'. Check the name in: say -v '?'")
            return
        }
        // Resample to the mix rate (linear is fine for speech)
        let ratio = file.processingFormat.sampleRate / SR
        let outCount = Int(Double(buffer.frameLength) / ratio)
        let offset = Int(start * SR)
        for i in 0..<outCount {
            let pos = Double(i) * ratio, j = Int(pos), frac = Float(pos - Double(j))
            guard j + 1 < Int(buffer.frameLength), offset + i < N else { break }
            vo[offset + i] += data[j] * (1 - frac) + data[j + 1] * frac
        }
    }
    // Duck everything else under the voice (smooth envelope follower)
    var env: Float = 0
    let attack: Float = 1 - exp(-1 / Float(0.015 * SR)), release: Float = 1 - exp(-1 / Float(0.45 * SR))
    var voPeak: Float = 0
    for i in 0..<N { voPeak = max(voPeak, abs(vo[i])) }
    let voGain: Float = voPeak > 0 ? 0.62 / voPeak : 1
    for i in 0..<N {
        let level = abs(vo[i]) * voGain
        env += (level - env) * (level > env ? attack : release)
        let duck = 1 - 0.6 * min(env * 6, 1)
        L[i] = L[i] * duck + vo[i] * voGain
        R[i] = R[i] * duck + vo[i] * voGain
    }
}

let tempAudio = FileManager.default.temporaryDirectory.appendingPathComponent("perch-audio-\(UUID().uuidString).caf")

func writeAudio(to url: URL) {
    addMusic(musicStyle)
    addEffects()
    if useVoice { addVoice() }
    // Fades, gentle saturation, then normalise to a -3 dBFS peak
    var peak: Float = 0
    for i in 0..<N {
        let t = Double(i) / SR
        let env = Float(min(t / 1.5, 1) * min((duration - t) / 3, 1))
        L[i] = tanhf(L[i] * env * 1.2); R[i] = tanhf(R[i] * env * 1.2)
        peak = max(peak, abs(L[i]), abs(R[i]))
    }
    let gain = peak > 0 ? 0.708 / peak : 1
    for i in 0..<N { L[i] *= gain; R[i] *= gain }
    let format = AVAudioFormat(standardFormatWithSampleRate: SR, channels: 2)!
    let file = try! AVAudioFile(forWriting: url, settings: format.settings)
    var offset = 0
    while offset < N {
        let n = min(48_000, N - offset)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buffer.frameLength = AVAudioFrameCount(n)
        for i in 0..<n { buffer.floatChannelData![0][i] = L[offset + i]; buffer.floatChannelData![1][i] = R[offset + i] }
        try! file.write(from: buffer)
        offset += n
    }
}

// Music preview only
if let style = previewStyle {
    let out = URL(fileURLWithPath: positional.first ?? "Perch-music-\(style).m4a")
    writeAudio(to: tempAudio)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
    p.arguments = ["-f", "m4af", "-d", "aac", "-b", "192000", tempAudio.path, out.path]
    try! p.run(); p.waitUntilExit()
    try? FileManager.default.removeItem(at: tempAudio)
    print("Wrote \(out.path)")
    exit(0)
}

// MARK: - Assets

let statesDir = URL(fileURLWithPath: positional.first ?? "build/video-states")
let finalURL = URL(fileURLWithPath: positional.dropFirst().first ?? "build/perch-intro.mp4")

func load(_ name: String) -> NSImage {
    guard let image = NSImage(contentsOf: statesDir.appendingPathComponent(name)) else {
        fatalError("Missing \(name). Run: Perch --render-video-states \(statesDir.path)")
    }
    return image
}
func px(_ image: NSImage) -> CGSize {
    let rep = image.representations.first
    return CGSize(width: rep?.pixelsWide ?? Int(image.size.width), height: rep?.pixelsHigh ?? Int(image.size.height))
}

let pill0 = load("pill-0.png")
let shelf0 = load("shelf-0.png"), shelf1 = load("shelf-1.png"), shelf2 = load("shelf-2.png"), shelf3 = load("shelf-3.png")
let shelfSelect = load("shelf-select.png"), searchImg = load("search.png"), claudeImg = load("claude.png")
let styleNotch = load("style-notch.png"), styleFloating = load("style-floating.png"), styleOrb = load("style-orb.png")
let dashboard = load("drag-thumb.png"), sunset = load("thumb-sunset.png"), loginThumb = load("thumb-login.png")
guard let appIcon = NSImage(contentsOf: URL(fileURLWithPath: "Resources/AppIcon-1024.png")) else { fatalError("Missing app icon") }

let pad: CGFloat = 48 // transparent padding in the island images (px)

/// Where an island image sits on screen, and where its cards are.
struct Placed {
    let image: NSImage
    let rect: CGRect
    var k: CGFloat { rect.width / px(image).width }
    func card(_ i: Int) -> CGRect {
        CGRect(x: rect.minX + (88 + 224 * CGFloat(i)) * k, y: rect.minY + 161 * k, width: 208 * k, height: 252 * k)
    }
    func preview(_ i: Int) -> CGRect {
        CGRect(x: rect.minX + (98 + 224 * CGFloat(i)) * k, y: rect.minY + 171 * k, width: 184 * k, height: 116 * k)
    }
}
func place(_ image: NSImage, width: CGFloat, x: CGFloat, y: CGFloat) -> Placed {
    let size = px(image), k = width / size.width
    return Placed(image: image, rect: CGRect(x: x - pad * k, y: y - pad * k, width: size.width * k, height: size.height * k))
}
func placeTop(_ image: NSImage, scale: CGFloat) -> Placed {
    let size = px(image)
    return Placed(image: image, rect: CGRect(x: W / 2 - size.width * scale / 2, y: 34 + 12 - pad * scale,
                                             width: size.width * scale, height: size.height * scale))
}

// MARK: - Drawing helpers (top-left origin)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let white = rgb(0xF5F5F7), grey = rgb(0x8E8E93), blueAccent = rgb(0x7AA7FF), clay = rgb(0xE8957A)
var ctxRef: CGContext!

func draw(_ image: NSImage, in r: CGRect, alpha: Double = 1) {
    guard alpha > 0.002 else { return }
    image.draw(in: r, from: .zero, operation: .sourceOver, fraction: CGFloat(min(alpha, 1)), respectFlipped: true,
               hints: [.interpolation: NSNumber(value: NSImageInterpolation.high.rawValue)])
}
func drawClipped(_ image: NSImage, in r: CGRect, radius: CGFloat, alpha: Double = 1) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).addClip()
    draw(image, in: r, alpha: alpha)
    NSGraphicsContext.restoreGraphicsState()
}
func fill(_ r: CGRect, _ c: NSColor, radius: CGFloat = 0) {
    c.setFill()
    if radius > 0 { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill() } else { NSBezierPath(rect: r).fill() }
}
func stroke(_ r: CGRect, _ c: NSColor, radius: CGFloat, width: CGFloat = 1) {
    c.setStroke(); let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius); p.lineWidth = width; p.stroke()
}
func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular, mono: Bool = false) -> NSFont {
    mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
}
func width(_ s: String, _ f: NSFont, kern: CGFloat = 0) -> CGFloat { NSAttributedString(string: s, attributes: [.font: f, .kern: kern]).size().width }
func text(_ s: String, _ f: NSFont, _ c: NSColor, x: CGFloat, y: CGFloat, alpha: Double = 1, kern: CGFloat = 0) {
    guard alpha > 0.002 else { return }
    NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c.withAlphaComponent(c.alphaComponent * CGFloat(alpha)), .kern: kern])
        .draw(at: NSPoint(x: x, y: y))
}
func shadow(blur: CGFloat = 60, y: CGFloat = 24, a: CGFloat = 0.55, _ body: () -> Void) {
    ctxRef.saveGState()
    ctxRef.setShadow(offset: CGSize(width: 0, height: y), blur: blur, color: NSColor.black.withAlphaComponent(a).cgColor)
    body()
    ctxRef.restoreGState()
}
func layer(_ a: Double, _ body: () -> Void) {
    guard a > 0.002 else { return }
    ctxRef.saveGState(); ctxRef.setAlpha(CGFloat(min(a, 1))); ctxRef.beginTransparencyLayer(auxiliaryInfo: nil)
    body()
    ctxRef.endTransparencyLayer(); ctxRef.restoreGState()
}
/// Scale everything drawn in `body` around `anchor` (a camera move).
func camera(scale k: CGFloat, anchor: CGPoint, _ body: () -> Void) {
    ctxRef.saveGState()
    ctxRef.translateBy(x: anchor.x, y: anchor.y); ctxRef.scaleBy(x: k, y: k); ctxRef.translateBy(x: -anchor.x, y: -anchor.y)
    body()
    ctxRef.restoreGState()
}
func symbol(_ name: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .medium) -> NSImage? {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size, weight: weight)) else { return nil }
    return NSImage(size: base.size, flipped: false) { r in base.draw(in: r); color.set(); r.fill(using: .sourceAtop); return true }
}
let claudeMark: NSImage? = {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop"),
          let img = Bundle(url: url)?.image(forResource: "TrayIconTemplate") else { return nil }
    return NSImage(size: img.size, flipped: false) { r in img.draw(in: r); clay.set(); r.fill(using: .sourceAtop); return true }
}()

// Film grain, generated once
let grain: CGImage = {
    let size = 256
    var bytes = [UInt8](repeating: 0, count: size * size * 4)
    for i in 0..<(size * size) { let v = UInt8.random(in: 0...255, using: &rng); bytes[i * 4] = v; bytes[i * 4 + 1] = v; bytes[i * 4 + 2] = v; bytes[i * 4 + 3] = 255 }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}()

// MARK: - Backgrounds

func backdrop(_ t: Double) {
    fill(CGRect(x: 0, y: 0, width: W, height: H), rgb(0x09090B))
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let glows: [(CGPoint, CGFloat, UInt32, CGFloat)] = [
        (CGPoint(x: 420 + 40 * sin(t * 0.15), y: 260), 760, 0x3B5BDB, 0.13),
        (CGPoint(x: 1560 + 50 * cos(t * 0.12), y: 900), 820, 0x7048E8, 0.10),
        (CGPoint(x: 1200, y: 180 + 30 * sin(t * 0.2)), 520, 0xD97757, 0.05),
    ]
    for (c, r, hex, a) in glows {
        let g = CGGradient(colorsSpace: space, colors: [rgb(hex, a).cgColor, rgb(hex, 0).cgColor] as CFArray, locations: [0, 1])!
        ctxRef.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [])
    }
}
func vignetteAndGrain(_ frame: Int) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let v = CGGradient(colorsSpace: space, colors: [rgb(0, 0).cgColor, rgb(0, 0.55).cgColor] as CFArray, locations: [0.55, 1])!
    ctxRef.drawRadialGradient(v, startCenter: CGPoint(x: W / 2, y: H / 2), startRadius: 0, endCenter: CGPoint(x: W / 2, y: H / 2), endRadius: 1150, options: [.drawsAfterEndLocation])
    ctxRef.saveGState()
    ctxRef.setAlpha(0.035)
    ctxRef.setBlendMode(.overlay)
    let ox = CGFloat((frame * 37) % 256), oy = CGFloat((frame * 91) % 256)
    var y: CGFloat = -oy
    while y < H { var x: CGFloat = -ox; while x < W { ctxRef.draw(grain, in: CGRect(x: x, y: y, width: 256, height: 256)); x += 256 }; y += 256 }
    ctxRef.restoreGState()
}
/// A dark macOS desktop with the menu bar, for the scenes that show Perch in place.
func desktop(_ t: Double) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let g = CGGradient(colorsSpace: space, colors: [rgb(0x101629).cgColor, rgb(0x1A1433).cgColor, rgb(0x0E0E14).cgColor] as CFArray, locations: [0, 0.6, 1])!
    ctxRef.drawLinearGradient(g, start: .zero, end: CGPoint(x: W * 0.6, y: H), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let glow = CGGradient(colorsSpace: space, colors: [rgb(0x4C6EF5, 0.16).cgColor, rgb(0x4C6EF5, 0).cgColor] as CFArray, locations: [0, 1])!
    ctxRef.drawRadialGradient(glow, startCenter: CGPoint(x: 1400, y: 820), startRadius: 0, endCenter: CGPoint(x: 1400, y: 820), endRadius: 900, options: [])
    fill(CGRect(x: 0, y: 0, width: W, height: 34), rgb(0x000000, 0.42))
    if let apple = symbol("applelogo", size: 15, color: white) { draw(apple, in: CGRect(x: 24, y: 8, width: apple.size.width, height: apple.size.height)) }
    text("Finder", font(14, .semibold), white, x: 54, y: 8)
    var x: CGFloat = 120
    for item in ["File", "Edit", "View", "Go", "Window", "Help"] { text(item, font(14), white, x: x, y: 8); x += width(item, font(14)) + 22 }
    text("Mon 9:41 AM", font(14), white, x: W - 120, y: 8)
}

// MARK: - Type

let display = font(56, .semibold)
let displayKern: CGFloat = -1.3
let subFont = font(24)
let eyebrowFont = font(14, .semibold)

/// Line reveal: each line slides up from behind a mask, staggered.
func headline(_ lines: [String], x: CGFloat, y: CGFloat, t: Double, start: Double, end: Double, align: NSTextAlignment = .left,
              eyebrow: String? = nil, eyebrowColor: NSColor = blueAccent, sub: [String] = []) {
    let out = 1 - prog(t, end - 0.5, end)
    guard t >= start - 0.01, out > 0.002 else { return }
    let lineH: CGFloat = 66
    func xFor(_ w: CGFloat) -> CGFloat { align == .center ? x - w / 2 : (align == .right ? x - w : x) }
    var cy = y
    if let eyebrow {
        let p = quintOut(prog(t, start, start + 0.7))
        let s = eyebrow.uppercased()
        text(s, eyebrowFont, eyebrowColor, x: xFor(width(s, eyebrowFont, kern: 2.4)), y: cy + CGFloat(1 - p) * 10, alpha: p * out, kern: 2.4)
        cy += 34
    }
    for (i, line) in lines.enumerated() {
        let p = expoOut(prog(t, start + 0.12 + Double(i) * 0.1, start + 1.1 + Double(i) * 0.1))
        let w = width(line, display, kern: displayKern)
        let box = CGRect(x: xFor(w) - 4, y: cy - 4, width: w + 8, height: lineH + 6)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: box).addClip()
        text(line, display, white, x: xFor(w), y: cy + CGFloat(1 - p) * lineH, alpha: out, kern: displayKern)
        NSGraphicsContext.restoreGraphicsState()
        cy += lineH
    }
    cy += 14
    for (i, line) in sub.enumerated() {
        let p = quintOut(prog(t, start + 0.45 + Double(i) * 0.06, start + 1.3 + Double(i) * 0.06))
        text(line, subFont, grey, x: xFor(width(line, subFont)), y: cy + CGFloat(1 - p) * 12, alpha: p * out)
        cy += 34
    }
}

func cursor(_ p: CGPoint, pressed: Bool) {
    let s: CGFloat = pressed ? 1.0 : 1.12
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 25), (6, 19.5), (10.5, 28.5), (14.5, 26.8), (10.2, 18), (18, 18)]
    let path = NSBezierPath(); path.move(to: p)
    for q in pts.dropFirst() { path.line(to: NSPoint(x: p.x + q.0 * s, y: p.y + q.1 * s)) }
    path.close()
    shadow(blur: 6, y: 2, a: 0.4) { NSColor.black.setFill(); path.fill() }
    path.lineWidth = 1.8; NSColor.white.setStroke(); path.stroke()
}
func ring(_ r: CGRect, t: Double, start: Double, color: NSColor = blueAccent, radius: CGFloat = 12) {
    let p = prog(t, start, start + 1.0)
    guard p > 0 && p < 1 else { return }
    let g = CGFloat(expoOut(p)) * 10
    stroke(r.insetBy(dx: -4 - g, dy: -4 - g), color.withAlphaComponent(CGFloat(1 - p) * 0.9), radius: radius + g, width: 2)
}
func keycaps(_ keys: [String], cx: CGFloat, cy: CGFloat, t: Double, start: Double, end: Double) {
    let a = fade(t, start, end, 0.25)
    guard a > 0.002 else { return }
    let f = font(22, .medium), h: CGFloat = 50, gap: CGFloat = 10
    let ws = keys.map { max(h, width($0, f) + 30) }
    var x = cx - (ws.reduce(0, +) + gap * CGFloat(keys.count - 1)) / 2
    for (i, key) in keys.enumerated() {
        let p = spring(prog(t, start + Double(i) * 0.08, start + Double(i) * 0.08 + 0.55))
        let r = CGRect(x: x, y: cy - h / 2 + CGFloat(1 - p) * 10, width: ws[i], height: h)
        layer(a * min(1, p * 1.5)) {
            fill(r, rgb(0x1C1C21), radius: 11); stroke(r, rgb(0x3A3A42), radius: 11)
            text(key, f, white, x: r.midX - width(key, f) / 2, y: r.midY - 14)
        }
        x += ws[i] + gap
    }
}
func appWindow(_ r: CGRect, title: String, alpha: Double, body: (CGRect) -> Void) {
    layer(alpha) {
        shadow(blur: 50, y: 22, a: 0.6) { fill(r, rgb(0x1C1C1F), radius: 12) }
        stroke(r, rgb(0xFFFFFF, 0.08), radius: 12)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12).addClip()
        fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 38), rgb(0x26262A))
        fill(CGRect(x: r.minX, y: r.minY + 37, width: r.width, height: 1), rgb(0x000000, 0.4))
        NSGraphicsContext.restoreGraphicsState()
        for (i, hex) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
            rgb(hex).setFill(); NSBezierPath(ovalIn: CGRect(x: r.minX + 14 + CGFloat(i) * 19, y: r.minY + 13, width: 12, height: 12)).fill()
        }
        let f = font(13, .semibold)
        text(title, f, rgb(0xB0B0B6), x: r.midX - width(title, f) / 2, y: r.minY + 11)
        body(CGRect(x: r.minX, y: r.minY + 38, width: r.width, height: r.height - 38))
    }
}
func panel(_ p: Placed, alpha: Double = 1) { shadow { draw(p.image, in: p.rect, alpha: alpha) } }
/// Cross-fades a sequence of island images placed at the same spot.
func states(_ list: [(NSImage, Double)], at rect: CGRect, t: Double) {
    shadow {
        layer(1) {
            for (i, s) in list.enumerated() {
                let a = (s.1 == 0 ? 1 : prog(t, s.1, s.1 + 0.4)) * (i + 1 < list.count ? 1 - prog(t, list[i + 1].1, list[i + 1].1 + 0.4) : 1)
                if a > 0 { draw(s.0, in: rect, alpha: a) }
            }
        }
    }
}

// MARK: - Scenes

/// A scene draws itself; the frame cross-fades overlapping scenes.
struct Scene { let start: Double; let end: Double; let draw: (Double) -> Void }
let fadeTime = 0.6

// Split-layout positions
let panelW: CGFloat = 1000
let rightPanelX: CGFloat = 830, leftPanelX: CGFloat = 110
let textLeftX: CGFloat = 150, textRightX: CGFloat = 1180
let heroScale = 1440 / px(shelf0).width

var scenes: [Scene] = []

func logoScene(_ t: Double, start: Double) {
    let p = quintOut(prog(t, start + 0.2, start + 1.4))
    let c = CGPoint(x: W / 2, y: 470)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let bloom = CGGradient(colorsSpace: space, colors: [rgb(0xD97757, 0.26 * CGFloat(p)).cgColor, rgb(0xD97757, 0).cgColor] as CFArray, locations: [0, 1])!
    ctxRef.drawRadialGradient(bloom, startCenter: c, startRadius: 0, endCenter: c, endRadius: 360, options: [])
    let size = 210 * CGFloat(0.92 + 0.08 * p)
    shadow(blur: 50, y: 20, a: 0.6) { draw(appIcon, in: CGRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size), alpha: p) }
    let f = font(64, .semibold)
    let w = width("Perch", f, kern: -1.5)
    let q = expoOut(prog(t, start + 0.9, start + 2.0))
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: CGRect(x: W / 2 - w / 2 - 10, y: 600, width: w + 20, height: 84)).addClip()
    text("Perch", f, white, x: W / 2 - w / 2, y: 606 + CGFloat(1 - q) * 76, kern: -1.5)
    NSGraphicsContext.restoreGraphicsState()
}

// 1. Logo
scenes.append(Scene(start: 0, end: 3.6) { t in logoScene(t, start: 0) })
sfx(0.25, .whoosh, 0.5)

// 2. The pill drops in at the top of the screen
let heroPill = placeTop(pill0, scale: heroScale)
scenes.append(Scene(start: 3.2, end: 8.2) { t in
    let push = inOut(prog(t, 3.4, 8.2))
    camera(scale: 1 + 0.02 * CGFloat(push), anchor: CGPoint(x: W / 2, y: 60)) {
        desktop(t)
        let drop = expoOut(prog(t, 4.0, 5.0))
        shadow(blur: 30, y: 10, a: 0.5) { draw(heroPill.image, in: heroPill.rect.offsetBy(dx: 0, dy: CGFloat(1 - drop) * -90), alpha: drop) }
    }
    headline(["A shelf at the top of your Mac."], x: W / 2, y: 770, t: t, start: 4.6, end: 8.2, align: .center, eyebrow: "Meet Perch")
})
sfx(4.0, .whoosh, 0.5)

// 3. Hover to open
let heroShelf = placeTop(shelf0, scale: heroScale)
scenes.append(Scene(start: 7.6, end: 12.6) { t in
    desktop(t)
    let open = spring(prog(t, 9.3, 10.1))
    if t < 9.3 {
        shadow(blur: 30, y: 10, a: 0.5) { draw(heroPill.image, in: heroPill.rect) }
    } else {
        let k0 = heroPill.rect.width / heroShelf.rect.width
        let k = lerp(k0, 1, open)
        let r = CGRect(x: W / 2 - heroShelf.rect.width * k / 2, y: heroShelf.rect.minY + pad * heroShelf.k * (1 - k),
                       width: heroShelf.rect.width * k, height: heroShelf.rect.height * k)
        shadow { draw(heroShelf.image, in: r, alpha: clamp(open * 1.8)) }
        draw(heroPill.image, in: heroPill.rect, alpha: 1 - clamp(open * 3))
    }
    let target = CGPoint(x: W / 2 + 8, y: 62)
    var c = lerp(CGPoint(x: 1300, y: 760), target, inOut(prog(t, 8.1, 9.2)))
    if t > 10.3 { c = lerp(target, CGPoint(x: 1340, y: 720), inOut(prog(t, 10.4, 11.6))) }
    cursor(c, pressed: false)
    headline(["Everything you need, one hover away."], x: W / 2, y: 770, t: t, start: 10.0, end: 12.6, align: .center)
})
sfx(9.3, .whoosh, 0.8)

// 4. Capture — text left, shelf right
scenes.append(Scene(start: 12.2, end: 18.4) { t in
    backdrop(t)
    let p = place(shelf0, width: panelW, x: rightPanelX, y: 300)
    let drift = CGFloat(inOut(prog(t, 12.2, 18.4))) * -12
    let rect = p.rect.offsetBy(dx: drift, dy: 0)
    states([(shelf0, 0), (shelf1, 14.5), (shelf2, 16.5)], at: rect, t: t)
    let moved = Placed(image: shelf1, rect: rect)
    ring(moved.card(0), t: t, start: 14.7)
    ring(moved.card(0), t: t, start: 16.7, color: rgb(0xFF6B6B))
    keycaps(["⌘", "⇧", "4"], cx: rect.midX, cy: rect.maxY + 30, t: t, start: 13.5, end: 14.6)
    if t > 14.3 && t < 14.7 { fill(rect.insetBy(dx: pad * p.k, dy: pad * p.k), rgb(0xFFFFFF, 0.12 * CGFloat(1 - prog(t, 14.3, 14.7))), radius: 28 * p.k) }
    headline(["Screenshots and", "recordings, caught", "automatically."], x: textLeftX, y: 360, t: t, start: 12.6, end: 18.4,
             eyebrow: "Capture", sub: ["They land on your shelf the", "moment you take them."])
})
sfx(13.5, .key); sfx(13.58, .key); sfx(13.66, .key); sfx(14.3, .click, 0.6); sfx(14.55, .pop); sfx(16.5, .pop)

// 5. Drag & drop — shelf left, text right
scenes.append(Scene(start: 18.0, end: 24.0) { t in
    backdrop(t)
    let p = place(shelf2, width: 860, x: leftPanelX, y: 210)
    panel(p)
    let chat = CGRect(x: 470, y: 600, width: 520, height: 300)
    let chatIn = expoOut(prog(t, 18.6, 19.4))
    appWindow(chat.offsetBy(dx: 0, dy: CGFloat(1 - chatIn) * 60), title: "Team chat", alpha: chatIn) { body in
        fill(CGRect(x: body.minX + 18, y: body.minY + 18, width: 330, height: 42), rgb(0x2C2C30), radius: 16)
        text("Can you send me the dashboard?", font(15), white, x: body.minX + 34, y: body.minY + 30)
        let landed = spring(prog(t, 21.9, 22.5))
        if landed > 0 {
            let k = CGFloat(0.75 + 0.25 * landed)
            let r = CGRect(x: body.maxX - 18 - 210 * k, y: body.minY + 76, width: 210 * k, height: 140 * k)
            drawClipped(dashboard, in: r, radius: 12, alpha: min(1, landed * 1.4))
            let b = CGRect(x: body.maxX - 18 - 112, y: body.minY + 224, width: 112, height: 30)
            fill(b, rgb(0x0A84FF, CGFloat(min(1, landed))), radius: 15)
            text("Here it is", font(14, .medium), .white, x: b.midX - width("Here it is", font(14, .medium)) / 2, y: b.minY + 6, alpha: min(1, landed))
        }
    }
    let card = CGPoint(x: p.preview(1).midX, y: p.preview(1).midY)
    let drop = CGPoint(x: chat.maxX - 120, y: chat.minY + 160)
    var c = lerp(CGPoint(x: 900, y: 820), card, inOut(prog(t, 19.0, 19.9)))
    if t > 20.1 { c = lerp(card, drop, inOut(prog(t, 20.2, 21.7))) }
    if t > 22.0 { c = lerp(drop, CGPoint(x: 1000, y: 900), inOut(prog(t, 22.2, 23.2))) }
    if t > 20.1 && t < 21.95 {
        let lift = expoOut(prog(t, 20.1, 20.4))
        shadow(blur: 26, y: 12, a: 0.5) { drawClipped(dashboard, in: CGRect(x: c.x - 70, y: c.y - 44, width: 150, height: 100), radius: 10, alpha: lift * 0.97) }
    }
    cursor(c, pressed: t > 20.05 && t < 21.9)
    headline(["Drag anything out,", "into any app."], x: textRightX, y: 390, t: t, start: 18.4, end: 24.0,
             eyebrow: "Drag & drop", sub: ["Drop images, files and text straight", "into a chat, an email or Finder."])
})
sfx(18.6, .whoosh, 0.4); sfx(20.1, .click); sfx(20.25, .whoosh, 0.35); sfx(21.9, .click); sfx(22.0, .pop)

// 6. Select several — text left, shelf right
scenes.append(Scene(start: 23.6, end: 29.4) { t in
    backdrop(t)
    let p = place(shelf3, width: panelW, x: rightPanelX, y: 230)
    states([(shelf3, 0), (shelfSelect, 25.9)], at: p.rect, t: t)
    for (i, at) in [24.7, 25.2, 25.7].enumerated() where t > at && t < 26.1 {
        stroke(p.card(i).insetBy(dx: 1, dy: 1), blueAccent, radius: 20 * p.k, width: 3)
    }
    let finder = CGRect(x: 1180, y: 640, width: 560, height: 300)
    let fIn = expoOut(prog(t, 24.0, 24.8))
    appWindow(finder.offsetBy(dx: 0, dy: CGFloat(1 - fIn) * 60), title: "Project files", alpha: fIn) { body in
        fill(CGRect(x: body.minX, y: body.minY, width: 130, height: body.height), rgb(0x232327))
        for (i, s) in ["Recents", "Desktop", "Documents"].enumerated() { text(s, font(13), grey, x: body.minX + 16, y: body.minY + 16 + CGFloat(i) * 26) }
        let landed = spring(prog(t, 27.9, 28.5))
        if landed > 0 {
            let items: [NSImage?] = [symbol("doc.text.fill", size: 44, color: rgb(0x8E8E93)), sunset, dashboard]
            for (i, img) in items.enumerated() {
                let k = CGFloat(0.7 + 0.3 * landed)
                let r = CGRect(x: body.minX + 150 + CGFloat(i) * 130, y: body.minY + 30, width: 100 * k, height: 72 * k)
                if let img { drawClipped(img, in: r, radius: 7, alpha: min(1, landed * 1.4)) }
            }
        }
    }
    let c0 = CGPoint(x: p.preview(0).midX, y: p.preview(0).midY), c1 = CGPoint(x: p.preview(1).midX, y: p.preview(1).midY)
    let c2 = CGPoint(x: p.preview(2).midX, y: p.preview(2).midY)
    let drop = CGPoint(x: finder.midX + 40, y: finder.midY + 20)
    var c = lerp(CGPoint(x: 1300, y: 860), c0, inOut(prog(t, 24.2, 24.65)))
    if t > 24.75 { c = lerp(c0, c1, inOut(prog(t, 24.8, 25.15))) }
    if t > 25.25 { c = lerp(c1, c2, inOut(prog(t, 25.3, 25.65))) }
    if t > 26.3 { c = lerp(c2, drop, inOut(prog(t, 26.5, 27.7))) }
    if t > 28.0 { c = lerp(drop, CGPoint(x: 1500, y: 980), inOut(prog(t, 28.2, 29.1))) }
    if t > 26.4 && t < 27.95 {
        let lift = expoOut(prog(t, 26.4, 26.7))
        for (i, img) in [loginThumb, sunset, dashboard].enumerated() {
            shadow(blur: 18, y: 10, a: 0.45) { drawClipped(img, in: CGRect(x: c.x - 66 + CGFloat(i) * 7, y: c.y - 40 - CGFloat(i) * 7, width: 132, height: 88), radius: 9, alpha: lift * 0.97) }
        }
        let b = CGRect(x: c.x + 64, y: c.y - 62, width: 28, height: 28)
        rgb(0xFF453A, CGFloat(lift)).setFill(); NSBezierPath(ovalIn: b).fill()
        text("3", font(15, .bold), .white, x: b.midX - 4.5, y: b.minY + 5, alpha: lift)
    }
    cursor(c, pressed: (t > 24.68 && t < 24.8) || (t > 25.18 && t < 25.3) || (t > 25.68 && t < 25.8) || (t > 26.3 && t < 27.9))
    headline(["Grab a few", "at once."], x: textLeftX, y: 390, t: t, start: 24.0, end: 29.4,
             eyebrow: "Select", sub: ["⌘-click to select, then drag", "them all together."])
})
sfx(24.0, .whoosh, 0.35); sfx(24.7, .click); sfx(25.15, .key, 0.6); sfx(25.2, .click); sfx(25.7, .click); sfx(26.3, .click); sfx(27.9, .click); sfx(28.0, .pop)

// 7. Preview & find — shelf left, text right
scenes.append(Scene(start: 29.0, end: 34.6) { t in
    backdrop(t)
    let p = place(shelf3, width: 860, x: leftPanelX, y: 300)
    states([(shelf3, 0), (searchImg, 32.9)], at: p.rect, t: t)
    keycaps(["Space"], cx: p.rect.midX, cy: p.rect.maxY + 20, t: t, start: 29.6, end: 30.4)
    let ql = spring(prog(t, 29.9, 30.5)) * (1 - inOut(prog(t, 31.6, 32.0)))
    if ql > 0.002 {
        let k = CGFloat(0.9 + 0.1 * ql)
        let r = CGRect(x: p.rect.midX - 300 * k, y: 330 + (1 - k) * 100, width: 600 * k, height: 430 * k)
        appWindow(r, title: "Screenshot 9.41.12 AM.png", alpha: min(1, ql * 1.3)) { body in
            fill(body, rgb(0x151517)); draw(dashboard, in: body.insetBy(dx: 20, dy: 20))
        }
    }
    keycaps(["⌥", "⌘", "F"], cx: p.rect.midX, cy: p.rect.maxY + 20, t: t, start: 32.1, end: 33.2)
    headline(["Space to preview.", "⌥⌘F to find."], x: textRightX, y: 390, t: t, start: 29.4, end: 34.6,
             eyebrow: "Preview & find", sub: ["Quick Look anything, or search", "every card by name and text."])
})
sfx(29.6, .key); sfx(29.9, .whoosh, 0.4); sfx(31.6, .key); sfx(32.1, .key); sfx(32.18, .key); sfx(32.26, .key); sfx(32.6, .key, 0.7); sfx(32.75, .key, 0.7)

// 8. Built for Claude Code
scenes.append(Scene(start: 34.2, end: 38.0) { t in
    backdrop(t)
    let a = 1 - prog(t, 37.5, 38.0)
    let eye = quintOut(prog(t, 34.6, 35.3))
    let s = "CLAUDE CODE"
    text(s, eyebrowFont, clay, x: W / 2 - width(s, eyebrowFont, kern: 2.4) / 2, y: 412 + CGFloat(1 - eye) * 10, alpha: eye * a, kern: 2.4)
    let prefix = "Built for", chipLabel = "Claude Code"
    let pw = width(prefix, display, kern: displayKern), cw = width(chipLabel, display, kern: displayKern) + 44 + 40
    let total = pw + 18 + cw
    let x0 = W / 2 - total / 2, y0: CGFloat = 470
    let p1 = expoOut(prog(t, 34.75, 35.8))
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(rect: CGRect(x: x0 - 4, y: y0 - 6, width: pw + 8, height: 76)).addClip()
    text(prefix, display, white, x: x0, y: y0 + CGFloat(1 - p1) * 66, alpha: a, kern: displayKern)
    NSGraphicsContext.restoreGraphicsState()
    let pop = spring(prog(t, 35.1, 36.0))
    let k = CGFloat(0.9 + 0.1 * pop)
    let chip = CGRect(x: x0 + pw + 18 + cw * (1 - k) / 2, y: y0 - 4 + 36 * (1 - k), width: cw * k, height: 72 * k)
    layer(min(1, pop * 1.5) * a) {
        fill(chip, rgb(0x2A1D17), radius: chip.height / 2)
        stroke(chip, clay.withAlphaComponent(0.35), radius: chip.height / 2)
        if let m = claudeMark { draw(m, in: CGRect(x: chip.minX + 22 * k, y: chip.midY - 15 * k, width: 30 * k, height: 30 * k)) }
        text(chipLabel, font(56 * k, .semibold), clay, x: chip.minX + 64 * k, y: chip.minY + 2 * k, kern: displayKern * k)
    }
    let sub = "Every session and your plan usage, right on the shelf."
    let p2 = quintOut(prog(t, 35.6, 36.5))
    text(sub, subFont, grey, x: W / 2 - width(sub, subFont) / 2, y: 572 + CGFloat(1 - p2) * 12, alpha: p2 * a)
})
sfx(35.1, .pop, 0.6)

// 9. Claude sessions in place: the camera pushes in, then the terminal
let heroClaude = placeTop(claudeImg, scale: heroScale)
scenes.append(Scene(start: 37.6, end: 44.6) { t in
    let push = inOut(prog(t, 38.3, 40.2)) * (1 - inOut(prog(t, 41.0, 41.8)))
    let focus = CGPoint(x: heroClaude.card(0).midX + 120, y: heroClaude.card(0).midY)
    camera(scale: 1 + 0.32 * CGFloat(push), anchor: focus) {
        desktop(t)
        shadow { draw(heroClaude.image, in: heroClaude.rect, alpha: quintOut(prog(t, 37.6, 38.4))) }
        ring(heroClaude.card(0), t: t, start: 39.3, color: rgb(0xF5B13A))
        ring(heroClaude.card(0), t: t, start: 40.1, color: rgb(0xF5B13A))
    }
    let goTab = CGPoint(x: heroClaude.card(0).midX, y: heroClaude.card(0).minY + 222 * heroClaude.k)
    if t > 41.8 && t < 43.8 {
        var c = lerp(CGPoint(x: 1200, y: 760), goTab, inOut(prog(t, 41.8, 42.3)))
        if t > 42.6 { c = lerp(goTab, CGPoint(x: 1500, y: 920), inOut(prog(t, 42.9, 43.7))) }
        cursor(c, pressed: t > 42.35 && t < 42.5)
    }
    let termIn = expoOut(prog(t, 42.6, 43.3))
    let r = CGRect(x: 520, y: 470 + CGFloat(1 - termIn) * 70, width: 880, height: 330)
    appWindow(r, title: "api — claude", alpha: termIn * (1 - prog(t, 44.1, 44.6))) { body in
        let f = font(17, .regular, mono: true)
        let lines: [(String, UInt32)] = [("~/code/api ❯ claude", 0xD1D1D6), ("✻ Refactoring the API client…", 0xE8957A),
                                         ("  Updated 4 files, tests passing", 0x8E8E93), ("", 0), ("⏺ Allow edits to src/client.ts?", 0xF5B13A), ("  ❯ 1. Yes    2. No", 0xD1D1D6)]
        for (i, l) in lines.enumerated() { text(l.0, f, rgb(l.1), x: body.minX + 26, y: body.minY + 22 + CGFloat(i) * 32) }
    }
    headline(["Jump straight to the session that needs you."], x: W / 2, y: 880, t: t, start: 38.6, end: 44.6, align: .center,
             eyebrow: "Sessions", eyebrowColor: clay)
})
sfx(37.7, .whoosh, 0.5); sfx(39.3, .chime, 0.8); sfx(42.35, .click); sfx(42.6, .whoosh, 0.4)

// 10. Usage: zoom into the meters
scenes.append(Scene(start: 44.2, end: 48.8) { t in
    let z = inOut(prog(t, 44.5, 45.6))
    let focus = CGPoint(x: heroClaude.rect.minX + 560 * heroClaude.k, y: heroClaude.rect.minY + 455 * heroClaude.k)
    camera(scale: 1 + 0.75 * CGFloat(z), anchor: focus) {
        desktop(t)
        shadow { draw(heroClaude.image, in: heroClaude.rect) }
    }
    headline(["Your plan limits, live."], x: W / 2, y: 820, t: t, start: 45.2, end: 48.8, align: .center, eyebrow: "Usage", eyebrowColor: clay,
             sub: ["5-hour and weekly usage, with reset timers."])
})
sfx(44.5, .whoosh, 0.35)

// 11. Styles
scenes.append(Scene(start: 48.4, end: 53.8) { t in
    backdrop(t)
    headline(["Notch, floating or orb."], x: W / 2, y: 250, t: t, start: 48.7, end: 53.8, align: .center, eyebrow: "Make it yours")
    let items: [(NSImage, String, Bool)] = [(styleNotch, "Notch", true), (styleFloating, "Floating", false), (styleOrb, "Orb", false)]
    let leave = 1 - prog(t, 53.3, 53.8)
    for (i, item) in items.enumerated() {
        let p = expoOut(prog(t, 49.2 + Double(i) * 0.15, 50.2 + Double(i) * 0.15))
        let screen = CGRect(x: W / 2 - 230 + CGFloat(i - 1) * 500, y: 430 + CGFloat(1 - p) * 40, width: 460, height: 280)
        layer(p * leave) {
            shadow(blur: 50, y: 20, a: 0.6) { fill(screen, rgb(0x141418), radius: 16) }
            stroke(screen, rgb(0xFFFFFF, 0.08), radius: 16)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: screen, xRadius: 16, yRadius: 16).addClip()
            fill(CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: 18), rgb(0x1F1F25))
            let size = px(item.0), s: CGFloat = 0.95 * heroScale
            let top = item.2 ? screen.minY : screen.minY + 30 - pad * s
            draw(item.0, in: CGRect(x: screen.midX - size.width * s / 2, y: top, width: size.width * s, height: size.height * s))
            NSGraphicsContext.restoreGraphicsState()
            let f = font(20, .medium)
            text(item.1, f, grey, x: screen.midX - width(item.1, f) / 2, y: screen.maxY + 20)
        }
    }
    let sub = "Top, left or right edge. Dark or light. Drag it anywhere."
    let q = quintOut(prog(t, 50.4, 51.2))
    text(sub, subFont, grey, x: W / 2 - width(sub, subFont) / 2, y: 820 + CGFloat(1 - q) * 12, alpha: q * leave)
})
sfx(49.2, .pop, 0.4); sfx(49.35, .pop, 0.4); sfx(49.5, .pop, 0.4)

// 12. Private by design
scenes.append(Scene(start: 53.4, end: 57.8) { t in
    backdrop(t)
    headline(["Private by design."], x: W / 2, y: 400, t: t, start: 53.7, end: 57.8, align: .center, eyebrow: "Privacy")
    let pills: [(String, String, Double)] = [("eye.slash", "Secrets stay blurred", 54.5), ("play.rectangle", "Hides during full-screen video", 54.7),
                                             ("hand.raised", "Copies stay off the shelf unless you ask", 54.9)]
    let f = font(19, .medium)
    let ws = pills.map { width($0.1, f) + 74 }
    var x = W / 2 - (ws.reduce(0, +) + 14 * CGFloat(pills.count - 1)) / 2
    for (i, item) in pills.enumerated() {
        let p = expoOut(prog(t, item.2, item.2 + 0.8)) * (1 - prog(t, 57.3, 57.8))
        let r = CGRect(x: x, y: 540 + CGFloat(1 - p) * 14, width: ws[i], height: 48)
        layer(p) {
            fill(r, rgb(0x18181C), radius: 24); stroke(r, rgb(0xFFFFFF, 0.09), radius: 24)
            if let ic = symbol(item.0, size: 17, color: rgb(0xC7C7CC)) { draw(ic, in: CGRect(x: r.minX + 20, y: r.midY - ic.size.height / 2, width: ic.size.width, height: ic.size.height)) }
            text(item.1, f, rgb(0xE5E5EA), x: r.minX + 50, y: r.minY + 12)
        }
        x += ws[i] + 14
    }
})

// 13. End: logo and name
scenes.append(Scene(start: 57.4, end: 62.0) { t in logoScene(t, start: 57.4) })
sfx(57.6, .whoosh, 0.45)

func renderFrame(_ ctx: CGContext, frame: Int) {
    ctxRef = ctx
    let t = Double(frame) / Double(FPS)
    fill(CGRect(x: 0, y: 0, width: W, height: H), rgb(0x09090B))
    for s in scenes where t >= s.start && t < s.end {
        // Overlapping scenes cross-dissolve with a subtle scale
        let inA = s.start == 0 ? 1 : prog(t, s.start, s.start + fadeTime)
        let outA = s.end >= duration ? 1 : 1 - prog(t, s.end - fadeTime, s.end)
        let a = min(inA, outA)
        let k = 1 + 0.015 * CGFloat(1 - inA) - 0.01 * CGFloat(1 - outA)
        layer(a) { camera(scale: k, anchor: CGPoint(x: W / 2, y: H / 2)) { s.draw(t) } }
    }
    vignetteAndGrain(frame)
}

// MARK: - Video

let tempVideo = FileManager.default.temporaryDirectory.appendingPathComponent("perch-video-\(UUID().uuidString).mp4")

func writeVideo() {
    let writer = try! AVAssetWriter(outputURL: tempVideo, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(W), AVVideoHeightKey: Int(H),
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 16_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
    ])
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(W), kCVPixelBufferHeightKey as String: Int(H),
    ])
    writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
    let frames = Int(duration * Double(FPS))
    for f in 0..<frames {
        while !input.isReadyForMoreMediaData { usleep(2000) }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        let pb = buffer!
        CVPixelBufferLockBaseAddress(pb, [])
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: Int(W), height: Int(H), bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        renderFrame(ctx, frame: f)
        NSGraphicsContext.restoreGraphicsState()
        CVPixelBufferUnlockBaseAddress(pb, [])
        adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(FPS)))
        if f % 300 == 0 { print("video \(f)/\(frames)") }
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
}

func mux() {
    let composition = AVMutableComposition()
    // Keep the assets alive while their tracks are used.
    let videoAsset = AVURLAsset(url: tempVideo), audioAsset = AVURLAsset(url: tempAudio)
    let videoTrack = videoAsset.tracks(withMediaType: .video)[0]
    let audioTrack = audioAsset.tracks(withMediaType: .audio)[0]
    // Use the encoded video's real length (it can end a fraction of a frame before `duration`).
    let length = CMTimeMinimum(videoTrack.timeRange.duration, audioTrack.timeRange.duration)
    let range = CMTimeRange(start: .zero, duration: length)
    let v = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    let a = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try! v.insertTimeRange(range, of: videoTrack, at: .zero)
    try! a.insertTimeRange(range, of: audioTrack, at: .zero)
    try? FileManager.default.removeItem(at: finalURL)
    let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)!
    export.outputURL = finalURL; export.outputFileType = .mp4
    let done = DispatchSemaphore(value: 0)
    export.exportAsynchronously { done.signal() }
    done.wait()
    withExtendedLifetime((videoAsset, audioAsset)) {}
}

writeVideo()
print("audio (\(musicStyle)\(useVoice ? ", voice: \(voiceName)" : ""))…")
writeAudio(to: tempAudio)
print("mux…")
mux()
try? FileManager.default.removeItem(at: tempVideo)
try? FileManager.default.removeItem(at: tempAudio)
print("Wrote \(finalURL.path)")

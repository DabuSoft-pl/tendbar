// Synthesizes Tendbar's alert sounds: short bird calls built from frequency swept sine tones, so the app ships
// no recorded or licensed audio. Run from the repository root: swift tools/make-sounds.swift
import Foundation

let rate = 44_100.0

/// One chirp: a tone sweeping from `from` to `to` Hz with a soft attack, a quick decay and a little vibrato.
struct Chirp {
    var start: Double
    var length: Double
    var from: Double
    var to: Double
    var level = 0.8
    var vibrato = 0.0
    var overtone = 0.12
}

func render(_ chirps: [Chirp], tail: Double = 0.08) -> [Int16] {
    let total = (chirps.map { $0.start + $0.length }.max() ?? 0) + tail
    var samples = [Double](repeating: 0, count: Int(total * rate))
    for chirp in chirps {
        var phase = 0.0
        let count = Int(chirp.length * rate)
        let offset = Int(chirp.start * rate)
        for i in 0..<count {
            let t = Double(i) / Double(count)
            let curve = t * t * (3 - 2 * t)
            let frequency = chirp.from + (chirp.to - chirp.from) * curve
                + chirp.vibrato * sin(2 * .pi * 38 * Double(i) / rate)
            phase += 2 * .pi * frequency / rate
            let attack = min(1, t / 0.12)
            let decay = pow(1 - t, 1.6)
            let tone = sin(phase) + chirp.overtone * sin(2 * phase)
            samples[offset + i] += chirp.level * attack * decay * tone
        }
    }
    let peak = samples.map(abs).max() ?? 1
    return samples.map { Int16(($0 / peak * 0.7 * Double(Int16.max)).rounded()) }
}

func wav(_ samples: [Int16]) -> Data {
    var data = Data()
    func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
    let bytes = UInt32(samples.count * 2)
    data.append(contentsOf: Array("RIFF".utf8)); append(36 + bytes)
    data.append(contentsOf: Array("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
    append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
    data.append(contentsOf: Array("data".utf8)); append(bytes)
    samples.forEach(append)
    return data
}

let sounds: [String: [Chirp]] = [
    // Two rising calls, like a question: something waits for you.
    "tendbar-waiting": [
        Chirp(start: 0, length: 0.09, from: 2600, to: 3700),
        Chirp(start: 0.15, length: 0.11, from: 2700, to: 4000),
    ],
    // A short falling trill that settles: the turn is done.
    "tendbar-done": [
        Chirp(start: 0, length: 0.06, from: 3900, to: 3600, level: 0.6),
        Chirp(start: 0.07, length: 0.06, from: 3600, to: 3300, level: 0.65),
        Chirp(start: 0.14, length: 0.07, from: 3300, to: 3000, level: 0.7),
        Chirp(start: 0.23, length: 0.18, from: 3000, to: 2500, vibrato: 60),
    ],
    // Two low, rough falling notes: something went wrong.
    "tendbar-error": [
        Chirp(start: 0, length: 0.08, from: 2000, to: 1400, overtone: 0.45),
        Chirp(start: 0.13, length: 0.12, from: 1900, to: 1100, vibrato: 90, overtone: 0.45),
    ],
]

let folder = URL(fileURLWithPath: "Tendbar/Sounds")
for (name, chirps) in sounds {
    try wav(render(chirps)).write(to: folder.appendingPathComponent("\(name).wav"))
    print("wrote \(name).wav")
}

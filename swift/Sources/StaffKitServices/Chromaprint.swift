import Foundation

/// Chromaprint's audio fingerprint, computed in Swift so a sandboxed app (Velvet Display can't run `fpcalc`) and the
/// iPhone can fingerprint a song themselves. It is the same algorithm as Chromaprint's default (`TEST2`, what `fpcalc`
/// and AcoustID use), ported from its MIT-licensed parts (chroma, filters, classifiers, compression; Copyright (C)
/// 2010-2016 Lukas Lalinsky, MIT). Resampling to 11025 Hz is left to the caller (AVFoundation on Apple platforms),
/// not Chromaprint's LGPL resampler, so a fingerprint can differ from `fpcalc`'s in a few bits, as two encodings of
/// one recording do; AcoustID and `FingerprintTimeline` match on similarity, not equality.
///
/// Feed it mono 16-bit samples at `Chromaprint.sampleRate` with `consume(_:)`, then read `fingerprint` (raw
/// sub-fingerprints, about eight a second) or `compressed` (what `fpcalc` prints and AcoustID's lookup takes).
public struct Chromaprint: Sendable {
    public static let sampleRate = 11025
    /// AcoustID's algorithm number for this fingerprint (Chromaprint's `CHROMAPRINT_ALGORITHM_TEST2`).
    public static let algorithm = 1
    static let frameSize = 4096
    /// A frame every 1365 samples: frames overlap by two thirds.
    static let frameStep = frameSize - (frameSize - frameSize / 3)
    static let minFrequency = 28.0
    static let maxFrequency = 3520.0
    static let bands = 12
    static let filterCoefficients = [0.25, 0.75, 1.0, 0.75, 0.25]

    /// The raw fingerprint so far, one 32-bit sub-fingerprint per frame step once the first 16 frames are in.
    public private(set) var fingerprint: [UInt32] = []

    private var pending: [Int16] = []
    private var fft = RealFFT(size: frameSize)
    private var chromaHistory: [[Double]] = []
    private var integral: [[Double]] = []

    public init() {}

    /// Adds mono samples at 11025 Hz.
    public mutating func consume<C: Collection>(_ samples: C) where C.Element == Int16 {
        pending.append(contentsOf: samples)
        var start = 0
        while pending.count - start >= Self.frameSize {
            frame(pending[start..<(start + Self.frameSize)])
            start += Self.frameStep
        }
        if start > 0 { pending.removeFirst(start) }
    }

    /// The fingerprint as `fpcalc` prints it and AcoustID takes it: compressed, URL-safe base64 without padding.
    public var compressed: String { Self.compress(fingerprint) }

    /// Fingerprints mono 11025 Hz samples in one go.
    public static func fingerprint<C: Collection>(_ samples: C) -> [UInt32] where C.Element == Int16 {
        var printer = Chromaprint()
        printer.consume(samples)
        return printer.fingerprint
    }

    // MARK: Pipeline: FFT, chroma, chroma filter, normalizer, integral image, classifiers

    private mutating func frame(_ samples: ArraySlice<Int16>) {
        let power = fft.powerSpectrum(samples)
        var chroma = [Double](repeating: 0, count: Self.bands)
        for index in Self.notes.indices where Self.notes[index] >= 0 {
            chroma[Self.notes[index]] += power[index]
        }
        chromaHistory.append(chroma)
        guard chromaHistory.count >= Self.filterCoefficients.count else { return }
        if chromaHistory.count > Self.filterCoefficients.count { chromaHistory.removeFirst() }
        var filtered = [Double](repeating: 0, count: Self.bands)
        for (row, coefficient) in zip(chromaHistory, Self.filterCoefficients) {
            for band in 0..<Self.bands { filtered[band] += row[band] * coefficient }
        }
        let norm = filtered.reduce(0) { $0 + $1 * $1 }.squareRoot()
        if norm < 0.01 {
            filtered = [Double](repeating: 0, count: Self.bands)
        } else {
            for band in 0..<Self.bands { filtered[band] /= norm }
        }
        addRow(filtered)
        if integral.count >= Self.maxFilterWidth {
            fingerprint.append(subfingerprint(at: integral.count - Self.maxFilterWidth))
        }
    }

    private mutating func addRow(_ row: [Double]) {
        var sums = [Double](repeating: 0, count: Self.bands)
        var running = 0.0
        for band in 0..<Self.bands {
            running += row[band]
            sums[band] = running + (integral.last?[band] ?? 0)
        }
        integral.append(sums)
    }

    /// The sum of rows `r1..<r2` (frames) and columns `c1..<c2` (chroma bands).
    private func area(_ r1: Int, _ c1: Int, _ r2: Int, _ c2: Int) -> Double {
        guard r1 != r2, c1 != c2 else { return 0 }
        func at(_ row: Int, _ column: Int) -> Double { row < 0 || column < 0 ? 0 : integral[row][column] }
        return at(r2 - 1, c2 - 1) - at(r1 - 1, c2 - 1) - at(r2 - 1, c1 - 1) + at(r1 - 1, c1 - 1)
    }

    private func subfingerprint(at offset: Int) -> UInt32 {
        var bits: UInt32 = 0
        for classifier in Self.classifiers {
            let value = classifier.filter.apply(offset, area)
            bits = (bits << 2) | Self.grayCode[classifier.quantize(value)]
        }
        return bits
    }

    static let grayCode: [UInt32] = [0, 1, 3, 2]

    /// Each FFT bin's chroma band, -1 outside 28 Hz to 3520 Hz.
    static let notes: [Int] = {
        var notes = [Int](repeating: -1, count: frameSize / 2 + 1)
        func index(_ frequency: Double) -> Int { Int((Double(frameSize) * frequency / Double(sampleRate)).rounded()) }
        let low = max(1, index(minFrequency)), high = min(frameSize / 2, index(maxFrequency))
        for bin in low..<high {
            let frequency = Double(bin) * Double(sampleRate) / Double(frameSize)
            let octave = log(frequency / (440.0 / 16.0)) / log(2.0)
            notes[bin] = Int(Double(bands) * (octave - octave.rounded(.down)))
        }
        return notes
    }()

    struct Filter: Sendable {
        let type: Int, y: Int, height: Int, width: Int

        /// Chromaprint's six Haar-like filters over a `width`-frame, `height`-band window at frame `x`, compared as
        /// log((1 + a) / (1 + b)).
        func apply(_ x: Int, _ area: (Int, Int, Int, Int) -> Double) -> Double {
            let w = width, h = height
            let a: Double, b: Double
            switch type {
            case 0:
                a = area(x, y, x + w, y + h); b = 0
            case 1:
                a = area(x, y + h / 2, x + w, y + h); b = area(x, y, x + w, y + h / 2)
            case 2:
                a = area(x + w / 2, y, x + w, y + h); b = area(x, y, x + w / 2, y + h)
            case 3:
                a = area(x, y + h / 2, x + w / 2, y + h) + area(x + w / 2, y, x + w, y + h / 2)
                b = area(x, y, x + w / 2, y + h / 2) + area(x + w / 2, y + h / 2, x + w, y + h)
            case 4:
                a = area(x, y + h / 3, x + w, y + 2 * (h / 3))
                b = area(x, y, x + w, y + h / 3) + area(x, y + 2 * (h / 3), x + w, y + h)
            default:
                a = area(x + w / 3, y, x + 2 * (w / 3), y + h)
                b = area(x, y, x + w / 3, y + h) + area(x + 2 * (w / 3), y, x + w, y + h)
            }
            return log((1 + a) / (1 + b))
        }
    }

    struct Classifier: Sendable {
        let filter: Filter
        let thresholds: (Double, Double, Double)

        init(_ type: Int, _ y: Int, _ height: Int, _ width: Int, _ t0: Double, _ t1: Double, _ t2: Double) {
            filter = Filter(type: type, y: y, height: height, width: width); thresholds = (t0, t1, t2)
        }

        func quantize(_ value: Double) -> Int {
            value < thresholds.1 ? (value < thresholds.0 ? 0 : 1) : (value < thresholds.2 ? 2 : 3)
        }
    }

    /// Chromaprint's `TEST2` classifiers (fingerprinter_configuration.cpp).
    static let classifiers: [Classifier] = [
        Classifier(0, 4, 3, 15, 1.98215, 2.35817, 2.63523),
        Classifier(4, 4, 6, 15, -1.03809, -0.651211, -0.282167),
        Classifier(1, 0, 4, 16, -0.298702, 0.119262, 0.558497),
        Classifier(3, 8, 2, 12, -0.105439, 0.0153946, 0.135898),
        Classifier(3, 4, 4, 8, -0.142891, 0.0258736, 0.200632),
        Classifier(4, 0, 3, 5, -0.826319, -0.590612, -0.368214),
        Classifier(1, 2, 2, 9, -0.557409, -0.233035, 0.0534525),
        Classifier(2, 7, 3, 4, -0.0646826, 0.00620476, 0.0784847),
        Classifier(2, 6, 2, 16, -0.192387, -0.029699, 0.215855),
        Classifier(2, 1, 3, 2, -0.0397818, -0.00568076, 0.0292026),
        Classifier(5, 10, 1, 15, -0.53823, -0.369934, -0.190235),
        Classifier(3, 6, 2, 10, -0.124877, 0.0296483, 0.139239),
        Classifier(2, 1, 1, 14, -0.101475, 0.0225617, 0.231971),
        Classifier(3, 5, 6, 4, -0.0799915, -0.00729616, 0.063262),
        Classifier(1, 9, 2, 12, -0.272556, 0.019424, 0.302559),
        Classifier(3, 4, 2, 14, -0.164292, -0.0321188, 0.0846339),
    ]

    static let maxFilterWidth = classifiers.map(\.filter.width).max() ?? 16

    // MARK: Compression (fingerprint_compressor.cpp)

    /// Compresses a raw fingerprint the way Chromaprint does: each sub-fingerprint XOR the one before, its set bits as
    /// gaps in 3-bit values (7 and over spill into 5-bit values), behind a 4-byte header of algorithm and length.
    public static func compress(_ fingerprint: [UInt32], algorithm: Int = algorithm) -> String {
        var normal: [UInt8] = [], exceptional: [UInt8] = []
        for (index, value) in fingerprint.enumerated() {
            var x = index == 0 ? value : value ^ fingerprint[index - 1]
            var bit = 1, last = 0
            while x != 0 {
                if x & 1 != 0 {
                    let gap = bit - last
                    if gap >= 7 {
                        normal.append(7); exceptional.append(UInt8(gap - 7))
                    } else {
                        normal.append(UInt8(gap))
                    }
                    last = bit
                }
                x >>= 1; bit += 1
            }
            normal.append(0)
        }
        let size = fingerprint.count
        var bytes: [UInt8] = [UInt8(algorithm & 255), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)]
        bytes += pack(normal, bits: 3) + pack(exceptional, bits: 5)
        return base64URL(bytes)
    }

    /// Packs small values into bytes, least significant bit first.
    static func pack(_ values: [UInt8], bits: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: (values.count * bits + 7) / 8)
        var position = 0
        for value in values {
            for bit in 0..<bits where value & (1 << bit) != 0 {
                out[(position + bit) / 8] |= 1 << ((position + bit) % 8)
            }
            position += bits
        }
        return out
    }

    static func base64URL(_ bytes: [UInt8]) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// A radix-2 FFT of real frames, Hamming-windowed as Chromaprint does, giving each bin's power.
struct RealFFT: Sendable {
    let size: Int
    private let window: [Double]
    private let cosines: [Double]
    private let sines: [Double]
    private let reversed: [Int]

    init(size: Int) {
        self.size = size
        // Scaled to int16, as Chromaprint does, so its silence threshold means the same.
        window = (0..<size).map { (0.54 - 0.46 * cos(Double($0) * 2 * .pi / Double(size - 1))) / Double(Int16.max) }
        cosines = (0..<size / 2).map { cos(-2 * .pi * Double($0) / Double(size)) }
        sines = (0..<size / 2).map { sin(-2 * .pi * Double($0) / Double(size)) }
        let levels = size.trailingZeroBitCount
        reversed = (0..<size).map { index in
            var result = 0, value = index
            for _ in 0..<levels { result = (result << 1) | (value & 1); value >>= 1 }
            return result
        }
    }

    /// |X[k]|² for k in 0...size/2.
    func powerSpectrum(_ samples: ArraySlice<Int16>) -> [Double] {
        var real = [Double](repeating: 0, count: size), imaginary = [Double](repeating: 0, count: size)
        let start = samples.startIndex
        for index in 0..<size { real[reversed[index]] = Double(samples[start + index]) * window[index] }
        var length = 2
        while length <= size {
            let half = length / 2, step = size / length
            var block = 0
            while block < size {
                for k in 0..<half {
                    let c = cosines[k * step], s = sines[k * step]
                    let i = block + k, j = i + half
                    let tr = real[j] * c - imaginary[j] * s
                    let ti = real[j] * s + imaginary[j] * c
                    real[j] = real[i] - tr; imaginary[j] = imaginary[i] - ti
                    real[i] += tr; imaginary[i] += ti
                }
                block += length
            }
            length <<= 1
        }
        return (0...size / 2).map { real[$0] * real[$0] + imaginary[$0] * imaginary[$0] }
    }
}

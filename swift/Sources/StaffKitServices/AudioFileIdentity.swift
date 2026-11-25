import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

/// What an audio file says about itself, for identifying it: the tags stores and MusicBrainz Picard write. FLAC
/// files (what Qobuz and Bandcamp sell) are read here byte by byte, on any platform; other formats go through
/// AVFoundation on Apple platforms.
public enum AudioFileTags {
    /// The recording as the file's tags describe it, with its duration; the title falls back to the file name.
    public static func recording(at url: URL) async -> MediaRecording {
        var recording = MediaRecording(title: "")
        let handle = try? FileHandle(forReadingFrom: url)
        defer { try? handle?.close() }
        if let data = try? handle?.read(upToCount: 4 << 20), let flac = flac(data) {
            apply(flac.comments, to: &recording)
            recording.duration = flac.duration
        }
        #if canImport(AVFoundation)
        if recording.title.isEmpty || recording.duration == nil { await applyAVMetadata(url, to: &recording) }
        #endif
        if recording.title.isEmpty { recording.title = url.deletingPathExtension().lastPathComponent }
        return recording
    }

    /// Vorbis comments as MusicBrainz Picard names them (upper-cased keys), onto a recording.
    static func apply(_ comments: [String: String], to recording: inout MediaRecording) {
        func value(_ keys: String...) -> String? {
            keys.lazy.compactMap { comments[$0]?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        }
        if recording.title.isEmpty, let title = value("TITLE") { recording.title = title }
        recording.artist = recording.artist ?? value("ARTIST", "ALBUMARTIST")
        recording.album = recording.album ?? value("ALBUM")
        recording.isrc = recording.isrc ?? value("ISRC", "TSRC")
        recording.musicbrainzRecordingId = recording.musicbrainzRecordingId ?? value("MUSICBRAINZ_TRACKID")
        let releaseID = value("MUSICBRAINZ_ALBUMID"), barcode = value("BARCODE", "UPC", "EAN")
        if releaseID != nil || barcode != nil {
            var release = recording.release ?? MediaRelease(title: recording.album)
            release.musicbrainzReleaseId = release.musicbrainzReleaseId ?? releaseID
            release.barcode = release.barcode ?? barcode
            recording.release = release
        }
    }

    /// A FLAC file's Vorbis comments (keys upper-cased; the first of a repeated key) and its duration from
    /// STREAMINFO; nil when it isn't FLAC.
    public static func flac(_ data: Data) -> (comments: [String: String], duration: TimeInterval?)? {
        let bytes = [UInt8](data.prefix(4 << 20))
        // An ID3v2 tag some taggers put before "fLaC".
        var offset = 0
        if bytes.count > 10, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 {
            offset = 10 + (Int(bytes[6] & 0x7f) << 21 | Int(bytes[7] & 0x7f) << 14 | Int(bytes[8] & 0x7f) << 7
                | Int(bytes[9] & 0x7f))
        }
        guard bytes.count >= offset + 4, bytes[offset..<offset + 4] == [0x66, 0x4c, 0x61, 0x43] else { return nil }
        offset += 4
        var comments: [String: String] = [:]
        var duration: TimeInterval?
        var last = false
        while !last, offset + 4 <= bytes.count {
            let header = bytes[offset]
            last = header & 0x80 != 0
            let type = header & 0x7f
            let length = Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let start = offset + 4, end = start + length
            // Cover art can be megabytes; only the blocks read here need to be within the bytes read.
            guard end <= bytes.count || (type != 0 && type != 4) else { break }
            if type == 0, length >= 18 {
                let rate = Int(bytes[start + 10]) << 12 | Int(bytes[start + 11]) << 4 | Int(bytes[start + 12]) >> 4
                var samples = UInt64(bytes[start + 13] & 0x0f)
                for index in 14..<18 { samples = samples << 8 | UInt64(bytes[start + index]) }
                if rate > 0, samples > 0 { duration = Double(samples) / Double(rate) }
            } else if type == 4 {
                comments.merge(vorbisComments(bytes[start..<end])) { first, _ in first }
            }
            offset = end
        }
        return (comments, duration)
    }

    static func vorbisComments(_ block: ArraySlice<UInt8>) -> [String: String] {
        var position = block.startIndex
        func uint32() -> Int? {
            guard position + 4 <= block.endIndex else { return nil }
            defer { position += 4 }
            return Int(block[position]) | Int(block[position + 1]) << 8 | Int(block[position + 2]) << 16
                | Int(block[position + 3]) << 24
        }
        guard let vendor = uint32(), position + vendor <= block.endIndex else { return [:] }
        position += vendor
        guard let count = uint32() else { return [:] }
        var comments: [String: String] = [:]
        for _ in 0..<min(count, 10_000) {
            guard let length = uint32(), position + length <= block.endIndex else { break }
            let text = String(decoding: block[position..<position + length], as: UTF8.self)
            position += length
            guard let equals = text.firstIndex(of: "=") else { continue }
            let key = text[..<equals].uppercased()
            if comments[key] == nil { comments[key] = String(text[text.index(after: equals)...]) }
        }
        return comments
    }

    #if canImport(AVFoundation)
    /// Title, artist, album and duration from AVFoundation's common metadata (MP4, MP3, AIFF, WAV).
    static func applyAVMetadata(_ url: URL, to recording: inout MediaRecording) async {
        let asset = AVURLAsset(url: url)
        var values: [AVMetadataKey: String] = [:]
        for item in (try? await asset.load(.commonMetadata)) ?? [] {
            if let key = item.commonKey.map({ AVMetadataKey(rawValue: $0.rawValue) }),
               let text = try? await item.load(.stringValue) {
                values[key] = values[key] ?? text
            }
        }
        if recording.title.isEmpty, let title = values[.commonKeyTitle] { recording.title = title }
        recording.artist = recording.artist ?? values[.commonKeyArtist]
        recording.album = recording.album ?? values[.commonKeyAlbumName]
        if recording.duration == nil, let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 {
            recording.duration = Double(file.length) / file.fileFormat.sampleRate
        }
    }
    #endif
}

#if canImport(AVFoundation)
extension Chromaprint {
    /// Fingerprints the first `seconds` of an audio file AVFoundation can read (FLAC, ALAC, AAC, MP3, WAV, AIFF):
    /// decoded, resampled to 11025 Hz, channels averaged, as `fpcalc` does. Returns the raw fingerprint and the
    /// file's whole duration (what AcoustID wants with it).
    public static func fingerprint(fileAt url: URL, seconds: TimeInterval = 120) throws
        -> (fingerprint: [UInt32], duration: TimeInterval) {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        let channels = source.channelCount
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate),
                                         channels: channels, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else {
            throw SongLookupError.service("This audio can't be decoded for a fingerprint.")
        }
        let duration = Double(file.length) / source.sampleRate
        let wanted = AVAudioFramePosition(seconds * source.sampleRate)
        var printer = Chromaprint()
        var finished = false
        let chunk: AVAudioFrameCount = 32_768
        while !finished {
            guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 8_192) else { break }
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                let remaining = wanted - file.framePosition
                guard remaining > 0,
                      let input = AVAudioPCMBuffer(pcmFormat: source,
                                                   frameCapacity: AVAudioFrameCount(min(Int64(chunk), remaining))),
                      (try? file.read(into: input, frameCount: input.frameCapacity)) != nil, input.frameLength > 0
                else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return input
            }
            if let error { throw error }
            if let data = output.floatChannelData, output.frameLength > 0 {
                var mono = [Int16](repeating: 0, count: Int(output.frameLength))
                for frame in 0..<Int(output.frameLength) {
                    var sum: Float = 0
                    for channel in 0..<Int(channels) { sum += data[channel][frame] }
                    let value = sum / Float(channels) * 32767
                    mono[frame] = Int16(max(-32768, min(32767, value.rounded())))
                }
                printer.consume(mono)
            }
            finished = status == .endOfStream || status == .error
        }
        return (printer.fingerprint, duration)
    }
}
#endif

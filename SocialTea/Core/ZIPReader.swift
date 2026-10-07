import Foundation
import zlib

/// Minimal ZIP parser for reading Instagram and TikTok data-export archives directly,
/// so users don't need to unzip manually. Supports methods 0 (stored) and 8 (deflate).
enum ZIPReader {

    struct Entry {
        let path: String
        let data: Data
    }

    static func entries(from zip: Data) throws -> [Entry] {
        guard let eocd = findEOCD(in: zip) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let cdOffset = Int(zip.u32le(at: eocd + 16))
        let cdCount  = Int(zip.u16le(at: eocd + 10))

        var result: [Entry] = []
        var pos = cdOffset

        for _ in 0..<cdCount {
            guard pos + 46 <= zip.count,
                  zip.u32le(at: pos) == 0x02014B50 else { break } // PK\x01\x02

            let method         = zip.u16le(at: pos + 10)
            let compressedSz   = Int(zip.u32le(at: pos + 20))
            let uncompressedSz = Int(zip.u32le(at: pos + 24))
            let nameLen        = Int(zip.u16le(at: pos + 28))
            let extraLen       = Int(zip.u16le(at: pos + 30))
            let commentLen     = Int(zip.u16le(at: pos + 32))
            let localOffset    = Int(zip.u32le(at: pos + 42))

            let nameRange = (pos + 46)..<(pos + 46 + nameLen)
            guard nameRange.upperBound <= zip.count,
                  let name = String(data: zip[nameRange], encoding: .utf8),
                  !name.hasSuffix("/")
            else {
                pos += 46 + nameLen + extraLen + commentLen
                continue
            }

            // Local file header (PK\x03\x04)
            guard localOffset + 30 <= zip.count,
                  zip.u32le(at: localOffset) == 0x04034B50
            else {
                pos += 46 + nameLen + extraLen + commentLen
                continue
            }

            let lfhNameLen  = Int(zip.u16le(at: localOffset + 26))
            let lfhExtraLen = Int(zip.u16le(at: localOffset + 28))
            let dataStart   = localOffset + 30 + lfhNameLen + lfhExtraLen
            let dataEnd     = dataStart + compressedSz

            guard dataEnd <= zip.count else {
                pos += 46 + nameLen + extraLen + commentLen
                continue
            }

            let compressed = Data(zip[dataStart..<dataEnd])
            let fileData: Data?
            switch method {
            case 0:  fileData = compressed
            case 8:  fileData = rawInflate(compressed, expectedSize: uncompressedSz)
            default: fileData = nil
            }

            if let fileData {
                result.append(Entry(path: name, data: fileData))
            }

            pos += 46 + nameLen + extraLen + commentLen
        }

        return result
    }

    // MARK: -

    private static func findEOCD(in data: Data) -> Int? {
        // PK\x05\x06 = end-of-central-directory signature
        guard data.count >= 22 else { return nil }
        let minPos = max(0, data.count - 65558)
        var i = data.count - 22
        while i >= minPos {
            if data[data.startIndex + i    ] == 0x50,
               data[data.startIndex + i + 1] == 0x4B,
               data[data.startIndex + i + 2] == 0x05,
               data[data.startIndex + i + 3] == 0x06 { return i }
            i -= 1
        }
        return nil
    }

    private static func rawInflate(_ data: Data, expectedSize: Int) -> Data? {
        guard !data.isEmpty, expectedSize > 0 else { return Data() }
        var stream = z_stream()
        // Negative window bits = raw DEFLATE (ZIP stores without zlib header)
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION,
                            Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var out = Data(count: expectedSize)
        let status: Int32 = data.withUnsafeBytes { src in
            out.withUnsafeMutableBytes { dst in
                stream.next_in   = UnsafeMutablePointer(mutating: src.bindMemory(to: UInt8.self).baseAddress!)
                stream.avail_in  = uInt(data.count)
                stream.next_out  = dst.bindMemory(to: UInt8.self).baseAddress!
                stream.avail_out = uInt(out.count)
                return inflate(&stream, Z_FINISH)
            }
        }

        guard status == Z_STREAM_END else { return nil }
        let produced = out.count - Int(stream.avail_out)
        return out.prefix(produced)
    }
}

private extension Data {
    func u16le(at offset: Int) -> UInt16 {
        let b = startIndex
        return UInt16(self[b + offset]) | (UInt16(self[b + offset + 1]) << 8)
    }
    func u32le(at offset: Int) -> UInt32 {
        let b = startIndex
        return UInt32(self[b + offset    ])        |
              (UInt32(self[b + offset + 1]) << 8)  |
              (UInt32(self[b + offset + 2]) << 16) |
              (UInt32(self[b + offset + 3]) << 24)
    }
}

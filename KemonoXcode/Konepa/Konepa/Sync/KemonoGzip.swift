import Foundation
import zlib

nonisolated enum KemonoGzip {
    static func decompressIfNeeded(_ data: Data) throws -> Data {
        guard data.count >= 2, data[0] == 0x1F, data[1] == 0x8B else {
            return data
        }
        return try decompress(data)
    }

    /// Mirrors Qt `KemonoParser` gzip handling when URLSession leaves body compressed.
    static func decompress(_ data: Data) throws -> Data {
        var stream = z_stream()
        var status = inflateInit2_(
            &stream,
            16 + MAX_WBITS,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard status == Z_OK else {
            throw KemonoAPIError.badResponse
        }
        defer { inflateEnd(&stream) }

        var output = Data()
        var inputCopy = data
        let inputCount = inputCopy.count
        let bufferSize = 32_768
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        try inputCopy.withUnsafeMutableBytes { inputPointer in
            guard let inputBase = inputPointer.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
                throw KemonoAPIError.badResponse
            }

            stream.next_in = inputBase
            stream.avail_in = uInt(inputCount)

            repeat {
                var produced = 0
                buffer.withUnsafeMutableBufferPointer { bufferPointer in
                    guard let outBase = bufferPointer.baseAddress else { return }
                    stream.next_out = UnsafeMutableRawPointer(outBase).assumingMemoryBound(to: Bytef.self)
                    stream.avail_out = uInt(bufferSize)
                    status = inflate(&stream, Z_NO_FLUSH)
                    produced = bufferSize - Int(stream.avail_out)
                }
                if produced > 0 {
                    output.append(buffer, count: produced)
                }
            } while status == Z_OK

            guard status == Z_STREAM_END else {
                throw KemonoAPIError.badResponse
            }
        }

        return output
    }
}

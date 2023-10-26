import Foundation
import Compression

public enum WHCompressionAlgorithm: String, CaseIterable {
    case none
    case lz4
    case zlib
    case lzma
    case lzfse

    var underlyingAlgorithm: Compression.Algorithm {
        switch self {
        case .none:
            fatalError()
        case .lz4:
            return .init(rawValue: COMPRESSION_LZ4)!
        case .zlib:
            return .init(rawValue: COMPRESSION_ZLIB)!
        case .lzma:
            return .init(rawValue: COMPRESSION_LZMA)!
        case .lzfse:
            return .init(rawValue: COMPRESSION_LZFSE)!
        }
    }
}

extension Data {

    func compressed(using algo: WHCompressionAlgorithm, pageSize: Int = 128) throws -> Data {
        guard algo != .none else { return self }

        var outputData = Data()
        let filter = try OutputFilter(.compress, using: algo.underlyingAlgorithm, bufferCapacity: pageSize, writingTo: { $0.flatMap({ outputData.append($0) }) })

        var index = 0
        let bufferSize = count

        while true {
            let rangeLength = Swift.min(pageSize, bufferSize - index)

            let subdata = self.subdata(in: index ..< index + rangeLength)
            index += rangeLength

            try filter.write(subdata)

            if (rangeLength == 0) { break }
        }

        return outputData
    }

    func decompressed(from algo: WHCompressionAlgorithm, pageSize: Int = 128) throws -> Data {
        guard algo != .none else { return self }

        var outputData = Data()
        let bufferSize = count
        var decompressionIndex = 0

        let filter = try InputFilter(.decompress, using: algo.underlyingAlgorithm) { (length: Int) -> Data? in
            let rangeLength = Swift.min(length, bufferSize - decompressionIndex)
            let subdata = self.subdata(in: decompressionIndex ..< decompressionIndex + rangeLength)
            decompressionIndex += rangeLength

            return subdata
        }

        while let page = try filter.readData(ofLength: pageSize) {
            outputData.append(page)
        }

        return outputData
    }

}

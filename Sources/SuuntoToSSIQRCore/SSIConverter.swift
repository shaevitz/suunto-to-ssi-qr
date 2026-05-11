import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UniformTypeIdentifiers

public struct DiveSummary: Equatable, Sendable {
    public let startTime: Date
    public let durationSeconds: Double
    public let maxDepthMeters: Double
    public let minimumWaterTemperatureCelsius: Double?
    public let maximumWaterTemperatureCelsius: Double?

    public init(
        startTime: Date,
        durationSeconds: Double,
        maxDepthMeters: Double,
        minimumWaterTemperatureCelsius: Double?,
        maximumWaterTemperatureCelsius: Double?
    ) {
        self.startTime = startTime
        self.durationSeconds = durationSeconds
        self.maxDepthMeters = maxDepthMeters
        self.minimumWaterTemperatureCelsius = minimumWaterTemperatureCelsius
        self.maximumWaterTemperatureCelsius = maximumWaterTemperatureCelsius
    }
}

public struct ConversionResult: Sendable {
    public let summary: DiveSummary
    public let payload: String
    public let qrImage: NSImage
    public let qrURL: URL
    public let payloadURL: URL
}

public enum SSIConversionError: Error, LocalizedError {
    case invalidFITHeader
    case missingSession
    case missingStartTime
    case missingDuration
    case missingDepth
    case unsupportedQRCodeData
    case cannotCreatePNG

    public var errorDescription: String? {
        switch self {
        case .invalidFITHeader:
            "This file does not look like a FIT file."
        case .missingSession:
            "The FIT file does not contain a dive session."
        case .missingStartTime:
            "The FIT file does not contain a dive start time."
        case .missingDuration:
            "The FIT file does not contain dive duration data."
        case .missingDepth:
            "The FIT file does not contain dive depth data."
        case .unsupportedQRCodeData:
            "The SSI payload could not be encoded as QR data."
        case .cannotCreatePNG:
            "The QR image could not be written as a PNG."
        }
    }
}

public struct SSIPayloadBuilder: Sendable {
    public init() {}

    public func payload(for summary: DiveSummary, timeZone: TimeZone = .current) throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: summary.startTime
        )
        guard
            let year = components.year,
            let month = components.month,
            let day = components.day,
            let hour = components.hour,
            let minute = components.minute
        else {
            throw SSIConversionError.missingStartTime
        }

        let localDateTime = String(
            format: "%04d%02d%02d%02d%02d",
            year, month, day, hour, minute
        )
        let durationMinutes = Int((summary.durationSeconds / 60.0).rounded())

        var fields = [
            "dive",
            "noid",
            "dive_type:0",
            "divetime:\(durationMinutes)",
            "datetime:\(localDateTime)",
            String(format: "depth_m:%.1f", summary.maxDepthMeters),
            "user_firstname:",
            "user_lastname:",
        ]

        if let minimum = summary.minimumWaterTemperatureCelsius {
            fields.append("watertemp_c:\(formatNumber(minimum))")
        }
        if let maximum = summary.maximumWaterTemperatureCelsius {
            fields.append("watertemp_max_c:\(formatNumber(maximum))")
        }

        return fields.joined(separator: ";")
    }
}

public struct QRCodeWriter: Sendable {
    public init() {}

    public func writePNG(payload: String, to outputURL: URL) throws {
        let bitmap = try bitmapImage(payload: payload)
        guard let png = bitmap.representation(
            using: NSBitmapImageRep.FileType.png,
            properties: [:]
        ) else {
            throw SSIConversionError.cannotCreatePNG
        }
        try png.write(to: outputURL)
    }

    public func previewImage(payload: String) throws -> NSImage {
        let bitmap = try bitmapImage(payload: payload)
        let image = NSImage(size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        image.addRepresentation(bitmap)
        return image
    }

    private func bitmapImage(payload: String) throws -> NSBitmapImageRep {
        guard let data = payload.data(using: .utf8) else {
            throw SSIConversionError.unsupportedQRCodeData
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "M"

        guard let image = filter.outputImage else {
            throw SSIConversionError.cannotCreatePNG
        }

        let scaled = image
            .transformed(by: CGAffineTransform(scaleX: 14, y: 14))
            .transformed(by: CGAffineTransform(translationX: 56, y: 56))
        let extent = scaled.extent.insetBy(dx: -56, dy: -56)
        let background = CIImage(color: .white).cropped(to: extent)
        let composed = scaled.composited(over: background)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let cgImage = context.createCGImage(composed, from: extent) else {
            throw SSIConversionError.cannotCreatePNG
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        bitmap.size = NSSize(width: cgImage.width, height: cgImage.height)
        return bitmap
    }
}

public struct DiveConverter: Sendable {
    private let parser = FITDiveParser()
    private let payloadBuilder = SSIPayloadBuilder()
    private let qrWriter = QRCodeWriter()

    public init() {}

    public func convert(
        fitURL: URL,
        timeZone: TimeZone = .current,
        outputDirectory: URL? = nil
    ) throws -> ConversionResult {
        let summary = try parser.parse(url: fitURL)
        let payload = try payloadBuilder.payload(for: summary, timeZone: timeZone)
        let directory = outputDirectory ?? fitURL.deletingLastPathComponent()
        let stem = fitURL.deletingPathExtension().lastPathComponent
        let qrURL = directory.appendingPathComponent("\(stem)_ssi_qr.png")
        let payloadURL = directory.appendingPathComponent("\(stem)_ssi_payload.txt")
        let qrImage = try qrWriter.previewImage(payload: payload)

        try qrWriter.writePNG(payload: payload, to: qrURL)
        try (payload + "\n").write(to: payloadURL, atomically: true, encoding: .utf8)

        return ConversionResult(
            summary: summary,
            payload: payload,
            qrImage: qrImage,
            qrURL: qrURL,
            payloadURL: payloadURL
        )
    }
}

public struct FITDiveParser: Sendable {
    private static let fitEpochOffset: TimeInterval = 631_065_600

    public init() {}

    public func parse(url: URL) throws -> DiveSummary {
        let data = try Data(contentsOf: url)
        guard data.count >= 14 else { throw SSIConversionError.invalidFITHeader }
        let headerSize = Int(data[0])
        guard
            headerSize <= data.count,
            headerSize >= 12,
            String(data: data[8..<12], encoding: .ascii) == ".FIT"
        else {
            throw SSIConversionError.invalidFITHeader
        }

        let dataEnd = data.count - 2
        var offset = headerSize
        var definitions: [UInt8: MessageDefinition] = [:]
        var developerFieldNames: [UInt8: String] = [:]
        var developerFieldBaseTypes: [UInt8: UInt8] = [:]
        var startTime: Date?
        var durationSeconds: Double?
        var maxDepthMeters: Double?
        var depthValues: [Double] = []
        var temperatures: [Double] = []

        while offset < dataEnd {
            let header = data[offset]
            offset += 1

            let isDefinition = (header & 0x40) != 0
            let localMessageNumber = header & 0x0F

            if isDefinition {
                let definition = try readDefinition(
                    data: data,
                    offset: &offset,
                    hasDeveloperFields: (header & 0x20) != 0
                )
                definitions[localMessageNumber] = definition
                continue
            }

            guard let definition = definitions[localMessageNumber] else {
                throw SSIConversionError.invalidFITHeader
            }

            var fields: [UInt8: FieldValue] = [:]
            var developerFields: [UInt8: FieldValue] = [:]
            for field in definition.fields {
                fields[field.number] = try readField(
                    data: data,
                    offset: &offset,
                    size: Int(field.size),
                    baseType: field.baseType,
                    endian: definition.endian
                )
            }
            for field in definition.developerFields {
                developerFields[field.number] = try readField(
                    data: data,
                    offset: &offset,
                    size: Int(field.size),
                    baseType: developerFieldBaseTypes[field.number],
                    endian: definition.endian
                )
            }

            switch definition.globalMessageNumber {
            case 20:
                if let rawDepth = fields[92]?.number {
                    let depth = rawDepth / 1_000.0
                    depthValues.append(depth)
                }
                if let temp = fields[13]?.number {
                    temperatures.append(temp)
                }
            case 18:
                if let rawStart = fields[2]?.number {
                    startTime = Date(timeIntervalSince1970: rawStart + Self.fitEpochOffset)
                }
                if let duration = fields[8]?.number ?? fields[7]?.number {
                    durationSeconds = duration / 1_000.0
                }
                if let rawAvgTemp = fields[30]?.number, temperatures.isEmpty {
                    temperatures.append(rawAvgTemp)
                }
                for (number, value) in developerFields
                where developerFieldNames[number] == "max_depth" {
                    if let depth = value.number {
                        maxDepthMeters = depth
                    }
                }
            case 206:
                if let number = fields[1]?.uint8, let name = fields[3]?.text {
                    developerFieldNames[number] = name
                }
                if let number = fields[1]?.uint8, let baseType = fields[2]?.uint8 {
                    developerFieldBaseTypes[number] = baseType
                }
            default:
                break
            }
        }

        guard let startTime else { throw SSIConversionError.missingStartTime }
        guard let durationSeconds else { throw SSIConversionError.missingDuration }
        let resolvedDepth = maxDepthMeters ?? depthValues.max()
        guard let resolvedDepth else { throw SSIConversionError.missingDepth }

        return DiveSummary(
            startTime: startTime,
            durationSeconds: durationSeconds,
            maxDepthMeters: resolvedDepth,
            minimumWaterTemperatureCelsius: temperatures.min(),
            maximumWaterTemperatureCelsius: temperatures.max()
        )
    }

    private func readDefinition(
        data: Data,
        offset: inout Int,
        hasDeveloperFields: Bool
    ) throws -> MessageDefinition {
        offset += 1
        let endianFlag = data[offset]
        offset += 1
        let endian: Endian = endianFlag == 0 ? .little : .big
        let globalMessageNumber = try readUInt16(data: data, offset: &offset, endian: endian)
        let fieldCount = Int(data[offset])
        offset += 1
        var fields: [FieldDefinition] = []
        for _ in 0..<fieldCount {
            fields.append(FieldDefinition(
                number: data[offset],
                size: data[offset + 1],
                baseType: data[offset + 2]
            ))
            offset += 3
        }

        var developerFields: [DeveloperFieldDefinition] = []
        if hasDeveloperFields {
            let developerFieldCount = Int(data[offset])
            offset += 1
            for _ in 0..<developerFieldCount {
                developerFields.append(DeveloperFieldDefinition(
                    number: data[offset],
                    size: data[offset + 1],
                    developerDataIndex: data[offset + 2]
                ))
                offset += 3
            }
        }
        return MessageDefinition(
            globalMessageNumber: globalMessageNumber,
            endian: endian,
            fields: fields,
            developerFields: developerFields
        )
    }
}

private enum Endian {
    case little
    case big
}

private struct MessageDefinition {
    let globalMessageNumber: UInt16
    let endian: Endian
    let fields: [FieldDefinition]
    let developerFields: [DeveloperFieldDefinition]
}

private struct FieldDefinition {
    let number: UInt8
    let size: UInt8
    let baseType: UInt8
}

private struct DeveloperFieldDefinition {
    let number: UInt8
    let size: UInt8
    let developerDataIndex: UInt8
}

private enum FieldValue {
    case number(Double)
    case uint8(UInt8)
    case text(String)
    case empty

    var number: Double? {
        if case let .number(value) = self { return value }
        if case let .uint8(value) = self { return Double(value) }
        return nil
    }

    var uint8: UInt8? {
        if case let .uint8(value) = self { return value }
        if case let .number(value) = self { return UInt8(value) }
        return nil
    }

    var text: String? {
        if case let .text(value) = self { return value }
        return nil
    }
}

private func readField(
    data: Data,
    offset: inout Int,
    size: Int,
    baseType: UInt8?,
    endian: Endian
) throws -> FieldValue {
    guard offset + size <= data.count else { throw SSIConversionError.invalidFITHeader }
    defer { offset += size }
    let bytes = data[offset..<(offset + size)]
    let normalizedBaseType = baseType.map { $0 & 0x1F }

    if normalizedBaseType == 7 {
        return .text(String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? "")
    }
    if size == 1 {
        let value = bytes[bytes.startIndex]
        if normalizedBaseType == 1 {
            return .number(Double(Int8(bitPattern: value)))
        }
        return .uint8(value)
    }
    if size == 2 {
        return .number(Double(readUInt16(bytes: bytes, endian: endian)))
    }
    if size == 4 {
        if normalizedBaseType == 8 {
            return .number(Double(readFloat32(bytes: bytes, endian: endian)))
        }
        return .number(Double(readUInt32(bytes: bytes, endian: endian)))
    }
    return .empty
}

private func readUInt16(data: Data, offset: inout Int, endian: Endian) throws -> UInt16 {
    guard offset + 2 <= data.count else { throw SSIConversionError.invalidFITHeader }
    defer { offset += 2 }
    return readUInt16(bytes: data[offset..<(offset + 2)], endian: endian)
}

private func readUInt16(bytes: Data.SubSequence, endian: Endian) -> UInt16 {
    let values = Array(bytes)
    switch endian {
    case .little:
        return UInt16(values[0]) | (UInt16(values[1]) << 8)
    case .big:
        return (UInt16(values[0]) << 8) | UInt16(values[1])
    }
}

private func readUInt32(bytes: Data.SubSequence, endian: Endian) -> UInt32 {
    let values = Array(bytes)
    switch endian {
    case .little:
        return UInt32(values[0])
            | (UInt32(values[1]) << 8)
            | (UInt32(values[2]) << 16)
            | (UInt32(values[3]) << 24)
    case .big:
        return (UInt32(values[0]) << 24)
            | (UInt32(values[1]) << 16)
            | (UInt32(values[2]) << 8)
            | UInt32(values[3])
    }
}

private func readFloat32(bytes: Data.SubSequence, endian: Endian) -> Float {
    Float(bitPattern: readUInt32(bytes: bytes, endian: endian))
}

private func formatNumber(_ value: Double) -> String {
    if value.rounded() == value {
        return String(Int(value))
    }
    return String(format: "%.1f", value)
}

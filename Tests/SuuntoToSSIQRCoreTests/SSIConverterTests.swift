import Testing
import AppKit
import Foundation
@testable import SuuntoToSSIQRCore

@Test func sampleFitParsesDiveSummary() throws {
    let url = try #require(Bundle.module.url(
        forResource: "synthetic-dive",
        withExtension: "fit"
    ))

    let summary = try FITDiveParser().parse(url: url)

    #expect(summary.startTime == Date(timeIntervalSince1970: 1_778_351_750))
    #expect(abs(summary.durationSeconds - 575.97) < 0.01)
    #expect(abs(summary.maxDepthMeters - 1.34) < 0.01)
    #expect(summary.minimumWaterTemperatureCelsius == 31)
    #expect(summary.maximumWaterTemperatureCelsius == 32)
}

@Test func buildsExpectedSSIPayload() throws {
    let summary = DiveSummary(
        startTime: Date(timeIntervalSince1970: 1_778_351_750),
        durationSeconds: 575.97,
        maxDepthMeters: 1.34,
        minimumWaterTemperatureCelsius: 31,
        maximumWaterTemperatureCelsius: 32
    )

    let payload = try SSIPayloadBuilder().payload(
        for: summary,
        timeZone: TimeZone(identifier: "America/New_York")!
    )

    #expect(payload == "dive;noid;dive_type:0;divetime:10;datetime:202605091435;depth_m:1.3;user_firstname:;user_lastname:;watertemp_c:31;watertemp_max_c:32")
}

@Test func writesQRCodePNG() throws {
    let payload = "dive;noid;dive_type:0;divetime:10;datetime:202605091435;depth_m:1.3"
    let output = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("png")
    defer { try? FileManager.default.removeItem(at: output) }

    try QRCodeWriter().writePNG(payload: payload, to: output)

    let data = try Data(contentsOf: output)
    #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    #expect(data.count > 500)

    let image = try #require(NSImage(data: data))
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))
    var darkPixelCount = 0
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
            guard let color = bitmap.colorAt(x: x, y: y) else { continue }
            if color.brightnessComponent < 0.2 && color.alphaComponent > 0.9 {
                darkPixelCount += 1
            }
        }
    }
    #expect(darkPixelCount > 100)
}

@Test func createsVisibleQRCodePreviewImage() throws {
    let payload = "dive;noid;dive_type:0;divetime:10;datetime:202605091435;depth_m:1.3"

    let image = try QRCodeWriter().previewImage(payload: payload)
    let tiff = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: tiff))

    #expect(bitmap.pixelsWide >= 250)
    #expect(bitmap.pixelsHigh >= 250)

    var darkPixelCount = 0
    for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
        for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
            guard let color = bitmap.colorAt(x: x, y: y) else { continue }
            if color.brightnessComponent < 0.2 && color.alphaComponent > 0.9 {
                darkPixelCount += 1
            }
        }
    }
    #expect(darkPixelCount > 100)
}

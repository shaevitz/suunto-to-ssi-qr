import AppKit
import SwiftUI
import SuuntoToSSIQRCore
import UniformTypeIdentifiers

@main
struct SuuntoToSSIQRApp: App {
    var body: some Scene {
        WindowGroup {
            ConverterView()
                .frame(minWidth: 680, minHeight: 520)
        }
        .windowStyle(.titleBar)
    }
}

@MainActor
private final class ConverterModel: ObservableObject {
    @Published var selectedFile: URL?
    @Published var status = "Select or drop a Suunto .fit dive export."
    @Published var payload = ""
    @Published var qrURL: URL?
    @Published var qrImage: NSImage?
    @Published var summaryText = ""
    @Published var isConverting = false

    private let converter = DiveConverter()

    func selectFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Suunto FIT export"
        panel.allowedContentTypes = [.fitFile]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            selectedFile = url
            convert()
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
            guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                return
            }
            Task { @MainActor in
                self?.selectedFile = url
                self?.convert()
            }
        }
        return true
    }

    func convert() {
        guard let selectedFile else { return }
        isConverting = true
        status = "Converting \(selectedFile.lastPathComponent)..."
        payload = ""
        qrURL = nil
        qrImage = nil
        summaryText = ""

        do {
            let result = try converter.convert(fitURL: selectedFile, timeZone: .current)
            payload = result.payload
            qrURL = result.qrURL
            qrImage = result.qrImage
            summaryText = summary(for: result.summary)
            status = "Wrote \(result.qrURL.lastPathComponent) and \(result.payloadURL.lastPathComponent)."
        } catch {
            status = error.localizedDescription
        }

        isConverting = false
    }

    private func summary(for summary: DiveSummary) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = .current

        var lines = [
            "Start: \(formatter.string(from: summary.startTime))",
            "Duration: \(Int((summary.durationSeconds / 60.0).rounded())) min",
            String(format: "Max depth: %.1f m", summary.maxDepthMeters),
        ]
        if let minTemp = summary.minimumWaterTemperatureCelsius,
           let maxTemp = summary.maximumWaterTemperatureCelsius {
            lines.append("Water temp: \(formatNumber(minTemp))-\(formatNumber(maxTemp)) C")
        }
        return lines.joined(separator: "\n")
    }

    private func formatNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}

private struct ConverterView: View {
    @StateObject private var model = ConverterModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Suunto to SSI QR")
                        .font(.title.bold())
                    Text(model.status)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose FIT File") {
                    model.selectFile()
                }
                .keyboardShortcut("o")
            }

            dropZone

            if !model.summaryText.isEmpty || !model.payload.isEmpty || model.qrImage != nil {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Dive")
                            .font(.headline)
                        Text(model.summaryText)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)

                        Text("SSI Payload")
                            .font(.headline)
                            .padding(.top, 8)
                        Text(model.payload)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    qrPreview
                }
            }

            Spacer()
        }
        .padding(24)
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(.tertiary)
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.arrow.up")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text(model.selectedFile?.lastPathComponent ?? "Drop a .fit file here")
                    .font(.headline)
                Text("The QR PNG and payload text are saved next to the FIT file.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .frame(height: 150)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
            model.handleDrop(providers)
        }
    }

    @ViewBuilder
    private var qrPreview: some View {
        VStack(spacing: 10) {
            Text("QR Code")
                .font(.headline)
            ZStack {
                Color.white
                if let image = model.qrImage {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    ProgressView()
                }
            }
            .frame(width: 260, height: 260)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            }
            Text(model.qrURL?.lastPathComponent ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(width: 280, alignment: .top)
    }
}

private extension UTType {
    static let fitFile = UTType(filenameExtension: "fit") ?? .data
}

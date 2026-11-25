import AppKit
import ReadbackCore
import SwiftUI

struct AboutSettings: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Readback").font(.title2.weight(.semibold))
                        Text("Version \(Bundle.main.version)").foregroundStyle(.secondary)
                    }
                }
                Text("Reads your coding agent's replies out loud, with a small player you can pause, scrub and speed up. Everything runs on your Mac.")
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                LabeledContent("Logs") {
                    Button("Show in Finder") { reveal(ReadbackPaths().logs) }
                }
                LabeledContent("Licences") {
                    Button("Open") {
                        if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } footer: {
                FormNote("Voices by Kokoro-82M and Qwen3-TTS (Apache-2.0), run on Apple silicon by mlx-audio (MIT), with misaki and spaCy turning text into sounds. The engine is installed by uv (MIT). Thank you to their authors.")
            }
        }
        .formStyle(CardFormStyle())
    }

    private func reveal(_ url: URL) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            Log.error("couldn't create \(url.path): \(error)")
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

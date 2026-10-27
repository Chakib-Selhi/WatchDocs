import SwiftUI
import WatchDocsKit

/// IOS-08: quality, storage limit on the watch, default reading mode.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker("Quality", selection: $settings.quality) {
                        Text("Economy (500 px)").tag(ConversionQuality.economy)
                        Text("Standard (800 px)").tag(ConversionQuality.standard)
                        Text("High (1200 px)").tag(ConversionQuality.high)
                    }
                    Picker("Image format", selection: $settings.imageFormat) {
                        Text("HEIC (smaller)").tag(PageImageFormat.heic)
                        Text("JPEG (compatible)").tag(PageImageFormat.jpeg)
                    }
                } header: {
                    Text("Conversion")
                } footer: {
                    Text("Higher quality gives sharper pages but larger, slower transfers. There is no limit on the number of pages or documents.")
                }

                Section {
                    Picker("Open documents in", selection: $settings.preferredMode) {
                        Text("Pages").tag(ReadingMode.pages)
                        Text("Text").tag(ReadingMode.text)
                        Text("Table").tag(ReadingMode.table)
                    }
                } header: {
                    Text("Watch")
                } footer: {
                    Text("Used when a document offers several reading modes. You can switch on the watch.")
                }

                Section {
                    Picker("Storage limit", selection: $settings.storageLimitMB) {
                        ForEach(AppSettings.storageLimitChoices, id: \.self) { value in
                            if value == 0 {
                                Text("No limit").tag(value)
                            } else {
                                Text(ByteFormatting.string(Int64(value) * 1_000_000)).tag(value)
                            }
                        }
                    }
                } footer: {
                    Text("With “No limit”, WatchDocs can use all the free space of the watch. A send that does not fit is refused with a clear message.")
                }

                Section {
                    Toggle("Preview before sending", isOn: $settings.previewBeforeSend)
                    Toggle("Send shared files automatically", isOn: $settings.autoSendShared)
                } header: {
                    Text("Sending")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                    Text("Your documents never leave your devices: no server, no analytics.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

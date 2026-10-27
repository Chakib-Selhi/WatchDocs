import SwiftUI
import WatchDocsKit

/// IOS-07: paired, app installed, reachable, space used by the app.
struct WatchStatusView: View {
    @Environment(DocumentPipeline.self) private var pipeline
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let state = pipeline.linkState
        NavigationStack {
            List {
                Section {
                    StatusLine(title: "Paired", ok: state.isPaired)
                    StatusLine(title: "WatchDocs installed on the watch", ok: state.isCounterpartAppInstalled)
                    StatusLine(title: "Reachable now", ok: state.isReachable)
                } footer: {
                    if state.isPaired && !state.isCounterpartAppInstalled {
                        Text("Open the Watch app on the iPhone, then install WatchDocs from “Available Apps”.")
                    } else if !state.isReachable {
                        Text("Sending still works: files are queued and delivered when the watch is nearby, awake and unlocked. Opening WatchDocs on the watch speeds things up.")
                    }
                }

                if let context = pipeline.watchContext {
                    Section("On the watch") {
                        LabeledContent("Documents", value: "\(context.documentCount)")
                        LabeledContent("Used by WatchDocs", value: ByteFormatting.string(context.usedBytes))
                        if let free = context.freeBytes {
                            LabeledContent("Free space", value: ByteFormatting.string(free))
                        }
                        LabeledContent("Updated") {
                            Text(context.updatedAt, style: .relative)
                        }
                    }
                } else {
                    Section {
                        Text("Open WatchDocs on the watch once to see its storage.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Apple Watch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct StatusLine: View {
    let title: LocalizedStringKey
    let ok: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .secondary)
                .accessibilityLabel(ok ? Text("Yes") : Text("No"))
        }
    }
}

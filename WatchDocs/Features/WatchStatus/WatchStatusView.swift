import SwiftUI
import WatchDocsKit

/// IOS-07: paired, app installed, reachable, space used by the app.
struct WatchStatusView: View {
    @Environment(DocumentPipeline.self) private var pipeline
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let state = pipeline.linkState
        let installed = pipeline.isWatchAppDetected
        NavigationStack {
            List {
                Section {
                    StatusLine(title: "Paired", state: state.isPaired ? .ok : .missing)
                    StatusLine(title: "WatchDocs installed on the watch", state: installed ? .ok : .missing)
                    // Reachable only means the watch app is in the foreground:
                    // not being reachable is normal and does not block delivery.
                    StatusLine(title: "WatchDocs open on the watch", state: state.isReachable ? .ok : .idle)
                } footer: {
                    if state.isPaired && !installed {
                        Text("Open the Watch app on the iPhone, then install WatchDocs from “Available Apps”.")
                    } else if installed && !state.isReachable {
                        Text("Normal when WatchDocs is closed on the watch: documents are still delivered in the background.")
                    }
                }

                if let context = pipeline.watchContext {
                    Section("On the watch") {
                        LabeledContent("Documents", value: "\(context.documentCount)")
                        LabeledContent("Used by WatchDocs", value: ByteFormatting.string(context.usedBytes))
                        if let free = context.freeBytes {
                            LabeledContent("Free space", value: ByteFormatting.string(free))
                        }
                        LabeledContent("Last contact") {
                            Text(pipeline.lastWatchContact ?? context.updatedAt, style: .relative)
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
            .onAppear { pipeline.refreshLinkState() }
        }
    }
}

private struct StatusLine: View {
    enum Indicator { case ok, missing, idle }

    let title: LocalizedStringKey
    let state: Indicator

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            switch state {
            case .ok:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel(Text("Yes"))
            case .missing:
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("No"))
            case .idle:
                Image(systemName: "moon.zzz")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("No"))
            }
        }
    }
}

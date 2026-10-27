import PhotosUI
import SwiftUI
import UserNotifications
import WatchDocsKit

struct RootView: View {
    @Environment(DocumentPipeline.self) private var pipeline
    @State private var showFileImporter = false
    @State private var showPhotoPicker = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showSettings = false
    @State private var showWatchStatus = false
    @State private var passwordText = ""

    var body: some View {
        @Bindable var pipeline = pipeline
        NavigationStack {
            LibraryView()
                .navigationTitle("WatchDocs")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showWatchStatus = true
                        } label: {
                            Image(systemName: watchIcon)
                                .foregroundStyle(pipeline.linkState.isReachable ? .green : .secondary)
                        }
                        .accessibilityLabel(Text("Watch status"))
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel(Text("Settings"))

                        Menu {
                            Button {
                                showFileImporter = true
                            } label: {
                                Label("Files", systemImage: "folder")
                            }
                            Button {
                                showPhotoPicker = true
                            } label: {
                                Label("Photos", systemImage: "photo.on.rectangle")
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .accessibilityLabel(Text("Add documents"))
                        .accessibilityIdentifier("addButton")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if pipeline.isConverting {
                        ConversionBanner()
                    }
                }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: ImportTypes.all, allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                pipeline.importFiles(urls)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItems, maxSelectionCount: nil, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task {
                var urls: [URL] = []
                for item in items {
                    if let photo = try? await item.loadTransferable(type: PickedPhoto.self) {
                        urls.append(photo.url)
                    }
                }
                pipeline.importPhotos(urls)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showWatchStatus) {
            WatchStatusView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: previewBinding) {
            ImportPreviewView(ids: pipeline.previewIDs)
        }
        .alert(item: $pipeline.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .alert(
            pipeline.passwordPrompt?.wrongPassword == true ? Text("Wrong password") : Text("Password required"),
            isPresented: passwordBinding,
            presenting: pipeline.passwordPrompt
        ) { prompt in
            SecureField("Password", text: $passwordText)
            Button("Unlock") {
                pipeline.submitPassword(passwordText, for: prompt.id)
                passwordText = ""
            }
            Button("Cancel", role: .cancel) {
                pipeline.cancelPassword(for: prompt.id)
                passwordText = ""
            }
        } message: { prompt in
            Text("“\(prompt.title)” is protected. Enter its password to convert it.")
        }
        .task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    private var watchIcon: String {
        let state = pipeline.linkState
        if !state.isPaired { return "applewatch.slash" }
        return state.isReachable ? "applewatch.radiowaves.left.and.right" : "applewatch"
    }

    private var previewBinding: Binding<Bool> {
        Binding(
            get: { !pipeline.previewIDs.isEmpty && !pipeline.isConverting && pipeline.passwordPrompt == nil },
            set: { if !$0 { pipeline.discardPreview() } }
        )
    }

    private var passwordBinding: Binding<Bool> {
        Binding(
            get: { pipeline.passwordPrompt != nil },
            set: { if !$0 { pipeline.passwordPrompt = nil } }
        )
    }
}

private struct ConversionBanner: View {
    @Environment(DocumentPipeline.self) private var pipeline

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ProgressView()
                Text("Converting “\(pipeline.currentTitle ?? "")”")
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                if pipeline.queuedConversions > 0 {
                    Text("+\(pipeline.queuedConversions)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: pipeline.currentProgress)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }
}

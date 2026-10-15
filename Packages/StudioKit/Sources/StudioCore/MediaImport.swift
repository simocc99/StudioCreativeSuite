import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// One way to bring media into every editor: Photos library, Files, camera, clipboard and
// drag-and-drop all end in local file URLs handed to the editor's existing import function.
// The Photos picker runs out of process: the app sees only what the user picks and needs no
// photo-library permission. RAW and ProRAW come in as the original file (current encoding).

/// Where an import comes from; set by `ImportMenu`, consumed by `.mediaImporter`.
public enum ImportSource: Hashable, Sendable {
    case photos, files, camera, paste
}

/// What the Photos library and the camera offer for an editor.
public struct MediaLibraryKinds: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let images = MediaLibraryKinds(rawValue: 1)
    public static let videos = MediaLibraryKinds(rawValue: 2)
    public static let none: MediaLibraryKinds = []
}

/// The import choices, for a `Menu` (toolbar button, empty state, sub-menu).
public struct ImportMenuItems: View {
    @Binding var request: ImportSource?
    let library: MediaLibraryKinds
    let camera: MediaLibraryKinds

    public init(request: Binding<ImportSource?>, library: MediaLibraryKinds, camera: MediaLibraryKinds = .none) {
        _request = request
        self.library = library
        self.camera = camera
    }

    public var body: some View {
        if !library.isEmpty {
            Button { request = .photos } label: { Label("Libreria Foto", systemImage: "photo.on.rectangle.angled") }
        }
        Button { request = .files } label: { Label("File", systemImage: "folder") }
        if !camera.isEmpty, UIImagePickerController.isSourceTypeAvailable(.camera) {
            Button { request = .camera } label: {
                Label(camera.contains(.videos) && !camera.contains(.images) ? "Registra video" : "Fotocamera", systemImage: "camera")
            }
        }
        Button { request = .paste } label: { Label("Incolla", systemImage: "doc.on.clipboard") }
    }
}

/// Toolbar-style "Importa" menu.
public struct ImportMenu: View {
    let title: String
    let systemImage: String
    @Binding var request: ImportSource?
    let library: MediaLibraryKinds
    let camera: MediaLibraryKinds

    public init(_ title: String, systemImage: String, request: Binding<ImportSource?>, library: MediaLibraryKinds, camera: MediaLibraryKinds = .none) {
        self.title = title
        self.systemImage = systemImage
        _request = request
        self.library = library
        self.camera = camera
    }

    public var body: some View {
        Menu {
            ImportMenuItems(request: $request, library: library, camera: camera)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .accessibilityLabel(title)
    }
}

public extension View {
    /// Presents the source chosen in `request` and handles drops and paste. `onImport` gets local
    /// file URLs: files from the Files app as picked (security-scoped, as before), everything else
    /// copied into a temporary folder. With `audioFromVideo`, videos become M4A audio first.
    func mediaImporter(_ request: Binding<ImportSource?>, types: [UTType], library: MediaLibraryKinds,
                       camera: MediaLibraryKinds = .none, multiple: Bool = false, audioFromVideo: Bool = false,
                       onImport: @escaping ([URL]) -> Void) -> some View {
        modifier(MediaImporter(request: request, types: types, library: library, camera: camera, multiple: multiple,
                               audioFromVideo: audioFromVideo, onImport: onImport))
    }
}

struct MediaImporter: ViewModifier {
    @Binding var request: ImportSource?
    let types: [UTType]
    let library: MediaLibraryKinds
    let camera: MediaLibraryKinds
    let multiple: Bool
    let audioFromVideo: Bool
    let onImport: ([URL]) -> Void

    @State private var picked: [PhotosPickerItem] = []
    @State private var busy = false
    @State private var error: String?
    @State private var dropTargeted = false

    private func shows(_ s: ImportSource) -> Binding<Bool> {
        Binding(get: { request == s }, set: { if !$0, request == s { request = nil } })
    }

    private var filter: PHPickerFilter {
        switch (library.contains(.images), library.contains(.videos)) {
        case (true, true): .any(of: [.images, .videos])
        case (false, true): .videos
        default: .images
        }
    }

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: shows(.photos), selection: $picked, maxSelectionCount: multiple ? 50 : 1,
                          selectionBehavior: .ordered, matching: filter, preferredItemEncoding: .current)
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                picked = []
                Task { await loadPhotos(items) }
            }
            .fileImporter(isPresented: shows(.files), allowedContentTypes: types, allowsMultipleSelection: multiple) { r in
                if case .success(let urls) = r { Task { await deliver(urls) } }
            }
            .fullScreenCover(isPresented: shows(.camera)) {
                CameraPicker(kinds: camera) { url in
                    request = nil
                    if let url { Task { await deliver([url]) } }
                }
                .ignoresSafeArea()
            }
            .onChange(of: request) { _, r in
                guard r == .paste else { return }
                request = nil
                Task { await paste() }
            }
            .onDrop(of: types + (library.contains(.images) ? [.image] : []) + (library.contains(.videos) ? [.movie] : []),
                    isTargeted: $dropTargeted) { providers in
                Task { await load(providers) }
                return true
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(StudioTheme.accent, style: StrokeStyle(lineWidth: 3, dash: [10, 6]))
                        .padding(6)
                        .allowsHitTesting(false)
                }
            }
            .overlay { if busy { ProgressOverlay("Importazione…") } }
            .overlay(alignment: .bottom) { if let error { ErrorBanner(error) { self.error = nil } } }
    }

    // MARK: sources

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        busy = true
        defer { busy = false }
        var urls: [URL] = []
        for item in items {
            let t = item.supportedContentTypes
            do {
                // the original first: RAW/ProRAW stay raw, HEIC stays HEIC, videos keep their codec
                var file: PickedFile?
                if t.contains(where: { $0.conforms(to: .rawImage) }) {
                    file = try await item.loadTransferable(type: PickedRaw.self)?.file
                } else if t.contains(where: { $0.conforms(to: .movie) }) {
                    file = try await item.loadTransferable(type: PickedMovie.self)?.file
                } else {
                    file = try await item.loadTransferable(type: PickedImage.self)?.file
                }
                if let file { urls.append(file.url) }
            } catch {
                self.error = "Un elemento della libreria Foto non è stato importato: \(error.localizedDescription)"
            }
        }
        if !urls.isEmpty { await deliver(urls) }
    }

    private func paste() async {
        let providers = UIPasteboard.general.itemProviders
        guard !providers.isEmpty else { error = "Gli appunti sono vuoti."; return }
        await load(providers)
    }

    private func load(_ providers: [NSItemProvider]) async {
        busy = true
        defer { busy = false }
        var accepted = types
        if library.contains(.images) { accepted.append(.image) }
        if library.contains(.videos) { accepted.append(.movie) }
        var urls: [URL] = []
        for p in providers.prefix(multiple ? 50 : 1) {
            guard let t = p.registeredContentTypes.first(where: { ct in accepted.contains { ct.conforms(to: $0) } }) else { continue }
            if let u = await Self.loadFile(p, type: t) { urls.append(u) }
        }
        if urls.isEmpty { error = "Niente da importare qui: il contenuto non è di un tipo che questo editor accetta." } else { await deliver(urls) }
    }

    private static func loadFile(_ p: NSItemProvider, type: UTType) async -> URL? {
        await withCheckedContinuation { cont in
            _ = p.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                cont.resume(returning: url.flatMap { try? ImportStaging.copy($0, preferredName: p.suggestedName, type: type) })
            }
        }
    }

    private func deliver(_ urls: [URL]) async {
        guard audioFromVideo else { onImport(urls); return }
        busy = true
        defer { busy = false }
        var out: [URL] = []
        for u in urls {
            let isVideo = (UTType(filenameExtension: u.pathExtension)?.conforms(to: .movie) ?? false)
            if !isVideo { out.append(u); continue }
            do { out.append(try await ImportStaging.extractAudio(u)) } catch { self.error = error.localizedDescription }
        }
        if !out.isEmpty { onImport(out) }
    }
}

// MARK: - Transferables for the Photos picker

struct PickedFile: Sendable { let url: URL }

struct PickedRaw: Transferable {
    let file: PickedFile
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .rawImage) { r in PickedRaw(file: PickedFile(url: try ImportStaging.copy(r.file))) }
    }
}

struct PickedImage: Transferable {
    let file: PickedFile
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { r in PickedImage(file: PickedFile(url: try ImportStaging.copy(r.file))) }
    }
}

struct PickedMovie: Transferable {
    let file: PickedFile
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { r in PickedMovie(file: PickedFile(url: try ImportStaging.copy(r.file))) }
    }
}

/// Temporary copies of imported media (the system's own temporary files vanish after the callback).
enum ImportStaging {
    static func folder() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("Import", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func copy(_ src: URL, preferredName: String? = nil, type: UTType? = nil) throws -> URL {
        var name = src.lastPathComponent
        if let preferredName, !preferredName.isEmpty {
            let ext = src.pathExtension.isEmpty ? (type?.preferredFilenameExtension ?? "") : src.pathExtension
            name = ext.isEmpty || preferredName.lowercased().hasSuffix("." + ext.lowercased()) ? preferredName : "\(preferredName).\(ext)"
        }
        let dest = try folder().appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
        try FileManager.default.copyItem(at: src, to: dest)
        return dest
    }

    /// The audio track of a video as AAC in M4A.
    static func extractAudio(_ video: URL) async throws -> URL {
        let scoped = video.startAccessingSecurityScopedResource()
        defer { if scoped { video.stopAccessingSecurityScopedResource() } }
        let asset = AVURLAsset(url: video)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw StudioError.notAvailable("il video \"\(video.lastPathComponent)\" non ha una traccia audio")
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw StudioError.notAvailable("estrazione dell'audio non disponibile")
        }
        let out = try folder().appendingPathComponent(video.deletingPathExtension().lastPathComponent + ".m4a")
        try await session.export(to: out, as: .m4a)
        return out
    }
}

// MARK: - Camera

/// The system camera for one photo (JPEG) or one video, written to a temporary file.
struct CameraPicker: UIViewControllerRepresentable {
    let kinds: MediaLibraryKinds
    let done: (URL?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        var types: [String] = []
        if kinds.contains(.images) { types.append(UTType.image.identifier) }
        if kinds.contains(.videos) { types.append(UTType.movie.identifier) }
        c.mediaTypes = types.isEmpty ? [UTType.image.identifier] : types
        c.videoQuality = .typeHigh
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (URL?) -> Void
        init(done: @escaping (URL?) -> Void) { self.done = done }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let movie = info[.mediaURL] as? URL {
                done(try? ImportStaging.copy(movie, preferredName: "Video \(Self.stamp())", type: .movie))
            } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.95),
                      let dir = try? ImportStaging.folder() {
                let url = dir.appendingPathComponent("Foto \(Self.stamp()).jpg")
                done((try? data.write(to: url)) != nil ? url : nil)
            } else {
                done(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }

        static func stamp() -> String {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH.mm.ss"
            return f.string(from: .now)
        }
    }
}

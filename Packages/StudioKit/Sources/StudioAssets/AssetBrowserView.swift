import StudioCore
import SwiftUI
import UniformTypeIdentifiers

public struct AssetBrowserView: View {
    let catalog: AssetCatalog
    /// Opens an asset in an editor (the app decides how).
    let onOpen: (Asset, URL, StudioModule) -> Void
    @State private var query = ""
    @State private var kind: AssetKind?
    @State private var favoritesOnly = false
    @State private var tag: String?
    @State private var selected: Asset.ID?
    @State private var importing = false
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var newTag = ""
    @State private var refresh = 0

    public init(catalog: AssetCatalog = .shared, onOpen: @escaping (Asset, URL, StudioModule) -> Void) {
        self.catalog = catalog
        self.onOpen = onOpen
    }

    var results: [Asset] {
        _ = refresh
        return catalog.search(query, kind: kind, favoritesOnly: favoritesOnly, tag: tag)
    }

    var selectedAsset: Asset? { catalog.assets.first { $0.id == selected } }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                filters
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        ForEach(results) { a in
                            AssetTile(catalog: catalog, asset: a, selected: selected == a.id)
                                .onTapGesture { selected = a.id }
                        }
                    }
                    .padding()
                }
                .overlay {
                    if catalog.assets.isEmpty {
                        ContentUnavailableView("Libreria vuota", systemImage: "photo.on.rectangle.angled",
                                               description: Text("Importa foto, RAW, video, audio, documenti e font. I file identici vengono salvati una sola volta."))
                    }
                }
            }
            if let a = selectedAsset {
                Divider()
                detail(a).frame(width: 300)
            }
        }
        .navigationTitle("Libreria asset")
        .searchable(text: $query, prompt: "Nome, tag o metadati")
        .toolbar {
            Button { importing = true } label: { Label("Importa", systemImage: "plus") }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r else { return }
            Task {
                do {
                    let res = try await catalog.importFiles(urls)
                    message = "Importati \(res.added.count) file" + (res.duplicates.isEmpty ? "" : ", \(res.duplicates.count) già presenti (non duplicati)")
                    refresh += 1
                } catch {
                    message = error.localizedDescription
                }
            }
        }
        .overlay(alignment: .top) { if let m = message { ErrorBanner(m) { message = nil } } }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                chip("Tutti", selected: kind == nil) { kind = nil }
                ForEach(AssetKind.allCases, id: \.self) { k in chip(k.title, icon: k.icon, selected: kind == k) { kind = kind == k ? nil : k } }
                Divider().frame(height: 20)
                chip("Preferiti", icon: "star.fill", selected: favoritesOnly) { favoritesOnly.toggle() }
                ForEach(catalog.allTags, id: \.self) { t in chip("#\(t)", selected: tag == t) { tag = tag == t ? nil : t } }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func chip(_ title: String, icon: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(selected ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func detail(_ a: Asset) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                AssetTile(catalog: catalog, asset: a, selected: false).frame(height: 200)
                Text(a.name).font(.headline)
                Text("\(a.kind.title) · \(ByteCountFormatter.string(fromByteCount: a.bytes, countStyle: .file))").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { catalog.update(a.id) { $0.favorite.toggle() }; refresh += 1 } label: {
                        Label(a.favorite ? "Preferito" : "Aggiungi ai preferiti", systemImage: a.favorite ? "star.fill" : "star")
                    }
                    Spacer()
                }
                HStack {
                    ForEach(1 ... 5, id: \.self) { i in
                        Image(systemName: i <= a.rating ? "star.fill" : "star").foregroundStyle(.yellow)
                            .onTapGesture { catalog.update(a.id) { $0.rating = $0.rating == i ? 0 : i }; refresh += 1 }
                    }
                }
                ForEach(a.metadata.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                    HStack { Text(k).font(.caption).foregroundStyle(.secondary); Spacer(); Text(v).font(.caption) }
                }
                Text("Tag").font(.subheadline.weight(.semibold))
                FlowTags(tags: a.tags) { t in catalog.update(a.id) { $0.tags.removeAll { $0 == t } }; refresh += 1 }
                HStack {
                    TextField("Nuovo tag", text: $newTag).textFieldStyle(.roundedBorder).onSubmit { addTag(a) }
                    Button("Aggiungi") { addTag(a) }
                }
                Text("Apri in").font(.subheadline.weight(.semibold)).padding(.top)
                ForEach(targets(a), id: \.self) { m in
                    Button { onOpen(a, catalog.url(of: a), m) } label: { Label(m.title, systemImage: m.systemImage) }.buttonStyle(.bordered)
                }
                ShareLink(item: catalog.url(of: a)) { Label("Condividi / Salva in File", systemImage: "square.and.arrow.up") }
                Button("Rimuovi dalla libreria", role: .destructive) { confirmDelete = true }
                    .confirmationDialog("Rimuovere \(a.name)? La copia nella libreria verrà eliminata; i progetti che la usano hanno una propria copia.",
                                        isPresented: $confirmDelete, titleVisibility: .visible) {
                        Button("Rimuovi", role: .destructive) { try? catalog.remove(a.id); selected = nil; refresh += 1 }
                    }
            }
            .padding()
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func addTag(_ a: Asset) {
        let t = newTag.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        catalog.update(a.id) { if !$0.tags.contains(t) { $0.tags.append(t) } }
        newTag = ""
        refresh += 1
    }

    private func targets(_ a: Asset) -> [StudioModule] {
        switch a.kind {
        case .raw: [.photo]
        case .photo: [.photo, .raster]
        case .video: [.video]
        case .audio: [.audio, .video]
        case .document: a.name.lowercased().hasSuffix(".pdf") ? [.pdf] : a.name.lowercased().hasSuffix(".svg") ? [.vector] : []
        default: []
        }
    }
}

struct AssetTile: View {
    let catalog: AssetCatalog
    let asset: Asset
    let selected: Bool
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.15))
                if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: .fit).padding(4) } else {
                    Image(systemName: asset.kind.icon).font(.largeTitle).foregroundStyle(.secondary)
                }
                if asset.favorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow).padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
            Text(asset.name).font(.caption).lineLimit(1)
        }
        .task(id: asset.id) { image = await catalog.thumbnail(asset, size: CGSize(width: 300, height: 300)) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(asset.kind.title): \(asset.name)")
    }
}

struct FlowTags: View {
    let tags: [String]
    let remove: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], alignment: .leading) {
            ForEach(tags, id: \.self) { t in
                HStack(spacing: 2) {
                    Text("#\(t)").font(.caption)
                    Button { remove(t) } label: { Image(systemName: "xmark.circle.fill").font(.caption2) }.buttonStyle(.plain)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.2), in: Capsule())
            }
        }
    }
}

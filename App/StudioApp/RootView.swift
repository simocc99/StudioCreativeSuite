import StudioAssets
import StudioAudio
import StudioCore
import StudioLayout
import StudioMotion
import StudioPaint
import StudioPDF
import StudioPhoto
import StudioVector
import StudioVideo
import SwiftUI

struct RootView: View {
    @State private var state = AppState()
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $state.module) {
                Section {
                    // nil selection = Home; a row can't carry a nil tag, so Home is a button
                    Button { state.module = nil } label: { Label("Home", systemImage: "house") }
                        .listRowBackground(state.module == nil ? Color.accentColor.opacity(0.25) : nil)
                }
                Section("Immagini") { rows([.photo, .raster, .vector, .paint]) }
                Section("Video e animazione") { rows([.video, .motion, .animation]) }
                Section("Audio") { rows([.audio]) }
                Section("Documenti") { rows([.layout, .pdf]) }
                Section("Organizza") { rows([.assets]) }
            }
            .navigationTitle("Studio")
        } detail: {
            NavigationStack(path: $state.path) {
                Group {
                    switch state.module {
                    case nil: HomeView(state: state)
                    case .assets?: AssetBrowserView { a, url, m in state.open(asset: a, file: url, in: m) }
                    case .pdf?: PDFLibraryView()
                    case let m?: ProjectListView(state: state, module: m)
                    }
                }
                .navigationDestination(for: EditorRoute.self) { route in
                    switch route {
                    case .project(let url, let m, let pending): EditorHost(url: url, module: m, pendingImport: pending)
                    case .pdf(let url): PDFEditorHost(url: url)
                    }
                }
            }
            .id(state.module)
        }
        .onChange(of: state.module) { _, _ in state.path = NavigationPath() }
        // editors get the whole screen; the module list comes back on the way out
        .onChange(of: state.path.count) { _, n in withAnimation { columns = n > 0 ? .detailOnly : .all } }
        .onAppear { state.reload() }
        .overlay(alignment: .top) { if let e = state.error { ErrorBanner(e) { state.error = nil } } }
    }

    private func rows(_ ms: [StudioModule]) -> some View {
        ForEach(ms) { m in
            // the tag type must match the List selection type (StudioModule), not Optional
            Label(m.title, systemImage: m.systemImage).tag(m)
        }
    }
}

struct HomeView: View {
    let state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Studio Creative Suite").font(.largeTitle.bold())
                    Text("Editor creativi nativi per iPad. Tutto viene elaborato sul dispositivo: nessun file lascia l'iPad senza una tua azione.")
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(StudioModule.allCases) { m in
                        Button { state.module = m } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: m.systemImage).font(.title).foregroundStyle(Color.accentColor)
                                Text(m.title).font(.headline)
                                Text(m.subtitle).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                            .padding()
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !state.projects.isEmpty {
                    Text("Progetti recenti").font(.title2.bold())
                    ForEach(state.projects.prefix(8)) { p in
                        NavigationLink(value: EditorRoute.project(p.url, p.header.kind, pendingImport: nil)) {
                            HStack {
                                Image(systemName: p.header.kind.systemImage).frame(width: 30)
                                VStack(alignment: .leading) {
                                    Text(p.header.name).font(.headline)
                                    Text("\(p.header.kind.title) · \(p.header.modified.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Motore fotografico: \(PhotoEngine.version)").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(28)
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { state.reload() }
    }
}

struct ProjectListView: View {
    let state: AppState
    let module: StudioModule
    @State private var newName = ""
    @State private var showNew = false
    @State private var renaming: ProjectSummary?
    @State private var deleting: ProjectSummary?
    @State private var template: QuickTemplate?

    var body: some View {
        List {
            if module == .vector {
                Section("Composizioni rapide da modello") {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(QuickTemplate.all) { t in
                                Button {
                                    template = t
                                    newName = t.name
                                    showNew = true
                                } label: {
                                    VStack {
                                        Image(uiImage: VectorRenderer.image(t.document(), scale: 160 / max(t.width, t.height), opaque: true))
                                            .resizable().aspectRatio(contentMode: .fit).frame(height: 110)
                                        Text(t.name).font(.caption)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            Section("Progetti") {
                ForEach(state.projects(for: module)) { p in
                    NavigationLink(value: EditorRoute.project(p.url, module, pendingImport: nil)) {
                        VStack(alignment: .leading) {
                            Text(p.header.name).font(.headline)
                            Text("Modificato \(p.header.modified.formatted(date: .abbreviated, time: .shortened)) · formato v\(p.header.formatVersion)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu {
                        Button("Rinomina") { renaming = p; newName = p.header.name }
                        Button("Duplica") { _ = try? ProjectStore.shared.duplicate(p.url); state.reload() }
                        Button("Sposta nei progetti eliminati", role: .destructive) { deleting = p }
                    }
                    .swipeActions {
                        Button("Elimina", role: .destructive) { deleting = p }
                    }
                }
                if state.projects(for: module).isEmpty {
                    Text("Nessun progetto. Crea il primo con il pulsante +.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(module.title)
        .toolbar {
            Button { template = nil; newName = "\(module.title) \(state.projects(for: module).count + 1)"; showNew = true } label: {
                Label("Nuovo progetto", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        .alert("Nuovo progetto", isPresented: $showNew) {
            TextField("Nome", text: $newName)
            Button("Crea") {
                if let url = state.create(module, name: newName, template: template) {
                    state.path.append(EditorRoute.project(url, module, pendingImport: nil))
                }
            }
            Button("Annulla", role: .cancel) {}
        }
        .alert("Rinomina", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nome", text: $newName)
            Button("Rinomina") {
                if let r = renaming { _ = try? ProjectStore.shared.rename(r.url, to: newName) }
                state.reload()
            }
            Button("Annulla", role: .cancel) {}
        }
        .confirmationDialog("Spostare \"\(deleting?.header.name ?? "")\" nei progetti eliminati? Puoi recuperarlo dalla cartella Deleted Projects nell'app File.",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Sposta", role: .destructive) {
                if let d = deleting { try? ProjectStore.shared.moveToDeleted(d.url) }
                state.reload()
            }
        }
        .onAppear { state.reload() }
    }
}

/// Loads a project of the right type and shows its editor; reports unreadable / newer projects.
struct EditorHost: View {
    let url: URL
    let module: StudioModule
    let pendingImport: URL?
    @State private var content: AnyView?
    @State private var error: String?

    var body: some View {
        Group {
            if let content { content } else if let error {
                ContentUnavailableView("Impossibile aprire il progetto", systemImage: "exclamationmark.triangle", description: Text(error))
            } else { ProgressView() }
        }
        .task { load() }
    }

    @MainActor
    private func load() {
        guard content == nil else { return }
        do {
            switch module {
            case .photo: content = AnyView(PhotoEditorView(project: try ProjectController<PhotoProject>(url: url)))
            case .raster: content = AnyView(RasterEditorView(project: try ProjectController<RasterProject>(url: url)))
            case .vector: content = AnyView(VectorEditorView(project: try ProjectController<VectorProject>(url: url)))
            case .paint: content = AnyView(PaintEditorView(project: try ProjectController<PaintProject>(url: url)))
            case .video:
                let c = try ProjectController<VideoProject>(url: url)
                content = AnyView(VideoEditorView(project: c).task { if let p = pendingImport { await importVideo(p, c) } })
            case .motion: content = AnyView(MotionEditorView(project: try ProjectController<MotionProject>(url: url)))
            case .animation: content = AnyView(AnimationEditorView(project: try ProjectController<AnimationProject>(url: url)))
            case .audio:
                let c = try ProjectController<AudioProject>(url: url)
                if let p = pendingImport, c.payload.media.isEmpty, let rel = try? c.importMedia(p),
                   let m = try? AudioMediaProbe.probeSync(c.resolve(rel), path: rel) {
                    c.mutate("Importa") { $0.media.append(m); $0.addClip(m, track: 0) }
                }
                content = AnyView(AudioEditorView(project: c))
            case .layout: content = AnyView(LayoutEditorView(project: try ProjectController<LayoutProject>(url: url)))
            case .pdf, .assets: error = "Tipo di progetto non valido"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    private func importVideo(_ file: URL, _ c: ProjectController<VideoProject>) async {
        guard c.payload.media.isEmpty, let rel = try? c.importMedia(file),
              let item = try? await MediaProbe.probe(c.resolve(rel), relativePath: rel) else { return }
        c.mutate("Importa") { p in
            p.media.append(item)
            let t = p.tracks.firstIndex { item.hasVideo ? $0.kind == .video : $0.kind == .audio } ?? 0
            p.addClip(item, track: t)
        }
    }
}

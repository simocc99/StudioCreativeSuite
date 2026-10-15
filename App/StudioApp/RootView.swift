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

/// Module groups shown in the sidebar and on the home.
struct ModuleGroup: Identifiable, Sendable {
    let title: String
    let modules: [StudioModule]
    var id: String { title }
}

let moduleGroups: [ModuleGroup] = [
    ModuleGroup(title: "Immagini", modules: [.photo, .raster, .vector, .paint]),
    ModuleGroup(title: "Video e animazione", modules: [.video, .motion, .animation]),
    ModuleGroup(title: "Audio", modules: [.audio]),
    ModuleGroup(title: "Documenti", modules: [.layout, .pdf]),
    ModuleGroup(title: "Organizza", modules: [.assets]),
]

/// Modules that work on projects (PDF and the asset library open files directly).
let projectModules: [StudioModule] = StudioModule.allCases.filter { $0 != .pdf && $0 != .assets }

struct RootView: View {
    @State private var state: AppState
    @State private var columns: NavigationSplitViewVisibility = .all

    init(state: AppState = AppState()) {
        _state = State(initialValue: state)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar(state: state)
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
                    Group {
                        switch route {
                        case .project(let url, let m, let pending): EditorHost(url: url, module: m, pendingImport: pending)
                        case .pdf(let url): PDFEditorHost(url: url)
                        }
                    }
                    .studioEditorChrome()
                }
            }
            .id(state.module)
        }
        .tint(StudioTheme.accent)
        .onChange(of: state.module) { _, _ in state.path = NavigationPath() }
        // editors get the whole screen; the module list comes back on the way out
        .onChange(of: state.path.count) { _, n in withAnimation { columns = n > 0 ? .detailOnly : .all } }
        .onAppear {
            state.reload()
            if !state.path.isEmpty { columns = .detailOnly }
        }
        .overlay(alignment: .top) { if let e = state.error { ErrorBanner(e) { state.error = nil } } }
    }
}

/// Sidebar with explicit buttons (not List selection): full control over the highlight,
/// and Home can be "no module" without an optional tag.
struct Sidebar: View {
    let state: AppState

    var body: some View {
        List {
            Section {
                SidebarRow(title: "Home", selected: state.module == nil) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(state.module == nil ? Color.white : StudioTheme.accent)
                        .frame(width: 26, height: 26)
                        .background(state.module == nil ? StudioTheme.accent : StudioTheme.accent.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                } action: { state.module = nil }
            }
            ForEach(moduleGroups) { group in
                Section(group.title) {
                    ForEach(group.modules) { m in
                        let count = state.projects(for: m).count
                        SidebarRow(title: m.title, detail: projectModules.contains(m) && count > 0 ? "\(count)" : nil,
                                   selected: state.module == m) {
                            ModuleIcon(m, size: 26, highlighted: state.module == m)
                        } action: { state.module = m }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(StudioTheme.panel)
        .navigationTitle("Studio")
    }
}

struct SidebarRow<Icon: View>: View {
    let title: String
    var detail: String? = nil
    let selected: Bool
    @ViewBuilder let icon: Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                Text(title).font(.body.weight(selected ? .semibold : .regular)).foregroundStyle(.primary)
                Spacer(minLength: 4)
                if let detail { Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? StudioTheme.accent.opacity(0.18) : Color.clear)
                .padding(.horizontal, 8)
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct HomeView: View {
    let state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                header
                VStack(alignment: .leading, spacing: 14) {
                    StudioSectionHeader("Crea")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(projectModules) { m in
                                Button { quickCreate(m) } label: { CreateTile(module: m) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Nuovo progetto \(m.title)")
                            }
                        }
                    }
                }
                recents
                VStack(alignment: .leading, spacing: 18) {
                    StudioSectionHeader("Strumenti")
                    ForEach(moduleGroups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(group.title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                                ForEach(group.modules) { m in
                                    Button { state.module = m } label: {
                                        ModuleTile(module: m, count: projectModules.contains(m) ? state.projects(for: m).count : nil)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                Text("Motore fotografico \(PhotoEngine.version)").font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(32)
        }
        .background(StudioTheme.background)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { state.reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Studio").font(.system(size: 40, weight: .bold, design: .default))
            Text(state.projects.isEmpty
                 ? "Foto RAW, video, audio, grafica e documenti. Tutto viene elaborato sull'iPad."
                 : "\(state.projects.count) progetti · tutto viene elaborato sull'iPad")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var recents: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSectionHeader("Recenti")
            if state.projects.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles").font(.title2).foregroundStyle(StudioTheme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Inizia il tuo primo progetto").font(.headline)
                        Text("Tocca uno strumento in \"Crea\": il progetto si apre subito e si salva da solo.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .studioCard()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                    ForEach(state.projects.prefix(8)) { p in
                        NavigationLink(value: EditorRoute.project(p.url, p.header.kind, pendingImport: nil)) {
                            ProjectCard(project: p)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// One tap from the home to an open, empty editor; the name can be changed later.
    private func quickCreate(_ m: StudioModule) {
        let name = "\(m.title) \(state.projects(for: m).count + 1)"
        if let url = state.create(m, name: name) {
            state.path.append(EditorRoute.project(url, m, pendingImport: nil))
        }
    }
}

struct CreateTile: View {
    let module: StudioModule

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ModuleIcon(module, size: 34)
                Spacer()
                Image(systemName: "plus").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            Text(module.title).font(.subheadline.weight(.semibold)).lineLimit(1)
        }
        .padding(14)
        .frame(width: 168, alignment: .leading)
        .studioCard(radius: 12)
    }
}

struct ModuleTile: View {
    let module: StudioModule
    let count: Int?

    var body: some View {
        HStack(spacing: 12) {
            ModuleIcon(module, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(module.title).font(.subheadline.weight(.semibold))
                Text(module.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let count, count > 0 {
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .studioCard(radius: 12)
        .contentShape(Rectangle())
    }
}

/// Project tile: the editor's saved preview (or the module symbol) above name and date.
struct ProjectCard: View {
    let project: ProjectSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                StudioTheme.canvas
                if let u = project.thumbnailURL, let img = UIImage(contentsOfFile: u.path) {
                    Image(uiImage: img).resizable().aspectRatio(contentMode: .fit).padding(8)
                } else {
                    Image(systemName: project.header.kind.systemImage)
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 140)
            .clipped()
            HStack(spacing: 10) {
                ModuleIcon(project.header.kind, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.header.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(project.header.modified, format: .relative(presentation: .named))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: StudioTheme.cardRadius, style: .continuous))
        .studioCard()
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.header.name), \(project.header.kind.title)")
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
        let projects = state.projects(for: module)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 14) {
                    ModuleIcon(module, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(module.title).font(.largeTitle.bold())
                        Text(module.subtitle).font(.callout).foregroundStyle(.secondary)
                    }
                }
                if module == .vector { templates }
                VStack(alignment: .leading, spacing: 14) {
                    StudioSectionHeader("Progetti") {
                        Button { startNew() } label: { Label("Nuovo", systemImage: "plus") }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    if projects.isEmpty {
                        ContentUnavailableView {
                            Label("Nessun progetto \(module.title.lowercased())", systemImage: module.systemImage)
                        } description: {
                            Text("Crea un progetto: si salva da solo mentre lavori.")
                        } actions: {
                            Button("Crea progetto") { startNew() }.buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .studioCard()
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                            ForEach(projects) { p in
                                NavigationLink(value: EditorRoute.project(p.url, module, pendingImport: nil)) {
                                    ProjectCard(project: p)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { renaming = p; newName = p.header.name } label: { Label("Rinomina", systemImage: "pencil") }
                                    Button { _ = try? ProjectStore.shared.duplicate(p.url); state.reload() } label: {
                                        Label("Duplica", systemImage: "plus.square.on.square")
                                    }
                                    Button(role: .destructive) { deleting = p } label: {
                                        Label("Sposta nei progetti eliminati", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(32)
        }
        .background(StudioTheme.background)
        .navigationTitle(module.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button { startNew() } label: { Label("Nuovo progetto", systemImage: "plus") }
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

    private var templates: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioSectionHeader("Parti da un modello")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(QuickTemplate.all) { t in
                        Button {
                            template = t
                            newName = t.name
                            showNew = true
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Image(uiImage: VectorRenderer.image(t.document(), scale: 200 / max(t.width, t.height), opaque: true))
                                    .resizable().aspectRatio(contentMode: .fit)
                                    .frame(width: 180, height: 120)
                                    .background(StudioTheme.canvas)
                                Text(t.name).font(.subheadline.weight(.semibold)).padding(10)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .studioCard(radius: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func startNew() {
        template = nil
        newName = "\(module.title) \(state.projects(for: module).count + 1)"
        showNew = true
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

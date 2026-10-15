# Architettura

```
StudioCreativeSuite/
├── StudioCreativeSuite.xcworkspace     workspace: app + pacchetto
├── App/
│   ├── StudioCreativeSuite.xcodeproj   target iPadOS nativo (solo iPad, iOS 18+)
│   ├── Config/                         StudioApp.xcconfig, Info.plist parziale, Local.xcconfig (firma, ignorato da git)
│   └── StudioApp/                      shell SwiftUI: navigazione, elenco progetti, instradamento agli editor
├── Packages/StudioKit/                 pacchetto Swift con un modulo per editor
│   ├── Sources/StudioCore              progetti versionati, migrazioni, undo/redo, autosalvataggio, UI condivisa, writer video
│   ├── Sources/StudioPhoto             sviluppo RAW (LightCraft) + Fotoritocco a livelli (Core Image)
│   ├── Sources/StudioVector            vettoriale, SVG, booleane, modelli rapidi
│   ├── Sources/StudioPaint             motore pennelli, livelli bitmap
│   ├── Sources/StudioVideo             timeline multitraccia, compositor AVFoundation, export
│   ├── Sources/StudioMotion            composizioni a keyframe + animazione 2D a fotogrammi
│   ├── Sources/StudioAudio             DSP, mixer offline, registrazione, export
│   ├── Sources/StudioLayout            impaginazione multipagina → PDF
│   ├── Sources/StudioPDF               PDFKit: ricerca, annotazioni, pagine, unione
│   ├── Sources/StudioAssets            catalogo condiviso con deduplicazione
│   ├── Frameworks/                     StudioPhotoEngineFFI.xcframework (generato, non versionato)
│   └── Tests/StudioKitTests            test automatici
├── Engines/studio-photo-engine/        crate Rust: C ABI sopra LightCraft
└── Scripts/                            build-photo-engine.sh, build-ipa.sh, fetch-test-raws.sh, run-tests.sh
```

## Principi

- **Moduli = editor reali.** Ogni modulo esporta la sua vista principale (`PhotoEditorView`, `VideoEditorView`, …) e il suo tipo di documento (`ProjectPayload`). L'app non conosce i dettagli interni.
- **Funzioni pure per l'editing.** Le operazioni (dividere, rifilare, ripple, booleane, mix audio, interpolazione) sono funzioni su tipi valore, testate senza interfaccia.
- **Nessun lavoro pesante sul main thread.** Render RAW su una coda seriale dedicata del motore; mix audio, render raster e miniature in `Task.detached`; il compositor video lavora sulla sua coda; le richieste di render si fondono (l'ultima vince).
- **Originali intoccabili.** Ogni importazione copia il file nella cartella `Media/` del progetto (o nella libreria); le esportazioni vanno in `Documents/Exports` con nomi che non sovrascrivono. L'eliminazione di un progetto lo sposta in `Documents/Deleted Projects`.
- **Solo locale.** Nessuna chiamata di rete nel codice della suite. L'unico permesso richiesto è il microfono, e solo quando l'utente avvia una registrazione.

## Bridge Rust (StudioPhoto ↔ LightCraft)

C ABI minimale (`Engines/studio-photo-engine/include/StudioPhotoEngine.h`), scelto al posto di UniFFI perché l'interfaccia è piccola, stabile e senza callback:

| Funzione | Ruolo |
|---|---|
| `sc_photo_open(path, preview_edge, &err)` | decodifica (RAW dal sensore) a risoluzione di anteprima, importa nella sessione LightCraft |
| `sc_photo_default_settings_json` | impostazioni iniziali dell'engine per quel file (es. bilanciamento come scattato, nitidezza di cattura per i RAW) |
| `sc_photo_render(photo, settings_json, w, h, draft, &err)` | render RGBA8 con cache degli stadi (`render_cached`) |
| `sc_photo_export(photo, settings_json, out, format, quality, long_edge, &err)` | ridecodifica a piena risoluzione ed esporta con la stessa pipeline |
| `sc_raw_probe` | riconoscimento del contenitore senza decodifica |

Proprietà: ogni stringa e immagine restituita ha la sua funzione di rilascio; nessun panic attraversa il confine (`catch_unwind` → stringa d'errore). Il lato Swift (`PhotoEngine`) serializza le chiamate su una coda propria perché l'handle non è thread-safe.

Le impostazioni viaggiano come JSON dello schema `DevelopSettings` di LightCraft; Swift le conserva come `JSONValue` intero, così i campi che l'interfaccia non espone ancora non vengono persi.

## Video

`VideoProject` (tracce video/audio, clip con sorgente/velocità/fade/transizione/keyframe/colore/effetto, titoli, marcatori) → `CompositionBuilder` → `AVMutableComposition` con tracce A/B per traccia di progetto (per le dissolvenze incrociate), `AVMutableAudioMix` (volumi e rampe), `AVMutableVideoComposition` con **compositor personalizzato** (`StudioVideoCompositor`, Core Image): stessa resa in anteprima (`AVPlayer`) e in esportazione (`AVAssetExportSession`). I preset di esportazione mostrati sono solo quelli che `AVAssetExportSession.compatibility(...)` conferma per la sequenza sul dispositivo. Proxy 960×540 opzionali per l'anteprima.

## Formato di progetto

Vedi `docs/PROJECT_FORMAT.md`. In sintesi: cartella `<nome>.studio/` con `project.json` (`header` con tipo e versione del formato + `payload`) e `Media/`. Le migrazioni sono passi registrati `tipo#versione → versione+1` applicati all'albero JSON prima della decodifica; un file più recente dell'app viene rifiutato con un messaggio esplicito invece di essere letto male.

## Interfaccia

`NavigationSplitView` con barra laterale per moduli; ogni editor ha struttura a tre colonne (strumenti · canvas/monitor · ispettore) e, dove serve, una timeline ridimensionabile. Tastiera esterna: ⌘Z/⇧⌘Z ovunque; spazio, ⌘B, frecce, Canc, M nel video; V/A/M/L/P/T nel vettoriale. Apple Pencil: pressione e inclinazione nella pittura, modalità "solo Pencil" con le dita riservate a zoom/scorrimento; disegno a inchiostro nel PDF.

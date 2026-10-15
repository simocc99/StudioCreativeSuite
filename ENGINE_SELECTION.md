# Selezione dei motori

Data dell'analisi: 14 ottobre 2026. Ambiente: Xcode 27.0 (27A266a), SDK iOS 27.0, Rust 1.99.0, macOS 26.6 su Apple silicon.
Dispositivo di destinazione: iPad Pro 13" (M5), iPadOS 27.0.

## Criteri

Per ogni candidato sono stati valutati: licenza effettiva e obblighi, disponibilità e stato del sorgente, dipendenze native non disponibili su iOS (X11/Wayland, Qt desktop, GTK, processi figli, JIT, plugin caricati a runtime), separabilità del motore dall'interfaccia desktop, interoperabilità con Swift, uso di GPU/Metal, peso e memoria, funzionamento solo locale, lavoro di porting.

Vincoli specifici di iPadOS che pesano sulla scelta:

- nessun `fork`/`exec`: i programmi che delegano a eseguibili esterni (es. `ffmpeg` da riga di comando) non funzionano così come sono;
- niente caricamento dinamico di plugin non firmati e niente JIT per le app di terze parti;
- le librerie vanno collegate staticamente o come framework firmati nell'app;
- **GPL e iOS**: la GPL non vieta di compilare per iOS, ma ridistribuire un binario GPL impone di fornire il sorgente corrispondente e di non aggiungere restrizioni ulteriori; le condizioni dell'App Store sono considerate incompatibili dalla FSF. Per il sideloading/Xcode il problema è la redistribuzione: se un giorno la suite venisse distribuita a terzi, ogni componente GPL renderebbe GPL l'intera app. **LGPL** collegata staticamente (l'unico modo realistico su iOS) richiede di consentire il ricollegamento (oggetti o sorgente).

Per mantenere libera la scelta della licenza finale e la distribuzione, nella fase attuale **non è integrato alcun codice GPL/LGPL**.

## Matrice dei candidati

| Candidato | Licenza verificata | Stato (ultimo push) | iOS | Esito | Motivazione |
|---|---|---|---|---|---|
| **LightCraft** (storytold/lightcraft @ `3b4279f`) | MIT OR Apache-2.0 (+ marchi ArtCraft esclusi) | attivo, 14/10/2026 | **compilato e testato** per `aarch64-apple-ios` | **Adottato** (foto/RAW) | Rust puro, nessuna dipendenza C; il crate `lightcraft-engine` compila per iOS senza modifiche; decoder RAW proprio (DNG, CR2, CR3, NEF, NRW, ARW, RAF, RW2, PEF, SRW, 3FR/FFF), pipeline non distruttiva a 32 bit float, export JPEG/PNG/TIFF/WebP/AVIF/DNG. 279 crate nell'albero, tutti con licenze permissive. |
| GIMP / GEGL | GPL-3.0+ / LGPL-3.0+ | attivo | no (GTK, plugin come processi) | Scartato | Interfaccia GTK inseparabile; i plugin sono processi separati; GPL. Alternativa: compositore Core Image proprio (StudioPhoto › Fotoritocco). |
| Krita | GPL-3.0 | attivo | no (Qt Widgets desktop, una build Android esiste) | Scartato | Motore di pittura legato a Qt e alla sua architettura KDE; GPL. Alternativa: motore pennelli proprio (StudioPaint). |
| Inkscape | GPL-2.0+ (GPL-3 per l'insieme) | repository GitHub è un mirror (GitLab) | no (GTK) | Scartato | GTK; lib2geom (LGPL/MPL) potrebbe servire in futuro per booleane avanzate. Oggi: booleane `CGPath` di iOS 16+. |
| Kdenlive / MLT | GPL-3.0 / LGPL-2.1 | attivi | MLT forse, con FFmpeg; Kdenlive no (Qt/KDE) | Scartato per ora | MLT + FFmpeg su iOS è un porting pesante (C, plugin dinamici). AVFoundation copre H.264/HEVC/ProRes con accelerazione hardware. |
| Shotcut | GPL-3.0 | attivo | no | Scartato | Interfaccia Qt su MLT. |
| Blender | GPL-2.0+ (GPL-3 insieme) | attivo | no | Scartato | Applicazione desktop monolitica, OpenGL/Vulkan/Metal desktop, Python. Nessuna parte di compositing separabile a costo ragionevole. |
| Audacity | GPL-3.0 (3.x) | attivo | no (wxWidgets) | Scartato | wxWidgets; GPL. Alternativa: DSP proprio in Swift/Accelerate (StudioAudio). |
| Scribus | GPL-2.0+ | attivo | no (Qt) | Scartato | Qt desktop. Alternativa: impaginazione TextKit + UIGraphicsPDFRenderer (StudioLayout). |
| PDFium | BSD-3-Clause + Apache-2.0 | attivo (Google) | possibile, porting C++ con GN/clang | Rinviato | PDFKit di sistema copre lettura, ricerca, annotazioni e struttura delle pagine. PDFium servirà solo per la modifica del contenuto delle pagine. |
| Poppler | GPL-2.0/3.0 | attivo | possibile | Scartato | GPL; ridondante con PDFKit. |
| MuPDF | AGPL-3.0 (o commerciale) | attivo | sì (SDK iOS ufficiale) | Scartato | AGPL incompatibile con una distribuzione libera da obblighi; licenza commerciale non appropriata. |
| FFmpeg | LGPL-2.1+ (GPL se si abilitano componenti GPL) | attivo | sì, come librerie statiche | Rinviato | Utile per formati che AVFoundation non legge (MKV, WebM/VP9/AV1 su certi dispositivi, FLAC in container vari). Richiede ricollegabilità LGPL → da integrare come framework dinamico firmato con le build non-GPL. |
| LibRaw | LGPL-2.1 / CDDL-1.0 | attivo | sì | Non necessario | Il decoder di LightCraft ha superato i test su 7 formati; LibRaw resta un'opzione per le fotocamere non coperte. |

Le licenze nella tabella sono state controllate tramite l'API di GitHub (`license.spdx_id`) e, per LightCraft, leggendo `LICENSE-APACHE`, `LICENSE-MIT` e `NOTICE` del commit adottato. I campi `NOASSERTION` di GitHub (GIMP, Blender, Audacity, Scribus, FFmpeg, LibRaw) indicano licenze multiple: i valori riportati sono quelli dichiarati dai progetti.

## Verifica di LightCraft

- Repository esistente: `https://github.com/storytold/lightcraft`, descrizione "open-source non-destructive photo editor written by scratch in pure Rust", commit `3b4279fc2485bb51847c0071a1b3c514aa0f98f4` del 14/10/2026.
- `cargo build -p lightcraft-engine --release --target aarch64-apple-ios`: riuscito in 2 min 53 s **senza modifiche al codice**.
- Bridge C (`Engines/studio-photo-engine`) compilato per `aarch64-apple-ios` e `aarch64-apple-ios-sim`, impacchettato come XCFramework statico.
- Test su 9 file RAW reali (archivio raw.pixls.us, licenza CC0) attraverso lo **stesso C ABI usato dall'app**: tutti decodificati dai dati del sensore (`isRaw = true`), renderizzati ed esportati in JPEG. Dettagli in `TEST_REPORT.md`.
- Parti di LightCraft **non usate**: interfaccia egui (`ui-egui`, `apps/lightcraft`), server MCP, download di modelli (`lightcraft-fetch` è compilato come dipendenza dell'engine ma il bridge non invoca alcun comando di rete), denoise AI e segmentazione SAM (feature opzionali non abilitate).
- Marchi: il nome e i loghi ArtCraft/LightCraft non sono usati nell'interfaccia; il motore è citato solo nei crediti tecnici.

## Componenti di sistema Apple usati come "motori"

| Area | Framework | Ruolo |
|---|---|---|
| Video | AVFoundation, VideoToolbox (implicito), Core Image | composizione multitraccia, compositor personalizzato, decodifica/codifica hardware |
| Audio | AVFoundation (AVAudioFile/Engine), Accelerate | I/O e conversione; DSP proprio (biquad, gate, mix) |
| Grafica | Core Graphics, Core Image, ImageIO | vettoriale, pittura, compositing raster, filtri, codifica immagini |
| Documenti | PDFKit, TextKit, UIGraphicsPDFRenderer | PDF (lettura, annotazioni, struttura), impaginazione |
| Asset | CryptoKit, QuickLookThumbnailing | deduplicazione SHA-256, miniature |

## Decisioni rinviate

1. **FFmpeg** (LGPL, build senza componenti GPL) come framework dinamico per formati non supportati da AVFoundation.
2. **PDFium** per la modifica del contenuto delle pagine PDF (testo e immagini nel content stream).
3. **Metal** diretto: oggi la GPU è usata tramite Core Image (compositing raster, video) e Core Animation (pittura). Un renderer Metal dedicato servirà per pennelli con texture GPU e per anteprime RAW interattive a piena risoluzione (LightCraft include un renderer `wgpu` che su iOS userebbe Metal: da valutare).

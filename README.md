# Studio Creative Suite

Suite creativa nativa per iPadOS (Swift/SwiftUI + motore RAW in Rust), pensata per iPad Pro 13" M5. Tutto il lavoro avviene sul dispositivo.

| Modulo | Cosa fa oggi |
|---|---|
| Sviluppo foto | RAW (DNG, CR2, CR3, NEF, ARW, RAF, RW2 verificati) e immagini tramite LightCraft: luce, bilanciamento, curva di tono, presenza, miscelatore, dettaglio, effetti, geometria, preset, prima/dopo, istogramma, export a piena risoluzione |
| Fotoritocco | livelli immagine/pittura/riempimento, 15 metodi di fusione, opacità, maschere, filtri non distruttivi, selezione rettangolare, ritaglio |
| Vettoriale | rettangoli, ellissi, penna Bézier, modifica nodi, testo, gradienti, booleane, allineamento, gruppi, livelli, SVG in/out, PNG fino a 4×, PDF, modelli rapidi |
| Pittura | 6 pennelli con pressione/inclinazione Apple Pencil, livelli, fusione in export, contagocce, modalità solo Pencil |
| Montaggio video | timeline multitraccia, dividi, rifila, ripple, sposta tra tracce, aggancio, marcatori, titoli e SRT, dissolvenze, transizioni incrociate, velocità, keyframe di trasformazione, colore, effetti, proxy, export H.264/HEVC/ProRes 422 |
| Motion | composizioni, livelli forma/testo/immagine, keyframe con 6 easing, maschere animate, testo animato, sfocatura, render video/PNG/GIF |
| Animazione 2D | fotogrammi, livelli, onion skin, riproduzione, export video/GIF |
| Audio | multitraccia, waveform, dividi/taglia, guadagno, normalizzazione, fade, reverse, EQ a 3 bande, filtri, noise gate, pan, automazione, meter, clipping, registrazione, export WAV/AIFF/CAF/M4A |
| Impaginazione | pagine A3/A4/A5/Letter, margini, griglia, cornici di testo multicolonna con stili, immagini, forme, numeri di pagina, PDF |
| PDF | lettura, ricerca, evidenziazione, note, disegno a inchiostro, riordino/rotazione/eliminazione pagine, pagina vuota, unione |
| Libreria asset | importazione con deduplicazione SHA-256, miniature, metadati EXIF/durata, tag, preferiti, valutazioni, ricerca, "Apri in" |

Documenti: [INSTALL.md](INSTALL.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [ENGINE_SELECTION.md](ENGINE_SELECTION.md) · [IPADOS_PORT_STATUS.md](IPADOS_PORT_STATUS.md) · [TEST_REPORT.md](TEST_REPORT.md) · [ROADMAP.md](ROADMAP.md) · [docs/FORMATS.md](docs/FORMATS.md) · [docs/PROJECT_FORMAT.md](docs/PROJECT_FORMAT.md) · [docs/CI.md](docs/CI.md) (build automatiche e AltSource) · [docs/CI.md](docs/CI.md) (build automatiche e AltSource) · [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

Avvio rapido:

```bash
Scripts/build-photo-engine.sh
```

```bash
open StudioCreativeSuite.xcworkspace
```

Questo progetto non è affiliato ad Adobe; i nomi dei prodotti Adobe sono citati solo per descrivere le categorie di strumenti.

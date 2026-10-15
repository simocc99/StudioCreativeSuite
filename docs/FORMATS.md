# Inventario dei formati

Legenda: **T** = verificato da un test automatico (simulatore iPad iOS 27, Apple silicon) · **M** = verificato sul Mac con lo stesso codice Rust/C ABI · **A** = dichiarato da API Apple / dal motore, non testato qui · **—** = non supportato.
**D** = verificato da test automatico sull'**iPad Pro 13" M5 fisico** (iPadOS 27.0), 14/10/2026.

## RAW (LightCraft)

"Sviluppo" = decodifica dei dati del sensore (demosaicizzazione, matrici colore, bilanciamento), non l'anteprima JPEG incorporata: il test controlla `isRaw = true` e il motore ricade sul JPEG incorporato solo se la variante non è decodificabile, segnalandolo come immagine renderizzata.

| Formato | Riconoscimento | Sviluppo RAW | Esportazione | Campione di test |
|---|---|---|---|---|
| DNG | D, T, M | D, T, M | D, T, M | Apple iPhone 12 Pro, Google Pixel 4a, Leica M10 |
| CR2 | D, T, M | D, T, M | D, T, M | Canon EOS 5D Mark III |
| CR3 | D, T, M | D, T, M | D, T, M | Canon EOS R10 |
| NEF | D, T, M | D, T, M | D, T, M | Nikon D750 (compresso 12 bit) |
| ARW | D, T, M | D, T, M | D, T, M | Sony ILCE-7M3 (non compresso 14 bit) |
| RAF | D, T, M | D, T, M | D, T, M | Fujifilm X-E3 (X-Trans) |
| RW2 | D, T, M | D, T, M | D, T, M | Panasonic DC-G9 |
| NRW, PEF, SRW, 3FR/FFF, Kodak DCS | A | A | A | nessun campione testato |
| ORF, CRW, MRW, X3F | A (riconosciuti) | — (LightCraft: non ancora decodificati) | anteprima incorporata se presente | — |

Ogni fotocamera/variante di compressione può comportarsi diversamente: i test coprono un file per formato. Altre varianti (CR3 C-RAW, NEF HE, ARW compressi, RAF compressi lossless) vanno aggiunte a `build/test-raws` e verificate con `Scripts/run-tests.sh`.

## Immagini

| Formato | Lettura | Scrittura |
|---|---|---|
| JPEG, PNG | T (motore foto, pittura, raster) | T |
| TIFF | A (ImageIO, LightCraft) | A (export foto 16 bit e raster) |
| HEIC/HEIF | A (ImageIO) | — |
| WebP, AVIF | A (LightCraft) | A (export foto) |
| GIF | A | T (motion, animazione) |
| PSD, AI, XCF, KRA | — | — |

## Vettoriale

| Formato | Lettura | Scrittura |
|---|---|---|
| SVG | T, sottoinsieme: rect, circle, ellipse, line, polyline, polygon, path (M L H V C S Q T Z assoluti e relativi), text, fill/stroke/opacity, `style`, `translate()`. Archi `A` approssimati con segmenti; filtri, maschere, clip, CSS a classi, `<use>`, immagini incorporate **ignorati e segnalati** all'utente | T: forme, tracciati, gradienti lineari/radiali, testo, rotazione |
| PDF | — | T (vettoriale, una pagina) |
| PNG / JPEG | — | T (1×, 2×, 4×) |
| AI, EPS | — | — |

## Video

Operazioni distinte come richiesto. Test eseguiti sul simulatore: la codifica/decodifica hardware dell'iPad può differire.

| Codec | Importazione/probe | Decodifica | Riproduzione | Elaborazione (compositor) | Esportazione |
|---|---|---|---|---|---|
| H.264 | D, T | D, T | A (AVPlayer) | D, T | D, T (preset 720p verificato; 1080p dichiarato da `compatibility`) |
| HEVC | D, T | D, T | A | A | D, T (codifica AVAssetWriter); preset di export mostrati solo se `compatibility` li conferma |
| ProRes 422 | D | D | A | A | **D**: codifica e ridecodifica riuscite sull'iPad M5 (FourCC `apcn`); nel simulatore la codifica fallisce ("Cannot Encode") |
| ProRes 4444 | A (FourCC riconosciuto) | A | A | A | — |
| ProRes RAW | FourCC `aprn`/`aprh` riconosciuto | **non supportato**: nessuna decodifica verificata attraverso API pubbliche disponibili all'app | — | — | — |
| VP9, AV1, MKV, WebM | — | — | — | — | — (in ROADMAP: FFmpeg LGPL) |

Contenitori di uscita: MP4 (H.264), MOV (HEVC, ProRes), M4A (solo audio), sequenze PNG, GIF.

## Audio

| Formato | Lettura | Scrittura |
|---|---|---|
| WAV 16/24 bit | T | T |
| AIFF | T | T |
| CAF 32 bit float | T | T |
| M4A/AAC | T | T |
| MP3, ALAC, FLAC | A (AVAudioFile) | — |
| Audio di file video | T (traccia audio nella timeline video) | T (mix nell'export video) |

## Documenti

| Formato | Lettura | Scrittura |
|---|---|---|
| PDF (visualizzazione, ricerca, annotazioni evidenziazione/nota/inchiostro, riordino, rotazione, eliminazione, unione) | T | T |
| PDF: modifica del contenuto originale delle pagine | — | — (le annotazioni restano livelli sopra la pagina) |
| PDF protetti da password | rifiutati con messaggio | — |
| Impaginazione → PDF con testo ricercabile | — | T |
| INDD, IDML | — | — |
| SRT (sottotitoli) | T | — |

## Progetti

Formato proprio documentato in `docs/PROJECT_FORMAT.md`, con versione e migrazioni (T). Nessuna compatibilità con PSD, AI, AEP, PRPROJ, INDD.

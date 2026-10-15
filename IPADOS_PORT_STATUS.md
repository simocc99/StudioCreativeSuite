# Stato del porting iPadOS

Aggiornato al 14/10/2026.

## Stato globale

| Verifica | Esito |
|---|---|
| Compilazione per iPadOS (arm64, iOS 27 SDK, deployment 18.0) | ✅ Debug e Release |
| Motore Rust LightCraft per `aarch64-apple-ios` / `-sim` | ✅ |
| Avvio dell'app nel simulatore iPad Pro 13" (M5), navigazione, creazione e riapertura di un progetto | ✅ verificato a mano |
| Test automatici (simulatore) | vedi `TEST_REPORT.md` |
| IPA non firmato, struttura verificata | ✅ `Scripts/build-ipa.sh` |
| Firma | ✅ automatica con un Personal Team (account gratuito, profilo valido 7 giorni); team e bundle in `App/Config/Local.xcconfig`, non versionato |
| **Installazione e avvio sull'iPad Pro 13" M5 fisico (iPadOS 27.0)** | ✅ installata con `devicectl`, avviata, processo stabile; nessun crash report |
| **Test automatici sull'iPad fisico** | ✅ 31 test XCTest, 65/65 verifiche atteso/osservato (`Scripts/run-device-tests.sh`, report in `docs/device-test-report.json`) |
| Installazione tramite SideStore | ⏳ non verificata (richiede SideStore configurato sull'iPad) |
| Prestazioni e memoria sull'iPad (benchmark + Time Profiler) | ✅ `docs/PERFORMANCE.md`: export RAW 80 MP portato da "terminata da iPadOS" a 4,0 s / 2,85 GB; thread principale 0,4 % |
| Touch e rotazione nel simulatore | ✅ orientamento orizzontale, trascinamento livello Motion, tratto di pittura; corretto un bug della barra laterale |
| Apple Pencil (pressione/inclinazione), touch e rotazione sull'iPad fisico | ⏳ da fare a mano: `docs/MANUAL_TEST_CHECKLIST.md` |

Legenda: ✅ completato e testato · 🟡 parziale · 🔵 implementato, non ancora verificato · ⬜ da realizzare · ⛔ bloccato.

## Per modulo

### Sviluppo foto (alternativa a Lightroom / Camera Raw)
- ✅ Decodifica RAW dai dati del sensore: DNG, CR2, CR3, NEF, ARW, RAF, RW2 (un campione ciascuno), verificata nel simulatore **e sull'iPad M5** (9 file in 4,4 s, incluso l'export JPEG 2048 px)
- ✅ Esposizione con effetto misurato, preset (bianco e nero verificato neutro), esportazione JPEG a piena risoluzione e ridimensionata, file corrotti segnalati senza crash
- 🔵 Interfaccia: luce, bilanciamento (preset e Kelvin/tinta), curva di tono a regioni, presenza, vividezza/saturazione, miscelatore (saturazione per 8 bande), nitidezza, riduzione rumore, vignettatura, grana, raddrizzamento, prospettiva, rotazione, riflessione, prima/dopo, istogramma, cronologia, undo/redo, zoom
- 🔵 Esportazione PNG, TIFF 16 bit, WebP, AVIF, DNG (dal motore; testato solo JPEG)
- ⬜ Ritaglio interattivo, curve a punti, maschere locali, catalogo multi-foto
- Originale copiato nel progetto, impostazioni non distruttive: ✅

### Fotoritocco (alternativa a Photoshop, nucleo)
- ✅ Compositing: metodo di fusione Moltiplica, opacità, filtro (inversione), esportazione PNG
- 🔵 Livelli immagine/pittura/riempimento, 15 metodi di fusione, 14 filtri non distruttivi, maschere da selezione e a pennello, inverti maschera, selezione rettangolare (riempi, cancella, ritaglia tela), pennello e gomma, export PNG/JPEG/TIFF
- ⬜ Selezioni libere/magiche, testo, livelli di regolazione, PSD

### Vettoriale (alternativa a Illustrator) e composizioni rapide (Express)
- ✅ SVG andata/ritorno, comandi SVG relativi, elementi non supportati segnalati, booleane (unione, intersezione), allineamento, PNG 4×, PDF
- 🔵 Strumenti rettangolo, ellisse, penna (nodi angolari e morbidi, chiusura), modifica nodi e maniglie, testo con font di sistema, gradienti, contorni, gruppi, livelli, ordine, duplicazione, 4 modelli rapidi originali
- ⬜ Maniglie di trasformazione sulla tela, archi SVG esatti

### Pittura (alternativa a Fresco)
- ✅ Tratto reale nei pixel, pressione che varia lo spessore, gomma, salvataggio e riapertura dei pixel, unione dei livelli
- 🔵 6 pennelli, pressione su dimensione/opacità, inclinazione (matita), tratti coalescenti della Pencil, modalità solo Pencil con dita per zoom/scorrimento, livelli, opacità, fusione in export, contagocce, import immagine, undo per pixel
- 🟡 Le modalità di fusione non sono mostrate dal vivo sulla tela (solo in export/unione) — documentato nell'interfaccia
- ⏳ Pressione/inclinazione reali: da verificare a mano con Apple Pencil sull'iPad

### Montaggio video (alternativa a Premiere Pro) — priorità
- ✅ Timeline multitraccia: aggiunta, divisione, ripple delete, rifilatura entro la sorgente, velocità, spostamento senza sovrapposizioni, import SRT, salvataggio/riapertura identici
- ✅ Esportazione H.264 di 2 clip + traccia audio con titolo e dissolvenza incrociata: durata, fotogrammi (rosso/blu) e mix della dissolvenza verificati sul file prodotto
- 🔵 Interfaccia timeline: righello con scorrimento, marcatori, tracce mute/nascoste/bloccate, trascinamento tra tracce, maniglie di rifilatura, aggancio, zoom (pinch e cursore), miniature e waveform, selezione multipla (pressione lunga), keyframe di trasformazione, opacità, colore (luminosità, contrasto, saturazione, temperatura), 6 effetti, fade audio/video, volume, titoli e sottotitoli, proxy 960×540, scorciatoie da tastiera
- 🔵 Esportazione HEVC 1080p/4K, ProRes 422 (mostrate solo se confermate da AVFoundation)
- ✅ Codifica/decodifica ProRes 422 verificata sull'iPad M5 (non nel simulatore)
- ⛔ ProRes RAW non supportato (vedi `docs/FORMATS.md`)
- ⬜ Trascinamento dal bin, slip/slide/roll, scopes, LUT

### Motion (alternativa ad After Effects, 2D) e Animazione 2D (alternativa ad Animate)
- ✅ Interpolazione keyframe (lineare, tieni, morbido), render di un livello animato verificato ai fotogrammi, esportazione video H.264 e sequenza PNG
- 🔵 Livelli forma/stella/testo/immagine/tinta unita, 8 proprietà animabili, 6 easing, maschere animate, testo a macchina da scrivere/per parole, sfocatura, trascinamento sulla tela, timeline con keyframe, GIF, HEVC/ProRes
- 🔵 Animazione a fotogrammi: tratti per fotogramma e livello, mantenimento, onion skin, riproduzione a FPS scelto, export video/GIF
- Nessun 3D: non dichiarato.

### Audio (alternativa ad Audition)
- ✅ Normalizzazione a -1 dBFS, fade, passa-basso (-20 dB a 10 kHz), shelf +6 dB, gate, mix a 2 tracce, pan, taglio ripple, conteggio del clipping, export/rilettura WAV16/WAV24/AIFF/CAF/M4A
- 🔵 Interfaccia multitraccia con waveform, selezione d'intervallo, dividi, taglia, silenzia, guadagno clip, reverse, EQ a 3 bande e filtri per traccia, automazione volume, muto/solo, meter, master, riproduzione (AVAudioEngine), registrazione dal microfono previo permesso
- 🟡 Il mix viene ricalcolato per intero a ogni modifica (adatto a progetti brevi; per progetti lunghi serve il render a blocchi — ROADMAP)
- ⬜ Riduzione del rumore spettrale (il gate non elimina il rumore e non è presentato come tale)

### Impaginazione (alternativa a InDesign, nucleo)
- ✅ PDF multipagina con testo ricercabile, rilevamento del testo in eccesso
- 🔵 Formati pagina, margini interno/esterno per pagine affiancate, griglia a colonne, cornici di testo multicolonna, stili di paragrafo, immagini, forme, numeri di pagina, aggancio alle colonne, ridimensionamento
- ⬜ Testo concatenato tra cornici, pagine mastro

### PDF (alternativa ad Acrobat, nucleo)
- ✅ Unione, riordino, rotazione, eliminazione, ricerca, evidenziazione, nota, inchiostro, salvataggio e rilettura delle annotazioni
- 🔵 Interfaccia: miniature con riordino, modalità lettura/evidenzia/nota/disegno, ricerca con contesto, pagina vuota, salva / esporta copia (l'originale importato resta intatto)
- ⛔ Modifica del contenuto delle pagine: non disponibile con PDFKit (ROADMAP: PDFium)

### Libreria asset (alternativa a Bridge)
- ✅ Importazione con deduplicazione per contenuto, tag, preferiti, ricerca, metadati, persistenza
- 🔵 Griglia con miniature, filtri per tipo/tag/preferiti, valutazioni, "Apri in" (sviluppo foto, fotoritocco, vettoriale da SVG, video, audio, PDF), condivisione, rimozione con conferma

### Media Encoder
- 🟡 Ogni editor esporta direttamente con preset verificati; manca una coda di esportazione in background unica (ROADMAP)

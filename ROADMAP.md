# Roadmap

Ordine di priorità: (1) foto/RAW, (2) video multitraccia, poi gli altri moduli. Ogni voce è un incremento che deve arrivare con test.

## Fase A–C (questa consegna)

Fatto: ricognizione, scelta motori, progetto Xcode, pacchetto modulare, formato di progetto versionato, una funzione reale (e testata in modo automatico dove indicato in `TEST_REPORT.md`) per ogni modulo, IPA non firmato verificato strutturalmente. Dettaglio per modulo in `IPADOS_PORT_STATUS.md`.

Non fatto in questa fase: installazione e test sul dispositivo fisico (manca la firma: vedi `INSTALL.md` §2).

## Fase D — funzioni professionali

### Foto / RAW (priorità 1)
1. Anteprima RAW zoomata a piena risoluzione con `PixelWindow` (render della sola porzione visibile).
2. Strumento di ritaglio interattivo con proporzioni (il motore supporta già `crop.geometry.rect` e `aspect`).
3. Curve a punti (RGB e canali), color grading a tre vie, calibrazione: già nello schema LightCraft, manca l'interfaccia.
4. Maschere locali di LightCraft (pennello, lineari, radiali) dall'interfaccia.
5. Esportazione in batch e catalogo multi-foto (riuso di `lightcraft-catalog`).
6. Valutare il renderer GPU di LightCraft (`lightcraft-gpu`, wgpu → Metal) per le anteprime interattive.
7. Copertura RAW: test con più varianti per marca (compressioni CR3 C-RAW, NEF HE/HE*, ARW compressi lossless, RAF compressi, X-Trans).

### Video (priorità 2)
1. Trascinamento dei media dal bin alla traccia (oggi pulsante "Aggiungi").
2. Selezione multipla con riquadro, spostamento di gruppo, slip/slide/roll edit.
3. Keyframe per volume e colore, curve di velocità (time remap).
4. LUT `.cube` come effetto colore; scopes (waveform, vettorscopio, istogramma) dal compositor.
5. Generazione automatica dei proxy all'importazione oltre una soglia di risoluzione.
6. Rendering in background con coda di esportazione (funzione "Media Encoder").
7. Verifica ProRes RAW con file reali e hardware: oggi **non supportato** (vedi `docs/FORMATS.md`).
8. FFmpeg (build LGPL senza componenti GPL, framework dinamico) per MKV/WebM.

### Fotoritocco
Selezioni a mano libera ed ellittiche, bacchetta magica, pennello correttivo (riuso di `lightcraft-inpaint`), livelli di regolazione, testo, trasformazione con maniglie, PSD in sola lettura (livelli raster) se una libreria con licenza adatta si dimostra affidabile.

### Vettoriale
Maniglie di trasformazione sulla tela, strumento forbici/unione nodi, testo su tracciato, pannelli simboli e stili, archi SVG esatti (oggi approssimati), `<use>`, gradienti con più fermate modificabili.

### Pittura
Render della tela in Metal con fusione dal vivo, pennelli con texture e dual brush, smoothing/stabilizzatore, selezioni e trasformazioni, riempimento, predizione dei tocchi Pencil (`predictedTouches`), hover di Pencil Pro.

### Motion / Animazione
Grafico delle curve temporali (editor di Bézier per l'easing), parentela tra livelli, precomposizioni, maschere con tracciato vettoriale, collegamento vivo con la timeline video, interpolazione dei tratti nell'animazione 2D, esportazione con canale alfa (ProRes 4444).

### Audio
Timeline audio sincronizzata con la timeline video, editor di waveform a campione, riduzione del rumore spettrale (FFT con profilo di rumore, Accelerate) con misure prima/dopo, compressore/limiter, LUFS, automazione disegnabile, plugin AUv3 ospitati.

### Impaginazione
Concatenamento del testo tra cornici e pagine, pagine mastro, stili di carattere, testo attorno agli oggetti, esportazione PDF/X con profili colore, gestione font importati (con verifica della licenza di incorporamento).

### PDF
Modifica del contenuto delle pagine (testo e immagini) tramite PDFium; moduli compilabili; firma; redazione (rimozione reale del contenuto, distinta dall'annotazione).

## Fase E — integrazione
Libreria asset usata dagli importatori di tutti gli editor ("scegli dalla libreria" accanto all'app File), riferimenti invece di copie quando il file è già nella libreria, "Apri in" per pittura/motion/impaginazione, ricerca globale.

## Fase F — distribuzione
Installazione verificata con Xcode sul dispositivo; IPA re-firmato e installato con SideStore secondo la sua documentazione; script di rinnovo documentati.

## Fase G — stabilizzazione
Profiling Instruments (Time Profiler, Allocations, Metal System Trace) sul dispositivo con file grandi (RAW da 100 MP, timeline 4K da 30 min, progetti di pittura 8K), test di interfaccia XCUITest per i flussi principali, test di file corrotti per ogni importatore.

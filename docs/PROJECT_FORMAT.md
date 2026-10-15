# Formato dei progetti Studio

Un progetto è una cartella `Nome.studio/` in `Documents/Projects/` (visibile nell'app File, "Sul mio iPad › Studio").

```
Nome.studio/
├── project.json
└── Media/            copie degli originali importati e dati binari (livelli PNG, maschere, proxy)
```

`project.json`:

```json
{
  "header": {
    "kind": "video",               // photo | raster | vector | paint | video | motion | animation | audio | layout
    "formatVersion": 1,
    "name": "Montaggio",
    "created": "2026-10-14T19:00:00Z",
    "modified": "2026-10-14T19:30:00Z",
    "appVersion": "0.1.0"
  },
  "payload": { … }                 // schema del modulo (struct Codable `…Project`)
}
```

## Regole

- `kind` usa i valori grezzi di `StudioModule`: non vanno mai rinominati.
- Chi modifica lo schema di un payload incrementa `formatVersion` del tipo e registra una migrazione con `ProjectMigrations.register(kind, from: n) { json in … }`, che riceve e restituisce l'albero JSON del payload.
- In lettura: versione minore → migrazioni in sequenza; versione maggiore → errore `newerFormat` (il file non viene toccato); JSON non valido → errore `corruptProject`.
- La scrittura è atomica (file temporaneo + sostituzione).
- I percorsi dei media sono relativi alla cartella del progetto, così il progetto resta portabile (copiato con l'app File o AirDrop).

## Contenuto dei payload (v1)

| Tipo | Contenuto principale | Binari in `Media/` |
|---|---|---|
| photo | `source` (percorso), `settings` (JSON `DevelopSettings` di LightCraft, intero) | originale RAW/immagine |
| raster | dimensioni, sfondo, livelli (immagine/riempimento/pittura) con fusione, opacità, trasformazione, filtri, maschera | immagini, `Raster/<id>.png`, `Raster/<id>-mask.png` |
| vector | tavola, livelli, forme (rettangolo, ellisse, tracciato Bézier, composto, testo), riempimenti/gradienti, contorni, gruppi | — |
| paint | dimensioni, sfondo, livelli (nome, opacità, fusione, visibilità), pennello corrente, campioni colore | `Layers/<id>.png` |
| video | tracce, clip (sorgente, velocità, volume, fade, transizione, trasformazione, keyframe, colore, effetto), titoli, marcatori, media, formato | originali, `Proxies/` |
| motion | composizione, livelli con proprietà animabili (keyframe + easing), maschere, animazioni di testo | immagini |
| animation | livelli, tratti per fotogramma (punti, spessori, colore), FPS, durata | — |
| audio | frequenza, tracce (clip, volume, pan, muto/solo, EQ, gate, automazione), media | originali, registrazioni |
| layout | formato pagina, margini, griglia, stili di paragrafo, pagine con cornici (testo/immagine/forma) | immagini |

## Collegamento Motion → Video

Il collegamento è per file: una composizione Motion si renderizza (H.264/HEVC/ProRes o sequenza PNG) e il file si importa nella timeline video come qualsiasi clip. Il formato JSON del progetto Motion è documentato qui sopra; un collegamento "vivo" (ri-render automatico) è in `ROADMAP.md`.

## Compatibilità con formati proprietari

PSD, AI, AEP, PRPROJ, INDD non sono letti né scritti. Vedi `docs/FORMATS.md`.

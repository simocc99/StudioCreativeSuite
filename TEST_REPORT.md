# Rapporto dei test

Data: 14/10/2026. Esecuzione: `Scripts/run-tests.sh` su simulatore **iPad Pro 13-inch (M5), iOS 27.0 (24A434)**, Mac Apple silicon, Xcode 27.0.

**Risultato: 31 test XCTest eseguiti, 0 falliti. 65/65 verifiche atteso/osservato superate.**

Non eseguito: test d'interfaccia automatici (XCUITest). La pressione e l'inclinazione di Apple Pencil, le prestazioni e la memoria reali richiedono il dispositivo.

## Esecuzione sull'iPad fisico

Data: 14/10/2026. Dispositivo: **iPad Pro 13" (M5), iPadOS 27.0**, collegato via USB-C. Esecuzione: `Scripts/run-device-tests.sh` (test ospitati dall'app firmata con il Personal Team; i 9 campioni RAW copiati in `Documents/TestRAW` dell'app).

**Risultato: 31 test XCTest eseguiti, 0 falliti; 65/65 verifiche atteso/osservato superate.** Differenza rispetto al simulatore: la codifica **ProRes 422 funziona** sul dispositivo.

App: installata e avviata con `devicectl`; il processo resta attivo, nessun crash report dell'app tra i log di sistema.

| Esito | Verifica (dispositivo) | Osservato |
|---|---|---|
| PASS | `audio.export.aiff` | 2.000 s, peak 0.94 |
| PASS | `audio.export.caf` | 2.000 s, peak 0.94 |
| PASS | `audio.export.m4a` | 2.000 s, peak 0.94 |
| PASS | `audio.export.wav16` | 2.000 s, peak 0.94 |
| PASS | `audio.export.wav24` | 2.000 s, peak 0.94 |
| PASS | `codec.h264.dispositivo` | encode=true decode=true fourcc=avc1 |
| PASS | `codec.hevc.dispositivo` | encode=true decode=true fourcc=hvc1 |
| PASS | `codec.prores.dispositivo` | encode=true decode=true fourcc=apcn |
| PASS | `photo.corrupt` | Errore del motore: unrecognised image format |
| PASS | `photo.export.jpg` | 600 |
| PASS | `photo.exposure` | 102.0 → 141.0 |
| PASS | `photo.preset.bw` | 90/90/90 |
| PASS | `photo.rendered.notRaw` | isRaw=false |
| PASS | `raw.ARW.Sony_ILCE-7M3_UNCOMPRESSED_14bit.ARW` | isRaw=true format=ARW export=2048x1365 mean=124,125,117 top=169 |
| PASS | `raw.CR2.Canon_EOS_205D_20Mark_20III_5G4A9394.CR2` | isRaw=true format=CR2 export=2048x1365 mean=141,109,76 top=124 |
| PASS | `raw.CR3.Canon_Canon_20EOS_20R10_IMG_6310.CR3` | isRaw=true format=CR3 export=2048x1365 mean=186,178,155 top=186 |
| PASS | `raw.DNG.Apple_iPhone_2012_20Pro_IMG_1361.DNG` | isRaw=true format=DNG export=1536x2048 mean=67,73,82 top=105 |
| PASS | `raw.DNG.Google_Pixel_204a_PXL_20201121_100251397.dng` | isRaw=true format=DNG export=2048x1534 mean=95,90,84 top=140 |
| PASS | `raw.DNG.Leica_M10_f5381888.dng` | isRaw=true format=DNG export=2048x1365 mean=111,99,85 top=120 |
| PASS | `raw.NEF.Nikon_D750_compressed_12_bit.NEF` | isRaw=true format=NEF export=2048x1369 mean=61,24,26 top=57 |
| PASS | `raw.RAF.Fujifilm_X-E3_DSCF2175.RAF` | isRaw=true format=RAF export=2048x1365 mean=158,122,119 top=169 |
| PASS | `raw.RW2.Panasonic_DC-G9_P1000475.RW2` | isRaw=true format=RW2 export=2048x1536 mean=65,91,57 top=77 |
| PASS | `video.export.dissolve` | 137,125 |
| PASS | `video.export.duration` | 3.50 s, 1 video, 1 audio |
| PASS | `video.export.frames` | 237,0,1 / 1,0,245 |
| PASS | `video.move.noOverlap` | 0.0-4.0 4.0-5.5 |
| PASS | `video.presets` | h264_1080,h264_720,hevc_1080,hevc_2160,prores422,audioM4A |
| PASS | `video.reopen` | identical |
| PASS | `video.ripple` | 1.5 |
| PASS | `video.split` | 1.5, src 1.5 |
| PASS | `video.timecode` | 00:01:00, 01:01:15 |
| PASS | `video.trim.bound` | dur 4.0 b@4.0 |

## Difetti trovati dai test e corretti in questa sessione

| Test | Problema osservato | Correzione |
|---|---|---|
| paint.stroke / paint.erase | alfa 0,11 al centro del tratto: la punta del pennello era una *image mask* Core Graphics, che usa 0 = dipingi (maschera invertita) | punta come immagine in scala di grigi usata come alfa |
| video.export.dissolve | impostare una transizione incrociata non sovrapponeva le clip: nessuna dissolvenza, durata errata | `setTransition` sposta la clip (e le successive) per creare la sovrapposizione |
| vector.svg.roundtrip | lo sfondo esportato come `<rect width="100%">` veniva perso all'importazione | il rettangolo a tutta tavola diventa lo sfondo del documento |
| video.timecode | il righello mostrava `00:01:29` invece di `00:01:00` (arrotondamento dei fotogrammi) | arrotondamento al fotogramma più vicino |
| audio.gate, vector.png, video.export.duration | aspettative errate nei test stessi (picco misurato durante il rilascio, area campionata sotto un'altra forma, tono di test più lungo dei video) | test corretti; codice invariato |

## Verifiche atteso / osservato

| Esito | Verifica | Atteso | Osservato |
|---|---|---|---|
| PASS | `assets.dedup` | 2 stored, 1 duplicate | 2 added, 1 duplicates |
| PASS | `audio.clipping` | clipped samples counted | 60400 |
| PASS | `audio.export.aiff` | readable 2 s file | 2.000 s, peak 0.94 |
| PASS | `audio.export.caf` | readable 2 s file | 2.000 s, peak 0.94 |
| PASS | `audio.export.m4a` | readable 2 s file | 2.000 s, peak 0.94 |
| PASS | `audio.export.wav16` | readable 2 s file | 2.000 s, peak 0.94 |
| PASS | `audio.export.wav24` | readable 2 s file | 2.000 s, peak 0.94 |
| PASS | `audio.fade` | silent at both ends | 0.0 … -0.0 |
| PASS | `audio.gate` | signal under threshold attenuated ~40 dB (−54 → ≈−94 dBFS) | -85.9 dBFS |
| PASS | `audio.lowpass` | 10 kHz attenuated > 20 dB by a 1 kHz low-pass | -42.7 dB |
| PASS | `audio.lowshelf` | ≈ +6 dB at 60 Hz | 5.62 dB |
| PASS | `audio.mix.length` | 2.00 s | 2.000 s |
| PASS | `audio.normalize` | -1.00 dBFS | -1.00 dBFS |
| PASS | `audio.pan` | left louder than right | L 0.4898988 R 0.2828427 |
| PASS | `codec.h264.simulatore` | encode + decode | encode=true decode=true fourcc=avc1 |
| PASS | `codec.hevc.simulatore` | osservazione | encode=true decode=true fourcc=hvc1 |
| PASS | `codec.prores.simulatore` | osservazione | encode=false decode=false fourcc=errore: Errore del motore: Cannot Encode |
| PASS | `json.int` | "version":1 | {"light":{"contrast":10,"exposure":0.5},"new":{"deep":{"key":"a"}},"version":1} |
| PASS | `json.path` | set/get nested keeps siblings | {"light":{"contrast":10,"exposure":0.5},"new":{"deep":{"key":"a"}},"version":1} |
| PASS | `layout.overflow` | overflow detected | true |
| PASS | `layout.pdf` | 3 pages, text searchable | 3 pages, 1 hits |
| PASS | `media.unique` | two distinct copies, original kept | Media/a.png, Media/a-2.png |
| PASS | `motion.export` | 1 s movie | 1.000 s |
| PASS | `motion.linear` | 50 at t=1 | 50.0 |
| PASS | `motion.render` | box moves left → right | 255 / 255 |
| PASS | `paint.erase` | erased to transparent | 0.0 |
| PASS | `paint.persist` | pixels survive save + reopen | Optional(StudioCore.RGBAColor(r: 0.0, g: 0.0, b: 1.0, a: 1.0)) |
| PASS | `paint.stroke` | blue along the stroke, transparent elsewhere | mid Optional(StudioCore.RGBAColor(r: 0.0, g: 0.0, b: 1.0, a: 1.0)) off Optional(StudioCore.RGBAColor(r: 0.0, g: 0.0, b: 0.0, a: 0.0)) |
| PASS | `pdf.reorder` | page 3 first | Pagina numero 3 parola3 3 |
| PASS | `pdf.save` | 5 pages, ≥3 annotations, rotation kept | 5 pages, 4 annotations, rot 90 |
| PASS | `photo.corrupt` | error, no crash | Errore del motore: unrecognised image format |
| PASS | `photo.export.jpg` | 600 px wide JPEG | 600 |
| PASS | `photo.exposure` | +1 EV brightens the render | 102.0 → 141.0 |
| PASS | `photo.preset.bw` | neutral grey | 90/90/90 |
| PASS | `photo.rendered.notRaw` | PNG opened as rendered image | isRaw=false |
| PASS | `project.migration` | count 42, v2 | count 42, v2 |
| PASS | `project.newer` | newerFormat error | newerFormat(kind: "layout", found: 99, supported: 2) |
| PASS | `project.roundtrip` | salvato | salvato |
| PASS | `raster.filter.invert` | inverted red = cyan | 0,255,255 |
| PASS | `raster.multiply` | red × white = red | 255,0,0 |
| PASS | `raster.opacity` | 50% red over white ≈ (255,128,128) | 255,128,128 |
| PASS | `raw.ARW.Sony_ILCE-7M3_UNCOMPRESSED_14bit.ARW` | raw decode from sensor data + export 2048 px | isRaw=true format=ARW export=2048x1365 mean=124,125,117 top=169 |
| PASS | `raw.CR2.Canon_EOS_205D_20Mark_20III_5G4A9394.CR2` | raw decode from sensor data + export 2048 px | isRaw=true format=CR2 export=2048x1365 mean=141,109,76 top=124 |
| PASS | `raw.CR3.Canon_Canon_20EOS_20R10_IMG_6310.CR3` | raw decode from sensor data + export 2048 px | isRaw=true format=CR3 export=2048x1365 mean=186,178,155 top=186 |
| PASS | `raw.DNG.Apple_iPhone_2012_20Pro_IMG_1361.DNG` | raw decode from sensor data + export 2048 px | isRaw=true format=DNG export=1536x2048 mean=67,73,82 top=105 |
| PASS | `raw.DNG.Google_Pixel_204a_PXL_20201121_100251397.dng` | raw decode from sensor data + export 2048 px | isRaw=true format=DNG export=2048x1534 mean=95,90,84 top=140 |
| PASS | `raw.DNG.Leica_M10_f5381888.dng` | raw decode from sensor data + export 2048 px | isRaw=true format=DNG export=2048x1365 mean=111,99,85 top=120 |
| PASS | `raw.NEF.Nikon_D750_compressed_12_bit.NEF` | raw decode from sensor data + export 2048 px | isRaw=true format=NEF export=2048x1369 mean=61,24,26 top=57 |
| PASS | `raw.RAF.Fujifilm_X-E3_DSCF2175.RAF` | raw decode from sensor data + export 2048 px | isRaw=true format=RAF export=2048x1365 mean=158,122,119 top=169 |
| PASS | `raw.RW2.Panasonic_DC-G9_P1000475.RW2` | raw decode from sensor data + export 2048 px | isRaw=true format=RW2 export=2048x1536 mean=65,91,57 top=77 |
| PASS | `undo.coalesce` | a drag is one undo step | 2 steps |
| PASS | `vector.boolean` | union 90×90, intersection 30×30 | (0.0, 0.0, 90.0, 90.0) / (30.0, 30.0, 30.0, 30.0) |
| PASS | `vector.png` | 800 px wide, red rect | 800 px, 255,0 |
| PASS | `vector.svg.relative` | rect 10,10 50×30; unknown element reported | (10.0, 10.0, 50.0, 30.0) ["foo": 1] |
| PASS | `vector.svg.roundtrip` | 3 shapes, white background, 200 wide | 3 shapes, 200.0 wide, skipped [:] |
| PASS | `video.export.dissolve` | red and blue mixed at 1.75 s | 144,125 |
| PASS | `video.export.duration` | 3.5 s with video + audio tracks | 3.50 s, 1 video, 1 audio |
| PASS | `video.export.frames` | red at 1.2 s, blue at 3.0 s | 232,34,0 / 25,35,245 |
| PASS | `video.move.noOverlap` | clips never overlap | 0.0-4.0 4.0-5.5 |
| PASS | `video.presets` | H.264 available | h264_1080,h264_720,hevc_1080,hevc_2160,prores422,audioM4A |
| PASS | `video.reopen` | identical project after reopen | identical |
| PASS | `video.ripple` | b moves to 1.5 s | 1.5 |
| PASS | `video.split` | 1.5 s + 2.5 s from 1.5 s | 1.5, src 1.5 |
| PASS | `video.timecode` | 00:01:00, 01:01:15 | 00:01:00, 01:01:15 |
| PASS | `video.trim.bound` | trim limited to source, no overlap | dur 4.0 b@4.0 |

## Verifica RAW sul Mac (stesso C ABI)

`cargo run --release --example rawcheck` sui 9 campioni: tutti `isRaw: true`, anteprima e JPEG 2048 px generati; tempi di apertura 115–434 ms ed esportazione 168 ms–1,3 s su Mac (i tempi sull'iPad non sono stati misurati). Controllo visivo di due esportazioni (RAF X-Trans, NEF): sviluppo corretto.

## Pacchetto

`Scripts/build-ipa.sh`: IPA Release non firmato di 14 MB; verificati `Payload/StudioCreativeSuite.app`, eseguibile arm64, `MinimumOSVersion` 18.0, `UIDeviceFamily` 2, `DTPlatformName` iphoneos, catalogo asset, simbolo `sc_photo_open` del motore. **Non** verificata l'installazione con SideStore.

## Verifica manuale nel simulatore

App avviata; Home, barra laterale, elenco progetti, creazione di un progetto video, apertura dell'editor, chiusura e riavvio con il progetto ritrovato tra i recenti. Corretti due difetti di layout in verticale emersi dagli screenshot (barra laterale sovrapposta all'editor; barre strumenti video/audio che andavano a capo).

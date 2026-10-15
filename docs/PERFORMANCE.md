# Prestazioni e memoria sull'iPad

Misurate il 14/10/2026 su **iPad Pro 13" (M5), iPadOS 27.0, 11.2 GB di RAM**, build Release, con `Scripts/run-benchmark.sh <UDID>` (modalità benchmark dell'app, avviata solo dall'argomento `-StudioBenchmark YES`). Memoria = `phys_footprint` del processo, campionata ogni 20 ms. Un'esecuzione; i tempi possono variare del 10–20 % tra esecuzioni.

## Problema trovato e corretto

Al primo benchmark l'app veniva **terminata da iPadOS (SIGKILL, nessun crash report)** durante l'export a piena risoluzione del RW2 Panasonic DC-G9 in modalità alta risoluzione (10368×7776, 80 MP):

| Fase | Limite memoria app | Esito |
|---|---|---|
| Limite standard | ≈ 5,1 GB (2,1 GB in uso + 3,0 GB disponibili) | terminata |
| + entitlement `com.apple.developer.kernel.increased-memory-limit` (accettato dal Personal Team) | ≈ 12,3 GB | terminata comunque: la pipeline di export di LightCraft richiede ≈ 150 byte/pixel (≈ 10,4 GB misurati sul Mac) |
| + **export a tasselli** (`sc_photo_render_tiled`, finestre `PixelWindow` 1024 px con margine 64) | ≈ 12,3 GB | ✅ JPEG 10368×7776 in 4,0 s, picco 2,85 GB |

Il render a tasselli è stato verificato identico al render a fotogramma intero (differenza media 0, massima 1 livello su 255, su DNG, RAF e RW2). L'app sceglie automaticamente: pipeline completa di LightCraft quando la stima sta nell'80 % della memoria disponibile (`os_proc_available_memory`), altrimenti tasselli + codifica ImageIO con i metadati EXIF/TIFF/GPS dell'originale (JPEG/PNG). Per TIFF 16 bit, WebP, AVIF e DNG troppo grandi l'app mostra un errore con il lato lungo massimo esportabile invece di farsi terminare.

## Risultati

| Misura | ms | picco MB | Note |
|---|---:|---:|---|
| raw.open Apple_iPhone_2012_20Pro_IMG_1361.DNG | 210 | 641 | DNG anteprima 1800×2400 |
| raw.render10 Apple_iPhone_2012_20Pro_IMG_1361.DNG | 258 | 798 | 10 render draft |
| raw.exportFullAdaptive Apple_iPhone_2012_20Pro_IMG_1361.DNG | 359 | 2383 | JPEG 3024×4032 pipeline completa |
| raw.exportFullTiled Apple_iPhone_2012_20Pro_IMG_1361.DNG | 339 | 2248 | render 3024×4032 |
| raw.open Canon_Canon_20EOS_20R10_IMG_6310.CR3 | 289 | 824 | CR3 anteprima 2400×1600 |
| raw.render10 Canon_Canon_20EOS_20R10_IMG_6310.CR3 | 423 | 834 | 10 render draft |
| raw.exportFullAdaptive Canon_Canon_20EOS_20R10_IMG_6310.CR3 | 1018 | 3947 | JPEG 6000×4000 pipeline completa |
| raw.exportFullTiled Canon_Canon_20EOS_20R10_IMG_6310.CR3 | 1094 | 1876 | render 6000×4000 |
| raw.open Canon_EOS_205D_20Mark_20III_5G4A9394.CR2 | 263 | 1058 | CR2 anteprima 2400×1600 |
| raw.render10 Canon_EOS_205D_20Mark_20III_5G4A9394.CR2 | 442 | 1172 | 10 render draft |
| raw.exportFullAdaptive Canon_EOS_205D_20Mark_20III_5G4A9394.CR2 | 825 | 3709 | JPEG 5760×3840 pipeline completa |
| raw.exportFullTiled Canon_EOS_205D_20Mark_20III_5G4A9394.CR2 | 969 | 3696 | render 5760×3840 |
| raw.open Fujifilm_X-E3_DSCF2175.RAF | 86 | 835 | RAF anteprima 2000×1333 |
| raw.render10 Fujifilm_X-E3_DSCF2175.RAF | 449 | 954 | 10 render draft |
| raw.exportFullAdaptive Fujifilm_X-E3_DSCF2175.RAF | 635 | 4146 | JPEG 6000×4000 pipeline completa |
| raw.exportFullTiled Fujifilm_X-E3_DSCF2175.RAF | 879 | 1622 | render 6000×4000 |
| raw.open Google_Pixel_204a_PXL_20201121_100251397.dng | 367 | 897 | DNG anteprima 2400×1798 |
| raw.render10 Google_Pixel_204a_PXL_20201121_100251397.dng | 474 | 1099 | 10 render draft |
| raw.exportFullAdaptive Google_Pixel_204a_PXL_20201121_100251397.dng | 496 | 2282 | JPEG 4016×3008 pipeline completa |
| raw.exportFullTiled Google_Pixel_204a_PXL_20201121_100251397.dng | 594 | 1317 | render 4016×3008 |
| raw.open Leica_M10_f5381888.dng | 260 | 824 | DNG anteprima 2400×1600 |
| raw.render10 Leica_M10_f5381888.dng | 398 | 957 | 10 render draft |
| raw.exportFullAdaptive Leica_M10_f5381888.dng | 853 | 3876 | JPEG 5976×3984 pipeline completa |
| raw.exportFullTiled Leica_M10_f5381888.dng | 985 | 3858 | render 5976×3984 |
| raw.open Nikon_D750_compressed_12_bit.NEF | 208 | 783 | NEF anteprima 2400×1604 |
| raw.render10 Nikon_D750_compressed_12_bit.NEF | 448 | 944 | 10 render draft |
| raw.exportFullAdaptive Nikon_D750_compressed_12_bit.NEF | 796 | 3992 | JPEG 6032×4032 pipeline completa |
| raw.exportFullTiled Nikon_D750_compressed_12_bit.NEF | 956 | 1652 | render 6032×4032 |
| raw.open Panasonic_DC-G9_P1000475.RW2 | 277 | 977 | RW2 anteprima 2400×1800 |
| raw.render10 Panasonic_DC-G9_P1000475.RW2 | 499 | 1105 | 10 render draft |
| raw.exportFullAdaptive Panasonic_DC-G9_P1000475.RW2 | 3994 | 2850 | JPEG 10368×7776 a tasselli |
| raw.exportFullTiled Panasonic_DC-G9_P1000475.RW2 | 3630 | 2279 | render 10368×7776 |
| raw.open Sony_ILCE-7M3_UNCOMPRESSED_14bit.ARW | 160 | 1756 | ARW anteprima 2400×1600 |
| raw.render10 Sony_ILCE-7M3_UNCOMPRESSED_14bit.ARW | 468 | 1889 | 10 render draft |
| raw.exportFullAdaptive Sony_ILCE-7M3_UNCOMPRESSED_14bit.ARW | 886 | 3847 | JPEG 6000×4000 pipeline completa |
| raw.exportFullTiled Sony_ILCE-7M3_UNCOMPRESSED_14bit.ARW | 992 | 3943 | render 6000×4000 |
| video.makeClips | 2298 | 948 | 2 × 10 s 1080p H.264 (AVAssetWriter) |
| video.exportHEVC1080 | 2254 | 369 | HEVC 1080p (.mov), 19.0 s |
| audio.mix4x60s | 243 | 160 | 60 s stereo, picco 1.8 dBFS |
| raster.compose6000x4000 | 29 | 161 | 6000×4000 |
| paint.stroke2000 | 81 | 181 | 2000 campioni, pennello 60 px |

Lettura dei dati:
- **Apertura RAW** (decodifica + anteprima 2400 px): 85–380 ms. **10 render interattivi** (bozza, viewport 2732×2048): 260–520 ms, cioè 26–52 ms a render.
- **Export a piena risoluzione 24 MP**: 0,6–1,1 s; picco 3,7–4,1 GB con la pipeline completa, 1,6–1,9 GB a tasselli dove la stima lo richiede.
- La memoria residua tra un file e l'altro resta a 0,8–1,9 GB (cache del motore e dell'allocatore): da ridurre (ROADMAP).
- **Video**: export HEVC 1080p di 19 s con dissolvenza, titolo e keyframe in 2,3 s (≈ 8× tempo reale), picco 369 MB.
- **Audio**: mix di 4 tracce × 60 s con EQ, gate e automazione in 0,24 s. Il picco del mix risulta +1,8 dBFS: è il clipping atteso dalla somma di 4 tracce in questo test, e l'app lo segnala.
- Raster 6000×4000 e tratto di pittura da 2000 campioni: 28 ms e 80 ms (carichi leggeri).

## Instruments (Time Profiler) sull'iPad

Traccia `build/traces/time.trace` (75 s durante il benchmark, simbolizzata con il dSYM Release):

- 176 s di CPU campionata in ≈ 75 s reali: il lavoro è distribuito su più core (rayon nel motore RAW).
- **Thread principale: 0,4 %** dei campioni. Le elaborazioni pesanti non bloccano l'interfaccia.
- Il binario dell'app (motore Rust incluso) fa l'82 % del tempo. Le funzioni più costose: operazioni per pixel di `lightcraft_raster::par_rows` (≈ 17 %), `cbrtf` (5,3 %, conversioni colore), `memmove` (5,0 %, copie di buffer), decodifica `load_vec` (2,8 %), codifica JPEG parallela (0,7 %).
- Possibili ottimizzazioni (ROADMAP): ridurre le copie di buffer nel bridge (`memmove`), riusare la sorgente decodificata tra render ed export, valutare il renderer GPU di LightCraft.

Allocations/Leaks non sono stati registrati: i picchi sono misurati dall'app stessa (tabella sopra).

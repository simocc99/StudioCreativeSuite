# Avvisi di terze parti

Questo file elenca il software di terzi incluso nella build dell'app. È generato dall'albero reale delle dipendenze
(`cargo metadata --filter-platform aarch64-apple-ios` sul crate `Engines/studio-photo-engine`, 14/10/2026) più i framework di sistema.

## Riepilogo degli obblighi

- **Nessuna dipendenza GPL, LGPL, AGPL o MPL** è inclusa. Tutte le licenze sono permissive.
- MIT / BSD / ISC / Zlib / IJG / Unicode-3.0: conservare l'avviso di copyright e il testo della licenza nella documentazione distribuita con il binario (questo file + `licenses/`).
- Apache-2.0: conservare gli avvisi e i file `NOTICE` dei progetti che ne hanno uno (LightCraft: vedi sotto); indicare le modifiche apportate.
- CDLA-Permissive-2.0 (`webpki-roots`, elenco dei certificati radice Mozilla): conservare il testo della licenza. Il bridge non usa la rete.
- I marchi ArtCraft/LightCraft (cartella `docs/brand/` del progetto originale) **non** sono coperti dalla licenza del codice e non sono usati.

## Componenti principali

| Componente | Versione | Origine | Licenza | Modifiche | Note |
|---|---|---|---|---|---|
| LightCraft (crate `lightcraft-*`) | 0.8.0, commit `3b4279fc2485bb51847c0071a1b3c514aa0f98f4` | https://github.com/storytold/lightcraft | MIT OR Apache-2.0 | nessuna (usato come dipendenza git fissata) | `NOTICE`: Copyright (c) 2026 ArtCraft Team and the LightCraft contributors. Il crate `lightcraft-raw` contiene matrici colore derivate da rawtoaces-data (Academy Software Foundation, Apache-2.0). Font Inter e foto dimostrative del progetto non sono incluse nel bridge. |
| studio-photo-engine | 0.1.0 | questo repository | MIT OR Apache-2.0 | codice originale | C ABI tra Swift e LightCraft |
| Framework Apple (SwiftUI, UIKit, AVFoundation, Core Image, Core Graphics, ImageIO, PDFKit, Accelerate, CryptoKit, QuickLookThumbnailing) | SDK iOS 27.0 | Apple | Licenza dell'SDK Apple | — | collegati dinamicamente dal sistema |

Campioni RAW di test: scaricati da https://raw.pixls.us (CC0 1.0), usati solo nei test, non inclusi nel repository né nell'app.

## Crate Rust inclusi nel motore fotografico (target aarch64-apple-ios)

| Crate | Versione | Licenza | Repository |
|---|---|---|---|
| ab_glyph | 0.2.32 | Apache-2.0 | https://github.com/alexheretic/ab-glyph |
| ab_glyph_rasterizer | 0.1.10 | Apache-2.0 | https://github.com/alexheretic/ab-glyph |
| adler2 | 2.0.1 | 0BSD OR MIT OR Apache-2.0 | https://github.com/oyvindln/adler2 |
| aead | 0.5.2 | MIT OR Apache-2.0 | https://github.com/RustCrypto/traits |
| aes | 0.8.4 | MIT OR Apache-2.0 | https://github.com/RustCrypto/block-ciphers |
| aes-gcm | 0.10.3 | Apache-2.0 OR MIT | https://github.com/RustCrypto/AEADs |
| aligned | 0.4.3 | MIT OR Apache-2.0 | https://github.com/rust-embedded-community/aligned |
| aligned-vec | 0.6.4 | MIT | https://github.com/sarah-ek/aligned-vec/ |
| alloc-no-stdlib | 2.0.4 | BSD-3-Clause | https://github.com/dropbox/rust-alloc-no-stdlib |
| alloc-stdlib | 0.2.4 | BSD-3-Clause | https://github.com/dropbox/rust-alloc-no-stdlib |
| allocator-api2 | 0.2.21 | MIT OR Apache-2.0 | https://github.com/zakarumych/allocator-api2 |
| anyhow | 1.0.104 | MIT OR Apache-2.0 | https://github.com/dtolnay/anyhow |
| arg_enum_proc_macro | 0.3.4 | MIT | https://github.com/lu-zero/arg_enum_proc_macro |
| arrayvec | 0.7.8 | MIT OR Apache-2.0 | https://github.com/bluss/arrayvec |
| as-slice | 0.2.1 | MIT OR Apache-2.0 | https://github.com/japaric/as-slice |
| ash | 0.38.0+1.3.281 | MIT OR Apache-2.0 | https://github.com/ash-rs/ash |
| autocfg | 1.5.1 | Apache-2.0 OR MIT | https://github.com/cuviper/autocfg |
| av-scenechange | 0.14.1 | MIT | https://github.com/rust-av/av-scenechange |
| av1-grain | 0.2.5 | BSD-2-Clause | https://github.com/rust-av/av1-grain |
| avif-serialize | 0.8.9 | BSD-3-Clause | https://github.com/kornelski/avif-serialize |
| base16ct | 0.2.0 | Apache-2.0 OR MIT | https://github.com/RustCrypto/formats/tree/master/base16ct |
| base64ct | 1.8.3 | Apache-2.0 OR MIT | https://github.com/RustCrypto/formats |
| bit-set | 0.10.0 | Apache-2.0 OR MIT | https://github.com/contain-rs/bit-set |
| bit-vec | 0.9.1 | Apache-2.0 OR MIT | https://github.com/contain-rs/bit-vec |
| bitflags | 2.13.2 | MIT OR Apache-2.0 | https://github.com/bitflags/bitflags |
| bitstream-io | 4.10.0 | MIT/Apache-2.0 | https://github.com/tuffy/bitstream-io |
| block-buffer | 0.10.4 | MIT OR Apache-2.0 | https://github.com/RustCrypto/utils |
| block2 | 0.6.2 | MIT | https://github.com/madsmtm/objc2 |
| brotli-decompressor | 5.0.3 | BSD-3-Clause/MIT | https://github.com/dropbox/rust-brotli-decompressor |
| built | 0.8.1 | MIT | https://github.com/lukaslueg/built |
| bumpalo | 3.20.3 | MIT OR Apache-2.0 | https://github.com/fitzgen/bumpalo |
| bytemuck | 1.25.2 | Zlib OR Apache-2.0 OR MIT | https://github.com/Lokathor/bytemuck |
| bytemuck_derive | 1.12.1 | Zlib OR Apache-2.0 OR MIT | https://github.com/Lokathor/bytemuck |
| byteorder-lite | 0.1.0 | Unlicense OR MIT | https://github.com/image-rs/byteorder-lite |
| cc | 1.8.0 | MIT OR Apache-2.0 | https://github.com/rust-lang/cc-rs |
| cfg-if | 1.0.5 | MIT OR Apache-2.0 | https://github.com/rust-lang/cfg-if |
| cfg_aliases | 0.2.2 | MIT | https://github.com/katharostech/cfg_aliases |
| chacha20 | 0.9.1 | Apache-2.0 OR MIT | https://github.com/RustCrypto/stream-ciphers |
| chacha20poly1305 | 0.10.1 | Apache-2.0 OR MIT | https://github.com/RustCrypto/AEADs/tree/master/chacha20poly1305 |
| cipher | 0.4.4 | MIT OR Apache-2.0 | https://github.com/RustCrypto/traits |
| codespan-reporting | 0.13.1 | Apache-2.0 | https://github.com/brendanzab/codespan |
| color_quant | 1.1.0 | MIT | https://github.com/image-rs/color_quant.git |
| const-oid | 0.9.6 | Apache-2.0 OR MIT | https://github.com/RustCrypto/formats/tree/master/const-oid |
| cpufeatures | 0.2.17 | MIT OR Apache-2.0 | https://github.com/RustCrypto/utils |
| crc32fast | 1.5.2 | MIT OR Apache-2.0 | https://github.com/srijs/rust-crc32fast |
| crossbeam-deque | 0.8.8 | MIT OR Apache-2.0 | https://github.com/crossbeam-rs/crossbeam |
| crossbeam-epoch | 0.9.21 | MIT OR Apache-2.0 | https://github.com/crossbeam-rs/crossbeam |
| crossbeam-utils | 0.8.23 | MIT OR Apache-2.0 | https://github.com/crossbeam-rs/crossbeam |
| crypto-bigint | 0.5.5 | Apache-2.0 OR MIT | https://github.com/RustCrypto/crypto-bigint |
| crypto-common | 0.1.7 | MIT OR Apache-2.0 | https://github.com/RustCrypto/traits |
| ctr | 0.9.2 | MIT OR Apache-2.0 | https://github.com/RustCrypto/block-modes |
| curve25519-dalek | 4.1.3 | BSD-3-Clause | https://github.com/dalek-cryptography/curve25519-dalek/tree/main/curve25519-dalek |
| der | 0.7.10 | Apache-2.0 OR MIT | https://github.com/RustCrypto/formats/tree/master/der |
| digest | 0.10.7 | MIT OR Apache-2.0 | https://github.com/RustCrypto/traits |
| dispatch2 | 0.3.1 | Zlib OR Apache-2.0 OR MIT | https://github.com/madsmtm/objc2 |
| document-features | 0.2.12 | MIT OR Apache-2.0 | https://github.com/slint-ui/document-features |
| ecdsa | 0.16.9 | Apache-2.0 OR MIT | https://github.com/RustCrypto/signatures/tree/master/ecdsa |
| ed25519 | 2.2.3 | Apache-2.0 OR MIT | https://github.com/RustCrypto/signatures/tree/master/ed25519 |
| ed25519-dalek | 2.2.0 | BSD-3-Clause | https://github.com/dalek-cryptography/curve25519-dalek/tree/main/ed25519-dalek |
| either | 1.19.0 | MIT OR Apache-2.0 | https://github.com/rayon-rs/either |
| elliptic-curve | 0.13.8 | Apache-2.0 OR MIT | https://github.com/RustCrypto/traits/tree/master/elliptic-curve |
| equator | 0.4.2 | MIT | https://github.com/sarah-ek/equator/ |
| equator-macro | 0.4.2 | MIT | https://github.com/sarah-ek/equator/ |
| equivalent | 1.0.3 | Apache-2.0 OR MIT | https://github.com/indexmap-rs/equivalent |
| fax | 0.2.7 | MIT | https://github.com/pdf-rs/fax |
| fdeflate | 0.3.7 | MIT OR Apache-2.0 | https://github.com/image-rs/fdeflate |
| ff | 0.13.1 | MIT/Apache-2.0 | https://github.com/zkcrypto/ff |
| find-msvc-tools | 0.1.14 | MIT OR Apache-2.0 | https://github.com/rust-lang/cc-rs |
| flate2 | 1.1.10 | MIT OR Apache-2.0 | https://github.com/rust-lang/flate2-rs |
| foldhash | 0.2.0 | Zlib | https://github.com/orlp/foldhash |
| font-types | 0.12.6 | MIT OR Apache-2.0 | https://github.com/googlefonts/fontations |
| generic-array | 0.14.7 | MIT | https://github.com/fizyk20/generic-array.git |
| getrandom | 0.2.17 | MIT OR Apache-2.0 | https://github.com/rust-random/getrandom |
| ghash | 0.5.1 | Apache-2.0 OR MIT | https://github.com/RustCrypto/universal-hashes |
| gif | 0.14.2 | MIT OR Apache-2.0 | https://github.com/image-rs/image-gif |
| gpu-allocator | 0.28.0 | MIT OR Apache-2.0 | https://github.com/Traverse-Research/gpu-allocator |
| group | 0.13.0 | MIT/Apache-2.0 | https://github.com/zkcrypto/group |
| half | 2.7.1 | MIT OR Apache-2.0 | https://github.com/VoidStarKat/half-rs |
| harfrust | 0.12.0 | MIT | https://github.com/harfbuzz/harfrust |
| hashbrown | 0.16.1 | MIT OR Apache-2.0 | https://github.com/rust-lang/hashbrown |
| hashbrown | 0.17.1 | MIT OR Apache-2.0 | https://github.com/rust-lang/hashbrown |
| hkdf | 0.12.4 | MIT OR Apache-2.0 | https://github.com/RustCrypto/KDFs/ |
| hmac | 0.12.1 | MIT OR Apache-2.0 | https://github.com/RustCrypto/MACs |
| image | 0.25.10 | MIT OR Apache-2.0 | https://github.com/image-rs/image |
| image-webp | 0.2.4 | MIT OR Apache-2.0 | https://github.com/image-rs/image-webp |
| imgref | 1.12.3 | CC0-1.0 OR Apache-2.0 | https://github.com/kornelski/imgref |
| indexmap | 2.14.2 | Apache-2.0 OR MIT | https://github.com/indexmap-rs/indexmap |
| inout | 0.1.4 | MIT OR Apache-2.0 | https://github.com/RustCrypto/utils |
| itertools | 0.14.0 | MIT OR Apache-2.0 | https://github.com/rust-itertools/itertools |
| itoa | 1.0.18 | MIT OR Apache-2.0 | https://github.com/dtolnay/itoa |
| jixel | 0.3.4 | BSD-3-Clause OR Apache-2.0 | https://github.com/awxkee/jixel |
| jobserver | 0.1.35 | MIT OR Apache-2.0 | https://github.com/rust-lang/jobserver-rs |
| jpeg-decoder | 0.3.2 | MIT OR Apache-2.0 | https://github.com/image-rs/jpeg-decoder |
| jpeg-encoder | 0.7.1 | (MIT OR Apache-2.0) AND IJG | https://github.com/vstroebel/jpeg-encoder |
| jxl-bitstream | 1.1.0 | MIT OR Apache-2.0 | https://github.com/tirr-c/jxl-oxide.git |
| jxl-coding | 1.0.1 | MIT OR Apache-2.0 | https://github.com/tirr-c/jxl-oxide.git |
| jxl-color | 0.11.0 | MIT OR Apache-2.0 | https://github.com/tirr-c/jxl-oxide.git |
| jxl-frame | 0.13.3 | MIT OR Apache-2.0 | https://github.com/tirr-c/jxl-oxide.git |
| jxl-grid | 0.6.2 | MIT OR Apache-2.0 | https://github.com/tirr-c/jxl-oxide.git |
| jxl-image | 0.13.0 | MIT OR Apache-2.0 | https://github.com/tirr-c/jxl-oxide.git |
| jxl-jbr | 0.2.1 | MIT OR Apache-2.0 | https://github.com/tirr-c/jxl-oxide.git |
| jxl-modular | 0.11.3 | MIT OR Apache-2.0 | https://github.com/tirr-c/jxl-oxide.git |
| jxl-oxide | 0.12.6 | MIT OR Apache-2.0 | https://github.com/tirr-c/jxl-oxide.git |
| jxl-oxide-common | 1.0.0 | MIT OR Apache-2.0 | https://github.com/tirr-c/jxl-oxide.git |
| jxl-render | 0.12.4 | MIT OR Apache-2.0 | https://github.com/tirr-c/jxl-oxide.git |
| jxl-threadpool | 1.0.0 | MIT OR Apache-2.0 | https://github.com/tirr-c/jxl-oxide.git |
| jxl-vardct | 0.11.1 | MIT OR Apache-2.0 | https://github.com/tirr-c/jxl-oxide.git |
| lazy_static | 1.5.1 | MIT OR Apache-2.0 | https://github.com/rust-lang-nursery/lazy-static.rs |
| libc | 0.2.190 | MIT OR Apache-2.0 | https://github.com/rust-lang/libc |
| libloading | 0.8.9 | ISC | https://github.com/nagisa/rust_libloading/ |
| libm | 0.2.16 | MIT | https://github.com/rust-lang/compiler-builtins |
| lightcraft-catalog | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-codecs | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-color | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-denoise-core | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-develop | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-engine | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-faces | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-fetch | 0.8.0 | Apache-2.0 |  |
| lightcraft-geocode | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-geom | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-gpu | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-inpaint | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-lensdb | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-merge | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-meta | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-pipeline | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-preview | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-raster | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-raw | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-scenes | 0.8.0 | MIT OR Apache-2.0 |  |
| lightcraft-tiff | 0.8.0 | MIT OR Apache-2.0 |  |
| litrs | 1.0.1 | MIT OR Apache-2.0 | https://github.com/LukasKalbertodt/litrs |
| lock_api | 0.4.14 | MIT OR Apache-2.0 | https://github.com/Amanieu/parking_lot |
| log | 0.4.34 | MIT OR Apache-2.0 | https://github.com/rust-lang/log |
| loop9 | 0.1.5 | MIT | https://gitlab.com/kornelski/loop9.git |
| matrixmultiply | 0.3.11 | MIT/Apache-2.0 | https://github.com/bluss/matrixmultiply/ |
| maybe-rayon | 0.1.1 | MIT | https://github.com/shssoichiro/maybe-rayon |
| memchr | 2.8.3 | Unlicense OR MIT | https://github.com/BurntSushi/memchr |
| miniz_oxide | 0.8.9 | MIT OR Zlib OR Apache-2.0 | https://github.com/Frommi/miniz_oxide/tree/master/miniz_oxide |
| miniz_oxide | 0.9.1 | MIT OR Zlib OR Apache-2.0 | https://github.com/Frommi/miniz_oxide/tree/master/miniz_oxide |
| moxcms | 0.8.1 | BSD-3-Clause OR Apache-2.0 | https://github.com/awxkee/moxcms.git |
| moxcms | 0.9.1 | BSD-3-Clause OR Apache-2.0 | https://github.com/awxkee/moxcms.git |
| naga | 30.0.1 | MIT OR Apache-2.0 | https://github.com/gfx-rs/wgpu |
| naga-types | 30.0.1 | MIT OR Apache-2.0 | https://github.com/gfx-rs/wgpu |
| ndarray | 0.17.2 | MIT OR Apache-2.0 | https://github.com/rust-ndarray/ndarray |
| new_debug_unreachable | 1.0.6 | MIT | https://github.com/mbrubeck/rust-debug-unreachable |
| no_std_io2 | 0.9.4 | Apache-2.0 OR MIT | https://github.com/wcampbell0x2a/no-std-io2 |
| nom | 8.0.0 | MIT | https://github.com/rust-bakery/nom |
| noop_proc_macro | 0.3.0 | MIT | https://github.com/lu-zero/noop_proc_macro |
| num-bigint | 0.4.8 | MIT OR Apache-2.0 | https://github.com/rust-num/num-bigint |
| num-bigint-dig | 0.8.6 | MIT/Apache-2.0 | https://github.com/dignifiedquire/num-bigint |
| num-complex | 0.4.6 | MIT OR Apache-2.0 | https://github.com/rust-num/num-complex |
| num-derive | 0.4.2 | MIT OR Apache-2.0 | https://github.com/rust-num/num-derive |
| num-integer | 0.1.47 | MIT OR Apache-2.0 | https://github.com/rust-num/num-integer |
| num-iter | 0.1.46 | MIT OR Apache-2.0 | https://github.com/rust-num/num-iter |
| num-rational | 0.4.2 | MIT OR Apache-2.0 | https://github.com/rust-num/num-rational |
| num-traits | 0.2.19 | MIT OR Apache-2.0 | https://github.com/rust-num/num-traits |
| objc2 | 0.6.5 | MIT | https://github.com/madsmtm/objc2 |
| objc2-core-foundation | 0.3.2 | Zlib OR Apache-2.0 OR MIT | https://github.com/madsmtm/objc2 |
| objc2-core-graphics | 0.3.2 | Zlib OR Apache-2.0 OR MIT | https://github.com/madsmtm/objc2 |
| objc2-encode | 4.1.0 | MIT | https://github.com/madsmtm/objc2 |
| objc2-foundation | 0.3.2 | MIT | https://github.com/madsmtm/objc2 |
| objc2-io-surface | 0.3.2 | Zlib OR Apache-2.0 OR MIT | https://github.com/madsmtm/objc2 |
| objc2-metal | 0.3.2 | Zlib OR Apache-2.0 OR MIT | https://github.com/madsmtm/objc2 |
| objc2-quartz-core | 0.3.2 | Zlib OR Apache-2.0 OR MIT | https://github.com/madsmtm/objc2 |
| once_cell | 1.21.4 | MIT OR Apache-2.0 | https://github.com/matklad/once_cell |
| opaque-debug | 0.3.1 | MIT OR Apache-2.0 | https://github.com/RustCrypto/utils |
| ordered-float | 5.5.0 | MIT | https://github.com/reem/rust-ordered-float |
| owned_ttf_parser | 0.25.1 | Apache-2.0 | https://github.com/alexheretic/owned-ttf-parser |
| p256 | 0.13.2 | Apache-2.0 OR MIT | https://github.com/RustCrypto/elliptic-curves/tree/master/p256 |
| p384 | 0.13.1 | Apache-2.0 OR MIT | https://github.com/RustCrypto/elliptic-curves/tree/master/p384 |
| parking_lot | 0.12.5 | MIT OR Apache-2.0 | https://github.com/Amanieu/parking_lot |
| parking_lot_core | 0.9.12 | MIT OR Apache-2.0 | https://github.com/Amanieu/parking_lot |
| paste | 1.0.15 | MIT OR Apache-2.0 | https://github.com/dtolnay/paste |
| pastey | 0.1.1 | MIT OR Apache-2.0 | https://github.com/as1100k/pastey |
| pem-rfc7468 | 0.7.0 | Apache-2.0 OR MIT | https://github.com/RustCrypto/formats/tree/master/pem-rfc7468 |
| pin-project-lite | 0.2.17 | Apache-2.0 OR MIT | https://github.com/taiki-e/pin-project-lite |
| pkcs1 | 0.7.5 | Apache-2.0 OR MIT | https://github.com/RustCrypto/formats/tree/master/pkcs1 |
| pkcs5 | 0.7.1 | Apache-2.0 OR MIT | https://github.com/RustCrypto/formats/tree/master/pkcs5 |
| pkcs8 | 0.10.2 | Apache-2.0 OR MIT | https://github.com/RustCrypto/formats/tree/master/pkcs8 |
| png | 0.18.1 | MIT OR Apache-2.0 | https://github.com/image-rs/image-png |
| pollster | 1.0.1 | Apache-2.0/MIT | https://github.com/zesterer/pollster |
| poly1305 | 0.8.0 | Apache-2.0 OR MIT | https://github.com/RustCrypto/universal-hashes |
| polyval | 0.6.2 | Apache-2.0 OR MIT | https://github.com/RustCrypto/universal-hashes |
| ppv-lite86 | 0.2.21 | MIT OR Apache-2.0 | https://github.com/cryptocorrosion/cryptocorrosion |
| presser | 0.3.1 | MIT OR Apache-2.0 | https://github.com/EmbarkStudios/presser |
| primeorder | 0.13.6 | Apache-2.0 OR MIT | https://github.com/RustCrypto/elliptic-curves/tree/master/primeorder |
| proc-macro2 | 1.0.107 | MIT OR Apache-2.0 | https://github.com/dtolnay/proc-macro2 |
| profiling | 1.0.18 | MIT OR Apache-2.0 | https://github.com/aclysma/profiling |
| profiling-procmacros | 1.0.18 | MIT OR Apache-2.0 | https://github.com/aclysma/profiling |
| pxfm | 0.1.30 | BSD-3-Clause OR Apache-2.0 | https://github.com/awxkee/pxfm |
| quick-error | 2.0.1 | MIT/Apache-2.0 | http://github.com/tailhook/quick-error |
| quick-xml | 0.38.4 | MIT | https://github.com/tafia/quick-xml |
| quote | 1.0.47 | MIT OR Apache-2.0 | https://github.com/dtolnay/quote |
| rand | 0.8.8 | MIT OR Apache-2.0 | https://github.com/rust-random/rand |
| rand_chacha | 0.3.1 | MIT OR Apache-2.0 | https://github.com/rust-random/rand |
| rand_core | 0.6.4 | MIT OR Apache-2.0 | https://github.com/rust-random/rand |
| rav1e | 0.8.1 | BSD-2-Clause | https://github.com/xiph/rav1e/ |
| ravif | 0.13.0 | BSD-3-Clause | https://github.com/kornelski/cavif-rs |
| raw-window-handle | 0.6.2 | MIT OR Apache-2.0 OR Zlib | https://github.com/rust-windowing/raw-window-handle |
| raw-window-metal | 1.1.0 | MIT OR Apache-2.0 | https://github.com/rust-windowing/raw-window-metal |
| rawpointer | 0.2.1 | MIT/Apache-2.0 | https://github.com/bluss/rawpointer/ |
| rayon | 1.12.0 | MIT OR Apache-2.0 | https://github.com/rayon-rs/rayon |
| rayon-core | 1.13.0 | MIT OR Apache-2.0 | https://github.com/rayon-rs/rayon |
| read-fonts | 0.41.0 | MIT OR Apache-2.0 | https://github.com/googlefonts/fontations |
| renderdoc-sys | 1.1.0 | MIT OR Apache-2.0 | https://github.com/ebkalderon/renderdoc-rs |
| rfc6979 | 0.4.0 | Apache-2.0 OR MIT | https://github.com/RustCrypto/signatures/tree/master/rfc6979 |
| rgb | 0.8.53 | MIT | https://github.com/kornelski/rust-rgb |
| ring | 0.17.14 | Apache-2.0 AND ISC | https://github.com/briansmith/ring |
| rsa | 0.9.10 | MIT OR Apache-2.0 | https://github.com/RustCrypto/RSA |
| rustc-hash | 1.1.0 | Apache-2.0/MIT | https://github.com/rust-lang-nursery/rustc-hash |
| rustc_version | 0.4.1 | MIT OR Apache-2.0 | https://github.com/djc/rustc-version-rs |
| rustls | 0.23.46 | Apache-2.0 OR ISC OR MIT | https://github.com/rustls/rustls |
| rustls-pki-types | 1.15.1 | MIT OR Apache-2.0 | https://github.com/rustls/pki-types |
| rustls-rustcrypto | 0.0.2-alpha | MIT OR Apache-2.0 | https://github.com/RustCrypto/rustls-rustcrypto |
| rustls-webpki | 0.102.8 | ISC | https://github.com/rustls/webpki |
| rustls-webpki | 0.103.15 | ISC | https://github.com/rustls/webpki |
| rustversion | 1.0.23 | MIT OR Apache-2.0 | https://github.com/dtolnay/rustversion |
| scopeguard | 1.2.0 | MIT OR Apache-2.0 | https://github.com/bluss/scopeguard |
| sec1 | 0.7.3 | Apache-2.0 OR MIT | https://github.com/RustCrypto/formats/tree/master/sec1 |
| semver | 1.0.28 | MIT OR Apache-2.0 | https://github.com/dtolnay/semver |
| serde | 1.0.229 | MIT OR Apache-2.0 | https://github.com/serde-rs/serde |
| serde_core | 1.0.229 | MIT OR Apache-2.0 | https://github.com/serde-rs/serde |
| serde_derive | 1.0.229 | MIT OR Apache-2.0 | https://github.com/serde-rs/serde |
| serde_json | 1.0.154 | MIT OR Apache-2.0 | https://github.com/serde-rs/json |
| sha2 | 0.10.9 | MIT OR Apache-2.0 | https://github.com/RustCrypto/hashes |
| shlex | 2.0.1 | MIT OR Apache-2.0 | https://github.com/comex/rust-shlex |
| signature | 2.2.0 | Apache-2.0 OR MIT | https://github.com/RustCrypto/traits/tree/master/signature |
| simd-adler32 | 0.3.10 | MIT | https://github.com/mcountryman/simd-adler32 |
| simd_helpers | 0.1.0 | MIT | https://github.com/lu-zero/simd_helpers |
| siphasher | 1.0.4 | MIT OR Apache-2.0 | https://github.com/jedisct1/rust-siphash |
| smallvec | 1.16.3 | MIT OR Apache-2.0 | https://github.com/servo/rust-smallvec |
| spin | 0.9.9 | MIT | https://github.com/mvdnes/spin-rs.git |
| spirv | 0.4.0+sdk-1.4.341.0 | Apache-2.0 | https://github.com/gfx-rs/rspirv |
| spki | 0.7.3 | Apache-2.0 OR MIT | https://github.com/RustCrypto/formats/tree/master/spki |
| stable_deref_trait | 1.2.1 | MIT OR Apache-2.0 | https://github.com/storyyeller/stable_deref_trait |
| static_assertions | 1.1.0 | MIT OR Apache-2.0 | https://github.com/nvzqz/static-assertions-rs |
| studio-photo-engine | 0.1.0 | MIT OR Apache-2.0 |  |
| subtle | 2.6.1 | BSD-3-Clause | https://github.com/dalek-cryptography/subtle |
| syn | 2.0.119 | MIT OR Apache-2.0 | https://github.com/dtolnay/syn |
| syn | 3.0.9 | MIT OR Apache-2.0 | https://github.com/dtolnay/syn |
| thiserror | 2.0.21 | MIT OR Apache-2.0 | https://github.com/dtolnay/thiserror |
| thiserror-impl | 2.0.21 | MIT OR Apache-2.0 | https://github.com/dtolnay/thiserror |
| tiff | 0.11.3 | MIT | https://github.com/image-rs/image-tiff |
| tracing | 0.1.44 | MIT | https://github.com/tokio-rs/tracing |
| tracing-core | 0.1.36 | MIT | https://github.com/tokio-rs/tracing |
| ttf-parser | 0.25.1 | MIT OR Apache-2.0 | https://github.com/harfbuzz/ttf-parser |
| typenum | 1.20.1 | MIT OR Apache-2.0 | https://github.com/paholg/typenum |
| unicode-ident | 1.0.27 | (MIT OR Apache-2.0) AND Unicode-3.0 | https://github.com/dtolnay/unicode-ident |
| unicode-segmentation | 1.13.3 | MIT OR Apache-2.0 | https://github.com/unicode-rs/unicode-segmentation |
| unicode-width | 0.2.2 | MIT OR Apache-2.0 | https://github.com/unicode-rs/unicode-width |
| universal-hash | 0.5.1 | MIT OR Apache-2.0 | https://github.com/RustCrypto/traits |
| untrusted | 0.9.0 | ISC | https://github.com/briansmith/untrusted |
| v_frame | 0.3.9 | BSD-2-Clause | https://github.com/rust-av/v_frame |
| version_check | 0.9.5 | MIT/Apache-2.0 | https://github.com/SergioBenitez/version_check |
| wasm-bindgen | 0.2.129 | MIT OR Apache-2.0 | https://github.com/wasm-bindgen/wasm-bindgen |
| wasm-bindgen-macro | 0.2.129 | MIT OR Apache-2.0 | https://github.com/wasm-bindgen/wasm-bindgen/tree/master/crates/macro |
| wasm-bindgen-macro-support | 0.2.129 | MIT OR Apache-2.0 | https://github.com/wasm-bindgen/wasm-bindgen/tree/main/crates/macro-support |
| wasm-bindgen-shared | 0.2.129 | MIT OR Apache-2.0 | https://github.com/wasm-bindgen/wasm-bindgen/tree/master/crates/shared |
| web-time | 1.1.0 | MIT OR Apache-2.0 | https://github.com/daxpedda/web-time |
| webpki-roots | 1.0.9 | CDLA-Permissive-2.0 | https://github.com/rustls/webpki-roots |
| weezl | 0.1.12 | MIT OR Apache-2.0 | https://github.com/image-rs/weezl |
| wgpu | 30.0.1 | MIT OR Apache-2.0 | https://github.com/gfx-rs/wgpu |
| wgpu-core | 30.0.1 | MIT OR Apache-2.0 | https://github.com/gfx-rs/wgpu |
| wgpu-core-deps-apple | 30.0.1 | MIT OR Apache-2.0 | https://github.com/gfx-rs/wgpu |
| wgpu-hal | 30.0.1 | MIT OR Apache-2.0 | https://github.com/gfx-rs/wgpu |
| wgpu-naga-bridge | 30.0.1 | MIT OR Apache-2.0 | https://github.com/gfx-rs/wgpu |
| wgpu-types | 30.0.1 | MIT OR Apache-2.0 | https://github.com/gfx-rs/wgpu |
| x25519-dalek | 2.0.1 | BSD-3-Clause | https://github.com/dalek-cryptography/curve25519-dalek/tree/main/x25519-dalek |
| y4m | 0.8.0 | MIT | https://github.com/image-rs/y4m.git |
| zerocopy | 0.8.63 | BSD-2-Clause OR Apache-2.0 OR MIT | https://github.com/google/zerocopy |
| zerocopy-derive | 0.8.63 | BSD-2-Clause OR Apache-2.0 OR MIT | https://github.com/google/zerocopy |
| zeroize | 1.9.1 | Apache-2.0 OR MIT | https://github.com/RustCrypto/utils |
| zeroize_derive | 1.5.0 | Apache-2.0 OR MIT | https://github.com/RustCrypto/utils |
| zlib-rs | 0.6.8 | Zlib | https://github.com/trifectatechfoundation/zlib-rs |
| zmij | 1.0.23 | MIT | https://github.com/dtolnay/zmij |
| zune-core | 0.5.3 | MIT OR Apache-2.0 OR Zlib | https://github.com/etemesi254/zune-image |
| zune-jpeg | 0.5.15 | MIT OR Apache-2.0 OR Zlib | https://github.com/etemesi254/zune-image/tree/dev/crates/zune-jpeg |

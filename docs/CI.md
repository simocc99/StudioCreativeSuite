# Build automatiche, release e AltSource

Ogni commit sul ramo principale produce una IPA non firmata, la pubblica in una release e aggiorna la sorgente per SideStore / AltStore. Tutto gira su GitHub Actions con runner macOS ospitati da GitHub: in un **repository pubblico** i minuti sono gratuiti e senza limite.

Modellato sui workflow di [Xarber/LiveContainer27](https://github.com/Xarber/LiveContainer27) (release continua + `apps.json` a URL fisso) e [Xarber/Velunivo](https://github.com/Xarber/Velunivo) (scelta di Xcode beta, archivio senza firma, metadati letti dalla IPA, sorgente pubblicata e riverificata).

## Indirizzi

| Cosa | URL |
|---|---|
| Sorgente da aggiungere a SideStore / AltStore | `https://github.com/<utente>/<repo>/releases/download/source/apps.json` |
| Ultima IPA, sempre allo stesso indirizzo | `https://github.com/<utente>/<repo>/releases/download/source/StudioCreativeSuite.ipa` |
| Una build precisa | release `build-<numero>` |

## Flusso (`.github/workflows/build.yml`)

| Job | Runner | Cosa fa | Quando |
|---|---|---|---|
| `checks` | Ubuntu | test degli script CI (`Scripts/ci/test_ci_scripts.py`) | sempre |
| `build` | macOS (`macos-26`) | sceglie l'**Xcode beta** più recente, compila il motore Rust, archivia in Release **senza certificato**, applica una firma ad-hoc con le entitlement dell'app, crea `StudioCreativeSuite.ipa`, la verifica e scrive `build-info.json` | sempre (anche PR) |
| `tests` | macOS | test XCTest sul primo simulatore iPad disponibile, con i RAW di prova CC0; **informativo**, non blocca la pubblicazione | sempre, disattivabile |
| `release` | Ubuntu | crea la prerelease `build-<numero run>` con IPA, `build-info.json`, versione di Xcode e note dal messaggio di commit | solo push sul ramo principale |
| `source` | Ubuntu | tiene le ultime N build (cancella le più vecchie con il loro tag), **rigenera** `apps.json` da quelle rimaste, lo pubblica nella release fissa `source` insieme all'ultima IPA e all'icona, poi lo riscarica e confronta | dopo `release` |

Scelte importanti:
- **Mai Xcode stabile per sbaglio**: se il runner non ha una beta il job fallisce (`Scripts/ci/select_xcode.py`), a meno che la variabile `XCODE_ALLOW_STABLE` sia `true`.
- **Numero di build = numero del run**: finisce in `CFBundleVersion` e nel tag, quindi SideStore vede ogni commit come aggiornamento (stessa `version`, `buildVersion` più alta).
- **La sorgente non va mai fuori sincrono**: è ricostruita da zero dalle release esistenti; se un aggiornamento intermedio salta (job serializzati con `concurrency: altsource`), il successivo include tutto.
- **Permessi dichiarati = permessi nella IPA**: `appPermissions` viene letto dalla firma ad-hoc e dall'Info.plist (`Scripts/ci/build_info.py`); SideStore rifiuta le sorgenti in cui non coincidono.
- **Nessun segreto**: si usa solo il `GITHUB_TOKEN` automatico, con scrittura limitata ai job di pubblicazione.

## Variabili del repository (facoltative)

Impostazioni › Secrets and variables › Actions › Variables:

| Variabile | Predefinito | Effetto |
|---|---|---|
| `BUNDLE_ID` | `io.github.<utente>.studiocreativesuite` | identificativo dell'app nelle build CI |
| `KEEP_BUILDS` | `15` | build conservate nelle release e nella sorgente |
| `MACOS_RUNNER` | `macos-26` | etichetta del runner macOS (es. `macos-latest` o un runner proprio) |
| `XCODE_ALLOW_STABLE` | non impostata | `true` per accettare Xcode stabile quando non c'è una beta |
| `RUN_TESTS` | non impostata | `false` per saltare i test sul simulatore |

## Prima pubblicazione

1. Crea un repository **pubblico** su GitHub e carica il progetto (il `.gitignore` esclude build, motore compilato, RAW di prova e `App/Config/Local.xcconfig`).
2. Impostazioni › Actions › General › Workflow permissions: lascia "Read repository contents" — i job che pubblicano chiedono da soli `contents: write`.
3. Fai un push sul ramo principale: alla fine del run il riepilogo mostra l'URL della sorgente.
4. In SideStore: Sorgenti › + › incolla l'URL di `apps.json`. In LiveContainer: scarica `StudioCreativeSuite.ipa` e installala con il +.

## Provare in locale

```bash
Scripts/ci/build-unsigned-ipa.sh
```

```bash
python3 -m unittest discover -s Scripts/ci -p 'test_*.py'
```

Verifica fatta il 15/10/2026 sul Mac (Xcode 27.0 stabile, perché in locale non c'è una beta): archivio Release senza certificato riuscito, IPA da 12,9 MB che supera `Scripts/verify-ipa.sh`, `build-info.json` con l'entitlement `increased-memory-limit` e la descrizione d'uso del microfono, `apps.json` generato con il formato AltSource, IPA ri-firmata con un certificato di sviluppo e verificata con `codesign --verify --strict`. Il workflow su GitHub non è ancora stato eseguito.

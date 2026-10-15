# Compilazione, installazione e firma

## Requisiti

- Mac con Apple silicon, Xcode 27 (testato con 27.0 / 27A266a) e SDK iOS 27.
- Rust tramite rustup (`brew install rustup && rustup-init`), target `aarch64-apple-ios` e `aarch64-apple-ios-sim` (lo script li aggiunge se mancano).
- iPad con iPadOS 18 o successivo (sviluppato per iPad Pro 13" M5 con iPadOS 27). L'app è solo per iPad e solo arm64.

## 1. Motore fotografico (una volta, e dopo ogni aggiornamento di LightCraft)

```bash
Scripts/build-photo-engine.sh
```

Crea `Packages/StudioKit/Frameworks/StudioPhotoEngineFFI.xcframework` (≈ 600 MB di librerie statiche; l'app finale ne usa una frazione grazie al dead-stripping: l'IPA Release pesa ≈ 14 MB). Il primo build scarica i crate e richiede alcuni minuti.

## 2. Firma (Xcode, account Apple autorizzato)

La firma non è nel repository. Una sola volta:

1. Xcode › Impostazioni › Account › **+** › Apple Account: accedi tu, nell'interfaccia di Xcode (l'agente non chiede e non riceve credenziali).
2. Copia `App/Config/Local.xcconfig.example` in `App/Config/Local.xcconfig` (ignorato da git) e imposta:
   - `DEVELOPMENT_TEAM` = il Team ID mostrato in Xcode › Impostazioni › Account (anche quello "Personal Team" di un account gratuito);
   - `STUDIO_BUNDLE_ID` = un identificatore che nessun altro ha registrato, ad esempio `com.tuonome.studiocreativesuite`.
3. Sull'iPad: Impostazioni › Privacy e sicurezza › **Modalità sviluppatore** attiva (sul dispositivo di sviluppo risulta già attiva) e "Considera attendibile questo computer" accettato al collegamento.

## 3. Installazione con Xcode (debug)

1. Apri `StudioCreativeSuite.xcworkspace`.
2. Scheme **StudioCreativeSuite**, destinazione l'iPad collegato.
3. ⌘R. La prima volta, con un account gratuito, l'iPad chiede di autorizzare lo sviluppatore: Impostazioni › Generali › VPN e gestione dispositivi › il tuo Apple Account › Autorizza.

Da riga di comando:

```bash
xcodebuild -workspace StudioCreativeSuite.xcworkspace -scheme StudioCreativeSuite -configuration Debug -destination 'platform=iOS,name=iPad (133)' -allowProvisioningUpdates build
```

```bash
xcrun devicectl device install app --device <UDID> build/…/Debug-iphoneos/StudioCreativeSuite.app
```

```bash
xcrun devicectl device process launch --device <UDID> <bundle id>
```

Log: Xcode › Window › Devices and Simulators › Open Console, oppure `xcrun devicectl device info` per lo stato del dispositivo.

## 4. Pacchetto .ipa per SideStore

```bash
Scripts/build-ipa.sh
```

Produce `build/ipa/StudioCreativeSuite.ipa` **non firmato** (Release, arm64) e ne verifica la struttura: `Payload/StudioCreativeSuite.app`, eseguibile arm64, `MinimumOSVersion` 18.0, `UIDeviceFamily` = 2 (iPad), catalogo asset, motore fotografico collegato. SideStore (come AltStore) firma di nuovo il pacchetto sul dispositivo con il tuo Apple Account e adatta l'identificatore del bundle al tuo team: per questo il pacchetto si consegna non firmato.

`Scripts/build-ipa.sh --signed` crea invece un archivio firmato con il team di `Local.xcconfig` (utile per installarlo con Xcode/devicectl o Apple Configurator su un dispositivo registrato).

### Installare con SideStore

Segui la documentazione ufficiale della versione di SideStore che usi (https://docs.sidestore.io), che descrive il pairing file e la VPN locale necessari: le procedure cambiano tra le versioni e non sono state verificate da questo progetto. Il flusso generale è:

1. SideStore installato e funzionante sull'iPad, con il tuo Apple Account.
2. Copia `StudioCreativeSuite.ipa` sull'iPad (AirDrop o app File).
3. SideStore › My Apps › **+** › scegli il file `.ipa`.
4. Attendi che SideStore firmi e installi l'app.

### Limiti della firma gratuita

Con un Apple Account gratuito (vale per Xcode e per SideStore):

- il profilo di provisioning **scade dopo 7 giorni**: l'app smette di avviarsi finché non viene rinnovata (Xcode: ricompila e reinstalla; SideStore: "Refresh" prima della scadenza, con i requisiti di rete indicati dalla sua documentazione);
- Apple limita il numero di app sideloaded attive contemporaneamente per account gratuito (con SideStore l'app SideStore stessa occupa uno dei posti) e il numero di nuovi App ID registrabili in 7 giorni;
- alcune capability (iCloud, push, app group…) non sono disponibili: questa app non ne usa.

Con un account Apple Developer a pagamento la firma dura un anno. Nessuno strumento qui incluso promette installazioni permanenti o rinnovi automatici garantiti; non vengono usati certificati condivisi o di terzi.

I dati dell'app (progetti in `Documents`) restano sull'iPad anche se il profilo scade, purché l'app **non** venga eliminata; reinstallando con lo stesso identificatore li ritrovi.

## 5. Test automatici

```bash
Scripts/fetch-test-raws.sh
```

```bash
Scripts/run-tests.sh
```

Esegue `StudioKitTests` su un simulatore iPad (arm64) e scrive `build/test-report.json` con i risultati attesi/osservati. Senza campioni RAW il test RAW viene saltato (non segnato come riuscito).

Sull'iPad collegato (dopo aver configurato la firma):

```bash
Scripts/run-device-tests.sh <UDID>
```

Copia i campioni RAW di `build/test-raws` nella cartella `Documents/TestRAW` dell'app (visibile in File › Sul mio iPad › Studio: puoi eliminarla quando vuoi) ed esegue i test ospitati dall'app. Il report viene salvato in `Documents/test-report.json`.

Verifica rapida del motore RAW sul Mac (stesso codice Rust e stesso C ABI dell'app):

```bash
cd Engines/studio-photo-engine && cargo run --release --example rawcheck -- /tmp ../../build/test-raws/*
```

# Verifiche manuali sull'iPad (Apple Pencil, touch, rotazione)

Queste prove richiedono la mano sul dispositivo: gli strumenti automatici possono iniettare tocchi solo nel simulatore e non simulano pressione o inclinazione della Pencil. Durata stimata: 10 minuti. Annota ✅/❌ e cosa vedi.

## Apple Pencil — Pittura
1. Crea un progetto in **Pittura**, pennello **Tondo**, dimensione 40. Traccia premendo piano e poi forte: lo spessore deve crescere con la pressione.
2. Attiva **Pressione → opacità**, ripeti: con pressione leggera il tratto deve essere più trasparente.
3. Pennello **Matita**: traccia con la Pencil inclinata quasi piatta e poi verticale. Inclinata: tratto più largo e più chiaro (ombreggiatura).
4. Attiva **Solo Pencil**: un dito sulla tela non deve disegnare; due dita fanno zoom (pizzica) e scorrimento.
5. Disegna rapidamente un cerchio: il tratto deve seguire senza spigoli evidenti (tocchi coalescenti).
6. ⌘Z o il pulsante Annulla: l'ultimo tratto scompare.

## Apple Pencil — Altri editor
7. **PDF** › modalità Disegno: traccia un segno su una pagina, salva, riapri il PDF: il segno resta come annotazione.
8. **Animazione 2D**: disegna su 3 fotogrammi, attiva l'onion skin, premi Play.

## Touch
9. **Montaggio video**: importa due video, trascina una clip sulla timeline, rifila un bordo con la maniglia, pizzica sulla timeline per lo zoom.
10. **Sviluppo foto**: apri un RAW, trascina il cursore Esposizione: l'anteprima si aggiorna durante il trascinamento; doppio tocco sull'immagine per lo zoom.

## Rotazione
11. Ruota l'iPad tra verticale e orizzontale nella Home, in Pittura e nel Montaggio video: niente elementi tagliati o sovrapposti e lo stato non si perde (il tratto e la timeline restano).

Verificato automaticamente nel simulatore (14/10/2026): layout orizzontale di Home, elenchi, editor Motion e Pittura; selezione nella barra laterale (dopo la correzione); trascinamento di un livello Motion con creazione del keyframe; tratto di pittura col dito che segue il percorso del tocco.

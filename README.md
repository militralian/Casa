# KindHome

Casa trasforma un Kindle 4 con KOReader in una piccola schermata domestica a inchiostro elettronico. L’idea è riutilizzare il lettore come pannello informativo da tenere in casa.

## Cosa fa

- **Mostra data, ora, batteria e meteo** nella schermata iniziale.
- **Visualizza le previsioni** e apre una pagina testuale per il meteo di oggi e della settimana.
- **Organizza la schermata** con riquadri per meteo, calendario mensile e foto. Puoi scegliere l’orientamento verticale o orizzontale e regolare posizione e dimensioni dalla pagina Config.
- **Mostra le foto** in galleria o come cornice digitale a schermo intero. L’intervallo delle foto e l’avvio automatico dopo inattività si configurano dalla pagina Config.
- **Apre Ricette, Appunti e Agenda** dal menu di Casa, usando i documenti salvati sul Kindle.
- **Fornisce un menu controllabile con i tasti fisici** del Kindle, con accesso a meteo, calendario, foto, giochi leggeri e impostazioni.
- **Permette configurazione e invio foto in Wi‑Fi** da telefono o computer quando sono collegati alla stessa rete locale del Kindle.
- **Include script facoltativi** per avviare KOReader all’accensione e per inviare gli aggiornamenti di Casa via Wi‑Fi dopo una prima configurazione USB.

KindHome è un componente aggiuntivo di KOReader: non sostituisce il sistema operativo del Kindle e non installa Cookidoo o il software del Bimby. Il repository contiene il codice dell’interfaccia e dei servizi locali, ma non le foto, i documenti, le ricette personali, le ROM o i giochi commerciali.

## Requisiti

- Kindle 4 compatibile con KOReader.
- KOReader installato sul dispositivo.
- Connessione Wi‑Fi per il meteo, la pagina Config e gli aggiornamenti.
- Per l’avvio automatico: accesso di amministrazione già configurato sul Kindle.

## Installazione

1. Copia `casa.koplugin` nella cartella dei componenti aggiuntivi di KOReader.
2. Per l’avvio automatico facoltativo, copia i file di `casa-boot` nella cartella Casa sul Kindle e segui le istruzioni di `install.sh`.
3. Avvia KOReader e apri Casa dal menu dei componenti aggiuntivi.
4. Per abilitare gli aggiornamenti Wi‑Fi, esegui una volta `bootstrap_casa_wifi.py` con il Kindle collegato via USB. Poi `deploy_casa_wifi.py` invia i file aggiornati al Kindle sulla rete locale.
5. Apri l’indirizzo locale mostrato da Casa per usare la pagina Config da telefono o computer.

## Impostare il meteo

Il file `casa.koplugin/casa_model.lua` contiene le coordinate usate da Open‑Meteo. Nel repository sono impostate a `0.0, 0.0`: sostituiscile con quelle della località desiderata prima dell’installazione. Open‑Meteo non richiede un account.

## Privacy e rete

Il codice non include foto, appunti, ricette personali, ROM, chiavi di aggiornamento o indirizzi della rete domestica. La pagina Config è pensata per la rete locale; non va esposta direttamente a Internet.

## Aggiornare

Dopo aver modificato i file di `casa.koplugin`, esegui `deploy_casa_wifi.py` dalla rete locale. Per caricare il nuovo codice in KOReader, riavvia KOReader dal menu Casa; non è necessario riavviare tutto il Kindle.

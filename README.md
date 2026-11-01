# Casa

Casa trasforma un Kindle 4 con KOReader in una piccola schermata domestica a inchiostro elettronico. È pensata per restare aperta in casa e mostrare informazioni utili senza dover usare ogni volta un telefono.

## Cosa mostra e cosa permette di fare

- **Meteo:** condizioni attuali, temperatura e previsioni dei giorni successivi, con icone dedicate.
- **Calendario:** vista mensile con i giorni della settimana e il giorno corrente evidenziato.
- **Foto:** galleria e cornice digitale a schermo intero, con intervallo tra le immagini configurabile.
- **Disposizione personalizzabile:** scegli orientamento verticale o orizzontale e sposta o ridimensiona i riquadri meteo, calendario e foto dalla pagina Config.
- **Comandi dal Kindle:** usa i tasti fisici per passare tra schermata iniziale, foto, meteo e menu.
- **Configurazione dal telefono o dal computer:** quando Kindle e telefono sono sulla stessa rete Wi‑Fi, la pagina Config permette di inviare foto, regolare la schermata e preparare gli aggiornamenti via Wi‑Fi.
- **Avvio automatico:** gli script facoltativi in `casa-boot` aiutano a lanciare KOReader e Casa all’avvio del Kindle.

Casa è un componente aggiuntivo di KOReader: non sostituisce il sistema operativo del Kindle e non installa Cookidoo o il software del Bimby. Il codice non include ROM, giochi commerciali, foto, ricette personali, appunti, credenziali o configurazioni della rete di casa.

## Requisiti

- Kindle 4 compatibile con KOReader.
- KOReader installato sul dispositivo.
- Per la pagina Config e il meteo: connessione Wi‑Fi.
- Per l’avvio automatico: accesso di amministrazione già configurato sul Kindle.

## Installazione

1. Copia `casa.koplugin` nella cartella dei componenti aggiuntivi di KOReader.
2. Se vuoi l’avvio automatico, copia i file di `casa-boot` nella cartella Casa sul Kindle e segui le istruzioni di `install.sh`.
3. Avvia KOReader e apri Casa dal menu dei componenti aggiuntivi.
4. Per abilitare una volta gli aggiornamenti via Wi‑Fi, esegui `bootstrap_casa_wifi.py` con il Kindle collegato via USB. Poi `deploy_casa_wifi.py` invia i file aggiornati al Kindle sulla rete locale.
5. Apri l’indirizzo locale mostrato da Casa per usare la pagina Config da telefono o computer.

## Meteo

Il file `casa.koplugin/casa_model.lua` contiene le coordinate usate da Open‑Meteo. Nel repository sono impostate a `0.0, 0.0`: sostituiscile con quelle della località desiderata prima dell’installazione. Open‑Meteo non richiede un account.

## Dati e privacy

Le foto, gli appunti, le ricette, le ROM, le chiavi di aggiornamento e gli indirizzi di rete restano fuori dal repository. La pagina Config è pensata per l’uso sulla rete locale e non deve essere esposta direttamente a Internet.

## Aggiornare

Dopo aver modificato i file di `casa.koplugin`, esegui `deploy_casa_wifi.py) dalla rete locale. Per caricare il nuovo codice in KOReader, usa il comando di riavvio di KOReader nel menu Casa; non è necessario riavviare tutto il Kindle.

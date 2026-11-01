# Casa

Una schermata iniziale per Kindle 4 con KOReader: meteo, calendario, foto, appunti e accesso alle ricette. Il progetto include una pagina di configurazione utilizzabile dal telefono sulla rete Wi-Fi locale.

## Funzioni

- Home a schermo intero con meteo e previsioni.
- Calendario mensile e cornice fotografica.
- Configurazione dell’orientamento, della disposizione e delle dimensioni dei riquadri.
- Caricamento di fotografie dalla rete locale, con riduzione automatica e scarto dei duplicati.
- Modalità notte e avvio di KOReader all’accensione.
- Piccoli giochi utilizzabili con i tasti fisici del Kindle.

## Requisiti

- Kindle 4 con accesso di amministrazione già configurato.
- KOReader installato sul dispositivo.
- Connessione Wi-Fi per il meteo, la pagina Config e gli aggiornamenti senza cavo.

## Prima installazione

1. Copiare `casa.koplugin` nella cartella dei componenti aggiuntivi di KOReader sul Kindle.
2. Copiare i file contenuti in `casa-boot` nella cartella `casa` del Kindle.
3. Eseguire `install.sh` sul dispositivo per registrare l’avvio automatico.
4. Avviare KOReader e aprire Casa dal suo menu.
5. Per abilitare gli aggiornamenti via Wi-Fi, eseguire una volta `bootstrap_casa_wifi.py` con il Kindle collegato via USB. In seguito `deploy_casa_wifi.py` invia gli aggiornamenti alla pagina locale di Casa.

## Impostare il meteo

Il file `casa.koplugin/casa_model.lua` contiene le coordinate usate da Open-Meteo. Nel repository sono impostate a `0.0, 0.0`: sostituirle con le coordinate desiderate prima dell’installazione. Il servizio meteo non richiede un account.

## Foto e dati personali

Le foto, gli appunti, le ricette, le ROM, gli indirizzi di rete e le chiavi di aggiornamento restano sul dispositivo o sul computer. Non fanno parte di questo progetto. La pagina Config è accessibile soltanto sulla rete locale.

## Aggiornare

Dopo una modifica ai file di `casa.koplugin`, collegare il Kindle alla stessa rete e lanciare `deploy_casa_wifi.py`. Per caricare il nuovo codice, riavviare KOReader dal menu di Casa.

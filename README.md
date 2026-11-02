# KindHome

KindHome riutilizza un Kindle 4 con KOReader come pannello domestico a inchiostro elettronico, sempre pronto a mostrare informazioni utili.

## Funzioni

- Mostra data, orologio, batteria e meteo, con intensità Wi‑Fi e percentuale batteria nell’icona.
- Visualizza le previsioni dei prossimi giorni e una pagina testuale per il meteo di oggi e della settimana.
- Organizza la schermata con un massimo di quattro riquadri per meteo, calendario, foto, timer da cucina e lista della spesa; puoi scegliere i widget, spostarli e ridimensionarli dal configuratore.
- Offre un timer e una lista della spesa modificabili da telefono o computer tramite il pannello locale dedicato sulla porta `8766`.
- Mostra le fotografie in galleria o come cornice digitale a schermo intero, con intervallo e attivazione dopo inattività configurabili.
- Apre ricette, appunti e agenda salvati sul Kindle.
- Si controlla con i tasti fisici del lettore; HOME prolungato torna alla schermata principale, chiude le finestre aperte e mostra la memoria recuperata.
- Include modalità notte manuale o programmata e icone leggibili a schermo invertito.
- La patch per abilitare la pressione prolungata di HOME su KOReader è inclusa nella cartella `patches`.
- Permette di configurare il pannello e inviare foto da telefono o computer tramite la rete Wi‑Fi locale.
- Include strumenti facoltativi per avvio automatico e aggiornamenti senza cavo, dopo una prima configurazione USB.

Nel Kindle il plugin continua a comparire con il nome **Casa**, come nell’installazione esistente. KindHome non sostituisce il sistema operativo del lettore e non installa Cookidoo o il software del Bimby.

## Requisiti

- Kindle 4 compatibile con KOReader.
- KOReader installato.
- Wi‑Fi per il meteo, la pagina di configurazione e gli aggiornamenti.
- Per l’avvio automatico, accesso amministrativo già configurato sul Kindle.

## Installazione

1. Copia il componente aggiuntivo **KindHome** nella cartella dei plugin di KOReader.
2. Per l’avvio automatico facoltativo, copia sul Kindle i file di avvio inclusi nel repository ed esegui lo script `install.sh`.
3. Avvia KOReader e apri il plugin dal menu.
4. Per abilitare gli aggiornamenti Wi‑Fi, esegui una volta lo strumento di configurazione **KindHome** con il Kindle collegato via USB. In seguito, lo strumento **KindHome Wi‑Fi** invia gli aggiornamenti tramite la rete locale.
5. Apri l’indirizzo mostrato sul Kindle per configurare la schermata o inviare foto dal telefono o dal computer.

## Meteo

Imposta la località nel modulo meteo **KindHome** prima dell’installazione. Il servizio Open‑Meteo non richiede un account.

## Privacy e rete

Il repository non contiene foto, appunti, ricette personali, ROM, chiavi Wi‑Fi o indirizzi della rete domestica. La pagina di configurazione è pensata per l’uso sulla rete locale e non va esposta direttamente a Internet.

## Aggiornare

Dopo una modifica al codice di **KindHome**, esegui lo strumento **KindHome Wi‑Fi** dalla rete locale. Per caricare la versione aggiornata, riavvia KOReader dal menu del plugin; non occorre riavviare tutto il Kindle.

- Permette di scegliere cosa mostrare quando si riattiva il Kindle con il tasto di accensione: presentazione, calendario grande, meteo, timer o lista della spesa.

- All’avvio i server web sono spenti; si attivano dal menu Kindle e si spengono dopo cinque minuti senza richieste.
- Il pannello web permette di mostrare o nascondere i secondi dell’orologio.
- Consente di scegliere la schermata da mostrare al risveglio con il tasto di accensione: foto, calendario, meteo, timer o lista della spesa.
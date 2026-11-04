# KindHome

KindHome turns a Kindle 4 running KOReader into an e-ink home dashboard that always shows something useful.

## Features

- Date, clock, battery and weather, with Wi‑Fi strength and battery percentage in the status icon.
- Forecast for the coming days, plus text pages for today's and this week's weather.
- Up to four tiles for weather, calendar, photos, kitchen timer and shopping list. You choose, move and resize them from the web configurator.
- A timer and a shopping list you can edit from a phone or computer through the local kitchen panel on port `8766`.
- A photo gallery, or a full-screen digital photo frame with a configurable interval and idle delay.
- Recipes, notes and an agenda stored on the Kindle.
- Runs on the physical keys. A long press on HOME returns to the main screen, closes any open window and shows how much memory was freed.
- Night mode, manual or scheduled, with icons that stay readable on the inverted screen.
- The KOReader patch that enables the long press on HOME is in the `patches` folder.
- Configure the dashboard and send photos from a phone or computer over the local Wi‑Fi.
- Optional tools for starting at boot and updating without a cable, after a first setup over USB.
- When you wake the Kindle with the power button, it can show a slideshow, the large calendar, the weather, the timer or the shopping list. With that option off, standby shows the current photo as a still image.
- The web servers start switched off. You turn them on from the Kindle menu, and they close after five minutes without requests unless you set them to stay on.
- The web panel can show seconds on the clock. With seconds on, the display refreshes every second.
- Automatic standby is optional, from 15 seconds to 60 minutes, and only active within the time window you set. The window can cross midnight.

On the Kindle the plugin still appears as **Casa**, the name of the original installation. On screen its name follows the interface language. KindHome does not replace the Kindle's operating system.

## Languages

The Kindle screen and the web pages are translated into 11 languages: Italian, English, Spanish, French, German, Portuguese, Dutch, Polish, Swedish, Turkish and Russian.

- By default KindHome uses the Kindle's own interface language. If that language is not available, it falls back to English.
- You can change the language in two places: on the Kindle (Menu → **Language**, which cycles through Automatic and every language) or in the web configurator (**Language**, then save).
- The source text is Italian. Translations live in `casa.koplugin/lang/<code>.lua` and are applied only when text is displayed, so folder names and saved data never change. To add a language, add a file with the same keys and list the language in `casa_i18n.lua`.

## Weather

Weather comes from Open‑Meteo, which needs no account. In the web configurator, search for your city under **Weather location**, pick it from the results and save. Until a location is set, the weather tile asks you to choose one. The location is saved only on the Kindle, never in the code.

## Requirements

- A Kindle 4 that can run KOReader.
- KOReader installed.
- Wi‑Fi for the weather, the configuration page and updates.
- For starting at boot, root access already set up on the Kindle.

## Installation

1. Copy the `casa.koplugin` folder into KOReader's `plugins` folder.
2. To start at boot (optional), copy the boot files from `casa-boot` to the Kindle and run `install.sh`.
3. Start KOReader and open the plugin from the menu.
4. To enable Wi‑Fi updates, run the setup tool (`bootstrap_casa_wifi.py`) once with the Kindle connected over USB. After that, `deploy_casa_wifi.py` sends updates over the local network.
5. Open the address shown on the Kindle to configure the screen, set the weather location or send photos from your phone or computer.

## Privacy and network

The repository contains no photos, notes, personal recipes, ROMs, Wi‑Fi keys, locations or home network addresses. The configuration page is meant for the local network and must not be exposed directly to the Internet.

## Updating

After changing the code, run `deploy_casa_wifi.py` from the local network. To load the new version, restart KOReader from the plugin menu; there is no need to reboot the whole Kindle.

Alternatively, with SSH set up (see below), `tools/kindle update` checks the scripts, sends the whole plugin and restarts only Casa.

## Cable-free access (SSH/SFTP)

Casa starts the SSH/SFTP server bundled with KOReader on port `2222`. Login works **only with a key**; passwords are refused. The boot script also starts the server before Casa, so the Kindle stays reachable even if the plugin fails.

1. On the Mac, run `tools/crea-chiave`. It creates the private key in `chiavi/` and the public key `casa.koplugin/authorized_keys`. Neither file goes into the repository.
2. Copy the plugin to the Kindle (over USB the first time) and restart Casa.
3. Put the Kindle's address in `wifi-device-url.txt` (for example `http://192.168.x.x:8765`), or set the `KINDLE_IP` variable.

Commands are available in English and Italian:

| English | Italian | What it does |
| --- | --- | --- |
| `tools/kindle reboot` | `tools/kindle riavvia` | Reboots the Kindle. Double-clicking `tools/Riavvia Kindle.command` does the same. |
| `tools/kindle restart-home` | `tools/kindle riavvia-casa` | Restarts only Casa (within 10 seconds). |
| `tools/kindle update` | `tools/kindle aggiorna` | Sends Casa to the Kindle and restarts it. |
| `tools/kindle status` | `tools/kindle stato` | Shows Wi‑Fi state, battery, uptime and free space. |
| `tools/kindle server` | `tools/kindle server` | Turns on the Config server (5-minute mode) without using the Kindle menu. |
| `tools/kindle log` | `tools/kindle log` | Shows the KOReader log and the Wi‑Fi diagnosis. |
| `tools/kindle shell [CMD]` | `tools/kindle shell [CMD]` | Opens a shell on the Kindle, or runs a single command. |
| `tools/kindle send FILE [FOLDER]` | `tools/kindle invia FILE [CARTELLA]` | Copies a file to the Kindle. |
| `tools/kindle fetch PATH` | `tools/kindle scarica PERCORSO` | Copies a file from the Kindle. |

Any SFTP client such as Cyberduck works too (user `root`, port `2222`, key `chiavi/kindle_casa`).

On macOS, the app you run the commands from needs the **Local Network** permission (System Settings → Privacy & Security). While the Kindle is in standby its Wi‑Fi is off, so it cannot be reached.

## USB mode

The USB drive shares the storage where KOReader and Casa live, so Casa cannot stay open while a computer is using it.

- Menu → **USB mode** closes Casa and lets the Kindle handle the cable.
- If you plug the cable into a computer while Casa is open, Casa switches to USB mode by itself after about 5 seconds. With a wall charger it stays open.
- When you eject the Kindle and unplug the cable, Casa reopens by itself. If no cable is plugged in within 10 minutes, Casa reopens anyway.

## Wi‑Fi on the Kindle 4

On firmware 4.x KOReader cannot scan for or save networks, so Casa talks to the Kindle's own Wi‑Fi service directly. In the web configurator, **Manage Wi‑Fi networks** opens a window with:

- **Current connection**: network name, signal, IP address and **Disconnect**.
- **Available networks**: a scan runs when the window opens; **Scan** repeats it. Pick a new network, type its password and press **Test connection**. **Save network** unlocks only after a successful test.
- **Saved networks**: every network stored on the Kindle, with **Connect**, **Disconnect** and **Forget**. Saved passwords are never sent to the page.

During a test the Kindle joins the new network for a few seconds and then returns to the current one, so the phone can read the result. A failed test leaves the saved networks unchanged. Switching to or disconnecting from a network the phone is not on makes the page lose the Kindle; the page warns before doing it.

At startup, and from Menu → **Turn Wi‑Fi back on**, Casa turns off airplane mode, switches Wi‑Fi back on and saves a diagnosis to `casa/wifi-diag.log`. Casa also asks the Kindle's Wi‑Fi service for the connection state directly, so KOReader does not switch off a working connection.

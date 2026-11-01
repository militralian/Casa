from pathlib import Path
import os
import sys


root = Path(__file__).resolve().parent
volume = Path("/Volumes/Kindle")
key = root / "wifi-update-key.txt"
plugin = volume / "koreader/plugins/casa.koplugin/photo_server.lua"

if not (volume / "koreader/koreader.sh").is_file():
    sys.exit("Kindle non collegato in modalità USB.")
if not key.is_file():
    sys.exit("Chiave locale mancante.")
if not plugin.is_file() or 'path==\"/update\"' not in plugin.read_text(errors="ignore"):
    sys.exit("Il Kindle non ha il server Casa necessario. Aggiornalo prima via USB.")

destination = volume / "Casa/casa-update-key.txt"
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(key.read_text().strip())
print("Chiave Wi-Fi copiata. Espelli il Kindle e riavvia Casa; gli aggiornamenti successivi possono passare dalla rete.")

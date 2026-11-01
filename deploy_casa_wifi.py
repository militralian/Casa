from pathlib import Path
import json
import sys
from urllib.request import Request, urlopen

root = Path(__file__).resolve().parent
plugin = root / "casa.koplugin"
key_path = root / "wifi-update-key.txt"
url_file = root / "wifi-device-url.txt"

if not key_path.is_file():
    sys.exit("Manca la chiave Wi-Fi. Collega il Kindle via USB una volta per configurare gli aggiornamenti.")
base_url = (sys.argv[1].strip() if len(sys.argv) > 1 else (url_file.read_text().strip() if url_file.exists() else ""))
if not base_url.startswith("http://"):
    sys.exit("Indica l'indirizzo locale mostrato nella schermata Casa")
key = key_path.read_text().strip()
files = [p for p in plugin.rglob("*") if p.is_file() and (p.suffix == ".lua" or (p.parent.name == "icons" and p.suffix == ".svg"))]
files.sort(key=lambda p: (p.name == "photo_server.lua", p.as_posix()))
for path in files:
    relative = path.relative_to(plugin).as_posix()
    request = Request(base_url.rstrip("/") + "/update", data=path.read_bytes(), method="POST", headers={
        "Content-Type": "application/octet-stream",
        "X-Casa-Update-Key": key,
        "X-Casa-Update-File": relative,
    })
    try:
        with urlopen(request, timeout=8) as response:
            result = json.loads(response.read().decode("utf-8"))
    except Exception as exc:
        sys.exit(f"Aggiornamento interrotto su {relative}: {exc}")
    if not result.get("ok"):
        sys.exit(f"Aggiornamento rifiutato su {relative}.")
    print("Aggiornato:", relative)
print("File Casa aggiornati via Wi-Fi. Per caricare il nuovo codice, riavvia KOReader dal menu Casa; non serve riavviare tutto il Kindle.")

local M = {}
-- The place comes from the Config page (weather_place in the settings); no place, no request.
M.url_params = "&current=temperature_2m,weather_code,precipitation,rain,showers,relative_humidity_2m,apparent_temperature,wind_speed_10m,wind_direction_10m,cloud_cover,pressure_msl&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&timezone=auto&forecast_days=7"
function M.urlFor(place)
 local lat, lon = place and tonumber(place.latitude), place and tonumber(place.longitude)
 if not lat or not lon or lat < -90 or lat > 90 or lon < -180 or lon > 180 then return nil end
 return string.format("https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f", lat, lon) .. M.url_params
end
M.phrases = {
 "Una cosa alla volta, fatta con cura.", "Oggi lascia spazio a qualcosa di semplice.",
 "Le cose buone hanno bisogno del loro tempo.", "Comincia da quello che hai, qui e ora.",
 "Un piccolo gesto può cambiare il tono della giornata.", "Fai una pausa: anche il riposo è tempo ben speso.",
 "C'è sempre qualcosa di nuovo da imparare.", "La cura si vede nei dettagli di ogni giorno.",
 "Scegli una cosa importante e comincia da lì.", "Una tavola condivisa fa spazio alle storie.",
 "Non serve fare tutto oggi.", "Porta un po' di curiosità nelle cose abituali.",
 "Ogni giornata può avere un momento tutto tuo.", "Il tempo per ascoltare non è tempo perso.",
 "Lascia che una buona abitudine faccia il primo passo.", "Il prossimo passo può essere piccolo.",
 "Prenditi il tempo di assaporare.", "Una passeggiata cambia il punto di vista.",
 "Oggi prova qualcosa che rimandi da un po'.", "Condividi una cosa buona, anche piccola.",
 "Una casa vive dei gesti di chi la abita.", "Un momento tranquillo può bastare per ricominciare.",
 "Metti attenzione in quello che stai facendo.", "C'è bellezza anche nelle giornate ordinarie.",
 "Una domanda nuova apre una strada nuova.", "Semplificare è fare spazio a ciò che conta.",
 "Raccogli un'idea prima che passi.", "Le cose fatte insieme lasciano un ricordo diverso.",
 "Concediti il piacere di finire una cosa.", "Oggi trova un motivo per sorridere.",
 "Domani avrà il suo tempo. Abita questo giorno.",
}
local weekdays = {"domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato"}
local months = {"gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre"}
function M.romeTime(epoch)
 -- EU daylight saving: last Sunday of March/October at 01:00 UTC.
 local t = os.date("!*t", epoch)
 local function lastSunday(month)
  local d = os.date("!*t", os.time{year=t.year,month=month+1,day=0,hour=12})
  return d.day - (d.wday - 1)
 end
 local dst = t.month > 3 and t.month < 10
 if t.month == 3 then dst = t.day > lastSunday(3) or (t.day == lastSunday(3) and t.hour >= 1) end
 if t.month == 10 then dst = t.day < lastSunday(10) or (t.day == lastSunday(10) and t.hour < 1) end
 return os.date("!*t", epoch + (dst and 7200 or 3600))
end
function M.date(epoch)
 local t = M.romeTime(epoch or os.time())
 return weekdays[t.wday] .. " " .. t.day .. " " .. months[t.month], t
end
function M.phrase(epoch)
 local _, t = M.date(epoch)
 return M.phrases[((t.yday-1) % #M.phrases)+1]
end
function M.condition(code)
 if code == 0 then return "Sereno" end
 if code == 1 then return "Prevalentemente sereno" end
 if code == 2 then return "Parzialmente nuvoloso" end
 if code == 3 then return "Coperto" end
 if code == 45 or code == 48 then return "Nebbia" end
 if type(code) ~= "number" then return "Condizioni non disponibili" end
 if code >= 95 then return "Temporali" end
 if code >= 85 or (code >= 71 and code <= 77) then return "Neve" end
 if code >= 80 then return "Rovesci" end
 if code >= 61 then return "Pioggia" end
 if code >= 51 then return "Pioviggine" end
 return "Variabile"
end
function M.shortCondition(code)
 if code == 0 then return "Sereno" end
 if code == 1 then return "Poco nuvoloso" end
 if code == 2 then return "Parz. nuvoloso" end
 if code == 3 then return "Nuvoloso" end
 if code == 45 or code == 48 then return "Nebbia" end
 if type(code) ~= "number" then return "Non disponibile" end
 if code >= 95 then return "Temporali" end
 if code >= 85 or (code >= 71 and code <= 77) then return "Neve" end
 if code >= 80 then return "Rovesci" end
 if code >= 61 then return "Pioggia" end
 if code >= 51 then return "Pioviggine" end
 return "Variabile"
end
function M.icon(code)
 if code == 0 or code == 1 then return "sun" end
 if code == 2 then return "partly" end
 if code == 3 then return "cloud" end
 if code == 45 or code == 48 then return "fog" end
 if type(code) ~= "number" then return "unknown" end
 if code >= 95 then return "storm" end
 if code >= 85 or (code >= 71 and code <= 77) then return "snow" end
 if code >= 51 then return "rain" end
 return "unknown"
end
function M.currentCode(current)
 if type(current) ~= "table" then return nil end
 local code = current.weather_code
 -- The live precipitation measurement takes precedence over a stale/cloud-only symbol.
 if ((type(current.precipitation) == "number" and current.precipitation > 0)
  or (type(current.rain) == "number" and current.rain > 0)
  or (type(current.showers) == "number" and current.showers > 0))
  and type(code) == "number" and code < 51 then
  return 61
 end
 return code
end
function M.number(value)
 if type(value) ~= "number" then return "—" end
 return string.format("%.0f", value)
end
function M.windDirection(value)
 if type(value) ~= "number" then return "—" end
 local names={"N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSO", "SO", "OSO", "O", "ONO", "NO", "NNO"}
 return names[math.floor((value%360+11.25)/22.5)%16+1]
end
function M.valid(data)
 if type(data) ~= "table" or type(data.current) ~= "table" or type(data.daily) ~= "table" then return false end
 if data.fetched_at ~= nil and (type(data.fetched_at) ~= "number" or data.fetched_at <= 0 or data.fetched_at == math.huge or data.fetched_at ~= data.fetched_at) then return false end
 if type(data.current.temperature_2m) ~= "number" or type(data.current.weather_code) ~= "number" or type(data.daily.time) ~= "table" or #data.daily.time < 7 then return false end
 for i=1,7 do if type(data.daily.time[i]) ~= "string" or not data.daily.time[i]:match("^%d%d%d%d%-%d%d%-%d%d$") then return false end end
 for _, key in ipairs{"weather_code", "temperature_2m_max", "temperature_2m_min", "precipitation_probability_max"} do
  if type(data.daily[key]) ~= "table" then return false end
  for i=1,7 do if type(data.daily[key][i]) ~= "number" then return false end end
 end
 return true
end
function M.todayIndex(data, epoch)
 local t = M.romeTime(epoch or os.time())
 local today = string.format("%04d-%02d-%02d",t.year,t.month,t.day)
 for i, day in ipairs(data.daily.time) do if day == today then return i end end
end
function M.agenda(text, epoch)
 local t = M.romeTime(epoch or os.time())
 local today = string.format("%04d-%02d-%02d",t.year,t.month,t.day)
 local entries = {}
 for line in (text or ""):gmatch("[^\r\n]+") do
  local date, hour, title = line:match("^(%d%d%d%d%-%d%d%-%d%d)%s+(%d%d:%d%d)%s*|%s*(.+)$")
  if date and date >= today then entries[#entries+1] = {date=date,hour=hour,title=title} end
 end
 table.sort(entries,function(a,b) return a.date..a.hour < b.date..b.hour end)
 return entries
end
return M

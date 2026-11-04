-- Wi-Fi management for the Config page, through the Kindle's own wifid service.
-- FW 4.x has no liblipclua, so everything goes through the lipc-* command line tools:
-- hash properties (scanList, profileData, currentEssid, createProfile) via lipc-hash-prop,
-- plain ones (scan, cmConnect, cmDisconnect, deleteProfile) via lipc-set-prop.
-- Saved passwords are read only to restore a profile after a failed test; they never leave this module.
local W = {}

local SERVICE = "com.lab126.wifid"
local TEST_TIMEOUT, RETURN_TIMEOUT = 35, 45

local function quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

local function run(cmd)
 local pipe = io.popen(cmd .. " 2>/dev/null")
 if not pipe then return "" end
 local out = pipe:read("*a") or ""
 pipe:close()
 return out
end

local function getString(prop) return (run("lipc-get-prop " .. SERVICE .. " " .. prop):gsub("%s+$", "")) end
local function setString(prop, value) run("lipc-set-prop " .. SERVICE .. " " .. prop .. " " .. quote(value or "")) end

-- Parses lipc-hash-prop output: "Hash Index: N" blocks of `key = "text"` or `key = (number)` lines.
local function readHash(prop)
 local items, item = {}, nil
 for line in run("echo '{}' | lipc-hash-prop -n " .. SERVICE .. " " .. prop):gmatch("[^\n]+") do
  if line:match("^Hash Index:") then
   item = {}; items[#items + 1] = item
  elseif item then
   local key, text = line:match('^%s*([%w_]+) = "(.*)"%s*$')
   if key then item[key] = text
   else
    local nkey, num = line:match("^%s*([%w_]+) = %((%-?%d+)%)")
    if nkey then item[nkey] = tonumber(num) end
   end
  end
 end
 return items
end

local function hashText(fields)
 local parts = {}
 for _, f in ipairs(fields) do
  if type(f[2]) == "number" then parts[#parts + 1] = f[1] .. " = (" .. f[2] .. ")"
  else parts[#parts + 1] = f[1] .. ' = "' .. tostring(f[2]):gsub("[\\\"]", "\\%0") .. '"' end
 end
 return "{ " .. table.concat(parts, ", ") .. " }\n"
end

local function writeHash(prop, fields)
 local pipe = io.popen("lipc-hash-prop " .. SERVICE .. " " .. prop .. " >/dev/null 2>&1", "w")
 if not pipe then return false end
 pipe:write(hashText(fields))
 pipe:close()
 return true
end

local function cleanSSID(ssid)
 if type(ssid) ~= "string" then return nil end
 ssid = ssid:gsub("[%c]", "")
 if #ssid < 1 or #ssid > 32 then return nil end
 return ssid
end

local function savedProfiles()
 local list = {}
 for _, p in ipairs(readHash("profileData")) do
  if p.essid and p.essid ~= "" then list[#list + 1] = p end
 end
 return list
end

local function findProfile(ssid)
 for _, p in ipairs(savedProfiles()) do if p.essid == ssid then return p end end
end

local function currentNetwork()
 local state = getString("cmState")
 local cur = readHash("currentEssid")[1] or {}
 local essid = cur.essid ~= "" and cur.essid or nil
 local ip
 if state == "CONNECTED" then
  ip = run("ifconfig wlan0"):match("inet addr:(%d+%.%d+%.%d+%.%d+)")
 end
 return {state = state, essid = state == "CONNECTED" and essid or nil, signal = cur.signal, signal_max = cur.signal_max, ip = ip}
end

local test = nil -- running or finished connection test

function W.overview()
 local scan = {}
 for _, n in ipairs(readHash("scanList")) do
  if n.essid and n.essid ~= "" then
   scan[#scan + 1] = {essid = n.essid, secured = n.secured ~= "no", known = n.known == "yes",
    signal = n.signal or 0, signal_max = n.signal_max or 5, supported = n.supported ~= "no"}
  end
 end
 table.sort(scan, function(a, b) return a.signal > b.signal end)
 local saved = {}
 for _, p in ipairs(savedProfiles()) do
  saved[#saved + 1] = {essid = p.essid, security = p.smethod or (p.secured == "no" and "open" or "")}
 end
 return {current = currentNetwork(), scanning = getString("scanState") ~= "idle", networks = scan, saved = saved, test = W.testStatus()}
end

function W.scan() setString("scan", "") end

function W.connect(ssid)
 ssid = cleanSSID(ssid)
 if not ssid or not findProfile(ssid) then return false, "Rete non salvata" end
 setString("cmConnect", ssid)
 return true
end

function W.disconnect() setString("cmDisconnect", "") return true end

function W.forget(ssid)
 ssid = cleanSSID(ssid)
 if not ssid or not findProfile(ssid) then return false, "Rete non salvata" end
 setString("deleteProfile", ssid)
 return true
end

local function store(ssid, password)
 if password and password ~= "" then
  return writeHash("createProfile", {{"essid", ssid}, {"secured", "yes"}, {"psk", password}, {"store_nw_user_pref", 0}})
 end
 return writeHash("createProfile", {{"essid", ssid}, {"secured", "no"}})
end

local function checkPassword(password, secured)
 if not secured then return true end
 if type(password) ~= "string" or #password < 8 or #password > 63 then
  return false, "Controlla nome rete e password WPA (8–63 caratteri)."
 end
 return true
end

-- Save without testing is refused by the page; this is called after a successful test.
function W.save(ssid, password, secured)
 ssid = cleanSSID(ssid)
 if not ssid then return false, "Dati Wi‑Fi non validi." end
 local ok, err = checkPassword(password, secured)
 if not ok then return false, err end
 if not store(ssid, secured and password or nil) then return false, "Il Kindle non ha accettato il profilo Wi‑Fi." end
 return true, ssid
end

-- Connection test: store the profile, join the network, then always go back to the network the
-- page was opened on, so the phone can read the result. A failed test leaves the profiles as they were.
function W.startTest(ssid, password, secured)
 if test and test.phase ~= "done" then return false, "Prova già in corso" end
 ssid = cleanSSID(ssid)
 if not ssid then return false, "Dati Wi‑Fi non validi." end
 local ok, err = checkPassword(password, secured)
 if not ok then return false, err end
 local before = findProfile(ssid)
 local cur = currentNetwork()
 if cur.essid == ssid then return false, "Il Kindle è già collegato a questa rete." end
 if not store(ssid, secured and password or nil) then return false, "Il Kindle non ha accettato il profilo Wi‑Fi." end
 test = {phase = "testing", ssid = ssid, started = os.time(), previous = cur.essid, before = before}
 setString("cmConnect", ssid)
 return true
end

function W.step()
 if not test or test.phase == "done" then return end
 local now = os.time()
 if test.phase == "testing" then
  local cur = currentNetwork()
  local elapsed = now - test.started
  if cur.essid == test.ssid then test.ok = true
  elseif elapsed > TEST_TIMEOUT or (elapsed > 6 and cur.essid and cur.essid ~= test.ssid) then test.ok = false
  else return end
  -- The test never changes what is saved: remove the new profile, or put the old password back.
  if not test.before then setString("deleteProfile", test.ssid)
  else store(test.ssid, test.before.psk ~= "" and test.before.psk or nil) end
  test.before = nil
  if test.previous and test.previous ~= test.ssid then
   test.phase, test.returning = "returning", now
   setString("cmConnect", test.previous)
  else
   test.phase = "done"
  end
 elseif test.phase == "returning" then
  local cur = currentNetwork()
  if cur.state == "CONNECTED" or now - test.returning > RETURN_TIMEOUT then test.phase = "done" end
 end
end

function W.testStatus()
 if not test then return nil end
 return {phase = test.phase, ssid = test.ssid, ok = test.ok}
end

return W

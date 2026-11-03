-- Translations for Casa and its web pages.
-- The source text stays Italian everywhere in the code; strings are translated only when they are
-- shown (casa_layout text(), dialogs, web pages), so internal values such as folder names never change.
-- Dictionaries live in lang/<code>.lua and map the Italian text (or fragment) to the translation.
local I = {}

I.languages = {
 {code="it", name="Italiano"}, {code="en", name="English"}, {code="es", name="Español"},
 {code="fr", name="Français"}, {code="de", name="Deutsch"}, {code="pt", name="Português"},
 {code="nl", name="Nederlands"}, {code="pl", name="Polski"}, {code="sv", name="Svenska"},
 {code="tr", name="Türkçe"}, {code="ru", name="Русский"},
}
local known = {}
for _, l in ipairs(I.languages) do known[l.code] = l.name end

local plugin_dir = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]*$")) or "."
local current, dict, keys, cache, cache_size = "it", nil, nil, {}, 0
local page_cache = {}

-- The Kindle's own UI language (FW 4.x keeps it in the framework prefs), then KOReader's.
function I.detect()
 local f = io.open("/var/local/java/prefs/com.amazon.ebook.framework/prefs", "rb")
 if f then
  local raw = f:read("*a") or ""; f:close()
  local code = raw:match("\nlocale=(%a%a)") or raw:match("^locale=(%a%a)")
  if code and known[code:lower()] then return code:lower() end
 end
 local ok, lang = pcall(function() return G_reader_settings and G_reader_settings:readSetting("language") end)
 if ok and type(lang) == "string" and known[lang:sub(1, 2)] then return lang:sub(1, 2) end
 return "en"
end

function I.name(code) return known[code] end

local function load(code)
 if code == "it" then return nil end
 local chunk = loadfile(plugin_dir .. "/lang/" .. code .. ".lua")
 local ok, t = pcall(chunk or error)
 return ok and type(t) == "table" and t or nil
end

-- setting: "auto" or a language code; returns the language actually used.
function I.set(setting)
 local code = known[setting or ""] and setting or I.detect()
 if code ~= current or (code ~= "it" and not dict) then
  current, dict = code, load(code)
  keys, cache, cache_size, page_cache = nil, {}, 0, {}
  if dict then
   keys = {}
   for k in pairs(dict) do keys[#keys + 1] = k end
   table.sort(keys, function(a, b) return #a > #b end)
  end
 end
 return current
end

function I.current() return current end

-- Letters (ASCII or any UTF-8 byte) on both sides mean the key is only part of a word.
local function is_letter(byte) return byte and (byte >= 128 or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122)) end

-- Translate a whole string or the known fragments inside it (dynamic text such as
-- "Prossimo: 12/11 · Dentista"). Longest keys win; replaced parts are never translated twice.
function I.tr(s)
 if not dict or type(s) ~= "string" or s == "" then return s end
 local exact = dict[s]
 if exact then return exact end
 local hit = cache[s]
 if hit then return hit end
 local work, parts = s, {}
 for _, key in ipairs(keys) do
  if #key <= #work then
   local from = 1
   while true do
    local a, b = work:find(key, from, true)
    if not a then break end
    local first, last = key:byte(1), key:byte(-1)
    local ok = not (is_letter(first) and is_letter(work:byte(a - 1))) and not (is_letter(last) and is_letter(work:byte(b + 1)))
    if ok then
     parts[#parts + 1] = dict[key]
     local mark = "\1" .. #parts .. "\2"
     work = work:sub(1, a - 1) .. mark .. work:sub(b + 1)
     from = a + #mark
    else
     from = a + 1
    end
   end
  end
 end
 local out = work:gsub("\1(%d+)\2", function(n) return parts[tonumber(n)] end)
 if cache_size > 600 then cache, cache_size = {}, 0 end
 cache[s], cache_size = out, cache_size + 1
 return out
end

-- Web templates: only whole text nodes, user-facing attributes and JS string literals are
-- replaced, and only on an exact match, so markup and code can never be altered by accident.
function I.page(id, html)
 if not dict then return (html:gsub('<html lang="it"', '<html lang="it"', 1)) end
 local done = page_cache[id]
 if done then return done end
 local function exact(text)
  local lead, core, trail = text:match("^(%s*)(.-)(%s*)$")
  local t = dict[core]
  return t and (lead .. t .. trail) or nil
 end
 local out = html:gsub(">([^<>]+)<", function(t) local r = exact(t); return r and (">" .. r .. "<") end)
 for _, attr in ipairs({"placeholder", "aria%-label", "title", "alt"}) do
  out = out:gsub("(" .. attr .. '=")([^"]*)(")', function(a, t, c) local r = dict[t]; return r and (a .. r .. c) end)
 end
 out = out:gsub("'([^'\n]*)'", function(t) local r = dict[t]; return r and ("'" .. r:gsub("\\", "\\\\"):gsub("'", "\\'") .. "'") end)
 out = out:gsub('<html lang="it"', '<html lang="' .. current .. '"', 1):gsub("<html lang='it'", "<html lang='" .. current .. "'", 1)
 page_cache[id] = out
 return out
end

return I

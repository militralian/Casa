local socket = require("socket")
local Device = require("device")
local json = require("json")
local sha256 = require("ffi/sha2").sha256
local lfs = require("libs/libkoreader-lfs")

local Server = {}
Server.__index = Server

local DEFAULT_WIDGET_LAYOUT={
 weather={x=0,y=0,w=46,h=46},
 photo={x=46,y=0,w=54,h=100},
 calendar={x=0,y=46,w=46,h=54},
 timer={x=0,y=46,w=23,h=54},
 shopping={x=23,y=46,w=23,h=54},
}
local WIDGET_MINIMUMS={weather={w=35,h=30},photo={w=25,h=30},calendar={w=30,h=35},timer={w=20,h=24},shopping={w=20,h=24}}
local function normalizeWidgetLayout(layout)
 local normalized={}
 for name,defaults in pairs(DEFAULT_WIDGET_LAYOUT) do
  local value=type(layout)=="table" and type(layout[name])=="table" and layout[name] or {}
  local minimum=WIDGET_MINIMUMS[name]
  local x=math.max(0,math.min(100-minimum.w,tonumber(value.x) or defaults.x))
  local y=math.max(0,math.min(100-minimum.h,tonumber(value.y) or defaults.y))
  local w=math.max(minimum.w,math.min(100-x,tonumber(value.w) or defaults.w))
  local h=math.max(minimum.h,math.min(100-y,tonumber(value.h) or defaults.h))
  normalized[name]={x=x,y=y,w=w,h=h}
 end
 return normalized
end

local function response(client, status, body, content_type)
 body = body or ""
 local message = "HTTP/1.1 "..status.."\r\nContent-Type: "..(content_type or "text/html; charset=utf-8")
  .."\r\nContent-Length: "..#body.."\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"..body
 pcall(function()
  client:settimeout(8)
  local first=1
  while first<=#message do
   local sent,err,last=client:send(message,first)
   if sent then first=sent+1
   elseif last and last>=first then first=last+1
   else break end
  end
 end)
 pcall(function() client:close() end)
end

local function safeFilename(name)
 name = (name or "foto"):gsub("\\", "/"):match("([^/]+)$") or "foto"
 name = name:gsub("[^%w%._%-]", "_"):gsub("^%.+", "")
 if name == "" then name = "foto.jpg" end
 local ext = name:match("%.([^.]+)$")
 ext = ext and ext:lower()
 if ext ~= "jpg" and ext ~= "jpeg" and ext ~= "png" and ext ~= "bmp" then return nil end
 return name
end

function Server:new(folder, interval_path, plugin_dir, update_key_path, games_dir)
 return setmetatable({folder=folder, interval_path=interval_path or (folder.."/intervallo-foto.txt"),
  plugin_dir=plugin_dir, update_key_path=update_key_path, games_dir=games_dir, clients={}}, self)
end

local function updateKeyMatches(self, header)
 local key_file=self.update_key_path and io.open(self.update_key_path,"rb")
 local saved_key=key_file and key_file:read("*a") or ""
 if key_file then key_file:close() end
 local supplied=header:match("[Xx]%-[Cc]asa%-[Uu]pdate%-[Kk]ey:%s*([^\r\n]+)") or ""
 return saved_key~="" and supplied==saved_key
end

function Server:getInterval()
 local f=io.open(self.interval_path,"rb")
 if not f then return 30 end
 local value=tonumber(f:read("*a"));f:close()
 if not value then return 30 end
 return math.max(5,math.min(300,math.floor(value+0.5)))
end

function Server:getSlideshowSettings()
 local interval=self:getInterval()
 local enabled=false
 local delay=60
 local f=io.open(self.interval_path,"rb")
 if f then
  local raw=f:read("*a");f:close()
  local ok,data=pcall(json.decode,raw or "")
  if ok and type(data)=="table" then
   interval=math.max(5,math.min(300,math.floor((tonumber(data.interval_seconds) or interval)+0.5)))
   -- Before settings version 2, users could turn the slideshow off in the preview
   -- without saving the live Kindle preference. Migrate that ambiguous state to off.
   enabled=tonumber(data.settings_version or 0)>=2 and data.screensaver_enabled==true
   delay=math.max(15,math.min(600,math.floor((tonumber(data.screensaver_delay_seconds) or 60)+0.5)))
  end
 end
 local night_mode="manual"
 local night_enabled=false
 local night_start="22:00"
 local night_end="07:00"
 local calendar_enabled=false
 local timer_enabled=true
 local shopping_enabled=true
 local weather_enabled=true
 local photo_enabled=true
 local weather_side="left"
 local photo_side="right"
 local calendar_side="right"
 local screen_orientation="landscape"
 local widget_layout=normalizeWidgetLayout(nil)
 local f=io.open(self.interval_path,"rb")
 if f then
  local raw=f:read("*a");f:close()
  local ok,data=pcall(json.decode,raw or "")
  if ok and type(data)=="table" then
   night_mode=data.night_mode=="automatic" and "automatic" or "manual"
   night_enabled=data.night_enabled==true
   night_start=type(data.night_start)=="string" and data.night_start:match("^%d%d:%d%d$") and data.night_start or night_start
   night_end=type(data.night_end)=="string" and data.night_end:match("^%d%d:%d%d$") and data.night_end or night_end
   calendar_enabled=data.calendar_enabled==true
   timer_enabled=data.timer_enabled~=false
   shopping_enabled=data.shopping_enabled~=false
   weather_enabled=data.weather_enabled~=false
   photo_enabled=data.photo_enabled~=false
   weather_side=data.weather_side=="right" and "right" or "left"
   photo_side=data.photo_side=="left" and "left" or "right"
   calendar_side=data.calendar_side=="left" and "left" or "right"
   screen_orientation=data.screen_orientation=="portrait" and "portrait" or "landscape"
   -- Version 3 replaces the old overlapping starter layout with a three-zone
   -- arrangement: weather/calendar on the left and photos on the right.
   if tonumber(data.settings_version or 0)>=3 then
    widget_layout=normalizeWidgetLayout(data.widget_layout)
   end
  end
 end
 return {interval_seconds=interval,screensaver_enabled=enabled,screensaver_delay_seconds=delay,
  night_mode=night_mode,night_enabled=night_enabled,night_start=night_start,night_end=night_end,
  calendar_enabled=calendar_enabled,timer_enabled=timer_enabled,shopping_enabled=shopping_enabled,weather_enabled=weather_enabled,photo_enabled=photo_enabled,
  weather_side=weather_side,photo_side=photo_side,calendar_side=calendar_side,
  widget_layout=widget_layout,screen_orientation=screen_orientation,settings_version=4}
end

function Server:saveSlideshowSettings(payload)
 if type(payload)~="table" then return nil end
 local current=self:getSlideshowSettings()
 local interval=tonumber(payload.interval_seconds) or current.interval_seconds
 interval=math.max(5,math.min(300,math.floor(interval/5+0.5)*5))
 local enabled=payload.screensaver_enabled
 if enabled==nil then enabled=current.screensaver_enabled else enabled=enabled==true end
 local delay=tonumber(payload.screensaver_delay_seconds) or current.screensaver_delay_seconds
 delay=math.max(15,math.min(600,math.floor(delay/15+0.5)*15))
 local function side(name,default) return payload[name]=="left" and "left" or payload[name]=="right" and "right" or current[name] or default end
 local night_mode=payload.night_mode=="automatic" and "automatic" or payload.night_mode=="manual" and "manual" or current.night_mode
 local timer_enabled=payload.timer_enabled==nil and current.timer_enabled or payload.timer_enabled==true
 local shopping_enabled=payload.shopping_enabled==nil and current.shopping_enabled or payload.shopping_enabled==true
 local screen_orientation=payload.screen_orientation=="portrait" and "portrait" or payload.screen_orientation=="landscape" and "landscape" or current.screen_orientation
 local visible_count=(payload.weather_enabled==nil and current.weather_enabled or payload.weather_enabled==true) and 1 or 0
 visible_count=visible_count+((payload.photo_enabled==nil and current.photo_enabled or payload.photo_enabled==true) and 1 or 0)
 visible_count=visible_count+((payload.calendar_enabled==nil and current.calendar_enabled or payload.calendar_enabled==true) and 1 or 0)
 visible_count=visible_count+(timer_enabled and 1 or 0)+(shopping_enabled and 1 or 0)
 if visible_count>4 then return nil end
 local widget_layout=normalizeWidgetLayout(payload.widget_layout or current.widget_layout)
 local visible_widgets={weather=payload.weather_enabled==nil and current.weather_enabled or payload.weather_enabled==true,
  photo=payload.photo_enabled==nil and current.photo_enabled or payload.photo_enabled==true,
  calendar=payload.calendar_enabled==nil and current.calendar_enabled or payload.calendar_enabled==true,
  timer=timer_enabled,shopping=shopping_enabled}
 local names={"weather","photo","calendar","timer","shopping"}
 for i=1,#names do
  if visible_widgets[names[i]] then
   local a=widget_layout[names[i]]
   for j=i+1,#names do
    if visible_widgets[names[j]] then
     local b=widget_layout[names[j]]
     if a.x<b.x+b.w and a.x+a.w>b.x and a.y<b.y+b.h and a.y+a.h>b.y then return nil end
    end
   end
  end
 end
 local settings={settings_version=4,interval_seconds=interval,screensaver_enabled=enabled,screensaver_delay_seconds=delay,
  night_mode=night_mode,night_enabled=payload.night_enabled==nil and current.night_enabled or payload.night_enabled==true,
  night_start=type(payload.night_start)=="string" and payload.night_start:match("^%d%d:%d%d$") and payload.night_start or current.night_start,
  night_end=type(payload.night_end)=="string" and payload.night_end:match("^%d%d:%d%d$") and payload.night_end or current.night_end,
  calendar_enabled=payload.calendar_enabled==nil and current.calendar_enabled or payload.calendar_enabled==true,
  timer_enabled=timer_enabled,shopping_enabled=shopping_enabled,
  weather_enabled=payload.weather_enabled==nil and current.weather_enabled or payload.weather_enabled==true,
  photo_enabled=payload.photo_enabled==nil and current.photo_enabled or payload.photo_enabled==true,
  weather_side=side("weather_side","left"),photo_side=side("photo_side","right"),calendar_side=side("calendar_side","right"),
  widget_layout=widget_layout,
  screen_orientation=screen_orientation}
 local f=io.open(self.interval_path..".tmp","wb")
 if not f then return nil end
 f:write(json.encode(settings));f:close()
 if not os.rename(self.interval_path..".tmp",self.interval_path) then return nil end
 self.last_interval_change=os.time()
 return settings
end

function Server:setInterval(value)
 value=tonumber(value)
 if not value then return false end
 value=math.max(5,math.min(300,math.floor(value/5+0.5)*5))
 local f=io.open(self.interval_path..".tmp","wb")
 if not f then return false end
 f:write(tostring(value));f:close()
 if not os.rename(self.interval_path..".tmp",self.interval_path) then return false end
 return value
end

function Server:loadHashIndex()
 if self.hashes then return end
 self.hashes={};self.names={}
 local ok,iter,dir_obj=pcall(lfs.dir,self.folder)
 if not ok or not iter then return end
 local extensions={jpg=true,jpeg=true,png=true,bmp=true}
 for name in iter,dir_obj do
  local ext=name:match("%.([^.]+)$")
  if name~="." and name~=".." and not name:match("^%._") and ext and extensions[ext:lower()] then
   local file=io.open(self.folder.."/"..name,"rb")
   if file then local bytes=file:read("*a");file:close();if bytes then self.hashes[sha256(bytes)]=name;self.names[name:lower()]=true end end
  end
 end
end

function Server:start()
 if self.listener then return true end
 local server, err = socket.bind("*", 8765)
 if not server then self.error = err; return false end
 server:settimeout(0)
 self.listener = server
 -- KOReader's stock firewall drops inbound TCP; permit this upload port on Wi-Fi only.
 if Device:isKindle() then
  os.execute("iptables -A INPUT -i wlan0 -p tcp --dport 8765 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT >/dev/null 2>&1; iptables -A OUTPUT -o wlan0 -p tcp --sport 8765 -m conntrack --ctstate ESTABLISHED -j ACCEPT >/dev/null 2>&1")
  self.firewall_open=true
 end
 return true
end

function Server:getURL()
 local udp = socket.udp()
 local ok = udp:setpeername("1.1.1.1", 53)
 local ip = ok and select(1, udp:getsockname())
 udp:close()
 if ip and ip ~= "0.0.0.0" then return "http://"..ip..":8765" end
end

function Server:handle(client, header, body)
 local request = header:match("^([^\r\n]+)") or ""
 local method, path = request:match("^(%S+)%s+(%S+)")
 if method=="GET" and path=="/settings" then
  return response(client,"200 OK",json.encode(self:getSlideshowSettings()),"application/json; charset=utf-8")
 end
 if method=="POST" and path=="/settings" then
  local ok,payload=pcall(json.decode,body or "")
  local saved=ok and type(payload)=="table" and self:saveSlideshowSettings(payload)
  if not saved then return response(client,"400 Bad Request",json.encode({error="Configurazione non salvata: in orizzontale massimo 4 widget, in verticale massimo 5."}),"application/json; charset=utf-8") end
  return response(client,"200 OK",json.encode(saved),"application/json; charset=utf-8")
 end
 if method=="POST" and path=="/update" then
  if not updateKeyMatches(self,header) then
   return response(client,"403 Forbidden",json.encode({error="Aggiornamento non autorizzato"}),"application/json; charset=utf-8")
  end
  local relative=header:match("[Xx]%-[Cc]asa%-[Uu]pdate%-[Ff]ile:%s*([^\r\n]+)") or ""
  local allowed=relative=="main.lua" or relative=="casa_model.lua" or relative=="casa_layout.lua" or relative=="photo_server.lua" or relative=="kitchen_server.lua" or relative=="_meta.lua" or relative=="core-input.lua" or relative:match("^icons/[%w%._%-]+%.svg$")
  if not allowed or relative:find("..",1,true) or not self.plugin_dir then
   return response(client,"400 Bad Request",json.encode({error="File di Casa non valido"}),"application/json; charset=utf-8")
  end
  if #body>512*1024 then return response(client,"413 Payload Too Large",json.encode({error="File troppo grande"}),"application/json; charset=utf-8") end
  local destination=relative=="core-input.lua" and (self.plugin_dir.."/../../frontend/device/input.lua") or (self.plugin_dir.."/"..relative)
  local temp=destination..".update-tmp"
  local file=io.open(temp,"wb")
  if not file then return response(client,"507 Insufficient Storage",json.encode({error="Spazio insufficiente"}),"application/json; charset=utf-8") end
  file:write(body);file:close()
  if not os.rename(temp,destination) then os.remove(temp);return response(client,"500 Internal Server Error",json.encode({error="Aggiornamento non completato"}),"application/json; charset=utf-8") end
  return response(client,"200 OK",json.encode({ok=true,file=relative,restart_required=true}),"application/json; charset=utf-8")
 end
 if method=="POST" and path=="/gameupload" then
  if not updateKeyMatches(self,header) then
   return response(client,"403 Forbidden",json.encode({error="Trasferimento non autorizzato"}),"application/json; charset=utf-8")
  end
  local name=header:match("[Xx]%-[Cc]asa%-[Gg]ame%-[Ff]ile:%s*([^\r\n]+)") or ""
  local allowed=name=="fbgnuboy" or name=="launch.sh" or name=="doom" or name=="doom1.wad" or name=="launch_doom.sh" or name:match("^[%w _%-%(%)%[%]%,%.!'&_+]+%.gb$")
  if not allowed or name:find("..",1,true) or name:find("/",1,true) or not self.games_dir then
   return response(client,"400 Bad Request",json.encode({error="Nome file gioco non valido"}),"application/json; charset=utf-8")
  end
  local limit=(name=="doom1.wad" or name=="doom") and 8*1024*1024 or 2*1024*1024
  if #body>limit then return response(client,"413 Payload Too Large",json.encode({error="File gioco troppo grande"}),"application/json; charset=utf-8") end
  local directory=self.games_dir
  lfs.mkdir(directory)
  if name:match("%.gb$") then directory=directory.."/ROMs";lfs.mkdir(directory) end
  local destination=directory.."/"..name
  local digest=sha256(body)
  local existing=io.open(destination,"rb")
  if existing then
   local old=existing:read("*a");existing:close()
   if old and sha256(old)==digest then
    return response(client,"200 OK",json.encode({ok=true,duplicate=true,file=name}),"application/json; charset=utf-8")
   end
  end
  local temp=destination..".part"
  local file=io.open(temp,"wb")
  if not file then return response(client,"507 Insufficient Storage",json.encode({error="Spazio giochi insufficiente"}),"application/json; charset=utf-8") end
  file:write(body);file:close()
  if not os.rename(temp,destination) then os.remove(temp);return response(client,"500 Internal Server Error",json.encode({error="Trasferimento gioco non completato"}),"application/json; charset=utf-8") end
  if name=="fbgnuboy" or name=="launch.sh" or name=="doom" or name=="launch_doom.sh" then os.execute("chmod 755 "..destination) end
  return response(client,"200 OK",json.encode({ok=true,file=name,bytes=#body}),"application/json; charset=utf-8")
 end
 if method=="POST" and path=="/gameremove" then
  if not updateKeyMatches(self,header) then
   return response(client,"403 Forbidden",json.encode({error="Rimozione non autorizzata"}),"application/json; charset=utf-8")
  end
  local name=header:match("[Xx]%-[Cc]asa%-[Gg]ame%-[Ff]ile:%s*([^\r\n]+)") or ""
  if not (name:match("^[%w _%-%(%)%[%]%,%.!'&_+]+%.gb$") or name=="fbgnuboy" or name=="launch.sh" or name=="doom" or name=="doom1.wad" or name=="launch_doom.sh") or name:find("..",1,true) or name:find("/",1,true) or not self.games_dir then
   return response(client,"400 Bad Request",json.encode({error="Nome file gioco non valido"}),"application/json; charset=utf-8")
  end
  local path=(name:match("%.gb$") and self.games_dir.."/ROMs/" or self.games_dir.."/")..name
  local file=io.open(path,"rb")
  if not file then return response(client,"404 Not Found",json.encode({error="Gioco non trovato"}),"application/json; charset=utf-8") end
  file:close()
  if not os.remove(path) then return response(client,"500 Internal Server Error",json.encode({error="Rimozione non completata"}),"application/json; charset=utf-8") end
  return response(client,"200 OK",json.encode({ok=true,file=name,removed=true}),"application/json; charset=utf-8")
 end
 if method=="POST" and path=="/gamesreset" then
  if not updateKeyMatches(self,header) then
   return response(client,"403 Forbidden",json.encode({error="Pulizia non autorizzata"}),"application/json; charset=utf-8")
  end
  if not self.games_dir then return response(client,"400 Bad Request",json.encode({error="Cartella giochi non disponibile"}),"application/json; charset=utf-8") end
  local removed=0
  local rom_dir=self.games_dir.."/ROMs"
  local ok,iter,dir_obj=pcall(lfs.dir,rom_dir)
  if ok and iter then
   for name in iter,dir_obj do
    if name~="." and name~=".." and name:lower():match("%.gb$") then
     if os.remove(rom_dir.."/"..name) then removed=removed+1 end
    end
   end
  end
  for _,name in ipairs({"fbgnuboy","launch.sh"}) do
   if os.remove(self.games_dir.."/"..name) then removed=removed+1 end
  end
  return response(client,"200 OK",json.encode({ok=true,removed=removed}),"application/json; charset=utf-8")
 end
 if method == "GET" then
  local page = [[<!doctype html>
<html lang="it"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="theme-color" content="#eef6fa"><title>Config Casa</title>
<style>
:root{color-scheme:light;--paper:#eef6fa;--surface:#fbfdff;--ink:#203746;--muted:#5c7180;--line:#d3e3ec;--green:#4a9bc4;--green-dark:#286d91;--sage:#e7f3f9;--gold:#c29a55}
*{box-sizing:border-box}html{min-height:100%;background:var(--paper)}body{min-height:100vh;margin:0;padding:24px 18px;display:grid;place-items:center;background:var(--paper);color:var(--ink);font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;-webkit-font-smoothing:antialiased}
main{width:min(100%,480px);padding:clamp(25px,7vw,42px);background:var(--surface);border:1px solid var(--line);border-radius:22px;box-shadow:0 16px 38px rgba(32,73,94,.10)}
.brand{display:flex;align-items:center;gap:10px;margin-bottom:27px;color:var(--green);font-family:Georgia,serif;font-size:21px;font-weight:700;letter-spacing:-.02em}.brand-mark{width:34px;height:34px;display:grid;place-items:center;border:1px solid #cbd7ca;border-radius:50%;background:var(--sage)}
h1{margin:0;font-family:Georgia,"Times New Roman",serif;font-size:clamp(34px,9vw,46px);font-weight:500;line-height:1.04;letter-spacing:-.035em} .intro{margin:16px 0 27px;color:var(--muted);font-size:16px;line-height:1.55}
.upload-input{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);clip-path:inset(50%);white-space:nowrap}.picker{min-height:128px;display:flex;align-items:center;gap:16px;padding:20px;border:1px dashed #92bfd4;border-radius:15px;background:#f2f8fb;cursor:pointer;transition:background .18s,border-color .18s}.picker:hover{background:#e5f2f8;border-color:var(--green)}.upload-input:focus-visible+.picker{outline:3px solid #78b9dc;outline-offset:3px}.picker-icon{width:48px;height:48px;flex:none;display:grid;place-items:center;border-radius:13px;background:#dceef7;color:var(--green)}.picker-copy strong{display:block;font-size:16px;line-height:1.3}.picker-copy span{display:block;margin-top:5px;color:var(--muted);font-size:13px;line-height:1.4}
.preview{margin-top:14px;overflow:hidden;border-radius:13px;background:#e7f0f4}.preview[hidden]{display:none}.preview img{display:block;width:100%;max-height:230px;object-fit:contain}.file-name{padding:9px 12px;color:var(--muted);font-size:13px;overflow-wrap:anywhere}
.interval{margin-top:24px;padding-top:19px;border-top:1px solid var(--line)}.interval-head{display:flex;align-items:baseline;justify-content:space-between;gap:12px}.interval-head label{font-size:15px;font-weight:600}.interval-value{color:var(--green);font-size:17px;font-weight:700;font-variant-numeric:tabular-nums}.range{display:block;width:100%;height:44px;margin:8px 0 0;accent-color:var(--green)}.range-ends{display:flex;justify-content:space-between;color:var(--muted);font-size:12px}.current-setting{margin:8px 0 0;color:var(--muted);font-size:12px;line-height:1.4}.current-setting[data-kind="error"]{color:#9a392c}.save-setting{width:auto;min-height:44px;margin:12px 0 0;padding:9px 15px;border:1px solid #92bfd4;border-radius:10px;background:transparent;color:var(--green);font-size:14px}.save-setting:hover:not(:disabled){background:var(--sage);color:var(--green-dark)}.save-setting:disabled{background:transparent;color:#567181;border-color:#c8d9e2;cursor:default}
.switch-row{display:flex;align-items:center;justify-content:space-between;gap:16px}.switch-label{font-size:15px;font-weight:600}.switch-help{margin:5px 0 0;color:var(--muted);font-size:13px;line-height:1.4}.switch{position:relative;flex:none;width:52px;height:32px}.switch input{position:absolute;width:1px;height:1px;opacity:0}.switch-track{position:absolute;inset:0;border-radius:20px;background:#c8d9e2;transition:background .2s;cursor:pointer}.switch-track:after{content:"";position:absolute;top:4px;left:4px;width:24px;height:24px;border-radius:50%;background:white;box-shadow:0 1px 3px #0002;transition:transform .2s}.switch input:checked+.switch-track{background:var(--green)}.switch input:checked+.switch-track:after{transform:translateX(20px)}.switch input:focus-visible+.switch-track{outline:3px solid #78b9dc;outline-offset:3px}.delay-head{margin-top:21px}.range:disabled{opacity:.4}
button{width:100%;min-height:54px;margin-top:17px;padding:14px 18px;border:0;border-radius:12px;background:var(--green);color:#fff;font:600 16px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;cursor:pointer;transition:background .18s,transform .18s}button:hover:not(:disabled){background:var(--green-dark)}button:active:not(:disabled){transform:translateY(1px)}button:focus-visible{outline:3px solid #78b9dc;outline-offset:3px}button:disabled{background:#aab7aa;color:#f8faf7;cursor:wait}.status{min-height:24px;margin:13px 0 0;color:var(--muted);font-size:13px;line-height:1.5}.status[data-kind="error"]{color:#9a392c}.status[data-kind="success"]{color:var(--green-dark)}.foot{margin-top:27px;padding-top:17px;border-top:1px solid var(--line);color:var(--muted);font-size:12px;line-height:1.55}.foot strong{color:var(--green-dark);font-weight:600}
.layout-editor{margin-top:22px}.layout-hint{color:var(--muted);font-size:12px;font-variant-numeric:tabular-nums}.preview-stage.is-portrait{width:min(100%,290px);aspect-ratio:3/4}.preview-stage{position:relative;width:min(100%,400px);aspect-ratio:4/3;margin:14px auto 0;overflow:hidden;border:2px solid var(--ink);background:#fff;color:#203746;box-shadow:0 8px 20px rgba(32,73,94,.11);touch-action:none;user-select:none}.preview-header{position:absolute;inset:0 0 auto;height:16%;display:flex;align-items:center;justify-content:space-between;padding:0 3.5%;border-bottom:1px solid #b1c8d4;font:600 clamp(8px,2.7vw,13px) -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}.preview-header strong{font-family:Georgia,serif;font-size:1.05em}.editor-canvas{position:absolute;top:16%;bottom:7%;left:0;right:0}.device-widget{position:absolute;min-width:0;min-height:0;display:flex;flex-direction:column;gap:3px;overflow:hidden;padding:3px;border:1px solid #7da4b9;background:#f5fafc;color:#1d2921;font:500 clamp(7px,2.2vw,11px) -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;touch-action:none;user-select:none;cursor:grab}.device-widget:active{cursor:grabbing}.device-widget.is-selected{outline:2px solid var(--green);outline-offset:1px;z-index:4}.device-widget[hidden]{display:none}.device-widget strong{font-size:1.05em}.weather-preview-main{display:flex;align-items:center;gap:7px}.weather-preview-main b{font-size:2em}.weather-preview-main span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.weather-preview-days{font-size:.9em;line-height:1.5}.photo-widget{padding:3px;background:#e9f4f9}.photo-placeholder{flex:1;display:grid;place-items:center;border:1px solid #bed4df;background:#f5fafc;color:#557384;font-weight:700;letter-spacing:.12em}.kitchen-preview b{font-size:2em;font-variant-numeric:tabular-nums}.kitchen-preview span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.calendar-preview-days{padding:3px 0;border-bottom:1px solid #c8d9e2;font-size:.8em}.calendar-preview-grid{line-height:1.55;font-size:.85em}.resize-handle{position:absolute;z-index:5;background:var(--green);touch-action:none}.resize-x{right:0;top:calc(50% - 13px);width:16px;height:26px;border-radius:4px 0 0 4px;cursor:ew-resize}.resize-y{left:calc(50% - 13px);bottom:0;width:26px;height:16px;border-radius:4px 4px 0 0;cursor:ns-resize}.resize-corner{right:0;bottom:0;width:22px;height:22px;border-radius:4px 0 0 0;cursor:nwse-resize}.resize-corner:before,.resize-corner:after{content:"";position:absolute;right:5px;bottom:5px;width:8px;height:1px;background:#fff;transform:rotate(-45deg);transform-origin:right center}.resize-corner:after{right:8px;bottom:8px;width:5px}.layout-actions{display:flex;justify-content:flex-end}.reset-layout{width:auto;min-height:42px;margin-top:10px}.preview-stage:after{content:"";position:absolute;inset:auto 0 0;height:7%;border-top:1px solid #c8d9e2;background:#eef6fa;pointer-events:none}@media(max-width:360px){.preview-stage{width:100%}.device-widget{padding:2px}.resize-corner{width:24px;height:24px}.resize-x{width:19px}.resize-y{height:19px}}
select,input[type=time]{width:100%;min-height:44px;margin-top:8px;padding:9px 11px;border:1px solid var(--line);border-radius:10px;background:var(--surface);color:var(--ink);font:500 15px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}select:focus-visible,input[type=time]:focus-visible{outline:3px solid #78b9dc;outline-offset:2px}.interval-head select{max-width:180px;margin:0}.interval-head input[type=time]{max-width:160px;margin:0}
@media(max-width:360px){body{padding:14px 10px}main{padding:23px 19px;border-radius:18px}.picker{padding:15px;gap:12px}.picker-icon{width:42px;height:42px}}

.layout-actions{display:flex;gap:10px;align-items:stretch;margin-top:12px}.layout-actions button{width:calc(50% - 5px);min-height:48px;margin:0;padding:10px 12px;font-size:14px}.layout-actions #save-setting{border-color:var(--green);background:var(--green);color:#fff}.layout-actions #save-setting:hover:not(:disabled){background:var(--green-dark);color:#fff}.layout-actions #reset-layout{border-color:#8dbbd3;background:#f4fafe;color:#286d91}.layout-actions #reset-layout:hover:not(:disabled){background:#e5f2f8;color:#205b79}.layout-actions button:disabled{opacity:.58}.preview-stage{max-width:100%;box-shadow:0 8px 20px rgba(32,73,94,.11)}.preview-stage.is-portrait{width:min(100%,360px);aspect-ratio:3/4}.device-widget{border-color:#7da4b9;background:#f5fafc}.device-widget.is-selected{outline-color:var(--green)}.photo-widget{background:#e9f4f9}.photo-placeholder{background:#f5fafc;color:#557384}.resize-handle{background:var(--green)}.photo-widget .resize-x{left:0;right:auto;border-radius:0 4px 4px 0}.photo-widget .resize-corner{left:0;right:auto;border-radius:0 4px 0 0;cursor:nesw-resize}.preview-stage:after{background:#eef6fa}
@media(max-width:520px){body{display:block;padding:max(12px,env(safe-area-inset-top)) 12px max(18px,env(safe-area-inset-bottom))}main{width:100%;max-width:480px;margin:0 auto;padding:clamp(20px,5vw,30px);border-radius:18px}.brand{margin-bottom:22px}.intro{margin-bottom:22px}.preview-stage{width:100%}.preview-stage.is-portrait{width:min(100%,360px)}.layout-actions{gap:8px}.layout-actions button{width:calc(50% - 4px);padding:9px 8px;font-size:13px}}
@media(max-width:350px){.layout-actions button{font-size:12px}.preview-stage.is-portrait{width:100%}.picker{gap:10px;padding:14px}.picker-icon{width:42px;height:42px}}
</style></head><body><main>
<div class="brand"><span class="brand-mark" aria-hidden="true"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M3.5 10.5 12 4l8.5 6.5v9a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1z"/><path d="M9 20.5v-6h6v6"/></svg></span>Casa · Config</div>
<h1>Configura<br>Casa.</h1><p class="intro">Personalizza la schermata del Kindle, la cornice digitale e la modalità notte. Puoi anche inviare le foto da qui.</p>
<form id="form" method="post" action="/upload" enctype="multipart/form-data">
<input class="upload-input" id="photo" type="file" name="photo" accept="image/*" multiple required>
<label class="picker" for="photo"><span class="picker-icon" aria-hidden="true"><svg width="25" height="25" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="8.5" cy="9" r="1.5"/><path d="m21 15-5-5L5 20"/></svg></span><span class="picker-copy"><strong>Scegli le foto</strong><span>Puoi selezionarne più di una · JPG, PNG o BMP</span></span></label>
<div class="preview" id="preview" hidden><div id="preview-frame"></div><div class="file-name" id="file-name"></div></div>
<button id="send" type="submit" disabled>Invia al Kindle</button><p class="status" id="status" aria-live="polite">Le foto grandi vengono ridotte automaticamente prima dell’invio.</p>
<section class="interval" aria-labelledby="interval-title"><div class="interval-head"><label id="interval-title" for="interval">Cambio foto ogni</label><span class="interval-value" id="interval-value">30 secondi</span></div><p class="switch-help">Vale sia per il riquadro Casa sia per la galleria a schermo intero.</p><input class="range" id="interval" type="range" min="5" max="300" step="5" value="30" aria-label="Intervallo tra le foto"><div class="range-ends"><span>5 secondi</span><span>5 minuti</span></div><p class="current-setting" id="current-setting" aria-live="polite">Leggo l’intervallo attuale dal Kindle…</p></section>
<section class="interval" aria-labelledby="screen-title"><div class="switch-row"><div><label class="switch-label" id="screen-title" for="screensaver">Avvia cornice digitale automaticamente</label><p class="switch-help">Solo foto a schermo intero, senza orologio o menu.</p></div><label class="switch"><input id="screensaver" type="checkbox"><span class="switch-track" aria-hidden="true"></span></label></div><div class="interval-head delay-head"><label for="delay">Avvia dopo</label><span class="interval-value" id="delay-value">1 minuto</span></div><input class="range" id="delay" type="range" min="15" max="600" step="15" value="60" aria-label="Attesa prima delle foto a schermo intero"><div class="range-ends"><span>15 secondi</span><span>10 minuti</span></div><p class="current-setting" id="screen-setting" aria-live="polite">Leggo le impostazioni del Kindle…</p></section>
<section class="interval"><div class="interval-head"><label for="screen-orientation">Orientamento del Kindle</label></div><select id="screen-orientation"><option value="landscape">Orizzontale · paesaggio</option><option value="portrait">Verticale · ritratto</option></select><div class="interval-head delay-head"><label for="night-mode">Modalità notte</label></div><select id="night-mode"><option value="manual">Manuale · pulsante nel menu Kindle</option><option value="automatic">Automatica · per orario</option></select><div class="interval-head delay-head"><label for="night-start">Da</label><label for="night-end">A</label></div><div class="interval-head"><input id="night-start" type="time" value="22:00"><input id="night-end" type="time" value="07:00"></div><p class="switch-help">Fuori da questi orari Casa usa il tema chiaro.</p>
<div class="switch-row delay-head"><label class="switch-label" for="widget-weather">Mostra meteo</label><label class="switch"><input id="widget-weather" type="checkbox" checked><span class="switch-track"></span></label></div>
<div class="switch-row delay-head"><label class="switch-label" for="widget-photo">Mostra foto</label><label class="switch"><input id="widget-photo" type="checkbox" checked><span class="switch-track"></span></label></div>
<div class="switch-row delay-head"><label class="switch-label" for="widget-calendar">Mostra calendario mensile</label><label class="switch"><input id="widget-calendar" type="checkbox"><span class="switch-track"></span></label></div>
<div class="switch-row delay-head"><label class="switch-label" for="widget-timer">Mostra timer cucina</label><label class="switch"><input id="widget-timer" type="checkbox"><span class="switch-track"></span></label></div>
<div class="switch-row delay-head"><label class="switch-label" for="widget-shopping">Mostra lista della spesa</label><label class="switch"><input id="widget-shopping" type="checkbox"><span class="switch-track"></span></label></div>
<p class="switch-help">Puoi mostrare al massimo 4 widget. <a id="kitchen-link" href="#">Apri Timer e lista della spesa ↗</a></p>
<div class="layout-editor"><div class="interval-head"><label>Anteprima della home</label><span class="layout-hint" id="layout-hint">Kindle 4 · orizzontale</span></div><p class="switch-help">I riquadri si agganciano alla griglia e non si sovrappongono. Trascinali per spostarli; usa i bordi per ridimensionarli.</p>
<div class="preview-stage" aria-label="Anteprima configurabile della schermata Casa"><div class="preview-header"><strong>KindHome</strong><span>Mercoledì 09:41</span></div><div id="editor-canvas" class="editor-canvas">
<div class="device-widget weather-widget" data-widget="weather"><strong>Meteo locale</strong><div class="weather-preview-main"><b>22°</b><span>Parz. nuvoloso</span></div><div class="weather-preview-days">Oggi&nbsp;&nbsp; 20° / 25°<br>Domani&nbsp;&nbsp; 18° / 24°</div><span class="resize-handle resize-x" data-axis="x" aria-label="Allarga o restringi il meteo"></span><span class="resize-handle resize-y" data-axis="y" aria-label="Allunga o accorcia il meteo"></span><span class="resize-handle resize-corner" data-axis="both" aria-label="Ridimensiona il meteo in larghezza e altezza"></span></div>
<div class="device-widget photo-widget" data-widget="photo"><span class="photo-placeholder"><span>FOTO</span></span><span class="resize-handle resize-x" data-axis="x" aria-label="Allarga o restringi le foto"></span><span class="resize-handle resize-y" data-axis="y" aria-label="Allunga o accorcia le foto"></span><span class="resize-handle resize-corner" data-axis="both" aria-label="Ridimensiona le foto in larghezza e altezza"></span></div>
<div class="device-widget kitchen-preview" data-widget="timer"><strong>Timer cucina</strong><b>10:00</b><span>Pronto</span><span class="resize-handle resize-x" data-axis="x" aria-label="Ridimensiona timer"></span><span class="resize-handle resize-y" data-axis="y" aria-label="Ridimensiona timer"></span><span class="resize-handle resize-corner" data-axis="both" aria-label="Ridimensiona timer"></span></div>
<div class="device-widget kitchen-preview" data-widget="shopping"><strong>Lista spesa</strong><span>□ Pomodori</span><span>□ Pasta</span><span class="resize-handle resize-x" data-axis="x" aria-label="Ridimensiona lista"></span><span class="resize-handle resize-y" data-axis="y" aria-label="Ridimensiona lista"></span><span class="resize-handle resize-corner" data-axis="both" aria-label="Ridimensiona lista"></span></div>
<div class="device-widget calendar-widget" data-widget="calendar"><strong>Novembre 2026</strong><span class="calendar-preview-days">Lun&nbsp; Mar&nbsp; Mer&nbsp; Gio&nbsp; Ven&nbsp; Sab&nbsp; Dom</span><span class="calendar-preview-grid">1&nbsp; 2&nbsp; 3&nbsp; 4&nbsp; 5&nbsp; 6&nbsp; 7<br>8&nbsp; 9&nbsp; 10&nbsp; 11&nbsp; 12&nbsp; 13<br>15&nbsp; 16&nbsp; 17&nbsp; 18&nbsp; 19&nbsp; 20</span><span class="resize-handle resize-x" data-axis="x" aria-label="Allarga o restringi il calendario"></span><span class="resize-handle resize-y" data-axis="y" aria-label="Allunga o accorcia il calendario"></span><span class="resize-handle resize-corner" data-axis="both" aria-label="Ridimensiona il calendario in larghezza e altezza"></span></div>
</div></div><p class="current-setting" id="config-setting" aria-live="polite">Carico la configurazione del Kindle…</p><div class="layout-actions"><button class="save-setting reset-layout" id="reset-layout" type="button">Ripristina</button><button class="save-setting" id="save-setting" type="button" disabled>Salva configurazione</button></div></section>
</form><div class="foot"><strong>Resta tutto in casa.</strong> L’invio avviene sulla rete Wi‑Fi locale; il Kindle e il telefono devono essere collegati alla stessa rete.</div>
</main>
<script>
(function(){var input=document.getElementById('photo'),form=document.getElementById('form'),button=document.getElementById('send'),status=document.getElementById('status'),preview=document.getElementById('preview'),previewFrame=document.getElementById('preview-frame'),fileName=document.getElementById('file-name'),interval=document.getElementById('interval'),intervalValue=document.getElementById('interval-value'),currentSetting=document.getElementById('current-setting'),saveSetting=document.getElementById('save-setting'),screensaver=document.getElementById('screensaver'),delay=document.getElementById('delay'),delayValue=document.getElementById('delay-value'),screenSetting=document.getElementById('screen-setting'),nightMode=document.getElementById('night-mode'),nightStart=document.getElementById('night-start'),nightEnd=document.getElementById('night-end'),weather=document.getElementById('widget-weather'),photoWidget=document.getElementById('widget-photo'),calendar=document.getElementById('widget-calendar'),timerWidget=document.getElementById('widget-timer'),shoppingWidget=document.getElementById('widget-shopping'),screenOrientation=document.getElementById('screen-orientation'),stage=document.querySelector('.preview-stage'),configSetting=document.getElementById('config-setting'),kitchenLink=document.getElementById('kitchen-link'),canvas=document.getElementById('editor-canvas'),resetLayout=document.getElementById('reset-layout'),widgets={},objectUrl=null,previewImage=null,savedInterval=30,savedEnabled=false,savedDelay=60,widgetLayout=defaultLayout(),drag=null;
function defaultLayout(){return{weather:{x:0,y:0,w:46,h:46},photo:{x:46,y:0,w:54,h:100},calendar:{x:0,y:46,w:46,h:54},timer:{x:0,y:46,w:23,h:54},shopping:{x:23,y:46,w:23,h:54}}}['weather','photo','calendar','timer','shopping'].forEach(function(name){widgets[name]=canvas.querySelector('[data-widget="'+name+'"]')});
if(location.protocol!=='file:'){kitchenLink.href='http://'+location.hostname+':8766';}else{kitchenLink.hidden=true}function seconds(value){if(value<60)return value+' secondi';var minutes=Math.floor(value/60),rest=value%60;if(!rest)return minutes+(minutes===1?' minuto':' minuti');return minutes+' min e '+rest+' s'}function showInterval(value){interval.value=value;intervalValue.textContent=seconds(Number(value))}function showDelay(value){delay.value=value;delayValue.textContent=seconds(Number(value));delay.disabled=!screensaver.checked}function dirty(){saveSetting.disabled=false}interval.addEventListener('input',function(){showInterval(Number(interval.value));dirty()});screensaver.addEventListener('change',function(){showDelay(Number(delay.value));dirty()});delay.addEventListener('input',function(){showDelay(Number(delay.value));dirty()});[nightMode,nightStart,nightEnd,weather,photoWidget,calendar,timerWidget,shoppingWidget,screenOrientation].forEach(function(el){el.addEventListener('change',function(){syncVisibility();dirty()})});
var visibilityState={weather:false,photo:false,calendar:false,timer:false,shopping:false};function intersects(a,b,gap){gap=gap||0;return a.x<b.x+b.w+gap&&a.x+a.w+gap>b.x&&a.y<b.y+b.h+gap&&a.y+a.h+gap>b.y}function writeWidget(name){var p=widgetLayout[name],el=widgets[name];el.style.left=p.x+'%';el.style.top=p.y+'%';el.style.width=p.w+'%';el.style.height=p.h+'%'}function placeActiveGrid(next){var names=Object.keys(next).filter(function(name){return next[name]}),columns=2,rows=Math.ceil(names.length/columns);names.forEach(function(name,index){var col=index%columns,row=Math.floor(index/columns),cellW=100/columns,cellH=100/rows;widgetLayout[name]={x:Math.round(col*cellW),y:Math.round(row*cellH),w:Math.round(cellW),h:Math.round(cellH)};writeWidget(name)})}function syncVisibility(){var next={weather:weather.checked,photo:photoWidget.checked,calendar:calendar.checked,timer:timerWidget.checked,shopping:shoppingWidget.checked};var names=Object.keys(next).filter(function(name){return next[name]}),limit=4;if(names.length>limit){var changed=[timerWidget,shoppingWidget,calendar,photoWidget,weather].find(function(el){return el===document.activeElement});if(changed)changed.checked=false;configSetting.textContent='Puoi mostrare al massimo 4 widget. Disattivane uno per aggiungerne un altro.';dirty();next={weather:weather.checked,photo:photoWidget.checked,calendar:calendar.checked,timer:timerWidget.checked,shopping:shoppingWidget.checked};names=Object.keys(next).filter(function(name){return next[name]})}Object.keys(widgets).forEach(function(name){widgets[name].hidden=!next[name]});var added=names.some(function(name){return next[name]&&!visibilityState[name]});var overlap=names.some(function(name,index){return names.slice(index+1).some(function(other){return intersects(widgetLayout[name],widgetLayout[other])})});if(added&&overlap){placeActiveGrid(next);configSetting.textContent='Riquadri disposti automaticamente senza sovrapposizioni. Puoi trascinarli e ridimensionarli.'}visibilityState=next}function syncOrientation(){var portrait=screenOrientation.value==='portrait';stage.classList.toggle('is-portrait',portrait);document.getElementById('layout-hint').textContent='Kindle 4 · '+(portrait?'verticale':'orizzontale')}screenOrientation.addEventListener('change',syncOrientation);function paintLayout(layout){var clean=defaultLayout();['weather','photo','calendar','timer','shopping'].forEach(function(name){var v=layout&&layout[name]||clean[name],x=Number(v.x),y=Number(v.y),w=Number(v.w),h=Number(v.h),min=name==='weather'?{w:35,h:30}:name==='photo'?{w:25,h:30}:name==='calendar'?{w:30,h:35}:{w:20,h:24};x=Math.max(0,Math.min(100-min.w,isFinite(x)?x:clean[name].x));y=Math.max(0,Math.min(100-min.h,isFinite(y)?y:clean[name].y));w=Math.max(min.w,Math.min(100-x,isFinite(w)?w:clean[name].w));h=Math.max(min.h,Math.min(100-y,isFinite(h)?h:clean[name].h));widgetLayout[name]={x:Math.round(x),y:Math.round(y),w:Math.round(w),h:Math.round(h)};writeWidget(name)});visibilityState={weather:false,photo:false,calendar:false,timer:false,shopping:false};syncVisibility()}
function applySetting(data,isPreview){savedInterval=Math.max(5,Math.min(300,Math.round(Number(data.interval_seconds||30)/5)*5));savedEnabled=data.screensaver_enabled===true;savedDelay=Math.max(15,Math.min(600,Math.round(Number(data.screensaver_delay_seconds||60)/15)*15));screensaver.checked=savedEnabled;showInterval(savedInterval);showDelay(savedDelay);nightMode.value=data.night_mode||'manual';nightStart.value=data.night_start||'22:00';nightEnd.value=data.night_end||'07:00';screenOrientation.value=data.screen_orientation||'landscape';syncOrientation();weather.checked=data.weather_enabled!==false;photoWidget.checked=data.photo_enabled!==false;calendar.checked=data.calendar_enabled===true;timerWidget.checked=data.timer_enabled===true;shoppingWidget.checked=data.shopping_enabled===true;paintLayout(data.widget_layout);saveSetting.disabled=!!isPreview;currentSetting.textContent=(isPreview?'Anteprima · ':'Attualmente sul Kindle: ')+seconds(savedInterval);screenSetting.textContent='Cornice '+(savedEnabled?'attiva':'disattivata')+(savedEnabled?' · dopo '+seconds(savedDelay):'');configSetting.textContent=(isPreview?'Anteprima · ':'Sul Kindle · ')+(nightMode.value==='automatic'?'notte '+nightStart.value+'–'+nightEnd.value:'notte manuale')}
function getPreview(){var data={settings_version:4,interval_seconds:30,screensaver_enabled:false,screensaver_delay_seconds:60,night_mode:'manual',night_enabled:false,night_start:'22:00',night_end:'07:00',weather_enabled:true,photo_enabled:true,calendar_enabled:false,timer_enabled:true,shopping_enabled:true,screen_orientation:'landscape',widget_layout:defaultLayout()};try{data=JSON.parse(localStorage.getItem('casa_slideshow_settings')||JSON.stringify(data))}catch(_e){}if(Number(data.settings_version||0)<3){data.widget_layout=defaultLayout();data.settings_version=4}return data}function saveAll(){var payload={settings_version:4,interval_seconds:Number(interval.value),screensaver_enabled:screensaver.checked,screensaver_delay_seconds:Number(delay.value),night_mode:nightMode.value,night_start:nightStart.value,night_end:nightEnd.value,weather_enabled:weather.checked,photo_enabled:photoWidget.checked,calendar_enabled:calendar.checked,timer_enabled:timerWidget.checked,shopping_enabled:shoppingWidget.checked,screen_orientation:screenOrientation.value,widget_layout:widgetLayout};if(nightMode.value==='automatic')payload.night_enabled=false;if(location.protocol==='file:'){try{localStorage.setItem('casa_slideshow_settings',JSON.stringify(payload))}catch(_e){}applySetting(payload,true);currentSetting.textContent='Anteprima · '+seconds(payload.interval_seconds);saveSetting.disabled=false;return}saveSetting.disabled=true;configSetting.textContent='Salvo la configurazione sul Kindle…';fetch('/settings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}).then(function(r){return r.json().then(function(v){if(!r.ok)throw new Error(v.error||'Configurazione non salvata');return v})}).then(function(data){applySetting(data,false);configSetting.textContent='Configurazione salvata · layout applicato in Casa';saveSetting.disabled=false}).catch(function(e){configSetting.dataset.kind='error';configSetting.textContent=e.message||'Non riesco a salvare. Verifica che Casa sia aperta e riprova.';saveSetting.disabled=false})}saveSetting.addEventListener('click',saveAll);resetLayout.addEventListener('click',function(){paintLayout(defaultLayout());dirty();configSetting.textContent='Disposizione originale ripristinata · salva per inviarla al Kindle'});
canvas.addEventListener('pointerdown',function(e){var el=e.target.closest('.device-widget');if(!el||el.hidden)return;e.preventDefault();var name=el.dataset.widget,handle=e.target.closest('.resize-handle'),rect=canvas.getBoundingClientRect(),mode=handle?(handle.dataset.axis||'both'):'move';if(name==='photo'&&handle&&(mode==='x'||mode==='both'))mode=mode==='both'?'left-both':'left-x';Object.keys(widgets).forEach(function(k){widgets[k].classList.toggle('is-selected',k===name)});drag={name:name,mode:mode,startX:e.clientX,startY:e.clientY,rect:rect,initial:Object.assign({},widgetLayout[name]),last:Object.assign({},widgetLayout[name])};if(el.setPointerCapture){try{el.setPointerCapture(e.pointerId)}catch(_e){}}});window.addEventListener('pointermove',function(e){if(!drag)return;var initial=drag.initial,dx=(e.clientX-drag.startX)/drag.rect.width*100,dy=(e.clientY-drag.startY)/drag.rect.height*100,min=drag.name==='weather'?{w:35,h:30}:drag.name==='photo'?{w:25,h:30}:drag.name==='calendar'?{w:30,h:35}:{w:20,h:24},p={x:initial.x,y:initial.y,w:initial.w,h:initial.h};function snap(v){return Math.round(v)}if(drag.mode==='move'){p.x=Math.max(0,Math.min(100-p.w,snap(initial.x+dx)));p.y=Math.max(0,Math.min(100-p.h,snap(initial.y+dy)))}else if(drag.mode==='left-x'||drag.mode==='left-both'){var right=initial.x+initial.w;p.x=Math.max(0,Math.min(right-min.w,snap(initial.x+dx)));p.w=right-p.x;if(drag.mode==='left-both')p.h=Math.max(min.h,Math.min(100-initial.y,snap(initial.h+dy)))}else{if(drag.mode==='x'||drag.mode==='both')p.w=Math.max(min.w,Math.min(100-p.x,snap(initial.w+dx)));if(drag.mode==='y'||drag.mode==='both')p.h=Math.max(min.h,Math.min(100-p.y,snap(initial.h+dy)))}function collides(candidate){return Object.keys(widgets).some(function(other){return other!==drag.name&&!widgets[other].hidden&&intersects(candidate,widgetLayout[other])})}if(drag.mode!=='move'){while(collides(p)&&(p.w>min.w||p.h>min.h)){if((drag.mode==='left-x'||drag.mode==='left-both')&&p.w>min.w){p.x=Math.min(100-min.w,p.x+1);p.w=Math.max(min.w,p.w-1)}else if((drag.mode==='x'||drag.mode==='both')&&p.w>min.w)p.w=Math.max(min.w,p.w-1);else if((drag.mode==='y'||drag.mode==='both'||drag.mode==='left-both')&&p.h>min.h)p.h=Math.max(min.h,p.h-1);else break}}if((drag.mode==='move'&&!collides(p))||(drag.mode!=='move'&&!collides(p))){widgetLayout[drag.name]=p;drag.last=Object.assign({},p);writeWidget(drag.name);dirty()}else if(drag.mode==='move'){widgetLayout[drag.name]=drag.last;writeWidget(drag.name)}});function endDrag(){if(drag){drag=null;configSetting.textContent='Disposizione agganciata alla griglia · salva per applicarla sul Kindle'}}window.addEventListener('pointerup',endDrag);window.addEventListener('pointercancel',endDrag);
if(location.protocol==='file:'){applySetting(getPreview(),true);saveSetting.disabled=false}else{fetch('/settings',{cache:'no-store'}).then(function(r){if(!r.ok)throw new Error('settings');return r.json()}).then(function(data){applySetting(data,false)}).catch(function(){configSetting.textContent='Non riesco a leggere la configurazione attuale del Kindle.';configSetting.dataset.kind='error';interval.disabled=true;screensaver.disabled=true;saveSetting.disabled=true})}
input.addEventListener('change',function(){var files=Array.prototype.slice.call(input.files||[]),file=files[0];button.disabled=files.length===0;button.textContent=files.length?'Invia '+files.length+(files.length===1?' foto':' foto'): 'Invia al Kindle';status.dataset.kind='';status.textContent=files.length?files.length+(files.length===1?' foto pronta.':' foto pronte.'):'Le foto grandi vengono ridotte automaticamente prima dell’invio.';if(objectUrl)URL.revokeObjectURL(objectUrl);if(file){objectUrl=URL.createObjectURL(file);if(!previewImage){previewImage=document.createElement('img');previewImage.alt='Anteprima della prima foto scelta';previewFrame.appendChild(previewImage)}previewImage.src=objectUrl;fileName.textContent=files.length===1?file.name:files.length+' foto selezionate';preview.hidden=false}else{preview.hidden=true;if(previewImage)previewImage.removeAttribute('src')}});
function compress(file){return createImageBitmap(file).then(function(bitmap){var scale=Math.min(1,1200/Math.max(bitmap.width,bitmap.height)),canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));canvas.getContext('2d').drawImage(bitmap,0,0,canvas.width,canvas.height);bitmap.close();return new Promise(function(resolve,reject){canvas.toBlob(function(blob){blob?resolve(blob):reject(new Error('compress'))},'image/jpeg',.78)})})}
form.addEventListener('submit',function(e){var files=Array.prototype.slice.call(input.files||[]);if(!files.length)return;if(!window.createImageBitmap)return;e.preventDefault();button.disabled=true;saveSetting.disabled=true;status.dataset.kind='';var totals={saved:0,duplicates:0,invalid:0};function sendAt(index){if(index>=files.length){status.dataset.kind=totals.saved?'success':'';status.textContent=totals.saved+' foto aggiunte';if(totals.duplicates)status.textContent+=' · '+totals.duplicates+' duplicati scartati';if(totals.invalid)status.textContent+=' · '+totals.invalid+' file non validi ignorati';status.textContent+='.';input.value='';preview.hidden=true;if(previewImage)previewImage.removeAttribute('src');button.disabled=true;button.textContent='Scegli altre foto';saveSetting.disabled=Number(interval.value)===savedInterval;return}status.textContent='Preparo la foto '+(index+1)+' di '+files.length+'…';compress(files[index]).then(function(blob){var data=new FormData(),name=files[index].name.replace(/\.[^.]+$/,'')+'.jpg';data.append('photo',blob,name);status.textContent='Invio la foto '+(index+1)+' di '+files.length+'…';return fetch('/upload',{method:'POST',headers:{Accept:'application/json'},body:data}).then(function(r){if(!r.ok)throw new Error('upload');return r.json()})}).then(function(result){totals.saved+=result.saved_count||0;totals.duplicates+=result.duplicate_count||0;totals.invalid+=result.invalid_count||0;sendAt(index+1)}).catch(function(){status.dataset.kind='error';status.textContent='Invio interrotto alla foto '+(index+1)+'. Le foto già ricevute restano in Casa; riprova con le altre.';button.disabled=false;button.textContent='Riprova invio';saveSetting.disabled=Number(interval.value)===savedInterval})}sendAt(0)});
})();
</script></body></html>]]
  return response(client, "200 OK", page)
 end
 if method ~= "POST" or path ~= "/upload" then return response(client, "404 Not Found", "Pagina non trovata", "text/plain") end
 local content_type = header:match("[Cc]ontent%-[Tt]ype:%s*([^\r\n]+)") or ""
 local boundary = content_type:match("boundary=([^;]+)")
 if boundary then boundary = boundary:gsub('^"', ""):gsub('"$', "") end
 if not boundary then return response(client, "400 Bad Request", "Modulo foto non valido", "text/plain") end
 local marker="--"..boundary
 local cursor,saved,duplicates,invalid=1,0,0,0
 local saved_names={}
 self:loadHashIndex()
 self.last_added_files={}
 while true do
  local part_start=body:find(marker,cursor,true)
  if not part_start or body:sub(part_start+#marker,part_start+#marker+1)=="--" then break end
  local headers_start=part_start+#marker+2
  local headers_end=body:find("\r\n\r\n",headers_start,true)
  if not headers_end then break end
  local data_start=headers_end+4
  local data_end=body:find("\r\n"..marker,data_start,true)
  if not data_end then break end
  local headers=body:sub(headers_start,headers_end-1)
  local original_name=headers:match('[Ff]ilename="([^"]*)"')
  if original_name and original_name~="" then
   local filename=safeFilename(original_name)
   local image=body:sub(data_start,data_end-1)
   if filename and #image>0 then
    local digest=sha256(image)
    if self.hashes[digest] or self.names[filename:lower()] then
     duplicates=duplicates+1
    else
     local destination=self.folder.."/"..filename
     local existing=io.open(destination,"rb")
     if existing then
      existing:close()
      local ext=filename:match("(%.[^.]+)$") or ".jpg"
      local stem=filename:sub(1,#filename-#ext)
      local suffix=1
      repeat
       destination=self.folder.."/"..stem.."-"..os.time().."-"..suffix..ext
       existing=io.open(destination,"rb")
       if existing then existing:close();suffix=suffix+1 end
      until not existing
     end
     local temp=destination..".part"
     local file=io.open(temp,"wb")
     if file then
      file:write(image);file:close()
      if os.rename(temp,destination) then
       saved=saved+1;saved_names[#saved_names+1]=destination
       self.last_added_files[#self.last_added_files+1]=destination
       self.hashes[digest]=destination
       self.names[filename:lower()]=true
      else invalid=invalid+1;os.remove(temp) end
     else invalid=invalid+1 end
    end
   else invalid=invalid+1 end
  end
  cursor=data_end+2
 end
 if saved>0 then
  self.upload_seq=(self.upload_seq or 0)+saved
  self.last_upload=saved_names[#saved_names]
 end
 local wants_json=(header:match("[Aa]ccept:%s*([^\r\n]+)") or ""):find("application/json",1,true)~=nil
 if wants_json then
  return response(client,"200 OK",json.encode({saved_count=saved,duplicate_count=duplicates,invalid_count=invalid,files=saved_names}),"application/json; charset=utf-8")
 end
 local message=saved>0 and (saved..(saved==1 and " foto aggiunta" or " foto aggiunte").." alla galleria.") or "Nessuna nuova foto aggiunta."
 if duplicates>0 then message=message.." "..duplicates..(duplicates==1 and " duplicato scartato." or " duplicati scartati.") end
 return response(client,"200 OK","<!doctype html><html lang='it'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Foto ricevute</title><body><h1>Invio completato</h1><p>"..message.."</p><p>Le nuove foto compaiono subito in Casa.</p></body></html>")
end

function Server:poll()
 if not self.listener then return end
 local client = self.listener:accept()
 if client then client:settimeout(0);self.clients[#self.clients+1]={socket=client,buffer="",started=os.time()} end
 for i=#self.clients,1,-1 do
  local item=self.clients[i]
  local data,err,partial=item.socket:receive(65536)
  item.buffer=item.buffer..(data or partial or "")
  local sep=item.buffer:find("\r\n\r\n",1,true)
  if sep and not item.header then
   item.header=item.buffer:sub(1,sep-1)
   item.body_start=sep+4
   item.expected=tonumber(item.header:match("[Cc]ontent%-[Ll]ength:%s*(%d+)")) or 0
   local game_upload=item.header:match("^POST%s+/gameupload%s")~=nil
   local limit=game_upload and 8*1024*1024 or 20*1024*1024
   if item.expected>limit then response(item.socket,"413 Payload Too Large",game_upload and "File gioco troppo grande (massimo 2 MB)" or "Foto troppo grande (massimo 20 MB)","text/plain");table.remove(self.clients,i);item=nil
   elseif item.expected==0 then self:handle(item.socket,item.header,"");table.remove(self.clients,i);item=nil end
  end
  if item and item.header and #item.buffer-item.body_start+1>=item.expected then
   self:handle(item.socket,item.header,item.buffer:sub(item.body_start,item.body_start+item.expected-1))
   table.remove(self.clients,i);item=nil
  end
  if item and (os.time()-item.started>90 or err and err~="timeout" and not partial) then
   pcall(function() item.socket:close() end);table.remove(self.clients,i)
  end
 end
end

function Server:close()
 if self.listener then pcall(function() self.listener:close() end);self.listener=nil end
 if self.firewall_open then
  os.execute("iptables -D INPUT -i wlan0 -p tcp --dport 8765 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT >/dev/null 2>&1; iptables -D OUTPUT -o wlan0 -p tcp --sport 8765 -m conntrack --ctstate ESTABLISHED -j ACCEPT >/dev/null 2>&1")
  self.firewall_open=nil
 end
 for _,item in ipairs(self.clients) do pcall(function() item.socket:close() end) end
 self.clients={}
end

return Server

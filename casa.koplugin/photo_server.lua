local socket = require("socket")
local Device = require("device")
local json = require("json")
local sha256 = require("ffi/sha2").sha256
local lfs = require("libs/libkoreader-lfs")
local I18N = require("casa_i18n")

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
local function validClock(value,fallback)
 if type(value)~="string" then return fallback end
 local hour,minute=value:match("^(%d%d):(%d%d)$")
 hour,minute=tonumber(hour),tonumber(minute)
 if not hour or not minute or hour>23 or minute>59 then return fallback end
 return string.format("%02d:%02d",hour,minute)
end
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

local function response(client, status, body, content_type, cache_control)
 body = body or ""
 if content_type and content_type:find("^text/plain") then body=I18N.tr(body) end
 local message = "HTTP/1.1 "..status.."\r\nContent-Type: "..(content_type or "text/html; charset=utf-8")
  .."\r\nContent-Length: "..#body.."\r\nConnection: close\r\nCache-Control: "..(cache_control or "no-store").."\r\n\r\n"..body
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

local function validPhotoName(name)
 if type(name)~="string" or name=="" or name=="." or name==".." or name:find("/",1,true) or name:find("\\",1,true) or name:find("..",1,true) or name:find("\r",1,true) or name:find("\n",1,true) then return false end
 local ext=(name:match("%.([^.]+)$") or ""):lower()
 return ext=="jpg" or ext=="jpeg" or ext=="png" or ext=="bmp"
end

function Server:new(folder, interval_path, plugin_dir, update_key_path, games_dir)
 return setmetatable({folder=folder, interval_path=interval_path or (folder.."/intervallo-foto.txt"),
  plugin_dir=plugin_dir, update_key_path=update_key_path, games_dir=games_dir, clients={}}, self)
end

local PHOTO_PROFILES={"widget_square","widget_wide","fullscreen"}
local function safePhotoSetting(value)
 value=type(value)=="table" and value or {}
 local rotation=tonumber(value.rotation) or 0
 if rotation~=0 and rotation~=90 and rotation~=180 and rotation~=270 then rotation=0 end
 return {zoom=math.max(1,math.min(3,tonumber(value.zoom) or 1)),rotation=rotation,
  mirror=value.mirror==true,center_x=math.max(0,math.min(1,tonumber(value.center_x) or 0.5)),
  center_y=math.max(0,math.min(1,tonumber(value.center_y) or 0.5))}
end

function Server:getPhotoSettings()
 local file=io.open(self.folder.."/.kindhome-photo-settings.json","rb")
 if not file then return {} end
 local raw=file:read("*a");file:close()
 local ok,data=pcall(json.decode,raw)
 return ok and type(data)=="table" and data or {}
end

function Server:getPhotoSetting(filename,profile)
 if not validPhotoName(filename) then return safePhotoSetting(nil) end
 local all=self:getPhotoSettings()
 local photo=type(all[filename])=="table" and all[filename] or {}
 return safePhotoSetting(photo[profile])
end

function Server:addWifiProfile(ssid,password)
 if type(ssid)~="string" or type(password)~="string" then return false,"Inserisci nome rete e password." end
 ssid=ssid:gsub("[%c]",""):match("^%s*(.-)%s*$") or ""
 if #ssid<1 or #ssid>32 or #password<8 or #password>63 then return false,"Controlla nome rete e password WPA (8–63 caratteri)." end
 local manager=self.network_manager
 if manager and manager.saveNetwork then
  pcall(manager.saveNetwork,manager,{ssid=ssid,password=password,flags="[WPA-PSK][ESS]"})
 end
 local ok,lipc=pcall(require,"libopenlipclua")
 if not ok or not lipc then return false,"Il Kindle non espone il servizio per salvare la rete." end
 local opened,handle=pcall(lipc.open_no_name)
 if not opened or not handle then return false,"Non riesco ad aprire il servizio Wi‑Fi del Kindle." end
 local success=false
 local ran=pcall(function()
  local profile=handle:new_hasharray()
  profile:add_hash()
  profile:put_string(0,"essid",ssid)
  profile:put_string(0,"secured","yes")
  profile:put_string(0,"psk",password)
  profile:put_int(0,"store_nw_user_pref",0)
  local result=handle:access_hash_property("com.lab126.wifid","createProfile",profile)
  if result then result:destroy() end
  profile:destroy()
  success=true
 end)
 pcall(handle.close,handle)
 if not ran or not success then return false,"Il Kindle non ha accettato il profilo Wi‑Fi." end
 return true,ssid
end

function Server:importPendingWifiProfiles(path)
 local file=io.open(path,"rb")
 if not file then return 0 end
 local raw=file:read("*a");file:close()
 local ok,profiles=pcall(json.decode,raw or "")
 if not ok or type(profiles)~="table" then return 0 end
 local imported=0
 for _,profile in ipairs(profiles) do
  local saved=self:addWifiProfile(profile.ssid,profile.password)
  if saved then imported=imported+1 end
 end
 if imported==#profiles then os.remove(path) end
 return imported
end

function Server:savePhotoSettings(updates)
 if type(updates)~="table" or #updates<1 or #updates>500 then return false end
 local all=self:getPhotoSettings()
 for _,update in ipairs(updates) do
  local filename,profile=update.name,update.profile
  if not validPhotoName(filename) then return false end
  local valid=false
  for _,name in ipairs(PHOTO_PROFILES) do if profile==name then valid=true;break end end
  if not valid then return false end
  local exists=io.open(self.folder.."/"..filename,"rb")
  if not exists then return false end
  exists:close()
  all[filename]=type(all[filename])=="table" and all[filename] or {}
  all[filename][profile]=safePhotoSetting(update.setting)
 end
 local temp=self.folder.."/.kindhome-photo-settings.json.tmp"
 local file=io.open(temp,"wb")
 if not file then return false end
 file:write(json.encode(all));file:close()
 local saved=os.rename(temp,self.folder.."/.kindhome-photo-settings.json")
 if saved then self.photo_settings_seq=(self.photo_settings_seq or 0)+1 end
 return saved
end

function Server:savePhotoSetting(filename,profile,value)
 return self:savePhotoSettings({{name=filename,profile=profile,setting=value}})
end

local function photoMime(name)
 local ext=(name:match("%.([^.]+)$") or ""):lower()
 if ext=="png" then return "image/png" end
 if ext=="bmp" then return "image/bmp" end
 return "image/jpeg"
end

function Server:listPhotos()
 local photos={}
 local ok,iter,dir_obj=pcall(lfs.dir,self.folder)
 if ok and iter then
  for name in iter,dir_obj do
   if name~="." and name~=".." and not name:match("^%.") then
    if validPhotoName(name) and lfs.attributes(self.folder.."/"..name,"mode")=="file" then
     local ext=name:match("%.([^.]+)$")
     if ext and ({jpg=true,jpeg=true,png=true,bmp=true})[ext:lower()] then
      photos[#photos+1]={name=name,url="/photo-image?name="..name}
     end
    end
   end
  end
 end
 table.sort(photos,function(a,b) return a.name:lower()<b.name:lower() end)
 return photos
end

function Server:getPhotoThumbnail(name)
 if not validPhotoName(name) then return nil end
 local original=self.folder.."/"..name
 local attr=lfs.attributes(original)
 if not attr or attr.mode~="file" then return nil end
 local cache_dir=self.folder.."/.kindhome-thumbnails"
 if not lfs.attributes(cache_dir,"mode") then pcall(lfs.mkdir,cache_dir) end
 if not lfs.attributes(cache_dir,"mode") then return nil end
 local digest=sha256(name)
 local key={}
 for i=1,#digest do key[#key+1]=string.format("%02x",digest:byte(i)) end
 local destination=cache_dir.."/"..table.concat(key)..".jpg"
 local cached=io.open(destination,"rb")
 if cached then local image=cached:read("*a");cached:close();if image and #image>0 then return image end end
 local RenderImage=require("ui/renderimage")
 local source=RenderImage:renderImageFile(original,false)
 if not source then return nil end
 local width,height=source:getWidth(),source:getHeight()
 local scale=math.min(180/width,180/height,1)
 local thumb=RenderImage:scaleBlitBuffer(source,math.max(1,math.floor(width*scale)),math.max(1,math.floor(height*scale)),true)
 local ok=thumb:writeToFile(destination,"jpg",58)
 thumb:free()
 if not ok then return nil end
 local file=io.open(destination,"rb")
 if not file then return nil end
 local image=file:read("*a");file:close()
 return image
end

local function languageOptions()
 local out={}
 for _,l in ipairs(I18N.languages) do out[#out+1]='<option value="'..l.code..'">'..l.name..'</option>' end
 return table.concat(out)
end

local function validLanguage(code)
 if code=="auto" then return "auto" end
 return type(code)=="string" and I18N.name(code) and code or nil
end

local function validPlace(place)
 if type(place)~="table" or type(place.name)~="string" then return nil end
 local lat,lon=tonumber(place.latitude),tonumber(place.longitude)
 if not lat or not lon or lat<-90 or lat>90 or lon<-180 or lon>180 then return nil end
 local name=place.name:gsub("[%c]",""):match("^%s*(.-)%s*$") or ""
 if name=="" then return nil end
 return {name=name:sub(1,60),latitude=math.floor(lat*10000+0.5)/10000,longitude=math.floor(lon*10000+0.5)/10000}
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
 local power_button_enabled=false
 local power_button_action="photos"
 local standby_action="last_photo"
 local standby_orientation="auto"
 local standby_interval_seconds=120
 local show_clock_seconds=false
 local auto_standby_enabled=false
 local auto_standby_delay_seconds=300
 local auto_standby_start="00:00"
 local auto_standby_end="23:59"
 local server_mode="off"
 local battery_display_mode="percent_time"
 local home_name="Casa"
 local language="auto"
 local weather_place=nil
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
   timer_enabled=data.timer_enabled==nil and data.calendar_enabled~=true or data.timer_enabled==true
   shopping_enabled=data.shopping_enabled==nil and data.calendar_enabled~=true or data.shopping_enabled==true
   weather_enabled=data.weather_enabled~=false
   photo_enabled=data.photo_enabled~=false
   weather_side=data.weather_side=="right" and "right" or "left"
   photo_side=data.photo_side=="left" and "left" or "right"
   calendar_side=data.calendar_side=="left" and "left" or "right"
   screen_orientation=data.screen_orientation=="portrait" and "portrait" or "landscape"
   power_button_enabled=data.power_button_enabled==true
   standby_action=({system=true,last_photo=true,slideshow=true})[data.standby_action] and data.standby_action or "last_photo"
   standby_orientation=({auto=true,landscape=true,portrait=true})[data.standby_orientation] and data.standby_orientation or "auto"
   standby_interval_seconds=math.max(30,math.min(3600,math.floor((tonumber(data.standby_interval_seconds) or 120)+0.5)))
   show_clock_seconds=data.show_clock_seconds==true
   auto_standby_enabled=data.auto_standby_enabled==true
   auto_standby_delay_seconds=math.max(15,math.min(3600,math.floor((tonumber(data.auto_standby_delay_seconds) or 300)+0.5)))
   auto_standby_start=validClock(data.auto_standby_start,auto_standby_start)
   auto_standby_end=validClock(data.auto_standby_end,auto_standby_end)
   server_mode=({off=true,timeout=true,always=true})[data.server_mode] and data.server_mode or "off"
   battery_display_mode=({percent=true,remaining=true,percent_time=true})[data.battery_display_mode] and data.battery_display_mode or "percent_time"
   if type(data.home_name)=="string" then
    local candidate=data.home_name:gsub("[%c]",""):match("^%s*(.-)%s*$") or ""
    if candidate~="" then home_name=candidate:sub(1,48) end
   end
   local actions={photos=true,calendar=true,weather=true,timer=true,shopping=true,home=true,last_photo=true}
   power_button_action=actions[data.power_button_action] and data.power_button_action or "photos"
   language=validLanguage(data.language) or "auto"
   weather_place=validPlace(data.weather_place)
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
  widget_layout=widget_layout,screen_orientation=screen_orientation,power_button_enabled=power_button_enabled,power_button_action=power_button_action,standby_action=standby_action,standby_orientation=standby_orientation,standby_interval_seconds=standby_interval_seconds,show_clock_seconds=show_clock_seconds,
  auto_standby_enabled=auto_standby_enabled,auto_standby_delay_seconds=auto_standby_delay_seconds,
  auto_standby_start=auto_standby_start,auto_standby_end=auto_standby_end,server_mode=server_mode,
  battery_display_mode=battery_display_mode,home_name=home_name,language=language,weather_place=weather_place,settings_version=8}
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
 local power_button_enabled=payload.power_button_enabled==nil and current.power_button_enabled or payload.power_button_enabled==true
 local standby_action=payload.standby_action=="system" and "system" or payload.standby_action=="last_photo" and "last_photo" or current.standby_action or "last_photo"
 if payload.standby_action=="slideshow" then standby_action="slideshow" end
 local standby_orientation=({auto=true,landscape=true,portrait=true})[payload.standby_orientation] and payload.standby_orientation or current.standby_orientation or "auto"
 local standby_interval_seconds=math.max(30,math.min(3600,math.floor((tonumber(payload.standby_interval_seconds) or current.standby_interval_seconds or 120)+0.5)))
 local show_clock_seconds=payload.show_clock_seconds==nil and current.show_clock_seconds or payload.show_clock_seconds==true
 local auto_standby_enabled=payload.auto_standby_enabled==nil and current.auto_standby_enabled or payload.auto_standby_enabled==true
 local auto_standby_delay_seconds=tonumber(payload.auto_standby_delay_seconds) or current.auto_standby_delay_seconds
 auto_standby_delay_seconds=math.max(15,math.min(3600,math.floor(auto_standby_delay_seconds/15+0.5)*15))
 local auto_standby_start=validClock(payload.auto_standby_start,current.auto_standby_start)
 local auto_standby_end=validClock(payload.auto_standby_end,current.auto_standby_end)
 local server_mode=({off=true,timeout=true,always=true})[payload.server_mode] and payload.server_mode or current.server_mode
 local battery_display_mode=({percent=true,remaining=true,percent_time=true})[payload.battery_display_mode] and payload.battery_display_mode or current.battery_display_mode
 local home_name=current.home_name or "Casa"
 if type(payload.home_name)=="string" then
  local candidate=payload.home_name:gsub("[%c]",""):match("^%s*(.-)%s*$") or ""
  if candidate~="" then home_name=candidate:sub(1,48) end
 end
 local actions={photos=true,calendar=true,weather=true,timer=true,shopping=true,home=true,last_photo=true}
 local power_button_action=actions[payload.power_button_action] and payload.power_button_action or current.power_button_action
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
 local settings={settings_version=8,interval_seconds=interval,screensaver_enabled=enabled,screensaver_delay_seconds=delay,
  night_mode=night_mode,night_enabled=payload.night_enabled==nil and current.night_enabled or payload.night_enabled==true,
  night_start=type(payload.night_start)=="string" and payload.night_start:match("^%d%d:%d%d$") and payload.night_start or current.night_start,
  night_end=type(payload.night_end)=="string" and payload.night_end:match("^%d%d:%d%d$") and payload.night_end or current.night_end,
  calendar_enabled=payload.calendar_enabled==nil and current.calendar_enabled or payload.calendar_enabled==true,
  timer_enabled=timer_enabled,shopping_enabled=shopping_enabled,
  weather_enabled=payload.weather_enabled==nil and current.weather_enabled or payload.weather_enabled==true,
  photo_enabled=payload.photo_enabled==nil and current.photo_enabled or payload.photo_enabled==true,
  weather_side=side("weather_side","left"),photo_side=side("photo_side","right"),calendar_side=side("calendar_side","right"),
  widget_layout=widget_layout,
  screen_orientation=screen_orientation,power_button_enabled=power_button_enabled,power_button_action=power_button_action,standby_action=standby_action,standby_orientation=standby_orientation,standby_interval_seconds=standby_interval_seconds,show_clock_seconds=show_clock_seconds,
  auto_standby_enabled=auto_standby_enabled,auto_standby_delay_seconds=auto_standby_delay_seconds,
  auto_standby_start=auto_standby_start,auto_standby_end=auto_standby_end,server_mode=server_mode,
  battery_display_mode=battery_display_mode,home_name=home_name,
  language=payload.language~=nil and (validLanguage(payload.language) or "auto") or current.language,
  weather_place=payload.weather_place~=nil and validPlace(payload.weather_place) or current.weather_place}
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
 self.last_activity=os.time()
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
 self.last_activity=os.time()
 local request = header:match("^([^\r\n]+)") or ""
 local method, path = request:match("^(%S+)%s+(%S+)")
 if method=="GET" and path=="/settings" then
  return response(client,"200 OK",json.encode(self:getSlideshowSettings()),"application/json; charset=utf-8")
 end
 if method=="GET" and path:match("^/home%-preview") then
  local ok,preview=pcall(function() return self.home_preview and self.home_preview() end)
  if not ok or type(preview)~="string" or #preview==0 then
   return response(client,"503 Service Unavailable","La schermata Casa è disponibile quando il Kindle mostra la home.","text/plain; charset=utf-8")
  end
  return response(client,"200 OK",preview,"image/png")
 end
 if method=="GET" and path=="/photo-list" then
  return response(client,"200 OK",json.encode({photos=self:listPhotos(),settings=self:getPhotoSettings()}),"application/json; charset=utf-8")
 end
 if method=="GET" and path:match("^/photo%-image%?") then
  local name=path:match("[?&]name=([^&]+)") or ""
  name=name:gsub("%%(%x%x)",function(hex) return string.char(tonumber(hex,16)) end)
  if not validPhotoName(name) then return response(client,"400 Bad Request","Nome foto non valido","text/plain; charset=utf-8") end
  local file=io.open(self.folder.."/"..name,"rb")
  if not file then return response(client,"404 Not Found","Foto non trovata","text/plain; charset=utf-8") end
  local image=file:read("*a");file:close()
  return response(client,"200 OK",image,photoMime(name))
 end
 if method=="GET" and path:match("^/photo%-thumb%?") then
  local name=path:match("[?&]name=([^&]+)") or ""
  name=name:gsub("%%(%x%x)",function(hex) return string.char(tonumber(hex,16)) end)
  local ok,image=pcall(self.getPhotoThumbnail,self,name)
  if not ok or not image then return response(client,"404 Not Found","Miniatura non disponibile","text/plain; charset=utf-8") end
  return response(client,"200 OK",image,"image/jpeg","public, max-age=86400")
 end
 if method=="POST" and path=="/photo-settings" then
  local ok,payload=pcall(json.decode,body or "")
  local updates=ok and type(payload)=="table" and (type(payload.items)=="table" and payload.items or {{name=payload.name,profile=payload.profile,setting=payload.setting}}) or nil
  if not updates or not self:savePhotoSettings(updates) then
   return response(client,"400 Bad Request",json.encode({error=I18N.tr("Regolazione foto non salvata")}),"application/json; charset=utf-8")
  end
  return response(client,"200 OK",json.encode({ok=true,count=#updates,settings=self:getPhotoSettings()}),"application/json; charset=utf-8")
 end
 if method=="POST" and path=="/wifi" then
  local ok,payload=pcall(json.decode,body or "")
  if not ok or type(payload)~="table" then return response(client,"400 Bad Request",json.encode({error=I18N.tr("Dati Wi‑Fi non validi.")}),"application/json; charset=utf-8") end
  local saved,detail=self:addWifiProfile(payload.ssid,payload.password)
  if not saved then return response(client,"400 Bad Request",json.encode({error=I18N.tr(detail)}),"application/json; charset=utf-8") end
  return response(client,"200 OK",json.encode({ok=true,ssid=detail,message=I18N.tr("Rete salvata nel Kindle; si collegherà quando sarà nel raggio.")}),"application/json; charset=utf-8")
 end
 if method=="POST" and path=="/settings" then
  local ok,payload=pcall(json.decode,body or "")
  local saved=ok and type(payload)=="table" and self:saveSlideshowSettings(payload)
  if not saved then return response(client,"400 Bad Request",json.encode({error=I18N.tr("Configurazione non salvata: in orizzontale massimo 4 widget, in verticale massimo 5.")}),"application/json; charset=utf-8") end
  return response(client,"200 OK",json.encode(saved),"application/json; charset=utf-8")
 end
 if method=="POST" and (path=="/reboot" or path=="/restart-casa") then
  if not updateKeyMatches(self,header) then
   return response(client,"403 Forbidden",json.encode({error=I18N.tr("Riavvio non autorizzato")}),"application/json; charset=utf-8")
  end
  response(client,"200 OK",json.encode({ok=true,action=path:sub(2)}),"application/json; charset=utf-8")
  if path=="/reboot" then
   os.execute("(sleep 2 && reboot) >/dev/null 2>&1 &")
  else
   require("ui/uimanager"):scheduleIn(1,function() require("ui/uimanager"):restartKOReader() end)
  end
  return
 end
 if method=="POST" and path=="/update" then
  if not updateKeyMatches(self,header) then
   return response(client,"403 Forbidden",json.encode({error=I18N.tr("Aggiornamento non autorizzato")}),"application/json; charset=utf-8")
  end
  local relative=header:match("[Xx]%-[Cc]asa%-[Uu]pdate%-[Ff]ile:%s*([^\r\n]+)") or ""
  local allowed=relative=="main.lua" or relative=="casa_model.lua" or relative=="casa_layout.lua" or relative=="photo_server.lua" or relative=="kitchen_server.lua" or relative=="_meta.lua" or relative=="core-input.lua" or relative:match("^icons/[%w%._%-]+%.svg$")
  if not allowed or relative:find("..",1,true) or not self.plugin_dir then
   return response(client,"400 Bad Request",json.encode({error=I18N.tr("File di Casa non valido")}),"application/json; charset=utf-8")
  end
  if #body>512*1024 then return response(client,"413 Payload Too Large",json.encode({error=I18N.tr("File troppo grande")}),"application/json; charset=utf-8") end
  local destination=relative=="core-input.lua" and (self.plugin_dir.."/../../frontend/device/input.lua") or (self.plugin_dir.."/"..relative)
  local temp=destination..".update-tmp"
  local file=io.open(temp,"wb")
  if not file then return response(client,"507 Insufficient Storage",json.encode({error=I18N.tr("Spazio insufficiente")}),"application/json; charset=utf-8") end
  file:write(body);file:close()
  if not os.rename(temp,destination) then os.remove(temp);return response(client,"500 Internal Server Error",json.encode({error=I18N.tr("Aggiornamento non completato")}),"application/json; charset=utf-8") end
  return response(client,"200 OK",json.encode({ok=true,file=relative,restart_required=true}),"application/json; charset=utf-8")
 end
 if method=="POST" and path=="/gameupload" then
  if not updateKeyMatches(self,header) then
   return response(client,"403 Forbidden",json.encode({error=I18N.tr("Trasferimento non autorizzato")}),"application/json; charset=utf-8")
  end
  local name=header:match("[Xx]%-[Cc]asa%-[Gg]ame%-[Ff]ile:%s*([^\r\n]+)") or ""
  local allowed=name=="fbgnuboy" or name=="launch.sh" or name=="doom" or name=="doom1.wad" or name=="launch_doom.sh" or name:match("^[%w _%-%(%)%[%]%,%.!'&_+]+%.gb$")
  if not allowed or name:find("..",1,true) or name:find("/",1,true) or not self.games_dir then
   return response(client,"400 Bad Request",json.encode({error=I18N.tr("Nome file gioco non valido")}),"application/json; charset=utf-8")
  end
  local limit=(name=="doom1.wad" or name=="doom") and 8*1024*1024 or 2*1024*1024
  if #body>limit then return response(client,"413 Payload Too Large",json.encode({error=I18N.tr("File gioco troppo grande")}),"application/json; charset=utf-8") end
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
  if not file then return response(client,"507 Insufficient Storage",json.encode({error=I18N.tr("Spazio giochi insufficiente")}),"application/json; charset=utf-8") end
  file:write(body);file:close()
  if not os.rename(temp,destination) then os.remove(temp);return response(client,"500 Internal Server Error",json.encode({error=I18N.tr("Trasferimento gioco non completato")}),"application/json; charset=utf-8") end
  if name=="fbgnuboy" or name=="launch.sh" or name=="doom" or name=="launch_doom.sh" then os.execute("chmod 755 "..destination) end
  return response(client,"200 OK",json.encode({ok=true,file=name,bytes=#body}),"application/json; charset=utf-8")
 end
 if method=="POST" and path=="/gameremove" then
  if not updateKeyMatches(self,header) then
   return response(client,"403 Forbidden",json.encode({error=I18N.tr("Rimozione non autorizzata")}),"application/json; charset=utf-8")
  end
  local name=header:match("[Xx]%-[Cc]asa%-[Gg]ame%-[Ff]ile:%s*([^\r\n]+)") or ""
  if not (name:match("^[%w _%-%(%)%[%]%,%.!'&_+]+%.gb$") or name=="fbgnuboy" or name=="launch.sh" or name=="doom" or name=="doom1.wad" or name=="launch_doom.sh") or name:find("..",1,true) or name:find("/",1,true) or not self.games_dir then
   return response(client,"400 Bad Request",json.encode({error=I18N.tr("Nome file gioco non valido")}),"application/json; charset=utf-8")
  end
  local path=(name:match("%.gb$") and self.games_dir.."/ROMs/" or self.games_dir.."/")..name
  local file=io.open(path,"rb")
  if not file then return response(client,"404 Not Found",json.encode({error=I18N.tr("Gioco non trovato")}),"application/json; charset=utf-8") end
  file:close()
  if not os.remove(path) then return response(client,"500 Internal Server Error",json.encode({error=I18N.tr("Rimozione non completata")}),"application/json; charset=utf-8") end
  return response(client,"200 OK",json.encode({ok=true,file=name,removed=true}),"application/json; charset=utf-8")
 end
 if method=="POST" and path=="/gamesreset" then
  if not updateKeyMatches(self,header) then
   return response(client,"403 Forbidden",json.encode({error=I18N.tr("Pulizia non autorizzata")}),"application/json; charset=utf-8")
  end
  if not self.games_dir then return response(client,"400 Bad Request",json.encode({error=I18N.tr("Cartella giochi non disponibile")}),"application/json; charset=utf-8") end
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
  local page = I18N.page("config", [[<!doctype html>
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
html,body{width:100%}body{display:flex;align-items:flex-start;justify-content:center}main{margin:24px auto}#gallery-page{margin:24px auto;place-self:auto}
@media(min-width:760px){body{padding:38px 24px}main#config-page{width:min(100%,820px);max-width:820px;padding:38px 46px}#gallery-page{width:min(100%,1120px);max-width:1120px;padding:34px 42px}.gallery-top{gap:16px}.gallery-top h1{font-size:28px}.gallery-help{margin:12px 0 22px}.photo-editor{display:grid;grid-template-columns:minmax(0,1.25fr) minmax(320px,.85fr);column-gap:30px;align-items:start}.photo-editor-preview{grid-column:1;grid-row:1;width:100%;max-width:none;max-height:62vh;aspect-ratio:4/3}.photo-editor-preview.is-wide{aspect-ratio:16/9}.photo-editor-preview.is-full{aspect-ratio:4/3}.photo-editor-preview img{max-height:62vh}.photo-editor-name{grid-column:1;grid-row:2;margin:10px 0 0}.photo-tools{grid-column:2;grid-row:1 / span 2;padding-top:5px}.photo-strip-label{margin-top:24px}.photo-grid{gap:10px;padding-bottom:12px}.photo-card{flex-basis:88px;width:88px;min-width:88px}.photo-card span{font-size:11px}}
@media(max-width:759px){#gallery-page{width:min(100%,520px);margin:0 auto}.photo-editor{display:block}.photo-tools{display:block}}
#photo-editor-preview img{width:auto;height:auto;max-width:100%;max-height:100%;margin:auto;object-fit:contain}
@media(min-width:760px){#form{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));column-gap:30px;align-items:start}#form>.picker,#form>#preview,#form>.status,#form>section.interval:last-of-type{grid-column:1/-1}#form>#send{grid-column:1}#form>.gallery-open{grid-column:2}#form>section.interval{min-width:0}#form>section.interval:last-of-type{width:100%}}

.actual-home-image{position:absolute;inset:0;width:100%;height:100%;object-fit:fill;pointer-events:none}.editor-canvas{top:0;bottom:0}.preview-header,.preview-stage:after{display:none}.device-widget{padding:0;border:1px solid rgba(92,170,208,.7);background:rgba(98,180,218,.08);color:transparent}.device-widget>:not(.resize-handle){display:none}.device-widget.is-selected{background:rgba(98,180,218,.18)}
.gallery-open{margin-top:10px;border:1px solid #92bfd4;background:#f3f9fc;color:var(--green-dark)}.gallery-open:hover:not(:disabled){background:#e5f2f8;color:var(--green-dark)}
#gallery-page{width:min(100%,520px);padding:clamp(18px,5vw,28px);place-self:start center}.gallery-top{display:flex;align-items:center;gap:10px}.gallery-top h1{flex:1;margin:0;font:600 23px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;letter-spacing:-.025em}.gallery-back,.gallery-refresh{width:auto;min-height:42px;margin:0;padding:8px 12px;border:1px solid var(--line);background:var(--surface);color:var(--ink);font-size:14px}.gallery-back:hover:not(:disabled),.gallery-refresh:hover:not(:disabled){background:var(--sage);color:var(--green-dark)}.gallery-help{margin:9px 0 15px;color:var(--muted);font-size:13px;line-height:1.4}.gallery-empty,.gallery-loading{margin:14px 0;padding:15px;border:1px solid var(--line);border-radius:12px;color:var(--muted);font-size:13px;line-height:1.45}.photo-editor{margin:0;padding:0;border:0;background:transparent}.photo-editor-preview{width:min(100%,430px);margin:0 auto;aspect-ratio:1;max-height:43vh;border:1px solid #c8d3d8;border-radius:12px;background:#e2e6e8}.photo-editor-preview.is-wide{aspect-ratio:16/9}.photo-editor-preview.is-full{aspect-ratio:4/3}.photo-editor-preview img{display:block;max-width:100%;max-height:43vh;object-fit:contain;filter:grayscale(1) contrast(1.18);transform-origin:center}.photo-editor-preview span{padding:15px;color:#5c7180;font-size:14px}.photo-editor-name{margin:8px 0 10px;text-align:center;font-size:12px}.photo-editor .interval-head{margin-top:11px}.photo-editor .range{height:34px;margin-top:2px}.photo-editor select{margin-top:6px}.photo-editor .mirror-row{margin-top:10px}.photo-strip-label{display:flex;justify-content:space-between;margin:16px 0 7px;font-size:14px;font-weight:600}.photo-grid{display:flex;gap:8px;overflow-x:auto;overscroll-behavior-x:contain;padding:3px 2px 9px;scroll-snap-type:x mandatory;-webkit-overflow-scrolling:touch;scrollbar-color:#9db8c6 transparent;scrollbar-width:thin}.photo-card{flex:0 0 76px;width:76px;min-width:76px;margin:0;padding:4px;border:1px solid var(--line);border-radius:10px;background:#f5f8f9;color:var(--ink);scroll-snap-align:center}.photo-card.is-active{padding:3px;border:2px solid var(--green)}.photo-card img{display:block;width:100%;aspect-ratio:1;object-fit:cover;filter:grayscale(1) contrast(1.18);border-radius:6px;background:#e5e9eb}.photo-card span{display:block;padding:4px 1px 1px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:10px}.photo-grid:focus-visible{outline:3px solid var(--upload-focus);outline-offset:2px}
/* Compact, quiet drag handles; the generous hit area is invisible. */
.resize-handle{z-index:5;background:transparent;touch-action:none}.resize-x{width:24px;height:34px;top:calc(50% - 17px);right:-1px;border-radius:0}.resize-y{width:34px;height:24px;left:calc(50% - 17px);bottom:-1px;border-radius:0}.resize-corner{width:30px;height:30px;right:-1px;bottom:-1px;border-radius:0;background:transparent}.resize-corner:before,.resize-corner:after{right:7px;bottom:7px;width:12px;height:2px;border-radius:2px;background:#fff;box-shadow:0 0 1px #203746;transform:rotate(-45deg)}.resize-corner:after{right:8px;bottom:12px;width:8px}.resize-x:after,.resize-y:after{content:"";position:absolute;background:rgba(255,255,255,.9);box-shadow:0 0 1px #203746;border-radius:2px}.resize-x:after{top:calc(50% - 8px);right:4px;width:2px;height:16px}.resize-y:after{left:calc(50% - 8px);bottom:4px;width:16px;height:2px}.device-widget.is-selected .resize-handle{background:transparent}.device-widget.is-selected .resize-corner:before,.device-widget.is-selected .resize-corner:after,.device-widget.is-selected .resize-x:after,.device-widget.is-selected .resize-y:after{background:#fff}

/* Final responsive overrides: desktop uses the width that the earlier compact mobile defaults intentionally cap. */
@media(min-width:760px){
 body{padding:36px 28px;align-items:flex-start}
 main#config-page{width:min(100%,940px);max-width:940px;margin:24px auto;padding:40px 48px}
 #gallery-page{width:min(100%,1100px);max-width:1100px;margin:24px auto;padding:34px 42px}
 #form{grid-template-columns:repeat(2,minmax(0,1fr));column-gap:34px}
 #form>.picker,#form>#preview,#form>.status,#form>section.interval:last-of-type{grid-column:1/-1}
 #form>#send,#form>.gallery-open{width:100%;margin-top:12px}
 .gallery-top{gap:16px}
 .gallery-top h1{font-size:28px}
 .gallery-help{margin:12px 0 22px;font-size:15px}
 .photo-editor{display:grid;grid-template-columns:minmax(0,1.25fr) minmax(300px,.75fr);column-gap:32px;align-items:start}
 .photo-editor-preview{grid-column:1;grid-row:1;width:100%;max-width:none;max-height:68vh;aspect-ratio:4/3;margin:0;border-radius:16px}
 .photo-editor-preview.is-wide{aspect-ratio:16/9}
 .photo-editor-preview.is-full{aspect-ratio:4/3}
 .photo-editor-preview img{max-height:68vh}
 .photo-editor-name{grid-column:1;grid-row:2;margin:10px 0 0;text-align:left;font-size:14px}
 .photo-tools{grid-column:2;grid-row:1/span 2;padding:22px 24px;background:#f2f8fb;border:1px solid var(--line);border-radius:16px}
 .photo-tools .editor-label{margin-top:2px}
 .photo-tools .interval-head{margin-top:20px}
 .photo-strip-label{margin-top:25px}
 .photo-grid{gap:11px;padding:4px 2px 12px}
 .photo-card{flex-basis:92px;width:92px;min-width:92px}
 .photo-card span{font-size:11px}
}
@media(min-width:1200px){
 main#config-page{width:min(100%,1040px);max-width:1040px;padding:46px 58px}
 #gallery-page{width:min(100%,1480px);max-width:1480px;padding:40px 52px}
 .photo-editor{grid-template-columns:minmax(0,1.65fr) minmax(340px,.75fr);column-gap:42px}
 .photo-editor-preview{max-height:70vh}
 .photo-editor-preview img{max-height:70vh}
 .photo-tools{padding:28px 30px}
}
@media(max-width:759px){main#config-page{width:min(100%,520px);margin:0 auto}#gallery-page{width:min(100%,520px);margin:0 auto;padding:clamp(18px,5vw,28px)}.photo-editor{display:block}.photo-editor-preview{width:min(100%,430px);max-height:43vh;margin:0 auto}.photo-editor-preview img{max-height:43vh}.photo-tools{padding:0;border:0;background:transparent}.photo-strip-label{margin-top:16px}}
</style>
<style>
/* Gallery editor fits the visible browser height on laptop screens. */
@media(min-width:760px){
 body{padding:clamp(12px,2.5vh,24px) 24px}
 #gallery-page{width:min(100%,1320px);max-width:1320px;max-height:calc(100vh - 28px);overflow:auto;margin:0 auto;padding:clamp(18px,2.6vh,28px) clamp(24px,3vw,42px)}
 .gallery-top h1{font-size:clamp(22px,2vw,27px)}
 .gallery-help{margin:8px 0 12px;font-size:13px}
 .photo-editor{grid-template-columns:minmax(0,1.55fr) minmax(280px,.75fr);column-gap:clamp(18px,2.5vw,32px);align-items:center}
 .photo-editor-preview{height:min(48vh,450px);max-height:calc(100vh - 390px);min-height:220px;aspect-ratio:auto}
 .photo-editor-preview img{max-height:100%;max-width:100%}
 .photo-tools{padding:clamp(14px,2vh,22px) clamp(16px,2vw,24px)}
 .photo-tools .interval-head{margin-top:clamp(10px,1.6vh,18px)}
 .photo-tools .range{height:30px}
 .photo-strip-label{margin-top:clamp(12px,2vh,20px)}
 .photo-grid{max-height:118px;overflow-y:hidden}
 .photo-card{flex-basis:78px;width:78px;min-width:78px}
}
@media(max-height:800px) and (min-width:760px){
 #gallery-page{padding-top:14px;padding-bottom:14px}
 .photo-editor-preview{height:min(42vh,340px);max-height:calc(100vh - 340px);min-height:180px}
 .photo-tools{padding:12px 18px}
 .photo-tools .interval-head{margin-top:8px}
 .photo-tools .range{height:26px}
 .photo-strip-label{margin-top:10px;margin-bottom:4px}
 .photo-grid{max-height:94px}
 .photo-card{flex-basis:68px;width:68px;min-width:68px}
}
@media(max-width:759px){#gallery-page{max-height:none;overflow:visible}.photo-editor-preview{height:auto;min-height:0}}
.weather-search-row{display:flex;gap:8px;align-items:center}.weather-search-row .home-name-input{flex:1}.weather-results{display:grid;gap:6px;margin-top:8px}.weather-result{text-align:left;padding:10px 12px;border:1px solid var(--line);border-radius:10px;background:#fff;color:var(--ink);font:inherit;cursor:pointer}.weather-result:hover{border-color:var(--ink)}
.home-name-input{display:block;width:100%;min-height:46px;margin-top:10px;padding:10px 13px;border:1px solid var(--line);border-radius:10px;background:#fff;color:var(--ink);font:inherit;font-size:16px}
</style>
<style>
@media(min-width:760px){.photo-editor{justify-items:start}.photo-editor-name{text-align:left!important}.photo-editor-preview{display:block;position:relative;justify-self:start;margin:0!important;overflow:hidden;width:min(100%,66vh);height:auto;min-height:0;max-height:none;aspect-ratio:4/3;touch-action:none;cursor:grab}.photo-editor-preview:active{cursor:grabbing}.photo-editor-preview[data-profile="widget_square"]{width:min(100%,46vh);aspect-ratio:1}.photo-editor-preview[data-profile="widget_wide"]{width:min(100%,80vh);aspect-ratio:16/9}.photo-editor-preview[data-profile="fullscreen"][data-orientation="portrait"]{width:min(100%,38vh);aspect-ratio:3/4}.photo-editor-preview[data-profile="fullscreen"][data-orientation="landscape"]{width:min(100%,66vh);aspect-ratio:4/3}.photo-editor-preview img{position:absolute;left:50%;top:50%;width:auto;height:auto;max-width:none;max-height:none;object-fit:fill;filter:grayscale(1) contrast(1.18);transform-origin:center;user-select:none;-webkit-user-drag:none}.photo-editor-preview span{position:absolute;inset:0;display:grid;place-items:center;pointer-events:none}.photo-editor-preview span[hidden]{display:none!important}}
@media(max-width:759px){.photo-editor-preview{display:block;position:relative;overflow:hidden;width:min(100%,52vh);height:auto;min-height:0;max-height:none;aspect-ratio:4/3;touch-action:none;cursor:grab}.photo-editor-preview:active{cursor:grabbing}.photo-editor-preview[data-profile="widget_square"]{width:min(100%,48vh);aspect-ratio:1}.photo-editor-preview[data-profile="widget_wide"]{width:min(100%,82vh);aspect-ratio:16/9}.photo-editor-preview[data-profile="fullscreen"][data-orientation="portrait"]{width:min(100%,40vh);aspect-ratio:3/4}.photo-editor-preview[data-profile="fullscreen"][data-orientation="landscape"]{width:min(100%,66vh);aspect-ratio:4/3}.photo-editor-preview img{position:absolute;left:50%;top:50%;width:auto;height:auto;max-width:none;max-height:none;object-fit:fill;filter:grayscale(1) contrast(1.18);transform-origin:center;user-select:none;-webkit-user-drag:none}.photo-editor-preview span{position:absolute;inset:0;display:grid;place-items:center;pointer-events:none}.photo-editor-preview span[hidden]{display:none!important}}
.photo-grid{justify-content:flex-start}
.photo-grid::before,.photo-grid::after{content:"";flex:1 0 0;min-width:0}
</style></head><body><main id="config-page">
<div class="brand"><span class="brand-mark" aria-hidden="true"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="M3.5 10.5 12 4l8.5 6.5v9a1 1 0 0 1-1 1h-15a1 1 0 0 1-1-1z"/><path d="M9 20.5v-6h6v6"/></svg></span>Casa · Config</div>
<h1>Configura<br>Casa.</h1><p class="intro">Personalizza la schermata del Kindle, la cornice digitale e la modalità notte. Puoi anche inviare le foto da qui.</p>
<section class="interval" aria-labelledby="wifi-add-title"><div class="interval-head"><label id="wifi-add-title" for="wifi-ssid">Aggiungi una rete Wi‑Fi</label></div><input id="wifi-ssid" type="text" maxlength="32" autocomplete="off" placeholder="Nome rete (SSID)"><input id="wifi-password" type="password" maxlength="63" autocomplete="new-password" placeholder="Password Wi‑Fi"><button class="save-setting" id="wifi-add-button" type="button">Salva rete nel Kindle</button><p class="switch-help" id="wifi-add-status" aria-live="polite">La rete si aggiunge alle reti già memorizzate e il Kindle proverà a collegarsi quando sarà nel suo raggio.</p></section>
<form id="form" method="post" action="/upload" enctype="multipart/form-data">
<input class="upload-input" id="photo" type="file" name="photo" accept="image/*" multiple required>
<label class="picker" for="photo"><span class="picker-icon" aria-hidden="true"><svg width="25" height="25" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="8.5" cy="9" r="1.5"/><path d="m21 15-5-5L5 20"/></svg></span><span class="picker-copy"><strong>Scegli le foto</strong><span>Puoi selezionarne più di una · JPG, PNG o BMP</span></span></label>
<div class="preview" id="preview" hidden><div id="preview-frame"></div><div class="file-name" id="file-name"></div></div>
<button id="send" type="submit" disabled>Invia al Kindle</button><button class="gallery-open" id="gallery-open" type="button">Apri la galleria <span id="gallery-count">—</span></button><p class="status" id="status" aria-live="polite">Le foto grandi vengono ridotte automaticamente prima dell’invio.</p>
<section class="interval" aria-labelledby="home-name-title"><div class="interval-head"><label id="home-name-title" for="home-name">Nome della schermata Casa</label></div><input class="home-name-input" id="home-name" type="text" maxlength="24" value="Casa" autocomplete="off"><p class="switch-help">Il titolo sulla schermata del Kindle cambia quando salvi la configurazione.</p></section>
<section class="interval" aria-labelledby="language-title"><div class="interval-head"><label id="language-title" for="casa-language">Lingua</label></div><select id="casa-language"><option value="auto">Automatica · lingua del Kindle</option>]]..languageOptions()..[[</select><p class="switch-help">Vale per la schermata Casa e per queste pagine. Si applica quando salvi la configurazione.</p></section>
<section class="interval" aria-labelledby="weather-place-title"><div class="interval-head"><label id="weather-place-title" for="weather-search">Località meteo</label><span class="interval-value" id="weather-place-current">Non impostata</span></div><div class="weather-search-row"><input class="home-name-input" id="weather-search" type="search" maxlength="60" autocomplete="off" placeholder="Cerca una città…"><button class="save-setting" id="weather-search-button" type="button">Cerca</button></div><div class="weather-results" id="weather-results"></div><p class="switch-help" id="weather-search-status" aria-live="polite">Scegli la città: il meteo si aggiorna quando salvi la configurazione.</p></section>
<section class="interval" aria-labelledby="interval-title"><div class="interval-head"><label id="interval-title" for="interval">Cambio foto ogni</label><span class="interval-value" id="interval-value">30 secondi</span></div><p class="switch-help">Vale sia per il riquadro Casa sia per la galleria a schermo intero.</p><input class="range" id="interval" type="range" min="5" max="300" step="5" value="30" aria-label="Intervallo tra le foto"><div class="range-ends"><span>5 secondi</span><span>5 minuti</span></div><p class="current-setting" id="current-setting" aria-live="polite">Leggo l’intervallo attuale dal Kindle…</p></section>
<section class="interval" aria-labelledby="screen-title"><div class="switch-row"><div><label class="switch-label" id="screen-title" for="screensaver">Avvia cornice digitale automaticamente</label><p class="switch-help">Solo foto a schermo intero, senza orologio o menu.</p></div><label class="switch"><input id="screensaver" type="checkbox"><span class="switch-track" aria-hidden="true"></span></label></div><div class="interval-head delay-head"><label for="delay">Avvia dopo</label><span class="interval-value" id="delay-value">1 minuto</span></div><input class="range" id="delay" type="range" min="15" max="600" step="15" value="60" aria-label="Attesa prima delle foto a schermo intero"><div class="range-ends"><span>15 secondi</span><span>10 minuti</span></div><p class="current-setting" id="screen-setting" aria-live="polite">Leggo le impostazioni del Kindle…</p></section>
<section class="interval" aria-labelledby="standby-action-title"><div class="interval-head"><label id="standby-action-title" for="standby-action">Quando entra in standby</label></div><select id="standby-action"><option value="last_photo">Mostra l’ultima foto, ferma</option><option value="slideshow">Carosello di foto</option><option value="system">Salvaschermo originale del Kindle</option></select><div id="standby-photo-options"><div class="interval-head delay-head"><label for="standby-orientation">Orientamento foto</label></div><select id="standby-orientation"><option value="auto">Automatico</option><option value="landscape">Orizzontale</option><option value="portrait">Verticale</option></select><div class="interval-head delay-head"><label for="standby-interval">Intervallo carosello</label><span class="interval-value" id="standby-interval-value">2 minuti</span></div><input class="range" id="standby-interval" type="range" min="30" max="3600" step="30" value="120"><p class="switch-help">Il carosello tiene attivo il display Casa: il Kindle non entra nel vero standby mentre le foto scorrono. Per l’ultima foto puoi regolare l’inquadratura da Galleria → foto → “Schermo intero”.</p></div></section>
<section class="interval" aria-labelledby="power-action-title"><div class="switch-row"><div><label class="switch-label" id="power-action-title" for="power-button-enabled">Azione speciale al risveglio</label><p class="switch-help">Attiva il comportamento speciale quando premi il tasto di accensione. Puoi mostrare una foto ferma, tornare a Casa o aprire una schermata.</p></div><label class="switch"><input id="power-button-enabled" type="checkbox"><span class="switch-track" aria-hidden="true"></span></label></div><div class="interval-head delay-head"><label for="power-button-action">Dopo il risveglio mostra</label></div><select id="power-button-action" disabled><option value="last_photo">Ultima foto, ferma</option><option value="home">Schermata Casa</option><option value="photos">Presentazione di foto</option><option value="calendar">Calendario mensile grande</option><option value="weather">Meteo dettagliato</option><option value="timer">Timer cucina</option><option value="shopping">Lista della spesa</option></select></section>
<section class="interval" aria-labelledby="clock-title"><div class="switch-row"><div><label class="switch-label" id="clock-title" for="clock-seconds">Mostra i secondi nell’orologio</label><p class="switch-help">Se attivi i secondi, l’orologio si aggiorna ogni secondo e il display si ridisegna più spesso.</p></div><label class="switch"><input id="clock-seconds" type="checkbox"><span class="switch-track" aria-hidden="true"></span></label></div></section>
<section class="interval" aria-labelledby="battery-display-title"><div class="interval-head"><label id="battery-display-title" for="battery-display-mode">Indicatore batteria</label></div><select id="battery-display-mode"><option value="percent_time">Percentuale dentro · autonomia sotto</option><option value="percent">Solo percentuale dentro</option><option value="remaining">Autonomia residua dentro</option></select><p class="switch-help">L’autonomia è una stima basata sul consumo osservato con i servizi attivi.</p></section>
<section class="interval" id="auto-standby-settings" aria-labelledby="auto-standby-title" hidden><div class="switch-row"><div><label class="switch-label" id="auto-standby-title" for="auto-standby-enabled">Avvia standby automaticamente</label><p class="switch-help">Se disattivato, Casa resta sempre aperta. Questa opzione compare quando l’azione speciale al risveglio è spenta.</p></div><label class="switch"><input id="auto-standby-enabled" type="checkbox"><span class="switch-track" aria-hidden="true"></span></label></div><div id="standby-delay-controls" hidden><div class="interval-head delay-head"><label for="auto-standby-delay">Entra in standby dopo</label><span class="interval-value" id="auto-standby-delay-value">5 minuti</span></div><input class="range" id="auto-standby-delay" type="range" min="15" max="3600" step="15" value="300" aria-label="Attesa prima dello standby automatico"><div class="range-ends"><span>15 secondi</span><span>60 minuti</span></div><div class="interval-head delay-head"><label for="auto-standby-start">Attivo dalle</label><label for="auto-standby-end">Alle</label></div><div class="interval-head"><input id="auto-standby-start" type="time" value="00:00"><input id="auto-standby-end" type="time" value="23:59"></div></div></section>
<section class="interval" aria-labelledby="server-mode-title"><div class="interval-head"><label id="server-mode-title" for="server-mode">Server Config e foto</label></div><select id="server-mode"><option value="off">Spento</option><option value="timeout">Attivo · si spegne dopo 5 minuti senza richieste</option><option value="always">Sempre attivo · anche dopo il riavvio di Casa</option></select><p class="switch-help">La modalità “Sempre attivo” riapre automaticamente il link quando Casa riparte. Consuma più batteria.</p></section>
<section class="interval"><div class="interval-head"><label for="screen-orientation">Orientamento del Kindle</label></div><select id="screen-orientation"><option value="landscape">Orizzontale · paesaggio</option><option value="portrait">Verticale · ritratto</option></select><div class="interval-head delay-head"><label for="night-mode">Modalità notte</label></div><select id="night-mode"><option value="manual">Manuale · pulsante nel menu Kindle</option><option value="automatic">Automatica · per orario</option></select><div class="interval-head delay-head"><label for="night-start">Da</label><label for="night-end">A</label></div><div class="interval-head"><input id="night-start" type="time" value="22:00"><input id="night-end" type="time" value="07:00"></div><p class="switch-help">Fuori da questi orari Casa usa il tema chiaro.</p>
<div class="switch-row delay-head"><label class="switch-label" for="widget-weather">Mostra meteo</label><label class="switch"><input id="widget-weather" type="checkbox" checked><span class="switch-track"></span></label></div>
<div class="switch-row delay-head"><label class="switch-label" for="widget-photo">Mostra foto</label><label class="switch"><input id="widget-photo" type="checkbox" checked><span class="switch-track"></span></label></div>
<div class="switch-row delay-head"><label class="switch-label" for="widget-calendar">Mostra calendario mensile</label><label class="switch"><input id="widget-calendar" type="checkbox"><span class="switch-track"></span></label></div>
<div class="switch-row delay-head"><label class="switch-label" for="widget-timer">Mostra timer cucina</label><label class="switch"><input id="widget-timer" type="checkbox"><span class="switch-track"></span></label></div>
<div class="switch-row delay-head"><label class="switch-label" for="widget-shopping">Mostra lista della spesa</label><label class="switch"><input id="widget-shopping" type="checkbox"><span class="switch-track"></span></label></div>
<p class="switch-help">Puoi mostrare al massimo 4 widget. <a id="kitchen-link" href="#">Apri Timer e lista della spesa ↗</a></p>
<div class="layout-editor"><div class="interval-head"><label>Anteprima della home</label><span class="layout-hint" id="layout-hint">Kindle 4 · orizzontale</span></div><p class="switch-help">Mostra la schermata reale del Kindle. Trascina i riquadri per impostare la posizione; dopo Salva l’anteprima si aggiorna.</p>
<div class="preview-stage" aria-label="Anteprima reale e configurabile della schermata Casa"><img id="actual-home-image" class="actual-home-image" alt="Schermata Casa attuale del Kindle"><div id="editor-canvas" class="editor-canvas">
<div class="device-widget weather-widget" data-widget="weather"><strong id="preview-weather-place">Meteo</strong><div class="weather-preview-main"><b>22°</b><span>Parz. nuvoloso</span></div><div class="weather-preview-days">Oggi&nbsp;&nbsp; 20° / 25°<br>Domani&nbsp;&nbsp; 18° / 24°</div><span class="resize-handle resize-x" data-axis="x" aria-label="Allarga o restringi il meteo"></span><span class="resize-handle resize-y" data-axis="y" aria-label="Allunga o accorcia il meteo"></span><span class="resize-handle resize-corner" data-axis="both" aria-label="Ridimensiona il meteo in larghezza e altezza"></span></div>
<div class="device-widget photo-widget" data-widget="photo"><span class="photo-placeholder"><span>FOTO</span></span><span class="resize-handle resize-x" data-axis="x" aria-label="Allarga o restringi le foto"></span><span class="resize-handle resize-y" data-axis="y" aria-label="Allunga o accorcia le foto"></span><span class="resize-handle resize-corner" data-axis="both" aria-label="Ridimensiona le foto in larghezza e altezza"></span></div>
<div class="device-widget kitchen-preview" data-widget="timer"><strong>Timer cucina</strong><b>10:00</b><span>Pronto</span><span class="resize-handle resize-x" data-axis="x" aria-label="Ridimensiona timer"></span><span class="resize-handle resize-y" data-axis="y" aria-label="Ridimensiona timer"></span><span class="resize-handle resize-corner" data-axis="both" aria-label="Ridimensiona timer"></span></div>
<div class="device-widget kitchen-preview" data-widget="shopping"><strong>Lista spesa</strong><span>□ Pomodori</span><span>□ Pasta</span><span class="resize-handle resize-x" data-axis="x" aria-label="Ridimensiona lista"></span><span class="resize-handle resize-y" data-axis="y" aria-label="Ridimensiona lista"></span><span class="resize-handle resize-corner" data-axis="both" aria-label="Ridimensiona lista"></span></div>
<div class="device-widget calendar-widget" data-widget="calendar"><strong>Novembre 2026</strong><span class="calendar-preview-days">Lun&nbsp; Mar&nbsp; Mer&nbsp; Gio&nbsp; Ven&nbsp; Sab&nbsp; Dom</span><span class="calendar-preview-grid">1&nbsp; 2&nbsp; 3&nbsp; 4&nbsp; 5&nbsp; 6&nbsp; 7<br>8&nbsp; 9&nbsp; 10&nbsp; 11&nbsp; 12&nbsp; 13<br>15&nbsp; 16&nbsp; 17&nbsp; 18&nbsp; 19&nbsp; 20</span><span class="resize-handle resize-x" data-axis="x" aria-label="Allarga o restringi il calendario"></span><span class="resize-handle resize-y" data-axis="y" aria-label="Allunga o accorcia il calendario"></span><span class="resize-handle resize-corner" data-axis="both" aria-label="Ridimensiona il calendario in larghezza e altezza"></span></div>
</div></div><p class="current-setting" id="config-setting" aria-live="polite">Carico la configurazione del Kindle…</p><div class="layout-actions"><button class="save-setting reset-layout" id="reset-layout" type="button">Ripristina</button><button class="save-setting" id="save-setting" type="button" disabled>Salva configurazione</button></div></section>
</form><div class="foot"><strong>Resta tutto in casa.</strong> L’invio avviene sulla rete Wi‑Fi locale; il Kindle e il telefono devono essere collegati alla stessa rete.</div>
</main><main id="gallery-page" hidden aria-labelledby="gallery-title"><div class="gallery-top"><button type="button" class="gallery-back" id="gallery-back">← Config</button><h1 id="gallery-title">Galleria foto</h1><button type="button" class="gallery-refresh" id="gallery-refresh" aria-label="Aggiorna galleria">Aggiorna</button></div><p class="gallery-help">Scegli una miniatura, poi trascina la foto nell’anteprima per spostare l’inquadratura. Salva quando hai finito.</p><div class="photo-editor" id="photo-editor" hidden><div class="photo-editor-preview" id="photo-editor-preview"><img id="photo-editor-image" alt="Anteprima in bianco e nero della foto selezionata"><span id="photo-preview-error" hidden>Anteprima non disponibile</span></div><div class="photo-editor-name" id="photo-editor-name"></div><div class="photo-tools"><label class="editor-label" for="photo-profile">Formato</label><select id="photo-profile"><option value="widget_square">Widget quadrato piccolo</option><option value="widget_wide">Widget allungato</option><option value="fullscreen">Schermo intero</option></select><div class="interval-head delay-head"><label for="photo-zoom">Zoom e ritaglio</label><span class="interval-value" id="photo-zoom-value">1×</span></div><input class="range" id="photo-zoom" type="range" min="1" max="3" step="0.05" value="1"><div class="interval-head delay-head"><label for="photo-rotation">Rotazione</label></div><select id="photo-rotation"><option value="0">Nessuna</option><option value="90">90° a destra</option><option value="180">180°</option><option value="270">90° a sinistra</option></select><label class="mirror-row"><input id="photo-mirror" type="checkbox"> Specchia orizzontalmente</label><p class="current-setting" id="photo-save-status" aria-live="polite">Seleziona una foto e regola l’anteprima.</p><button class="save-setting" id="photo-save-button" type="button" disabled>Salva modifiche</button></div></div><div class="gallery-empty" id="gallery-empty" hidden>Non ci sono ancora foto. Torna a Config e caricane alcune.</div><div class="photo-strip-label">Tutte le foto <span id="gallery-total"></span></div><div class="photo-grid" id="photo-grid" aria-label="Miniature delle foto caricate" tabindex="0"><p class="gallery-loading">Carico le foto del Kindle…</p></div></main>
<script>
(function(){var input=document.getElementById('photo'),form=document.getElementById('form'),button=document.getElementById('send'),status=document.getElementById('status'),preview=document.getElementById('preview'),previewFrame=document.getElementById('preview-frame'),fileName=document.getElementById('file-name'),interval=document.getElementById('interval'),intervalValue=document.getElementById('interval-value'),currentSetting=document.getElementById('current-setting'),saveSetting=document.getElementById('save-setting'),screensaver=document.getElementById('screensaver'),delay=document.getElementById('delay'),delayValue=document.getElementById('delay-value'),screenSetting=document.getElementById('screen-setting'),nightMode=document.getElementById('night-mode'),nightStart=document.getElementById('night-start'),nightEnd=document.getElementById('night-end'),weather=document.getElementById('widget-weather'),photoWidget=document.getElementById('widget-photo'),calendar=document.getElementById('widget-calendar'),timerWidget=document.getElementById('widget-timer'),shoppingWidget=document.getElementById('widget-shopping'),screenOrientation=document.getElementById('screen-orientation'),powerButton=document.getElementById('power-button-enabled'),powerAction=document.getElementById('power-button-action'),standbyAction=document.getElementById('standby-action'),standbyOrientation=document.getElementById('standby-orientation'),standbyInterval=document.getElementById('standby-interval'),standbyIntervalValue=document.getElementById('standby-interval-value'),standbyPhotoOptions=document.getElementById('standby-photo-options'),wifiSSID=document.getElementById('wifi-ssid'),wifiPassword=document.getElementById('wifi-password'),wifiAddButton=document.getElementById('wifi-add-button'),wifiAddStatus=document.getElementById('wifi-add-status'),clockSeconds=document.getElementById('clock-seconds'),autoStandby=document.getElementById('auto-standby-enabled'),autoStandbyDelay=document.getElementById('auto-standby-delay'),autoStandbyDelayValue=document.getElementById('auto-standby-delay-value'),autoStandbySettings=document.getElementById('auto-standby-settings'),standbyDelayControls=document.getElementById('standby-delay-controls'),autoStandbyStart=document.getElementById('auto-standby-start'),autoStandbyEnd=document.getElementById('auto-standby-end'),serverMode=document.getElementById('server-mode'),batteryDisplay=document.getElementById('battery-display-mode'),homeName=document.getElementById('home-name'),casaLanguage=document.getElementById('casa-language'),stage=document.querySelector('.preview-stage'),configSetting=document.getElementById('config-setting'),kitchenLink=document.getElementById('kitchen-link'),canvas=document.getElementById('editor-canvas'),actualHomeImage=document.getElementById('actual-home-image'),resetLayout=document.getElementById('reset-layout'),widgets={},objectUrl=null,previewImage=null,savedInterval=30,savedEnabled=false,savedDelay=60,widgetLayout=defaultLayout(),drag=null;
function refreshActualHomeImage(){if(location.protocol!=='file:')actualHomeImage.src='/home-preview?v='+Date.now()}actualHomeImage.addEventListener('error',function(){configSetting.textContent='Anteprima reale disponibile quando Casa è aperta sulla home.'});function defaultLayout(){return{weather:{x:0,y:0,w:46,h:46},photo:{x:46,y:0,w:54,h:100},calendar:{x:0,y:46,w:46,h:54},timer:{x:0,y:46,w:23,h:54},shopping:{x:23,y:46,w:23,h:54}}}['weather','photo','calendar','timer','shopping'].forEach(function(name){widgets[name]=canvas.querySelector('[data-widget="'+name+'"]')});
if(location.protocol!=='file:'){kitchenLink.href='http://'+location.hostname+':8766';}else{kitchenLink.hidden=true}wifiAddButton.addEventListener('click',function(){var ssid=wifiSSID.value.trim(),password=wifiPassword.value;if(!ssid||!password){wifiAddStatus.textContent='Inserisci nome rete e password.';return}wifiAddButton.disabled=true;wifiAddStatus.textContent='Salvo il profilo Wi‑Fi nel Kindle…';fetch('/wifi',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({ssid:ssid,password:password})}).then(function(r){return r.json().then(function(v){if(!r.ok)throw new Error(v.error||'Rete non salvata');return v})}).then(function(v){wifiPassword.value='';wifiAddStatus.textContent='Rete “'+v.ssid+'” salvata. Il Kindle si collegherà quando la troverà.'}).catch(function(e){wifiAddStatus.textContent=e.message||'Non riesco a salvare la rete.'}).finally(function(){wifiAddButton.disabled=false})});standbyAction.addEventListener('change',function(){standbyPhotoOptions.hidden=standbyAction.value==='system';dirty()});function showStandbyInterval(value){standbyInterval.value=value;var minutes=Math.floor(value/60),rest=value%60;standbyIntervalValue.textContent=minutes?(minutes+(minutes===1?' minuto':' minuti')+(rest?' e '+rest+' secondi':'')):value+' secondi'}standbyInterval.addEventListener('input',function(){showStandbyInterval(Number(standbyInterval.value));dirty()});powerButton.addEventListener('change',function(){powerAction.disabled=!powerButton.checked;syncStandbyVisibility();dirty()});function seconds(value){if(value<60)return value+' secondi';var minutes=Math.floor(value/60),rest=value%60;if(!rest)return minutes+(minutes===1?' minuto':' minuti');return minutes+' min e '+rest+' s'}function showInterval(value){interval.value=value;intervalValue.textContent=seconds(Number(value))}function showDelay(value){delay.value=value;delayValue.textContent=seconds(Number(value));delay.disabled=!screensaver.checked}function showStandbyDelay(value){autoStandbyDelay.value=value;autoStandbyDelayValue.textContent=seconds(Number(value))}function syncStandbyVisibility(){autoStandbySettings.hidden=powerButton.checked;standbyDelayControls.hidden=!autoStandby.checked}function dirty(){saveSetting.disabled=false}interval.addEventListener('input',function(){showInterval(Number(interval.value));dirty()});screensaver.addEventListener('change',function(){showDelay(Number(delay.value));dirty()});delay.addEventListener('input',function(){showDelay(Number(delay.value));dirty()});autoStandby.addEventListener('change',function(){syncStandbyVisibility();dirty()});autoStandbyDelay.addEventListener('input',function(){showStandbyDelay(Number(autoStandbyDelay.value));dirty()});[nightMode,nightStart,nightEnd,weather,photoWidget,calendar,timerWidget,shoppingWidget,screenOrientation,powerButton,powerAction,standbyAction,standbyOrientation,standbyInterval,clockSeconds,autoStandby,autoStandbyDelay,autoStandbyStart,autoStandbyEnd,serverMode,batteryDisplay,homeName].forEach(function(el){el.addEventListener('change',function(){syncVisibility();syncStandbyVisibility();dirty()})});
var visibilityState={weather:false,photo:false,calendar:false,timer:false,shopping:false};function intersects(a,b,gap){gap=gap||0;return a.x<b.x+b.w+gap&&a.x+a.w+gap>b.x&&a.y<b.y+b.h+gap&&a.y+a.h+gap>b.y}function writeWidget(name){var p=widgetLayout[name],el=widgets[name];el.style.left=p.x+'%';el.style.top=p.y+'%';el.style.width=p.w+'%';el.style.height=p.h+'%'}function placeActiveGrid(next){var names=Object.keys(next).filter(function(name){return next[name]}),columns=2,rows=Math.ceil(names.length/columns);names.forEach(function(name,index){var col=index%columns,row=Math.floor(index/columns),cellW=100/columns,cellH=100/rows;widgetLayout[name]={x:Math.round(col*cellW),y:Math.round(row*cellH),w:Math.round(cellW),h:Math.round(cellH)};writeWidget(name)})}function syncVisibility(){var next={weather:weather.checked,photo:photoWidget.checked,calendar:calendar.checked,timer:timerWidget.checked,shopping:shoppingWidget.checked};var names=Object.keys(next).filter(function(name){return next[name]}),limit=4;if(names.length>limit){var changed=[timerWidget,shoppingWidget,calendar,photoWidget,weather].find(function(el){return el===document.activeElement});if(changed)changed.checked=false;configSetting.textContent='Puoi mostrare al massimo 4 widget. Disattivane uno per aggiungerne un altro.';dirty();next={weather:weather.checked,photo:photoWidget.checked,calendar:calendar.checked,timer:timerWidget.checked,shopping:shoppingWidget.checked};names=Object.keys(next).filter(function(name){return next[name]})}Object.keys(widgets).forEach(function(name){widgets[name].hidden=!next[name]});var added=names.some(function(name){return next[name]&&!visibilityState[name]});var overlap=names.some(function(name,index){return names.slice(index+1).some(function(other){return intersects(widgetLayout[name],widgetLayout[other])})});if(added&&overlap){placeActiveGrid(next);configSetting.textContent='Riquadri disposti automaticamente senza sovrapposizioni. Puoi trascinarli e ridimensionarli.'}visibilityState=next}function syncOrientation(){var portrait=screenOrientation.value==='portrait';stage.classList.toggle('is-portrait',portrait);document.getElementById('layout-hint').textContent='Kindle 4 · '+(portrait?'verticale':'orizzontale')}screenOrientation.addEventListener('change',syncOrientation);function paintLayout(layout){var clean=defaultLayout();['weather','photo','calendar','timer','shopping'].forEach(function(name){var v=layout&&layout[name]||clean[name],x=Number(v.x),y=Number(v.y),w=Number(v.w),h=Number(v.h),min=name==='weather'?{w:35,h:30}:name==='photo'?{w:25,h:30}:name==='calendar'?{w:30,h:35}:{w:20,h:24};x=Math.max(0,Math.min(100-min.w,isFinite(x)?x:clean[name].x));y=Math.max(0,Math.min(100-min.h,isFinite(y)?y:clean[name].y));w=Math.max(min.w,Math.min(100-x,isFinite(w)?w:clean[name].w));h=Math.max(min.h,Math.min(100-y,isFinite(h)?h:clean[name].h));widgetLayout[name]={x:Math.round(x),y:Math.round(y),w:Math.round(w),h:Math.round(h)};writeWidget(name)});visibilityState={weather:false,photo:false,calendar:false,timer:false,shopping:false};syncVisibility()}
function applySetting(data,isPreview){homeName.value=data.home_name||'Casa';casaLanguage.value=data.language||'auto';window.casaWeatherPlace=data.weather_place||null;if(window.showWeatherPlace)showWeatherPlace();powerButton.checked=data.power_button_enabled===true;clockSeconds.checked=data.show_clock_seconds===true;autoStandby.checked=data.auto_standby_enabled===true;showStandbyDelay(Math.max(15,Math.min(3600,Math.round(Number(data.auto_standby_delay_seconds||300)/15)*15)));autoStandbyStart.value=data.auto_standby_start||'00:00';autoStandbyEnd.value=data.auto_standby_end||'23:59';serverMode.value=data.server_mode||'off';batteryDisplay.value=data.battery_display_mode||'percent_time';syncStandbyVisibility();powerAction.value=data.power_button_action||'photos';standbyAction.value=data.standby_action||'last_photo';standbyOrientation.value=data.standby_orientation||'auto';showStandbyInterval(Math.max(30,Math.min(3600,Number(data.standby_interval_seconds||120))));standbyPhotoOptions.hidden=standbyAction.value==='system';powerAction.disabled=!powerButton.checked;savedInterval=Math.max(5,Math.min(300,Math.round(Number(data.interval_seconds||30)/5)*5));savedEnabled=data.screensaver_enabled===true;savedDelay=Math.max(15,Math.min(600,Math.round(Number(data.screensaver_delay_seconds||60)/15)*15));screensaver.checked=savedEnabled;showInterval(savedInterval);showDelay(savedDelay);nightMode.value=data.night_mode||'manual';nightStart.value=data.night_start||'22:00';nightEnd.value=data.night_end||'07:00';screenOrientation.value=data.screen_orientation||'landscape';syncOrientation();weather.checked=data.weather_enabled!==false;photoWidget.checked=data.photo_enabled!==false;calendar.checked=data.calendar_enabled===true;timerWidget.checked=data.timer_enabled===true;shoppingWidget.checked=data.shopping_enabled===true;paintLayout(data.widget_layout);saveSetting.disabled=!!isPreview;currentSetting.textContent=(isPreview?'Anteprima · ':'Attualmente sul Kindle: ')+seconds(savedInterval);screenSetting.textContent='Cornice '+(savedEnabled?'attiva':'disattivata')+(savedEnabled?' · dopo '+seconds(savedDelay):'');configSetting.textContent=(isPreview?'Anteprima · ':'Sul Kindle · ')+(nightMode.value==='automatic'?'notte '+nightStart.value+'–'+nightEnd.value:'notte manuale')}
function getPreview(){var data={settings_version:8,interval_seconds:30,screensaver_enabled:false,screensaver_delay_seconds:60,night_mode:'manual',night_enabled:false,night_start:'22:00',night_end:'07:00',weather_enabled:true,photo_enabled:true,calendar_enabled:false,timer_enabled:true,shopping_enabled:true,screen_orientation:'landscape',power_button_enabled:false,power_button_action:'photos',standby_action:'last_photo',standby_orientation:'auto',standby_interval_seconds:120,show_clock_seconds:false,auto_standby_enabled:false,auto_standby_delay_seconds:300,auto_standby_start:'00:00',auto_standby_end:'23:59',server_mode:'off',battery_display_mode:'percent_time',home_name:'Casa',widget_layout:defaultLayout()};try{data=JSON.parse(localStorage.getItem('casa_slideshow_settings')||JSON.stringify(data))}catch(_e){}if(Number(data.settings_version||0)<3){data.widget_layout=defaultLayout();data.settings_version=8}return data}function saveAll(){var payload={settings_version:8,interval_seconds:Number(interval.value),screensaver_enabled:screensaver.checked,screensaver_delay_seconds:Number(delay.value),night_mode:nightMode.value,night_start:nightStart.value,night_end:nightEnd.value,weather_enabled:weather.checked,photo_enabled:photoWidget.checked,calendar_enabled:calendar.checked,timer_enabled:timerWidget.checked,shopping_enabled:shoppingWidget.checked,screen_orientation:screenOrientation.value,power_button_enabled:powerButton.checked,power_button_action:powerAction.value,standby_action:standbyAction.value,standby_orientation:standbyOrientation.value,standby_interval_seconds:Number(standbyInterval.value),show_clock_seconds:clockSeconds.checked,auto_standby_enabled:autoStandby.checked,auto_standby_delay_seconds:Number(autoStandbyDelay.value),auto_standby_start:autoStandbyStart.value,auto_standby_end:autoStandbyEnd.value,server_mode:serverMode.value,battery_display_mode:batteryDisplay.value,home_name:homeName.value.trim()||'Casa',language:casaLanguage.value,weather_place:window.casaWeatherPlace||null,widget_layout:widgetLayout};if(nightMode.value==='automatic')payload.night_enabled=false;if(location.protocol==='file:'){try{localStorage.setItem('casa_slideshow_settings',JSON.stringify(payload))}catch(_e){}applySetting(payload,true);currentSetting.textContent='Anteprima · '+seconds(payload.interval_seconds);saveSetting.disabled=false;return}saveSetting.disabled=true;configSetting.textContent='Salvo la configurazione sul Kindle…';fetch('/settings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)}).then(function(r){return r.json().then(function(v){if(!r.ok)throw new Error(v.error||'Configurazione non salvata');return v})}).then(function(data){applySetting(data,false);configSetting.textContent='Configurazione salvata · anteprima reale in aggiornamento';saveSetting.disabled=false;setTimeout(refreshActualHomeImage,11000)}).catch(function(e){configSetting.dataset.kind='error';configSetting.textContent=e.message||'Non riesco a salvare. Verifica che Casa sia aperta e riprova.';saveSetting.disabled=false})}saveSetting.addEventListener('click',saveAll);resetLayout.addEventListener('click',function(){paintLayout(defaultLayout());dirty();configSetting.textContent='Disposizione originale ripristinata · salva per inviarla al Kindle'});
canvas.addEventListener('pointerdown',function(e){var el=e.target.closest('.device-widget');if(!el||el.hidden)return;e.preventDefault();var name=el.dataset.widget,handle=e.target.closest('.resize-handle'),rect=canvas.getBoundingClientRect(),mode=handle?(handle.dataset.axis||'both'):'move';if(name==='photo'&&handle&&(mode==='x'||mode==='both'))mode=mode==='both'?'left-both':'left-x';Object.keys(widgets).forEach(function(k){widgets[k].classList.toggle('is-selected',k===name)});drag={name:name,mode:mode,startX:e.clientX,startY:e.clientY,rect:rect,initial:Object.assign({},widgetLayout[name]),last:Object.assign({},widgetLayout[name])};if(el.setPointerCapture){try{el.setPointerCapture(e.pointerId)}catch(_e){}}});window.addEventListener('pointermove',function(e){if(!drag)return;var initial=drag.initial,dx=(e.clientX-drag.startX)/drag.rect.width*100,dy=(e.clientY-drag.startY)/drag.rect.height*100,min=drag.name==='weather'?{w:35,h:30}:drag.name==='photo'?{w:25,h:30}:drag.name==='calendar'?{w:30,h:35}:{w:20,h:24},p={x:initial.x,y:initial.y,w:initial.w,h:initial.h};function snap(v){return Math.round(v)}if(drag.mode==='move'){p.x=Math.max(0,Math.min(100-p.w,snap(initial.x+dx)));p.y=Math.max(0,Math.min(100-p.h,snap(initial.y+dy)))}else if(drag.mode==='left-x'||drag.mode==='left-both'){var right=initial.x+initial.w;p.x=Math.max(0,Math.min(right-min.w,snap(initial.x+dx)));p.w=right-p.x;if(drag.mode==='left-both')p.h=Math.max(min.h,Math.min(100-initial.y,snap(initial.h+dy)))}else{if(drag.mode==='x'||drag.mode==='both')p.w=Math.max(min.w,Math.min(100-p.x,snap(initial.w+dx)));if(drag.mode==='y'||drag.mode==='both')p.h=Math.max(min.h,Math.min(100-p.y,snap(initial.h+dy)))}function collides(candidate){return Object.keys(widgets).some(function(other){return other!==drag.name&&!widgets[other].hidden&&intersects(candidate,widgetLayout[other])})}if(drag.mode!=='move'){while(collides(p)&&(p.w>min.w||p.h>min.h)){if((drag.mode==='left-x'||drag.mode==='left-both')&&p.w>min.w){p.x=Math.min(100-min.w,p.x+1);p.w=Math.max(min.w,p.w-1)}else if((drag.mode==='x'||drag.mode==='both')&&p.w>min.w)p.w=Math.max(min.w,p.w-1);else if((drag.mode==='y'||drag.mode==='both'||drag.mode==='left-both')&&p.h>min.h)p.h=Math.max(min.h,p.h-1);else break}}if((drag.mode==='move'&&!collides(p))||(drag.mode!=='move'&&!collides(p))){widgetLayout[drag.name]=p;drag.last=Object.assign({},p);writeWidget(drag.name);dirty()}else if(drag.mode==='move'){widgetLayout[drag.name]=drag.last;writeWidget(drag.name)}});function endDrag(){if(drag){drag=null;configSetting.textContent='Disposizione agganciata alla griglia · salva per applicarla sul Kindle'}}window.addEventListener('pointerup',endDrag);window.addEventListener('pointercancel',endDrag);
if(location.protocol==='file:'){applySetting(getPreview(),true);saveSetting.disabled=false}else{fetch('/settings',{cache:'no-store'}).then(function(r){if(!r.ok)throw new Error('settings');return r.json()}).then(function(data){applySetting(data,false);refreshActualHomeImage()}).catch(function(){configSetting.textContent='Non riesco a leggere la configurazione attuale del Kindle.';configSetting.dataset.kind='error';interval.disabled=true;screensaver.disabled=true;saveSetting.disabled=true})}
input.addEventListener('change',function(){var files=Array.prototype.slice.call(input.files||[]),file=files[0];button.disabled=files.length===0;button.textContent=files.length?'Invia '+files.length+(files.length===1?' foto':' foto'): 'Invia al Kindle';status.dataset.kind='';status.textContent=files.length?files.length+(files.length===1?' foto pronta.':' foto pronte.'):'Le foto grandi vengono ridotte automaticamente prima dell’invio.';if(objectUrl)URL.revokeObjectURL(objectUrl);if(file){objectUrl=URL.createObjectURL(file);if(!previewImage){previewImage=document.createElement('img');previewImage.alt='Anteprima della prima foto scelta';previewFrame.appendChild(previewImage)}previewImage.src=objectUrl;fileName.textContent=files.length===1?file.name:files.length+' foto selezionate';preview.hidden=false}else{preview.hidden=true;if(previewImage)previewImage.removeAttribute('src')}});
function compress(file){return createImageBitmap(file).then(function(bitmap){var scale=Math.min(1,1200/Math.max(bitmap.width,bitmap.height)),canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(bitmap.width*scale));canvas.height=Math.max(1,Math.round(bitmap.height*scale));canvas.getContext('2d').drawImage(bitmap,0,0,canvas.width,canvas.height);bitmap.close();return new Promise(function(resolve,reject){canvas.toBlob(function(blob){blob?resolve(blob):reject(new Error('compress'))},'image/jpeg',.78)})})}
form.addEventListener('submit',function(e){var files=Array.prototype.slice.call(input.files||[]);if(!files.length)return;if(!window.createImageBitmap)return;e.preventDefault();button.disabled=true;saveSetting.disabled=true;status.dataset.kind='';var totals={saved:0,duplicates:0,invalid:0};function sendAt(index){if(index>=files.length){status.dataset.kind=totals.saved?'success':'';status.textContent=totals.saved+' foto aggiunte';if(totals.duplicates)status.textContent+=' · '+totals.duplicates+' duplicati scartati';if(totals.invalid)status.textContent+=' · '+totals.invalid+' file non validi ignorati';status.textContent+='.';input.value='';preview.hidden=true;if(previewImage)previewImage.removeAttribute('src');button.disabled=true;button.textContent='Scegli altre foto';saveSetting.disabled=Number(interval.value)===savedInterval;loadGallery();return}status.textContent='Preparo la foto '+(index+1)+' di '+files.length+'…';compress(files[index]).then(function(blob){var data=new FormData(),name=files[index].name.replace(/\.[^.]+$/,'')+'.jpg';data.append('photo',blob,name);status.textContent='Invio la foto '+(index+1)+' di '+files.length+'…';return fetch('/upload',{method:'POST',headers:{Accept:'application/json'},body:data}).then(function(r){if(!r.ok)throw new Error('upload');return r.json()})}).then(function(result){totals.saved+=result.saved_count||0;totals.duplicates+=result.duplicate_count||0;totals.invalid+=result.invalid_count||0;sendAt(index+1)}).catch(function(){status.dataset.kind='error';status.textContent='Invio interrotto alla foto '+(index+1)+'. Le foto già ricevute restano in Casa; riprova con le altre.';button.disabled=false;button.textContent='Riprova invio';saveSetting.disabled=Number(interval.value)===savedInterval})}sendAt(0)});
var configPage=document.getElementById('config-page'),galleryPage=document.getElementById('gallery-page'),galleryOpen=document.getElementById('gallery-open'),galleryCount=document.getElementById('gallery-count'),galleryTotal=document.getElementById('gallery-total'),galleryEmpty=document.getElementById('gallery-empty'),photoGrid=document.getElementById('photo-grid'),photoEditor=document.getElementById('photo-editor'),photoEditorImage=document.getElementById('photo-editor-image'),photoEditorPreview=document.getElementById('photo-editor-preview'),photoPreviewError=document.getElementById('photo-preview-error'),photoEditorName=document.getElementById('photo-editor-name'),photoProfile=document.getElementById('photo-profile'),photoZoom=document.getElementById('photo-zoom'),photoZoomValue=document.getElementById('photo-zoom-value'),photoRotation=document.getElementById('photo-rotation'),photoMirror=document.getElementById('photo-mirror'),photoSaveStatus=document.getElementById('photo-save-status'),photoSaveButton=document.getElementById('photo-save-button'),selectedPhoto=null,photoSettings={},photoDirty={};
function currentPhotoSetting(){var entry=photoSettings[selectedPhoto]||{},setting=entry[photoProfile.value]||{};return{zoom:Number(setting.zoom||1),rotation:Number(setting.rotation||0),mirror:setting.mirror===true,center_x:Number(setting.center_x||.5),center_y:Number(setting.center_y||.5)}}
function paintPhotoEditor(){if(!selectedPhoto)return;var setting=currentPhotoSetting(),orientation=screenOrientation.value==='portrait'?'portrait':'landscape';photoZoom.value=setting.zoom;photoZoomValue.textContent=setting.zoom.toFixed(1).replace(/\.0$/,'')+'×';photoRotation.value=String(setting.rotation);photoMirror.checked=setting.mirror;photoEditorPreview.dataset.profile=photoProfile.value;photoEditorPreview.dataset.orientation=orientation;if(photoEditorImage.naturalWidth){var box=photoEditorPreview.getBoundingClientRect(),rotated=setting.rotation%180!==0,sourceW=rotated?photoEditorImage.naturalHeight:photoEditorImage.naturalWidth,sourceH=rotated?photoEditorImage.naturalWidth:photoEditorImage.naturalHeight,cover=Math.max(box.width/sourceW,box.height/sourceH),imageW=photoEditorImage.naturalWidth*cover,imageH=photoEditorImage.naturalHeight*cover,scaledW=sourceW*cover*setting.zoom,scaledH=sourceH*cover*setting.zoom,offsetX=(.5-setting.center_x)*scaledW,offsetY=(.5-setting.center_y)*scaledH;photoEditorImage.style.width=imageW+'px';photoEditorImage.style.height=imageH+'px';photoEditorImage.style.transform='translate(-50%,-50%) translate('+offsetX+'px,'+offsetY+'px) rotate('+setting.rotation+'deg) scale('+(setting.mirror?-setting.zoom:setting.zoom)+','+setting.zoom+')'}photoSaveStatus.textContent=photoDirty[selectedPhoto+'|'+photoProfile.value]?'Modifiche pronte · premi “Salva modifiche” sul pannello.':'Seleziona una foto e regola l’anteprima.';photoSaveButton.disabled=!Object.keys(photoDirty).length}
function updatePhotoDraft(center){if(!selectedPhoto)return;var current=currentPhotoSetting(),setting={zoom:Number(photoZoom.value),rotation:Number(photoRotation.value),mirror:photoMirror.checked,center_x:center?center.x:current.center_x,center_y:center?center.y:current.center_y},name=selectedPhoto,profile=photoProfile.value;photoSettings[name]=photoSettings[name]||{};photoSettings[name][profile]=setting;photoDirty[name+'|'+profile]={name:name,profile:profile,setting:setting};paintPhotoEditor();photoSaveStatus.textContent='Modifiche in anteprima · premi “Salva modifiche” quando hai finito.';photoSaveButton.disabled=false}
function clamp(value,min,max){return Math.max(min,Math.min(max,value))}
var previewDrag=null;photoEditorPreview.addEventListener('pointerdown',function(event){if(!selectedPhoto||event.target!==photoEditorImage||!photoEditorImage.naturalWidth)return;event.preventDefault();var setting=currentPhotoSetting(),box=photoEditorPreview.getBoundingClientRect(),rotated=setting.rotation%180!==0,sourceW=rotated?photoEditorImage.naturalHeight:photoEditorImage.naturalWidth,sourceH=rotated?photoEditorImage.naturalWidth:photoEditorImage.naturalHeight,cover=Math.max(box.width/sourceW,box.height/sourceH),renderW=sourceW*cover*setting.zoom,renderH=sourceH*cover*setting.zoom;previewDrag={id:event.pointerId,x:event.clientX,y:event.clientY,center_x:setting.center_x,center_y:setting.center_y,renderW:renderW,renderH:renderH,boxW:box.width,boxH:box.height};try{photoEditorPreview.setPointerCapture(event.pointerId)}catch(_e){}});window.addEventListener('pointermove',function(event){if(!previewDrag||previewDrag.id!==event.pointerId)return;var drag=previewDrag,maxX=Math.max(0,.5-drag.boxW/(2*drag.renderW)),maxY=Math.max(0,.5-drag.boxH/(2*drag.renderH)),center={x:clamp(drag.center_x-(event.clientX-drag.x)/drag.renderW,.5-maxX,.5+maxX),y:clamp(drag.center_y-(event.clientY-drag.y)/drag.renderH,.5-maxY,.5+maxY)};updatePhotoDraft(center)});function endPreviewDrag(event){if(previewDrag&&(!event||event.pointerId===previewDrag.id))previewDrag=null}window.addEventListener('pointerup',endPreviewDrag);window.addEventListener('pointercancel',endPreviewDrag)

function savePhotoDrafts(){var items=Object.keys(photoDirty).map(function(key){return photoDirty[key]});if(!items.length)return;photoSaveButton.disabled=true;photoSaveStatus.textContent='Salvo '+items.length+(items.length===1?' modifica':' modifiche')+' sul Kindle…';fetch('/photo-settings',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({items:items})}).then(function(r){return r.json().then(function(data){if(!r.ok)throw new Error(data.error||'Salvataggio non riuscito');return data})}).then(function(data){photoSettings=data.settings||photoSettings;photoDirty={};paintPhotoEditor();photoSaveStatus.textContent='Modifiche salvate sul Kindle.';photoSaveButton.disabled=true}).catch(function(){photoSaveStatus.textContent='Salvataggio non riuscito. Le modifiche restano in anteprima: riprova.';photoSaveButton.disabled=false})}
function chooseGalleryPhoto(name){selectedPhoto=name;Array.prototype.forEach.call(photoGrid.querySelectorAll('.photo-card'),function(card){card.classList.toggle('is-active',card.dataset.name===name)});photoEditor.hidden=false;galleryEmpty.hidden=true;photoEditorName.textContent=name;photoPreviewError.hidden=true;photoEditorImage.hidden=false;photoEditorImage.src='/photo-image?name='+encodeURIComponent(name)+'&v='+Date.now();paintPhotoEditor();var active=photoGrid.querySelector('.photo-card.is-active');if(active&&active.scrollIntoView)active.scrollIntoView({block:'nearest',inline:'center'})}
function openGallery(){configPage.hidden=true;galleryPage.hidden=false;window.scrollTo(0,0);loadGallery()}
function closeGallery(){if(Object.keys(photoDirty).length&&!window.confirm('Ci sono modifiche non salvate. Vuoi uscire dalla galleria e perderle?'))return;photoDirty={};galleryPage.hidden=true;configPage.hidden=false;window.scrollTo(0,0)}
function loadGallery(){if(location.protocol==='file:'){galleryCount.textContent='';galleryEmpty.hidden=false;galleryEmpty.textContent='Collega il Kindle e apri Config dal suo indirizzo per vedere le foto.';return}fetch('/photo-list',{cache:'no-store'}).then(function(r){if(!r.ok)throw new Error('gallery');return r.json()}).then(function(data){var photos=data.photos||[];photoSettings=data.settings||{};Object.keys(photoDirty).forEach(function(key){var pending=photoDirty[key];photoSettings[pending.name]=photoSettings[pending.name]||{};photoSettings[pending.name][pending.profile]=pending.setting});galleryCount.textContent='('+photos.length+')';galleryTotal.textContent=photos.length+' '+(photos.length===1?'foto':'foto');if(galleryPage.hidden)return;photoGrid.textContent='';if(!photos.length){photoEditor.hidden=true;galleryEmpty.hidden=false;return}galleryEmpty.hidden=true;photos.forEach(function(photo){var card=document.createElement('button');card.type='button';card.className='photo-card';card.dataset.name=photo.name;var image=document.createElement('img');image.loading='lazy';image.decoding='async';image.src='/photo-thumb?name='+encodeURIComponent(photo.name);image.alt='Anteprima in bianco e nero: '+photo.name;image.onerror=function(){image.alt='Anteprima non disponibile: '+photo.name};var caption=document.createElement('span');caption.textContent=photo.name;card.appendChild(image);card.appendChild(caption);card.addEventListener('click',function(){chooseGalleryPhoto(photo.name)});photoGrid.appendChild(card)});if(selectedPhoto&&photos.some(function(photo){return photo.name===selectedPhoto}))chooseGalleryPhoto(selectedPhoto);else chooseGalleryPhoto(photos[0].name)}).catch(function(){galleryCount.textContent='';if(!galleryPage.hidden){photoGrid.innerHTML='<p class=\"gallery-loading\">Galleria non raggiungibile. Controlla che il server Config sia acceso.</p>';photoEditor.hidden=true}})}
galleryOpen.addEventListener('click',openGallery);document.getElementById('gallery-back').addEventListener('click',closeGallery);document.getElementById('gallery-refresh').addEventListener('click',loadGallery);photoEditorImage.addEventListener('error',function(){photoEditorImage.hidden=true;photoPreviewError.hidden=false});photoEditorImage.addEventListener('load',function(){photoEditorImage.hidden=false;photoPreviewError.hidden=true;paintPhotoEditor()});photoProfile.addEventListener('change',paintPhotoEditor);photoZoom.addEventListener('input',updatePhotoDraft);photoRotation.addEventListener('change',updatePhotoDraft);photoMirror.addEventListener('change',updatePhotoDraft);photoSaveButton.addEventListener('click',savePhotoDrafts);loadGallery();
})();
<script>
(function(){var q=document.getElementById('weather-search'),button=document.getElementById('weather-search-button'),list=document.getElementById('weather-results'),status=document.getElementById('weather-search-status'),current=document.getElementById('weather-place-current'),preview=document.getElementById('preview-weather-place'),save=document.getElementById('save-setting'),lang=document.documentElement.lang||'en';
window.showWeatherPlace=function(){var p=window.casaWeatherPlace;current.textContent=p&&p.name?p.name:'Non impostata';if(preview)preview.textContent=p&&p.name?p.name:'Meteo'};
function search(){var name=q.value.trim();list.innerHTML='';if(name.length<2){status.textContent='Scrivi almeno due lettere.';return}status.textContent='Cerco…';fetch('https://geocoding-api.open-meteo.com/v1/search?count=6&format=json&language='+encodeURIComponent(lang)+'&name='+encodeURIComponent(name)).then(function(r){return r.json()}).then(function(d){var found=d.results||[];if(!found.length){status.textContent='Nessuna località trovata.';return}status.textContent='Scegli la località giusta:';found.forEach(function(p){var b=document.createElement('button');b.type='button';b.className='weather-result';b.textContent=[p.name,p.admin1,p.country].filter(Boolean).join(', ');b.addEventListener('click',function(){window.casaWeatherPlace={name:p.name,latitude:p.latitude,longitude:p.longitude};window.showWeatherPlace();list.innerHTML='';status.textContent='Località scelta: salva la configurazione per applicarla.';save.disabled=false});list.appendChild(b)})}).catch(function(){status.textContent='Ricerca non riuscita: serve la connessione a Internet.'})}
button.addEventListener('click',search);q.addEventListener('keydown',function(e){if(e.key==='Enter'){e.preventDefault();search()}});document.getElementById('casa-language').addEventListener('change',function(){save.disabled=false});window.showWeatherPlace()})();
</script></body></html>]])
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
 return response(client,"200 OK",I18N.tr("<!doctype html><html lang='"..I18N.current().."'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>Foto ricevute</title><body><h1>Invio completato</h1><p>"..message.."</p><p>Le nuove foto compaiono subito in Casa.</p></body></html>"))
end

function Server:poll()
 if not self.listener then return end
 local client = self.listener:accept()
 if client then
  self.last_activity=os.time()
  client:settimeout(0);self.clients[#self.clients+1]={socket=client,buffer="",started=os.time()}
 end
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
   elseif item.expected==0 then
    local handled=pcall(self.handle,self,item.socket,item.header,"")
    if not handled then response(item.socket,"500 Internal Server Error","Errore temporaneo nel server Casa.","text/plain; charset=utf-8") end
    table.remove(self.clients,i);item=nil
   end
  end
  if item and item.header and #item.buffer-item.body_start+1>=item.expected then
   local handled=pcall(self.handle,self,item.socket,item.header,item.buffer:sub(item.body_start,item.body_start+item.expected-1))
   if not handled then response(item.socket,"500 Internal Server Error","Errore temporaneo nel server Casa.","text/plain; charset=utf-8") end
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

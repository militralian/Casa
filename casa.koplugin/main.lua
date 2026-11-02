local Device = require("device")
local UIManager = require("ui/uimanager")
local PluginShare = require("pluginshare")
local InputContainer = require("ui/widget/container/inputcontainer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local TextBoxWidget = require("ui/widget/textboxwidget")
local ImageWidget = require("ui/widget/imagewidget")
local BB = require("ffi/blitbuffer")
local InfoMessage = require("ui/widget/infomessage")
local Model = require("casa_model")
local Layout = require("casa_layout")
local PhotoServer = require("photo_server")
local KitchenServer = require("kitchen_server")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local ROOT = "/mnt/us"
local CACHE = ROOT.."/koreader/settings/casa-weather.json"
local PHOTO_DIR = ROOT.."/Casa/Foto"
local GAMES_DIR = ROOT.."/Casa/Games"
local ROM_DIR = GAMES_DIR.."/ROMs"
local function read(path)
 local f=io.open(path,"rb"); if not f then return nil end
 local v=f:read("*a"); f:close(); return v
end
local function decode(raw)
 if not raw then return nil end
 local ok,v=pcall(json.decode,raw)
 return ok and Model.valid(v) and v or nil
end

local TETRIS_SHAPES={
 {"....","####","....","...."},
 {".##.",".##.","....","...."},
 {".###","..#.","....","...."},
 {"#...","###.","....","...."},
 {"...#","###.","....","...."},
 {".##.","##..","....","...."},
 {"##..",".##.","....","...."},
}
local function rotateMatrix(matrix)
 local rotated={}
 for y=1,4 do
  local row={}
  for x=1,4 do row[x]=matrix[5-x]:sub(y,y) end
  rotated[y]=table.concat(row)
 end
 return rotated
end
local function blankRow(width)
 local row={};for x=1,width do row[x]=false end;return row
end

local Home = InputContainer:extend{covers_fullscreen=true, modal=true}
function Home:init()
 self.dimen=Geom:new{x=0,y=0,w=Device.screen:getWidth(),h=Device.screen:getHeight()}
 -- Keep Casa awake as requested; this is the largest remaining battery cost.
 self.standby_prevented=pcall(UIManager.preventStandby,UIManager)
 self.previous_keepalive=PluginShare.keepalive
 self.previous_pause_auto_suspend=PluginShare.pause_auto_suspend
 PluginShare.keepalive=true
 PluginShare.pause_auto_suspend=true
 self:setKindleScreenSaverPrevented(true)
 self.state={page="home",selected=1,game_selected=1,data=decode(read(CACHE)),agenda_page=0,
  agenda_text=read(ROOT.."/documents/Appunti/Agenda.txt"),game_filter="Tutti",
  calendar_month=0,night_active=false,
  game_letters={"Tutti","0–9","A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"}}
 local power_ok,pct=pcall(function() return Device:getPowerDevice():getCapacityHW() end)
 if power_ok and type(pct)=="number" then self.state.battery_pct=math.max(0,math.min(100,math.floor(pct+0.5))) end
 local rt=Model.romeTime(os.time())
 self.state.clock_text=string.format("%02d:%02d",rt.hour,rt.min)
 local ok,summary=pcall(json.decode,read(ROOT.."/casa/library-summary.json") or "{}")
 if ok and type(summary)=="table" and type(summary.count)=="number" then self.state.recipe_count=summary.count end
 self:loadPhotos()
 self.photo_server=PhotoServer:new(PHOTO_DIR,ROOT.."/Casa/intervallo-foto.txt",
  ROOT.."/koreader/plugins/casa.koplugin",ROOT.."/Casa/casa-update-key.txt",GAMES_DIR)
 local slideshow=self.photo_server:getSlideshowSettings()
 self.state.photo_interval=slideshow.interval_seconds
 self.state.timer_enabled=slideshow.timer_enabled
 self.state.shopping_enabled=slideshow.shopping_enabled
 self.state.screensaver_enabled=slideshow.screensaver_enabled
 self.state.screensaver_delay=slideshow.screensaver_delay_seconds
 self.state.night_mode=slideshow.night_mode
 self.state.night_enabled=slideshow.night_enabled
 self.state.night_start=slideshow.night_start
 self.state.night_end=slideshow.night_end
 self.state.calendar_enabled=slideshow.calendar_enabled
 self.state.weather_enabled=slideshow.weather_enabled
 self.state.photo_enabled=slideshow.photo_enabled
 self.state.weather_side=slideshow.weather_side
 self.state.photo_side=slideshow.photo_side
 self.state.calendar_side=slideshow.calendar_side
 self.state.widget_layout=slideshow.widget_layout
 self.state.screen_orientation=slideshow.screen_orientation
 self.state.power_button_enabled=slideshow.power_button_enabled
 self.state.power_button_action=slideshow.power_button_action
 self.state.clock_seconds_enabled=slideshow.show_clock_seconds
 if self.state.clock_seconds_enabled then self.state.clock_text=string.format("%02d:%02d:%02d",rt.hour,rt.min,rt.sec) end
 self.state.auto_standby_enabled=slideshow.auto_standby_enabled
 self.state.auto_standby_delay=slideshow.auto_standby_delay_seconds
 self.state.auto_standby_start=slideshow.auto_standby_start
 self.state.auto_standby_end=slideshow.auto_standby_end
 self.state.server_enabled=false
 self.state.kitchen_data=nil
 self.kitchen_server=KitchenServer:new(ROOT.."/Casa/kitchen.json")
 self.state.page="home"
 self.last_input=os.time()
 self.standby_task=function()
  self.standby_due=nil
  self:scheduleCasaStandby()
 end
 self:scheduleCasaStandby()
 self.state.photo_index=1
 self:choosePhoto(0)
 self.state.photo_count=#self.photos
 self:loadGameList()
 self:installStandbyPhotoHook()
 self:installWakeEventHook()
  self.last_photo_change=os.time()
 self.key_events={
  MoveUp={{"Up"},event="Move",args=-1}, MoveDown={{"Down"},event="Move",args=1},
  Choose={{"Press"}}, Back={{"Back"}}, Home={{"Home"}},
  Refresh={{"Menu"}}, Next={{"Right"},{"RPgFwd"},{"RPgBack"}},
  Previous={{"Left"},{"LPgFwd"},{"LPgBack"}},
 }
 self.tick=function()
  if self.closed then return end
  local now=os.time()
  if now-(self.last_network_check or 0)>=60 then
   self.last_network_check=now
   self:updateNetworkStatus()
  end
  if self.photo_server and (self.photo_server.upload_seq or 0)~=(self.last_seen_upload_seq or 0) then
   self.last_seen_upload_seq=self.photo_server.upload_seq or 0
   self:loadPhotos()
   local latest=self.photo_server.last_added_files and self.photo_server.last_added_files[#self.photo_server.last_added_files]
   if latest then
    for i,path in ipairs(self.photos) do
     if path==latest then
      self.state.photo_index=i
      self.state.photo_file=path
      self.state.transition=nil
      self.last_photo_change=now
      if self.state.page=="home" or self.state.page=="photos" then self:repaint() end
      break
     end
    end
   end
  end
  local settings=self.photo_server and self.photo_server:getSlideshowSettings()
  if settings then
   local standby_settings_changed=settings.auto_standby_enabled~=self.state.auto_standby_enabled
    or settings.auto_standby_delay_seconds~=self.state.auto_standby_delay
    or settings.auto_standby_start~=self.state.auto_standby_start
    or settings.auto_standby_end~=self.state.auto_standby_end
    or settings.power_button_enabled~=self.state.power_button_enabled
   if standby_settings_changed then self.last_input=now;self.standby_triggered=false end
   local old_layout=self.state.widget_layout or {}
   local new_layout=settings.widget_layout or {}
   local layout_changed=false
   for _,name in ipairs({"weather","calendar","photo","timer","shopping"}) do
    local before,after=old_layout[name] or {},new_layout[name] or {}
    for _,key in ipairs({"x","y","w","h"}) do
     if tonumber(before[key])~=tonumber(after[key]) then layout_changed=true end
    end
   end
   local widgets_changed=settings.calendar_enabled~=self.state.calendar_enabled
    or settings.weather_enabled~=self.state.weather_enabled
    or settings.photo_enabled~=self.state.photo_enabled
    or settings.timer_enabled~=self.state.timer_enabled
    or settings.shopping_enabled~=self.state.shopping_enabled
   if settings.interval_seconds~=self.state.photo_interval then
    self.state.photo_interval=settings.interval_seconds
    self.last_photo_change=now
   end
   if settings.screensaver_enabled and not self.state.screensaver_enabled then self.last_input=now end
   self.state.screensaver_enabled=settings.screensaver_enabled
   self.state.screensaver_delay=settings.screensaver_delay_seconds
   self.state.night_mode=settings.night_mode
   self.state.night_enabled=settings.night_enabled
   self.state.night_start=settings.night_start
   self.state.night_end=settings.night_end
   self.state.calendar_enabled=settings.calendar_enabled
   self.state.weather_enabled=settings.weather_enabled
   self.state.photo_enabled=settings.photo_enabled
   self.state.timer_enabled=settings.timer_enabled
   self.state.shopping_enabled=settings.shopping_enabled
   self.state.weather_side=settings.weather_side
   self.state.photo_side=settings.photo_side
   self.state.calendar_side=settings.calendar_side
   self.state.widget_layout=settings.widget_layout
   self.state.power_button_enabled=settings.power_button_enabled
   self.state.power_button_action=settings.power_button_action
   if settings.show_clock_seconds~=self.state.clock_seconds_enabled then self:setClockSecondsVisible(settings.show_clock_seconds) end
   self.state.auto_standby_enabled=settings.auto_standby_enabled
   self.state.auto_standby_delay=settings.auto_standby_delay_seconds
   self.state.auto_standby_start=settings.auto_standby_start
   self.state.auto_standby_end=settings.auto_standby_end
   self:scheduleCasaStandby()
   if settings.screen_orientation~=self.state.screen_orientation then
    self.state.screen_orientation=settings.screen_orientation
    self:applyOrientation(settings.screen_orientation)
   end
   -- Config writes settings to disk; redraw Casa when the web editor changes
   -- widget positions, sizes, or visibility so the new layout appears live.
   if (layout_changed or widgets_changed) and self.state.page=="home" then
    self:repaint()
   end
  end
  if self.state.server_enabled then
   local last_access=math.max(self.photo_server and self.photo_server.last_activity or 0,self.kitchen_server and self.kitchen_server.last_activity or 0)
   if last_access>0 and now-last_access>=300 then
    self:stopServices()
   end
  end
  if self.kitchen_server and self.state.server_enabled then
   local kitchen=self.kitchen_server:getData()
   local previous=self.state.kitchen_data or {}
   if kitchen.updated_at~=previous.updated_at or kitchen.timer_remaining_seconds~=previous.timer_remaining_seconds or kitchen.timer_running~=previous.timer_running then
    self.state.kitchen_data=kitchen
    if self.state.page=="home" then self:repaint() end
   else self.state.kitchen_data=kitchen end
  end
  local nt=Model.romeTime(now)
  local current_minutes=nt.hour*60+nt.min
  local function parseMinutes(value, fallback)
   local h,m=(value or ""):match("^(%d%d):(%d%d)$")
   h,m=tonumber(h),tonumber(m)
   if not h or not m or h>23 or m>59 then return fallback end
   return h*60+m
  end
  local start_minutes=parseMinutes(self.state.night_start,1320)
  local end_minutes=parseMinutes(self.state.night_end,420)
  local scheduled=start_minutes<end_minutes and current_minutes>=start_minutes and current_minutes<end_minutes or start_minutes>=end_minutes and (current_minutes>=start_minutes or current_minutes<end_minutes)
  local was_night=self.state.night_active
  self.state.night_active=self.state.night_mode=="automatic" and scheduled or self.state.night_enabled==true
  if was_night~=self.state.night_active then self:repaint() end
  if not self.state.screensaver_enabled and self.state.photo_screensaver and self.state.page=="photos" then
   self.state.page="home"
   self.state.photo_screensaver=false
   self.last_input=now
   self.last_photo_change=now
   self:repaint()
  end
  if self.state.screensaver_enabled and #self.photos>0 and self.state.page=="home" and not self.state.menu_open and not self.state.transition and now-(self.last_input or self.last_photo_change or now)>=self.state.screensaver_delay then
   self.state.page="photos"
   self.state.photo_screensaver=true
   self.last_photo_change=now
   self:repaint()
  end
  if (self.state.page=="home" or self.state.page=="photos") and #self.photos>0 and not self.state.transition and now-(self.last_photo_change or now)>=self.state.photo_interval then
   self:nextPhoto(1)
  end
  local rt=Model.romeTime(now)
  local minute_key=rt.year*100000000+rt.month*1000000+rt.day*10000+rt.hour*100+rt.min
  if not self.state.clock_seconds_enabled and minute_key~=self.last_clock_minute then
   self.last_clock_minute=minute_key
   self.state.clock_text=string.format("%02d:%02d",rt.hour,rt.min)
   self:repaint(Geom:new{x=430,y=0,w=370,h=55})
  end
  if now-(self.last_battery_check or 0)>=300 then
   self.last_battery_check=now
   local power_ok,pct=pcall(function() return Device:getPowerDevice():getCapacityHW() end)
   if power_ok and type(pct)=="number" then
    self.state.battery_pct=math.max(0,math.min(100,math.floor(pct+0.5)))
    self:repaint(Geom:new{x=730,y=0,w=70,h=55})
   end
  end
  -- Refresh live weather every minute while connected; failures retry after a minute.
  if now-(self.last_weather_check or 0)>=900 then
   self.last_weather_check=now
   if require("ui/network/manager"):isConnected() then self:refresh(false) end
  end
  UIManager:scheduleIn(10,self.tick)
 end
 UIManager:scheduleIn(10,self.tick)
 self.upload_tick=function()
  if self.closed then return end
  if self.state.server_enabled and self.photo_server then
   self.photo_server:poll()
   if os.time()-(self.last_ip_lookup or 0)>=15 then
    self.last_ip_lookup=os.time()
    local current_url=self.photo_server:getURL()
    if current_url then self.state.upload_url=current_url end
   end
  end
  if self.state.server_enabled and self.kitchen_server then
   self.kitchen_server:poll()
   if os.time()-(self.last_kitchen_ip_lookup or 0)>=15 then
    self.last_kitchen_ip_lookup=os.time()
    local kitchen_url=self.kitchen_server:getURL()
    if kitchen_url then self.state.kitchen_url=kitchen_url end
   end
  end
  local request_activity=math.max(self.photo_server and self.photo_server.last_activity or 0,self.kitchen_server and self.kitchen_server.last_activity or 0)
  if self.state.server_enabled and request_activity>(self.last_seen_server_activity or 0) then
   self.last_seen_server_activity=request_activity
   self.last_input=os.time()
   self.standby_triggered=false
   self:scheduleCasaStandby()
  end
  UIManager:scheduleIn(0.5,self.upload_tick)
 end
 self.clock_tick=function()
  if self.closed or not self.state.clock_seconds_enabled then return end
  local current=Model.romeTime(os.time())
  local value=string.format("%02d:%02d:%02d",current.hour,current.min,current.sec)
  if value~=self.state.clock_text then
   self.state.clock_text=value
   self:repaint(Geom:new{x=430,y=0,w=300,h=55})
  end
  UIManager:scheduleIn(1,self.clock_tick)
 end
 if self.state.clock_seconds_enabled then UIManager:scheduleIn(1,self.clock_tick) end
 self.last_weather_check=os.time()
end

function Home:loadGameList()
 self.game_list={"Serpente","Tetris","Labirinto","Salti","Memory"}
 self.state.game_results=self.game_list
 self.state.game_selected=math.max(1,math.min(self.state.game_selected or 1,#self.state.game_results))
 self.state.game_scroll=1
end
function Home:installStandbyPhotoHook()
 local Screensaver=require("ui/screensaver")
 local original=Screensaver.setup
 local home=self
 self.screensaver_module=Screensaver
 self.screensaver_setup_original=original
 Screensaver.setup=function(widget,...)
  local settings=G_reader_settings
  local photo=not home.closed and not home.state.power_button_enabled and home.state.photo_file
  if not photo or not settings then return original(widget,...) end
  local keys={"screensaver_type","screensaver_document_cover","screensaver_show_message"}
  local previous={}
  for _,key in ipairs(keys) do previous[key]={exists=settings:has(key),value=settings:readSetting(key)} end
  settings:saveSetting("screensaver_type","document_cover")
  settings:saveSetting("screensaver_document_cover",photo)
  settings:makeFalse("screensaver_show_message")
  local result={pcall(original,widget,...)}
  for _,key in ipairs(keys) do
   local saved=previous[key]
   if saved.exists then settings:saveSetting(key,saved.value) else settings:delSetting(key) end
  end
  if not result[1] then error(result[2]) end
  return unpack(result,2)
 end
 self.screensaver_setup_wrapper=Screensaver.setup
end
function Home:installWakeEventHook()
 local original=UIManager.event_handlers and UIManager.event_handlers.OutOfSS
 if type(original)~="function" then return end
 local home=self
 self.previous_outofss_handler=original
 self.wake_event_wrapper=function(...)
  local result={original(...)}
  UIManager:scheduleIn(0.1,function()
   if not home.closed then home:onResume() end
  end)
  return unpack(result)
 end
 UIManager.event_handlers.OutOfSS=self.wake_event_wrapper
end

function Home:updateNetworkStatus()
 local network=require("ui/network/manager")
 local old_wifi=self.state.wifi_enabled
 local old_connected=self.state.wifi_connected
 local old_online=self.state.internet_online
 local ok_wifi,wifi=pcall(network.isWifiOn,network)
 local ok_connected,connected=pcall(network.isConnected,network)
 wifi=ok_wifi and wifi==true
 connected=wifi and ok_connected and connected==true
 self.state.wifi_enabled=wifi
 self.state.wifi_connected=connected
 self.state.wifi_strength=0
 if connected then
  local ok_online,online=pcall(network.isOnline,network)
  self.state.internet_online=ok_online and online==true
  local f=io.open("/proc/net/wireless","r")
  if f then
   local raw=f:read("*a");f:close()
   local signal=raw and (raw:match("wlan0:%s+[%x]+%s+[%d%.%-]+%s+([%d%.%-]+)") or raw:match("wifi0:%s+[%x]+%s+[%d%.%-]+%s+([%d%.%-]+)"))
   signal=tonumber(signal)
   if signal then
    if signal<0 then
     self.state.wifi_strength=signal>=-55 and 4 or signal>=-67 and 3 or signal>=-75 and 2 or 1
    else
     self.state.wifi_strength=signal>=65 and 4 or signal>=50 and 3 or signal>=35 and 2 or 1
    end
   end
  end
 else
  self.state.internet_online=false
 end
 if old_wifi~=self.state.wifi_enabled or old_connected~=self.state.wifi_connected or old_online~=self.state.internet_online then
  self:repaint()
 end
end

function Home:ensureGameVisible()
 local count=#(self.state.game_results or {})
 local selected=self.state.game_selected or 1
 local first=self.state.game_scroll or 1
 if selected<first then first=selected elseif selected>first+6 then first=selected-6 end
 self.state.game_scroll=math.max(1,math.min(first,math.max(1,count-6)))
end

function Home:startROM()
 local name=(self.state.game_results or {})[self.state.game_selected or 1]
 if not name then
  UIManager:show(InfoMessage:new{text="Non ci sono ROM Game Boy installati."})
  return true
 end
 local emulator=GAMES_DIR.."/fbgnuboy"
 local launcher=GAMES_DIR.."/launch.sh"
 if not lfs.attributes(emulator,"mode") or not lfs.attributes(launcher,"mode") then
  UIManager:show(InfoMessage:new{text="L’emulatore per Kindle 4 non è ancora presente in Casa/Games."})
  return true
 end
 local command="/bin/sh "..string.format("%q",launcher).." "..string.format("%q",ROM_DIR.."/"..name).." >>"..string.format("%q",GAMES_DIR.."/game.log").." 2>&1 &"
 local ConfirmBox=require("ui/widget/confirmbox")
 UIManager:show(ConfirmBox:new{text="Controlli: frecce = direzione · Back = A · Menu = B · tasti pagina sinistri = Select/Start. Premi Home per uscire e tornare a Casa.",ok_text="Avvia",cancel_text="Annulla",ok_callback=function() os.execute(command) end})
 return true
end

function Home:startGame(index)
 local kinds={"snake","tetris","maze","platform","memory"}
 local kind=kinds[index or self.state.game_selected or 1]
 self.state.game_selected=index or self.state.game_selected or 1
 self.state.page="game"
 self.state.game={kind=kind,score=0,over=false,won=false}
 if kind=="snake" then
  local g=self.state.game
  g.width=24;g.height=16;g.snake={{x=11,y=8},{x=10,y=8},{x=9,y=8}}
  g.direction={x=1,y=0};g.next_direction={x=1,y=0}
  self:placeSnakeFood()
 elseif kind=="tetris" then
  local g=self.state.game
  g.width=10;g.height=18;g.board={}
  for y=1,g.height do g.board[y]=blankRow(g.width) end
  self:spawnTetrisPiece()
 elseif kind=="maze" then
  local g=self.state.game
  g.map={"###############","#.............#","#.###.###.###.#","#...#.....#...#","###.#.###.#.###","#...#...#...#.#","#.###.#.#.###.#","#.....#.#.....#","#.#####.#####.#","#.............#","###############"}
  g.x=2;g.y=2;g.dots={};g.remaining=0
  for y,row in ipairs(g.map) do for x=1,#row do if row:sub(x,x)=="." then g.dots[x..","..y]=true;g.remaining=g.remaining+1 end end end
  g.dots[g.x..","..g.y]=nil;g.remaining=g.remaining-1
 elseif kind=="platform" then
  local g=self.state.game
  g.width=26;g.height=14;g.x=2;g.y=11;g.vy=0;g.grounded=true
  g.coins={{x=4,y=9},{x=7,y=8},{x=11,y=9},{x=16,y=6},{x=20,y=9},{x=23,y=8}}
 elseif kind=="memory" then
  local g=self.state.game
  g.cards={1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8}
  for i=#g.cards,2,-1 do local j=math.random(i);g.cards[i],g.cards[j]=g.cards[j],g.cards[i] end
  g.revealed={};g.matched={};g.cursor=1;g.first=nil;g.second=nil;g.pairs=0;g.moves=0
 end
 self.game_generation=(self.game_generation or 0)+1
 local generation=self.game_generation
 self.game_tick=function()
  if self.closed or generation~=self.game_generation or self.state.page~="game" then return end
  self:stepGame()
  self:repaint()
  local g=self.state.game
  if g.over then return end
  local delay=g.kind=="snake" and 0.42 or g.kind=="tetris" and 0.8 or 0.22
  UIManager:scheduleIn(delay,self.game_tick)
 end
 if kind~="maze" and kind~="memory" then UIManager:scheduleIn(kind=="snake" and 0.42 or kind=="tetris" and 0.8 or 0.22,self.game_tick) end
 self:repaint()
end

function Home:placeSnakeFood()
 local g=self.state.game
 local free={}
 for y=2,g.height-1 do for x=2,g.width-1 do
  local used=false
  for _,part in ipairs(g.snake) do if part.x==x and part.y==y then used=true;break end end
  if not used then free[#free+1]={x=x,y=y} end
 end end
 g.food=free[math.random(#free)]
end

function Home:spawnTetrisPiece()
 local g=self.state.game
 local shape=TETRIS_SHAPES[math.random(#TETRIS_SHAPES)]
 g.piece={matrix=shape,x=4,y=0}
 if not self:tetrisFits(g.piece.x,g.piece.y,g.piece.matrix) then g.over=true end
end

function Home:tetrisFits(px,py,matrix)
 local g=self.state.game
 for row=1,4 do for col=1,4 do if matrix[row]:sub(col,col)=="#" then
  local x=px+col-1;local y=py+row-1
  if x<1 or x>g.width or y>g.height or (y>=1 and g.board[y][x]) then return false end
 end end end
 return true
end

function Home:lockTetrisPiece()
 local g=self.state.game;local p=g.piece
 for row=1,4 do for col=1,4 do if p.matrix[row]:sub(col,col)=="#" then
  local y=p.y+row-1;local x=p.x+col-1
  if y>=1 then g.board[y][x]=true end
 end end end
 local cleared=0;local y=g.height
 while y>=1 do
  local full=true
  for x=1,g.width do if not g.board[y][x] then full=false;break end end
  if full then table.remove(g.board,y);table.insert(g.board,1,blankRow(g.width));cleared=cleared+1 else y=y-1 end
 end
 if cleared>0 then g.score=g.score+({0,100,300,500,800})[cleared+1] end
 self:spawnTetrisPiece()
end

function Home:stepGame()
 local g=self.state.game
 if not g or g.over or g.paused then return end
 if g.kind=="snake" then
  g.direction=g.next_direction
  local head=g.snake[1]
  local next_head={x=head.x+g.direction.x,y=head.y+g.direction.y}
  if next_head.x<1 or next_head.x>g.width or next_head.y<1 or next_head.y>g.height then g.over=true;return end
  local eaten=g.food and next_head.x==g.food.x and next_head.y==g.food.y
  for i,part in ipairs(g.snake) do
   if part.x==next_head.x and part.y==next_head.y and (eaten or i<#g.snake) then g.over=true;return end
  end
  table.insert(g.snake,1,next_head)
  if eaten then g.score=g.score+10;self:placeSnakeFood() else table.remove(g.snake) end
 elseif g.kind=="tetris" then
  if self:tetrisFits(g.piece.x,g.piece.y+1,g.piece.matrix) then g.piece.y=g.piece.y+1 else self:lockTetrisPiece() end
 elseif g.kind=="platform" then
  if not g.grounded then
   g.vy=g.vy+0.55;g.y=g.y+g.vy
   local floor=(g.x==8 or g.x==9 or g.x==17 or g.x==18) and 14 or (g.x==5 or g.x==6) and 9 or (g.x==13 or g.x==14) and 7 or 11
   if g.y>=floor then
    if floor>=14 then g.over=true else g.y=floor;g.vy=0;g.grounded=true end
   end
   if g.y>13 then g.over=true end
  end
  local y=math.floor(g.y+0.5)
  for i=#g.coins,1,-1 do local c=g.coins[i];if c.x==g.x and math.abs(c.y-y)<=1 then table.remove(g.coins,i);g.score=g.score+1 end end
  if g.x>=25 then g.won=true;g.over=true end
 end
end

function Home:moveGame(dx,dy)
 local g=self.state.game
 if not g or g.over then return end
 if g.kind=="snake" then
  local d=g.next_direction
  if dx*d.x+dy*d.y==0 then g.next_direction={x=dx,y=dy} end
 elseif g.kind=="tetris" then
  if dx~=0 and self:tetrisFits(g.piece.x+dx,g.piece.y,g.piece.matrix) then g.piece.x=g.piece.x+dx
  elseif dy>0 then if self:tetrisFits(g.piece.x,g.piece.y+1,g.piece.matrix) then g.piece.y=g.piece.y+1 else self:lockTetrisPiece() end
  elseif dy<0 then local rotated=rotateMatrix(g.piece.matrix);if self:tetrisFits(g.piece.x,g.piece.y,rotated) then g.piece.matrix=rotated end end
 elseif g.kind=="maze" then
  local x=g.x+dx;local y=g.y+dy;local row=g.map[y]
  if row and row:sub(x,x)~="#" then
   g.x=x;g.y=y
   local key=x..","..y
   if g.dots[key] then g.dots[key]=nil;g.remaining=g.remaining-1;g.score=g.score+10;if g.remaining==0 then g.won=true;g.over=true end end
  end
 elseif g.kind=="platform" and dx~=0 then
  local x=math.max(1,math.min(g.width-1,g.x+dx))
  local target_floor=(x==8 or x==9 or x==17 or x==18) and 14 or (x==5 or x==6) and 9 or (x==13 or x==14) and 7 or 11
  if not g.grounded or target_floor>=g.y then g.x=x;if g.grounded and target_floor~=g.y then g.grounded=false;g.vy=0 end end
 elseif g.kind=="memory" then
  local col=(g.cursor-1)%4;local row=math.floor((g.cursor-1)/4)
  col=math.max(0,math.min(3,col+dx));row=math.max(0,math.min(3,row+dy));g.cursor=row*4+col+1
 end
 self:repaint()
end

function Home:gameAction()
 local g=self.state.game
 if not g then return end
 if g.over then self:startGame(self.state.game_selected);return end
 if g.kind=="snake" then
  g.paused=not g.paused
  if g.paused then UIManager:unschedule(self.game_tick)
  else UIManager:scheduleIn(0.42,self.game_tick) end
 elseif g.kind=="tetris" then
  while self:tetrisFits(g.piece.x,g.piece.y+1,g.piece.matrix) do g.piece.y=g.piece.y+1 end
  self:lockTetrisPiece()
 elseif g.kind=="platform" and g.grounded then g.vy=-2.8;g.grounded=false
 elseif g.kind=="memory" then
  if g.second then g.revealed[g.first]=nil;g.revealed[g.second]=nil;g.first=nil;g.second=nil end
  local cell=g.cursor
  if not g.matched[cell] and not g.revealed[cell] then
   g.revealed[cell]=true
   if not g.first then g.first=cell
   else
    g.second=cell;g.moves=g.moves+1
    if g.cards[g.first]==g.cards[cell] then g.matched[g.first]=true;g.matched[cell]=true;g.pairs=g.pairs+1;g.first=nil;g.second=nil;if g.pairs==8 then g.over=true;g.won=true end end
   end
  end
 end
 self:repaint()
end

function Home:leaveGame()
 self.game_generation=(self.game_generation or 0)+1
 if self.game_tick then UIManager:unschedule(self.game_tick) end
 self.last_input=os.time()
 self.state.game=nil
 self.state.page="games"
 self:repaint()
end

function Home:paintTo(bb,x,y)
 local width,height=Device.screen:getWidth(),Device.screen:getHeight()
 if width~=self.dimen.w or height~=self.dimen.h then
  self.dimen=Geom:new{x=0,y=0,w=width,h=height}
 end
 self.dimen.x=x; self.dimen.y=y
 local night=self.state.night_active==true and self.state.page~="photos"
 bb:paintRect(x,y,self.dimen.w,self.dimen.h,night and BB.COLOR_BLACK or BB.COLOR_WHITE)
 self.state.now=os.time()
 for _,c in ipairs(Layout.build(self.state,self.dimen.w,self.dimen.h)) do
  if c.kind=="rect" then
   local dark=(c.black==true)~=night
   bb:paintRect(x+c.x,y+c.y,c.w,c.h,dark and BB.COLOR_BLACK or BB.COLOR_WHITE)
  elseif c.kind=="photo" then
   local key=c.file..":"..math.floor(c.w).."x"..math.floor(c.h)..":"..tostring(c.rotation or 0)
   if self.photo_widget_key~=key then
    if self.photo_widget then self.photo_widget:free() end
    self.photo_widget=ImageWidget:new{file=c.file,width=c.w,height=c.h,scale_factor=0,rotation_angle=c.rotation or 0,alpha=false}
    self.photo_widget_key=key
   end
   self.photo_widget:paintTo(bb,x+c.x,y+c.y)
  elseif c.kind=="icon" then
   local icon_name=c.night and (c.name.."-night") or c.name
   local widget=ImageWidget:new{file=ROOT.."/koreader/plugins/casa.koplugin/icons/"..icon_name..".svg",width=c.w,height=c.h,alpha=true}
   widget:paintTo(bb,x+c.x,y+c.y);widget:free()
  else
   local widget=TextBoxWidget:new{text=c.text,width=math.floor(c.w),
    face=Font:getFace(c.serif and "FreeSerif.ttf" or "cfont",math.floor(c.size)),
    alignment=c.alignment,bold=c.bold,fgcolor=((c.white==true)~=night) and BB.COLOR_WHITE or BB.COLOR_BLACK,
    bgcolor=((c.white==true)~=night) and BB.COLOR_BLACK or BB.COLOR_WHITE,
    height=c.max_height,height_overflow_show_ellipsis=true}
   widget:paintTo(bb,x+c.x,y+c.y); widget:free()
  end
 end
end
function Home:repaint(region)
 if not self.closed then UIManager:setDirty(self,"ui",region or self.dimen) end
end
function Home:applyOrientation(orientation)
 local screen=Device.screen
 -- Counter-clockwise landscape keeps the Kindle's physical buttons on the right.
 local mode=orientation=="portrait" and screen.DEVICE_ROTATED_UPRIGHT or screen.DEVICE_ROTATED_COUNTER_CLOCKWISE
 local Event=require("ui/event")
 UIManager:broadcastEvent(Event:new("SetRotationMode",mode))
end
function Home:onResume()
 if self.closed then return true end
 local resume_time=os.time()
 if self.last_power_resume_time and resume_time-self.last_power_resume_time<2 then return true end
 self.last_power_resume_time=resume_time
 self.last_input=os.time()
 self.standby_triggered=false
 if self.kindle_screensaver_prevented then self:setKindleScreenSaverPrevented(true) end
 local settings=self.photo_server and self.photo_server:getSlideshowSettings()
 if settings then
  self.state.power_button_enabled=settings.power_button_enabled
  self.state.power_button_action=settings.power_button_action
  self.state.auto_standby_enabled=settings.auto_standby_enabled
  self.state.auto_standby_delay=settings.auto_standby_delay_seconds
  self.state.auto_standby_start=settings.auto_standby_start
  self.state.auto_standby_end=settings.auto_standby_end
  self:scheduleCasaStandby()
  if settings.show_clock_seconds~=self.state.clock_seconds_enabled then self:setClockSecondsVisible(settings.show_clock_seconds) end
 end
 local action=self.state.power_button_enabled and self.state.power_button_action or nil
 if action then
  self.state.menu_open=false
  if action=="photos" then
   self:loadPhotos()
   if #self.photos>0 then
    self.state.page="photos";self.state.photo_screensaver=false;self.state.photo_index=1;self:choosePhoto(0);self.last_photo_change=self.last_input
   else self.state.page="home";UIManager:scheduleIn(0.6,function() if not self.closed then UIManager:show(InfoMessage:new{text="Non ci sono foto nella galleria."}) end end) end
  elseif action=="calendar" then self.state.page="calendar";self.state.calendar_month=0
  elseif action=="weather" then self.state.page="day"
  elseif action=="timer" then self.state.page="timer"
  elseif action=="shopping" then self.state.page="shopping";self.state.shopping_scroll=0 end
 end
 UIManager:scheduleIn(0.5,function()
  if self.closed then return end
  self:applyOrientation(self.state.screen_orientation)
  self.dimen=Geom:new{x=0,y=0,w=Device.screen:getWidth(),h=Device.screen:getHeight()}
  UIManager:setDirty(nil,"full")
  self:repaint()
 end)
 return true
end
function Home:onSetRotationMode(mode)
 local screen=Device.screen
 if mode~=nil and screen:getRotationMode()~=mode then screen:setRotationMode(mode) end
 -- Match KOReader's FileManager behavior: dimensions and a full redraw must be
 -- propagated after the framebuffer changes orientation.
 self.dimen=Geom:new{x=0,y=0,w=screen:getWidth(),h=screen:getHeight()}
 UIManager:broadcastEvent(require("ui/event"):new("SetDimensions", screen:getSize()))
 UIManager:setDirty(nil,"full")
 self:repaint()
 return true
end
function Home:touchActivity()
 self.last_input=os.time()
 self.standby_triggered=false
 self:scheduleCasaStandby()
 if self.state.page=="photos" then self.state.page="home";self.state.photo_screensaver=false;self.last_photo_change=self.last_input end
end
function Home:scheduleCasaStandby()
 if self.closed or not self.standby_task then return end
 if not self.state.auto_standby_enabled or self.state.power_button_enabled or self.standby_triggered then
  self.standby_window_active=false
  UIManager:unschedule(self.standby_task)
  self.standby_due=nil
  return
 end
 local function minutes(value,fallback)
  local hour,minute=(value or ""):match("^(%d%d):(%d%d)$")
  hour,minute=tonumber(hour),tonumber(minute)
  if not hour or not minute or hour>23 or minute>59 then return fallback end
  return hour*60+minute
 end
 local current_time=Model.romeTime(os.time())
 local current=current_time.hour*60+current_time.min
 local start=minutes(self.state.auto_standby_start,0)
 local finish=minutes(self.state.auto_standby_end,1439)
 local in_window=start==finish or start<finish and current>=start and current<finish or start>finish and (current>=start or current<finish)
 if not in_window then
  self.standby_window_active=false
  UIManager:unschedule(self.standby_task)
  self.standby_due=nil
  return
 end
 if not self.standby_window_active then
  self.standby_window_active=true
  self.last_input=os.time()
  self.standby_triggered=false
 end
 local deadline=(self.last_input or os.time())+(tonumber(self.state.auto_standby_delay) or 300)
 if self.standby_due==deadline then return end
 UIManager:unschedule(self.standby_task)
 self.standby_due=deadline
 local remaining=deadline-os.time()
 if remaining<=0 then
  self.standby_due=nil
  self.standby_triggered=true
  UIManager:suspend()
 else
  UIManager:scheduleIn(remaining,self.standby_task)
 end
end
function Home:loadPhotos()
 local files={}
 local image_ext={jpg=true,jpeg=true,png=true,bmp=true}
 local ok,iter,dir_obj=pcall(lfs.dir,PHOTO_DIR)
 if ok and iter then
  for name in iter,dir_obj do
   local ext=name:match("%.([^.]+)$")
   if name~="." and name~=".." and not name:match("^%._") and ext and image_ext[ext:lower()] then
    local path=PHOTO_DIR.."/"..name
    if lfs.attributes(path,"mode")=="file" then files[#files+1]=path end
   end
  end
 end
 table.sort(files)
 self.photos=files
 self.state.photo_count=#files
end
function Home:startServices()
 if self.closed then return end
 if self.state.server_enabled then return end
 self.services_started=true
 -- The Kindle power daemon has a separate inactivity screen saver. KOReader's
 -- standby lock alone does not suppress that Kindle 4 screen transition.
 self:setKindleScreenSaverPrevented(true)
 if self.photo_server and self.photo_server:start() then
  self.state.upload_url=self.photo_server:getURL()
  self.last_ip_lookup=0
 end
 if self.kitchen_server and self.kitchen_server:start() then
  self.state.kitchen_url=self.kitchen_server:getURL()
  self.last_kitchen_ip_lookup=0
 end
 self.state.server_enabled=(self.photo_server and self.photo_server.listener~=nil) or (self.kitchen_server and self.kitchen_server.listener~=nil) or false
 self.last_server_activity=os.time()
 if self.state.server_enabled then self:setKindleScreenSaverPrevented(true) end
 if self.state.server_enabled then UIManager:scheduleIn(0.1,self.upload_tick) end
 self:repaint()
end
function Home:stopServices()
 if self.photo_server then self.photo_server:close() end
 if self.kitchen_server then self.kitchen_server:close() end
 UIManager:unschedule(self.upload_tick)
 self.state.server_enabled=false
 self.state.upload_url=nil
 self.state.kitchen_url=nil
 self.services_started=false
 self:repaint()
end
function Home:toggleServices()
 if self.state.server_enabled then
  self:stopServices()
  UIManager:show(InfoMessage:new{text="Server spento."})
 else
  self:startServices()
  UIManager:show(InfoMessage:new{text=self.state.server_enabled and "Server attivo. Il link è in basso a destra; si spegnerà dopo 5 minuti senza richieste." or "Non riesco ad avviare il server. Controlla che il Wi-Fi sia attivo."})
 end
end
function Home:setClockSecondsVisible(enabled)
 self.state.clock_seconds_enabled=enabled==true
 if self.clock_tick then UIManager:unschedule(self.clock_tick) end
 local current=Model.romeTime(os.time())
 if self.state.clock_seconds_enabled then
  self.state.clock_text=string.format("%02d:%02d:%02d",current.hour,current.min,current.sec)
  if self.clock_tick then UIManager:scheduleIn(1,self.clock_tick) end
 else
  self.state.clock_text=string.format("%02d:%02d",current.hour,current.min)
  self.last_clock_minute=current.year*100000000+current.month*1000000+current.day*10000+current.hour*100+current.min
 end
 self:repaint(Geom:new{x=430,y=0,w=300,h=55})
end
function Home:setKindleScreenSaverPrevented(prevent)
 local value=prevent and "1" or "0"
 local ok,a,_,code=pcall(os.execute,
  "/usr/bin/lipc-set-prop com.lab126.powerd preventScreenSaver "..value.." >/dev/null 2>&1")
 if ok and (a==true or a==0 or code==0) then
  self.kindle_screensaver_prevented=prevent
 end
end
function Home:startPhotos()
 self:loadPhotos()
 self.last_input=os.time()
 self.state.page="photos"
 self.state.photo_screensaver=false
 self.state.photo_index=1
 self:choosePhoto(0)
 self.last_photo_change=os.time()
 self:repaint()
end
function Home:nextPhoto(delta)
 self:loadPhotos()
 if #self.photos==0 then self.state.photo_index=nil;self.state.photo_file=nil
 else
  local old=self.state.photo_file
  self.state.photo_index=((self.state.photo_index or 1)-1+delta)%#self.photos+1
  self.state.photo_file=self.photos[self.state.photo_index]
  if old and old~=self.state.photo_file then self.state.transition=nil end
 end
 self.last_photo_change=os.time()
 self:repaint()
end
function Home:startTransition(old)
 self.state.transition=nil
end
function Home:choosePhoto(delta)
 if #self.photos==0 then self.state.photo_file=nil; return end
 self.state.photo_index=((self.state.photo_index or 1)-1+delta)%#self.photos+1
 self.state.photo_file=self.photos[self.state.photo_index]
 self.state.photo_rotation=0
end
function Home:onMove(delta)
 self:touchActivity()
 if self.state.page=="home" and self.state.menu_open then self.state.selected=((self.state.selected-1+delta)%15)+1
 elseif self.state.page=="games" then
  self.state.game_selected=math.max(1,math.min(#self.state.game_results,(self.state.game_selected or 1)+delta))
 elseif self.state.page=="game_search" then
  local count=#self.state.game_letters
  self.state.game_letter_selected=math.max(1,math.min(count,(self.state.game_letter_selected or 1)+delta*7))
 elseif self.state.page=="game" then
  local g=self.state.game
  if g and g.kind=="platform" and delta<0 then self:gameAction() else self:moveGame(0,delta) end
 elseif self.state.page=="calendar" then
  self.state.calendar_month=(self.state.calendar_month or 0)+(delta>0 and 1 or -1)
 elseif self.state.page=="home" or self.state.page=="day" or self.state.page=="week" then
  local order={"home","day","week"}
  local index=1
  for i,value in ipairs(order) do if value==self.state.page then index=i end end
  index=index+delta
  if index<1 or index>#order then self.state.page="home" else self.state.page=order[index] end
 elseif self.state.page=="shopping" then
  local items=(self.state.kitchen_data or {}).shopping_items or {}
  self.state.shopping_scroll=math.max(0,math.min(math.max(0,math.ceil(#items/12)-1),(self.state.shopping_scroll or 0)+delta))
 elseif self.state.page=="agenda" then
  local count=#Model.agenda(self.state.agenda_text)
  self.state.agenda_page=math.max(0,math.min(math.max(0,math.ceil(count/5)-1),self.state.agenda_page+delta))
 end
 self:repaint(); return true
end
function Home:onNext()
 if self.state.page=="calendar" then self.state.calendar_month=(self.state.calendar_month or 0)+1;self:repaint();return true end
 if self.state.page=="game" then self:moveGame(1,0);return true end
 if self.state.page=="games" then
  self:touchActivity()
  if #((self.state.game_results) or {})>0 then self.state.game_selected=math.min(#self.state.game_results,(self.state.game_selected or 1)+1) end
  self:repaint();return true
 end
 if self.state.page=="game_search" then self.state.game_letter_selected=math.min(#self.state.game_letters,(self.state.game_letter_selected or 1)+1);self:repaint();return true end
 if self.state.page=="photos" then self:touchActivity();self:nextPhoto(1); return true end
 self:touchActivity()
 if self.state.page=="home" then self:startPhotos(); return true end
 if self.state.page=="agenda" then return self:onMove(1) end
 self.state.page="home"; self:repaint(); return true
end
function Home:onPrevious()
 if self.state.page=="calendar" then self.state.calendar_month=(self.state.calendar_month or 0)-1;self:repaint();return true end
 if self.state.page=="game" then self:moveGame(-1,0);return true end
 if self.state.page=="games" then
  self:touchActivity()
  if #((self.state.game_results) or {})>0 then self.state.game_selected=math.max(1,(self.state.game_selected or 1)-1) end
  self:repaint();return true
 end
 if self.state.page=="game_search" then self.state.game_letter_selected=math.max(1,(self.state.game_letter_selected or 1)-1);self:repaint();return true end
 if self.state.page=="photos" then self:touchActivity();self:nextPhoto(-1); return true end
 self:touchActivity()
 if self.state.page=="home" then self:startPhotos();return true end
 if self.state.page=="agenda" then return self:onMove(-1) end
 self.state.page="home"; self:repaint(); return true
end
function Home:openFolder(folder)
 UIManager:close(self)
 local fm=require("apps/filemanager/filemanager").instance
 if fm then fm.file_chooser:changeToPath(ROOT.."/documents/"..folder)
 elseif self.owner.ui.showFileManager then
  self.owner.ui:onClose()
  require("apps/filemanager/filemanager"):showFiles(ROOT.."/documents/"..folder)
 end
end
function Home:onChoose()
 if self.state.page=="photos" then self:touchActivity(); self.state.page="home"; self.state.photo_screensaver=false; self:repaint(); return true end
 self:touchActivity()
 if self.state.page=="game_search" then
  local chosen=self.state.game_letters[self.state.game_letter_selected or 1] or "Tutti"
  self.state.game_filter=chosen;self.state.game_selected=1;self.state.game_search_focus=false;self.state.page="games";self:loadGameList();self:repaint();return true
 end
 if self.state.page=="games" then
  return self:startGame(self.state.game_selected or 1)
 end
 if self.state.page=="game" then self:gameAction();return true end
 if self.state.page~="home" then self.state.page="home";self.state.menu_open=false;self:repaint();return true end
 if not self.state.menu_open then self.state.menu_open=true;self.state.selected=1;self:repaint();return true end
 local choice=self.state.selected
 self.state.menu_open=false
 if choice==1 then self.state.page="week"; self:repaint()
 elseif choice==2 then self:openFolder("Ricette")
 elseif choice==3 then self:openFolder("Appunti")
 elseif choice==4 then self.state.page="agenda"; self:repaint()
 elseif choice==5 then self.state.page="calendar";self.state.calendar_month=0;self:repaint()
 elseif choice==6 then self.state.page="games";self.state.game_selected=1;self.state.game_search_focus=false;self:loadGameList();self:repaint()
 elseif choice==7 then self:startPhotos()
 elseif choice==8 then
  local config=self.photo_server:getSlideshowSettings();config.night_enabled=not self.state.night_active;config.night_mode="manual"
  self.photo_server:saveSlideshowSettings(config);self.state.night_mode="manual";self.state.night_enabled=config.night_enabled;self.state.night_active=config.night_enabled;self:repaint()
 elseif choice==9 then self:refresh(true)
 elseif choice==10 then
  UIManager:show(InfoMessage:new{text=self.state.upload_url and ("Sul telefono apri "..self.state.upload_url.." e scegli una foto. Kindle e telefono devono usare la stessa rete Wi-Fi.") or "Connetti il Kindle al Wi-Fi e riapri Casa per ricevere un indirizzo locale."})
 elseif choice==11 then
  local ConfirmBox=require("ui/widget/confirmbox")
  UIManager:show(ConfirmBox:new{text="KOReader si chiuderà e si riaprirà per caricare gli aggiornamenti. Il Kindle non verrà riavviato.",ok_text="Riavvia KOReader",ok_callback=function()
   UIManager:close(self)
   UIManager:restartKOReader()
  end})
 elseif choice==12 then
  local ConfirmBox=require("ui/widget/confirmbox")
  UIManager:show(ConfirmBox:new{text="Vuoi riavviare il Kindle adesso?",ok_text="Riavvia",ok_callback=function()
   UIManager:close(self)
   os.execute("sleep 1 && reboot &")
  end})
 elseif choice==13 then self:clearMemory()
 elseif choice==14 then UIManager:show(InfoMessage:new{text=self.state.kitchen_url and ("Apri dal telefono "..self.state.kitchen_url.." per usare il timer e la lista della spesa. Kindle e telefono devono essere sulla stessa Wi-Fi.") or "Attiva il server dal menu Casa per aprire il pannello Cucina sulla rete Wi-Fi."})
 elseif choice==15 then self:toggleServices()
 end
 return true
end
function Home:onBack()
 if self.state.page=="game" then self:leaveGame();return true end
 if self.state.page=="game_search" then self.state.page="games";self.state.game_search_focus=true;self:repaint();return true end
 if self.state.page=="games" then self.state.page="home";self.state.menu_open=false;self:repaint();return true end
 if self.state.page=="photos" then self.state.page="home"; self.state.photo_screensaver=false; self.last_input=os.time(); self:repaint(); return true end
 self:touchActivity()
 if self.state.page~="home" then self.state.page="home"; self.state.selected=1; self.state.menu_open=false; self:repaint()
 else self.state.menu_open=false; self.state.selected=1; self:repaint() end
 return true
end
function Home:onRefresh()
 if self.state.page=="photos" then self:touchActivity();self:nextPhoto(1);return true end
 if self.state.page=="games" then return true end
 self:touchActivity();self:refresh(true);return true
end
function Home:onHome()
 self.home_repeat_count=0
 self.home_memory_cleared=false
 self:touchActivity()
 self.game_generation=(self.game_generation or 0)+1
 if self.game_tick then UIManager:unschedule(self.game_tick);self.game_tick=nil end
 self.state.game=nil;self.state.page="home";self.state.menu_open=false
 self:repaint()
 return true
end
function Home:onKeyRepeat(key)
 if key:match({"Home"}) then
  self.home_repeat_count=(self.home_repeat_count or 0)+1
  if self.home_repeat_count>=12 and not self.home_memory_cleared then
   self.home_memory_cleared=true
   self:clearMemory()
  end
  return true
 end
 return InputContainer.onKeyRepeat(self,key)
end
function Home:clearMemory()
 self:touchActivity()
 collectgarbage("collect")
 local memory_before=collectgarbage("count")
 self.game_generation=(self.game_generation or 0)+1
 if self.game_tick then UIManager:unschedule(self.game_tick); self.game_tick=nil end
 self.state.game=nil
 self.state.page="home"
 self.state.menu_open=false
 self.state.photo_screensaver=false
 self.state.transition=nil
 if self.photo_widget then self.photo_widget:free(); self.photo_widget=nil end
 self.photo_widget_key=nil
 -- Close transient dialogs/documents above Casa, keeping the Casa dashboard
 -- itself alive and available as the return point.
 local to_close={}
 for _,window in ipairs(UIManager._window_stack or {}) do
  local widget=window.widget
  if widget and widget~=self and not widget.is_always_active then to_close[#to_close+1]=widget end
 end
 for i=#to_close,1,-1 do pcall(UIManager.close,UIManager,to_close[i]) end
 collectgarbage("collect")
 collectgarbage("collect")
 local memory_after=collectgarbage("count")
 local freed_kb=math.max(0,math.floor(memory_before-memory_after+0.5))
 local freed_text=freed_kb>=1024 and string.format("%.1f MB",freed_kb/1024) or (freed_kb.." KB")
 UIManager:show(InfoMessage:new{text="Memoria liberata: "..freed_text})
 self:repaint()
 return true
end
function Home:onCloseWidget()
 self.closed=true
 if self.screensaver_module and self.screensaver_module.setup==self.screensaver_setup_wrapper then
  self.screensaver_module.setup=self.screensaver_setup_original
 end
 if UIManager.event_handlers and UIManager.event_handlers.OutOfSS==self.wake_event_wrapper then
  UIManager.event_handlers.OutOfSS=self.previous_outofss_handler
 end
 if self.kindle_screensaver_prevented and not self.previous_keepalive then self:setKindleScreenSaverPrevented(false) end
 PluginShare.keepalive=self.previous_keepalive
 PluginShare.pause_auto_suspend=self.previous_pause_auto_suspend
 if self.standby_prevented then
  pcall(UIManager.allowStandby,UIManager)
  self.standby_prevented=false
 end
 UIManager:unschedule(self.tick)
 UIManager:unschedule(self.upload_tick)
 UIManager:unschedule(self.clock_tick)
 UIManager:unschedule(self.standby_task)
 if self.game_tick then UIManager:unschedule(self.game_tick) end
 if self.photo_server then self.photo_server:close() end
 if self.kitchen_server then self.kitchen_server:close() end
 if self.photo_widget then self.photo_widget:free();self.photo_widget=nil end
 UIManager:setDirty(nil,"full")
end
function Home:refresh(interactive)
 if self.busy or self.closed then return end
 local network=require("ui/network/manager")
 local function fetch()
  if self.closed then return end
  self.busy=true
  require("ui/trapper"):wrap(function()
   local complete,raw=require("ui/trapper"):dismissableRunInSubprocess(function()
    local http=require("ssl.https")
    local util=require("socketutil")
    util:set_timeout(8,15)
    local body={}
    local ok,code=pcall(function()
     local _,status=http.request{url=Model.url,sink=util.table_sink(body),
      protocol="any",verify="peer",options="all",cafile="./data/ca-bundle.crt"}
     return status
    end)
    util:reset_timeout()
    if ok and tonumber(code)==200 then return table.concat(body) end
   end,"Aggiorno il meteo…\nIndietro per annullare",true)
   self.busy=false
   if self.closed then return end
   local data=complete and decode(raw)
   if data then
    data.fetched_at=os.time()
    local f=io.open(CACHE..".tmp","wb")
    if f then f:write(json.encode(data));f:close();os.rename(CACHE..".tmp",CACHE) end
    self.state.data=data;self.state.status=nil
   elseif interactive then
    UIManager:show(InfoMessage:new{text="Meteo non aggiornato. Controlla il Wi-Fi e la data del Kindle, poi riprova. I dati salvati restano disponibili."})
   end
   self:repaint()
  end)
 end
 if interactive then network:runWhenConnected(fetch)
 elseif network:isConnected() then fetch() end
end

local Casa=WidgetContainer:extend{name="casa",is_doc_only=false}
function Casa:init()
 self.ui.menu:registerToMainMenu(self)
 local function showCasaOnce()
  if self.startup_opened then return end
  self.startup_opened=true
  local log=io.open(ROOT.."/casa/casa-startup.log","a")
  if log then log:write(os.date("%Y-%m-%d %H:%M:%S")," Casa avviata\n");log:close() end
  self:showHome()
 end
 if self.ui.registerPostInitCallback then
  self.ui:registerPostInitCallback(function() UIManager:scheduleIn(0.2,showCasaOnce) end)
 end
 -- Keep a fallback for KOReader launches where the file manager's post-init
 -- callback is skipped during startup.
 UIManager:scheduleIn(5,showCasaOnce)
end
function Casa:showHome()
 local home=Home:new{owner=self}
 home.last_input=os.time()
 UIManager:show(home)
 -- Web servers deliberately start disabled; open the Casa menu to enable them.
 UIManager:scheduleIn(0.35,function() if not home.closed then home:applyOrientation(home.state.screen_orientation) end end)
 local data=home.state.data
 if not data or os.time()-(data.fetched_at or 0)>3600 then
  UIManager:scheduleIn(1,function() home:refresh(false) end)
 end
end
function Casa:addToMainMenu(items)
 items.casa={text="Casa · meteo e documenti",sorting_hint="more_tools",callback=function() self:showHome() end}
end
return Casa

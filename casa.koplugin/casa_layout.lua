local M = require("casa_model")
local L = {}

function L.build(state, width, height)
 local out={}
 local sx,sy=width/800,height/600
 local function text(x,y,w,size,value,bold,white,serif,max_height,alignment)
  out[#out+1]={kind="text",x=x*sx,y=y*sy,w=w*sx,size=size*sx,text=value or "",bold=bold,white=white,serif=serif,max_height=max_height and max_height*sy,alignment=alignment}
 end
 local function rect(x,y,w,h,black)
  out[#out+1]={kind="rect",x=x*sx,y=y*sy,w=w*sx,h=h*sy,black=black}
 end
 -- Keep the battery icon's width/height ratio identical in both orientations.
 local battery_scale=math.min(sx,sy)
 local function battery_rect(x,y,w,h,black)
  out[#out+1]={kind="rect",x=x*battery_scale,y=y*battery_scale,
   w=w*battery_scale,h=h*battery_scale,black=black}
 end
 local function rule(y,x,w) rect(x or 30,y,w or 740,1,true) end
 local function icon(x,y,size,code)
  if state.night_active and state.page~="photos" then rect(x-2,y-2,size+4,size+4,true) end
  local name=type(code)=="string" and code:match("^wifi[1-4]$") and code or code=="wifi" and "wifi" or M.icon(code)
  out[#out+1]={kind="icon",x=x*sx,y=y*sy,w=size*sx,h=size*sy,name=name,night=state.night_active and state.page~="photos"}
 end
 local function photo(file,x,y,w,h)
  if file then out[#out+1]={kind="photo",file=file,x=x*sx,y=y*sy,w=w*sx,h=h*sy} end
 end
 local now=state.now or os.time()
 local date=M.date(now)
 local page=state.page or "home"
 local data=state.data
 local title=page=="home" and "KindHome" or page=="games" and "Mini giochi" or page=="game_search" and "Cerca un gioco" or page=="game" and "Partita" or page=="week" and "Meteo della settimana" or page=="day" and "Meteo di oggi" or page=="calendar" and "Calendario" or page=="photos" and "Foto" or "La tua agenda"

 if page~="photos" then
  text(28,9,360,28,title,true)
  text(28,44,430,19,date:gsub("^%l", string.upper):gsub(" (%l)", function(letter) return " "..string.upper(letter) end),true)
  if page=="home" then text(28,69,520,16,M.phrase(now),false,false,true,22) end
  text(432,11,168,34,state.clock_text or "--:--:--",true)
  -- Wi-Fi strength is shown by the number of visible waves beside the battery.
  if state.wifi_enabled then
   local strength=math.max(1,math.min(4,tonumber(state.wifi_strength) or 1))
   icon(700,11,31,"wifi"..strength)
  else
   text(620,20,108,16,"Disattivato",false)
  end
  -- Battery level is a compact, centered number inside a clear battery outline.
  battery_rect(735,14,48,26,true); battery_rect(737,16,44,22,false)
  battery_rect(783,21,5,12,true)
  local charge=math.max(0,math.min(100,tonumber(state.battery_pct) or 0))
  battery_rect(739,33,math.floor(40*charge/100),3,true)
  text(738,17,42,15,state.battery_pct and (tostring(state.battery_pct).."%") or "—",true,false,false,16,"center")
  rule(94,24,752)
 end

 if page=="home" then
  local frames=state.widget_layout or {
   weather={x=0,y=0,w=46,h=46},photo={x=46,y=0,w=54,h=100},calendar={x=0,y=46,w=46,h=54},timer={x=46,y=0,w=27,h=49},shopping={x=73,y=0,w=27,h=49},
  }
  local area={x=24,y=102,w=752,h=464}
  local function box(name)
   local f=frames[name] or {x=0,y=0,w=40,h=40}
   return area.x+f.x*area.w/100,area.y+f.y*area.h/100,f.w*area.w/100,f.h*area.h/100
  end
  local fresh=data and data.fetched_at and now-data.fetched_at<180 and now>=data.fetched_at
  local today=M.romeTime(now)
  local months={"Gennaio","Febbraio","Marzo","Aprile","Maggio","Giugno","Luglio","Agosto","Settembre","Ottobre","Novembre","Dicembre"}
  local function drawCalendar(x,y,w,h)
   local stamp=os.time{year=today.year,month=today.month+(state.calendar_month or 0),day=1,hour=12}
   local first=os.date("*t",stamp);local days=os.date("*t",os.time{year=first.year,month=first.month+1,day=0,hour=12}).day
   text(x+6,y+5,w-12,math.min(21,19*sx),months[first.month].." "..first.year,true)
   local week_full={"Domenica","Lunedì","Martedì","Mercoledì","Giovedì","Venerdì","Sabato"}
   local show_today=state.calendar_month==0 and h>=155
   if show_today then text(x+6,y+25,w-12,13,"Oggi: "..week_full[today.wday].." "..today.day,true) end
   local cellw=w/7;local calendar_y=show_today and y+61 or y+49;local cellh=math.max(13,math.min(30,(h-(show_today and 66 or 54))/6));local short={"L","M","M","G","V","S","D"}
   local abbreviated={"Lun","Mar","Mer","Gio","Ven","Sab","Dom"}
   local labels=cellw>=70 and {"Lunedì","Martedì","Mercoledì","Giovedì","Venerdì","Sabato","Domenica"} or cellw>=31 and abbreviated or short
   for c=1,7 do text(x+(c-1)*cellw,y+(show_today and 43 or 31),cellw,math.min(13,12*sx),labels[c],true) end
   local offset=(first.wday+5)%7
   for d=1,days do
    local cell=offset+d-1;local col=cell%7;local row=math.floor(cell/7);local px=x+col*cellw;local py=calendar_y+row*cellh
    local active=state.calendar_month==0 and d==today.day and first.month==today.month
    if active then rect(px+1,py,cellw-3,cellh-2,true) end
    text(px+2,py+1,cellw-5,math.min(17,15*sx),tostring(d),active,active)
   end
  end
  if state.weather_enabled~=false then
   local x,y,w,h=box("weather");local code=fresh and M.currentCode(data.current) or nil
   text(x+6,y+5,w-12,22,"Meteo locale",true)
   local temp_size=h<285 and 42 or 50
   text(x+6,y+30,math.min(104,w*.34),temp_size,fresh and M.number(data.current.temperature_2m).."°" or "—°",true,false,false,temp_size+10)
   local icon_size=math.min(46,h<190 and 34 or h/4,w*.15)
   icon(x+w*.34,y+32,icon_size,code)
   text(x+w*.34+icon_size+5,y+40,w*.60-icon_size,18,fresh and M.shortCondition(code) or "Meteo non aggiornato",true,false,false,27)
   if fresh and data.daily and h>=132 then
    local idx=M.todayIndex(data,now);local maxrows=h<190 and 2 or h<285 and 4 or 7;local rowstep=h>=285 and math.min(32,(h-120)/maxrows) or 23
    local forecast_y=30+temp_size+20
    for i=1,math.min(maxrows,7) do
     local ry=y+forecast_y+(i-1)*rowstep;local day=data.daily.time[i]
     text(x+5,ry,53,14,i==idx and "Oggi" or day:sub(9,10).."/"..day:sub(6,7),true)
     icon(x+59,ry-2,math.min(19,rowstep),data.daily.weather_code[i])
     text(x+81,ry,w-185,13,M.shortCondition(data.daily.weather_code[i]),false,false,false,22)
     text(x+w-103,ry,98,13,M.number(data.daily.temperature_2m_min[i]).."° / "..M.number(data.daily.temperature_2m_max[i]).."°",true)
    end
   elseif h>=132 then
    text(x+6,y+91,w-12,14,fresh and "Previsioni non disponibili" or "Collega il Wi-Fi per il meteo")
   end
   if h>=285 and fresh then
    text(x+6,y+72,w-12,14,"Pioggia "..M.number(data.current.precipitation).." mm · Vento "..M.number(data.current.wind_speed_10m).." km/h")
   end
  end
  if state.photo_enabled~=false then
   local x,y,w,h=box("photo")
   rect(x,y,w,h,true);rect(x+2,y+2,w-4,h-4,false)
   if state.photo_file then photo(state.photo_file,x+6,y+6,w-12,h-12) else text(x+18,y+h/2,w-36,20,"Aggiungi foto in Casa/Foto",true) end
  end
  if state.calendar_enabled then
   local x,y,w,h=box("calendar")
   rect(x,y,w,h,true);rect(x+2,y+2,w-4,h-4,false)
   drawCalendar(x+5,y+5,w-10,h-10)
  end
  local kitchen=state.kitchen_data or {}
  if state.timer_enabled then
   local x,y,w,h=box("timer")
   rect(x,y,w,h,true);rect(x+2,y+2,w-4,h-4,false)
   text(x+7,y+6,w-14,math.min(18,16*sx),"Timer cucina",true)
   local remaining=math.max(0,tonumber(kitchen.timer_remaining_seconds) or tonumber(kitchen.timer_duration_seconds) or 600)
   local timer_text=string.format("%02d:%02d",math.floor(remaining/60),remaining%60)
   text(x+7,y+30,w-14,math.min(40,36*sx),timer_text,true,false,false,43)
   local timer_status=kitchen.timer_running and "In corso" or remaining==0 and "Scaduto" or "Pronto"
   text(x+7,y+h-27,w-14,14,timer_status,false)
  end
  if state.shopping_enabled then
   local x,y,w,h=box("shopping")
   rect(x,y,w,h,true);rect(x+2,y+2,w-4,h-4,false)
   text(x+7,y+6,w-14,math.min(18,16*sx),"Lista della spesa",true)
   local items=kitchen.shopping_items or {}
   local row_h=math.max(18,math.min(27,(h-38)/5))
   for i=1,math.min(#items,5) do
    local item=items[i]
    local mark=item.checked and "✓ " or "□ "
    text(x+8,y+30+(i-1)*row_h,w-16,math.min(17,15*sx),mark..item.text,item.checked,item.checked,false,row_h)
   end
   if #items>5 then text(x+8,y+h-24,w-16,13,"+"..(#items-5).." altri",false) end
   if #items==0 then text(x+8,y+33,w-16,15,"Lista vuota",false) end
  end
  if state.menu_open then
   rect(28,105,322,446,true); rect(30,107,318,442,false)
   local labels={"Meteo settimana",state.recipe_count and ("Ricette · "..state.recipe_count) or "Ricette","Appunti","Agenda","Calendario mensile","Mini giochi","Cornice digitale",state.night_active and "Modalità notte: attiva" or "Modalità notte: spenta","Aggiorna meteo","Config Casa","Riavvia KOReader","Riavvia Kindle","Libera memoria","Timer e lista"}
   for i,label in ipairs(labels) do
    local y=111+(i-1)*32
    local selected=i==state.selected
    if selected then rect(39,y-2,300,35,true) end
    text(49,y,278,23,label,selected,selected,false,27)
   end
  end
  local events=M.agenda(state.agenda_text,now)
  if events[1] then text(30,559,340,15,"Prossimo: "..events[1].date:sub(9,10).."/"..events[1].date:sub(6,7).." · "..events[1].hour.." · "..events[1].title,false,false,false,24) end
  text(28,582,510,14,state.menu_open and "Su/giù: scegli · Centro: apri · Indietro: chiudi menu" or "Centro: menu · Frecce: galleria · Su/giù: meteo")
  text(550,581,230,15,state.internet_online and state.upload_url and ("Config: "..state.upload_url) or "NO INTERNET FOUND",false)
 elseif page=="calendar" then
  local today=M.romeTime(now)
  local stamp=os.time{year=today.year,month=today.month+(state.calendar_month or 0),day=1,hour=12}
  local first=os.date("*t",stamp);local days=os.date("*t",os.time{year=first.year,month=first.month+1,day=0,hour=12}).day
  local months={"Gennaio","Febbraio","Marzo","Aprile","Maggio","Giugno","Luglio","Agosto","Settembre","Ottobre","Novembre","Dicembre"}
  text(30,107,720,24,months[first.month].." "..first.year,true)
  local names={"L","M","M","G","V","S","D"}
  local x0,y0=78,158;local cw=90
  for col=1,7 do text(x0+(col-1)*cw,y0,cw-4,20,names[col],true) end
  local offset=(first.wday+5)%7
  for day=1,days do
   local cell=offset+day-1;local row=math.floor(cell/7);local col=cell%7
   local x=x0+col*cw;local y=y0+31+row*54
   local selected=state.calendar_month==0 and day==today.day and first.month==today.month
   if selected then rect(x-4,y-5,46,38,true) end
   text(x,y,40,22,tostring(day),selected,selected)
   rule(y+34,x-2,56)
  end
  text(30,548,700,18,"← / →: mese precedente o successivo · Centro/Home: Casa")
 elseif page=="games" then
  local results=state.game_results or {}
  text(32,106,700,22,"Cinque giochi semplici, pensati per i tasti",true)
  rule(145,30,740)
  for row=1,5 do
   local index=row;local item=results[index]
   if item then
    local y=170+(row-1)*70;local selected=index==(state.game_selected or 1)
    if selected then rect(34,y-7,730,47,true) end
    text(49,y,49,16,string.format("%04d",index),false,selected)
    local display=item
    text(105,y-1,640,20,display,selected,selected,false,30)
    rule(y+35,46,710)
   end
  end
  text(28,582,740,14,"Su/giù: scegli · Centro: avvia · Indietro: torna a Casa")
 elseif page=="game_search" then
  local letters=state.game_letters or {"Tutti","0–9","A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"}
  text(42,110,700,20,"Scegli un’iniziale per restringere l’elenco",true)
  rect(104,160,592,278,true);rect(106,162,588,274,false)
  for i,label in ipairs(letters) do
   local col=(i-1)%7;local row=math.floor((i-1)/7);local x=120+col*82;local y=182+row*58
   local selected=i==(state.game_letter_selected or 1)
   if selected then rect(x-7,y-8,66,42,true) end
   text(x,y,52,22,label,true,selected)
  end
  text(28,582,740,14,"Frecce: scegli lettera · Centro: applica · Back: elenco giochi")
 elseif page=="game" then
  local g=state.game or {}
  local names={snake="Serpente",tetris="Blocchi",maze="Labirinto",platform="Salti",memory="Memory"}
  text(30,108,450,21,names[g.kind] or "Gioco",true)
  text(570,108,205,19,"Punti: "..tostring(g.score or 0),true)
  if g.kind=="snake" then
   local cell=18;local x0,y0=184,143
   rect(x0-3,y0-3,g.width*cell+6,g.height*cell+6,true);rect(x0,y0,g.width*cell,g.height*cell,false)
   for _,part in ipairs(g.snake or {}) do rect(x0+(part.x-1)*cell+1,y0+(part.y-1)*cell+1,cell-2,cell-2,true) end
   if g.food then local fx=x0+(g.food.x-1)*cell+5;local fy=y0+(g.food.y-1)*cell+5;rect(fx,fy,8,8,true) end
   text(28,582,740,14,g.over and "Partita finita · Centro: riprova · Back: giochi" or g.paused and "In pausa · Centro: riprendi · Back: esci" or "Frecce: guida · Centro: pausa · Back: esci")
  elseif g.kind=="tetris" then
   local cell=20;local x0,y0=300,128
   rect(x0-3,y0-3,g.width*cell+6,g.height*cell+6,true);rect(x0,y0,g.width*cell,g.height*cell,false)
   for y=1,g.height do for x=1,g.width do if g.board[y][x] then rect(x0+(x-1)*cell+1,y0+(y-1)*cell+1,cell-2,cell-2,true) end end end
   if g.piece then for row=1,4 do for col=1,4 do if g.piece.matrix[row]:sub(col,col)=="#" then
    local bx=g.piece.x+col-1;local by=g.piece.y+row-1
    if by>=1 then rect(x0+(bx-1)*cell+1,y0+(by-1)*cell+1,cell-2,cell-2,true) end
   end end end end
   text(28,582,740,14,g.over and "Partita finita · Centro: riprova · Back: giochi" or "←/→ sposta · ↑ ruota · ↓ scendi · Centro: lascia cadere")
  elseif g.kind=="maze" then
   local cell=28;local x0,y0=190,137
   for y,row in ipairs(g.map or {}) do for x=1,#row do
    local px=x0+(x-1)*cell;local py=y0+(y-1)*cell
    if row:sub(x,x)=="#" then rect(px,py,cell,cell,true)
    else
     rect(px,py,cell,cell,false)
     if g.dots[x..","..y] then rect(px+12,py+12,4,4,true) end
    end
   end end
   text(x0+(g.x-1)*cell+2,y0+(g.y-1)*cell+2,cell-4,cell-4,"@",true,false,false,24)
   text(28,582,740,14,g.over and (g.won and "Hai raccolto tutti i puntini! · Centro: rigioca" or "Labirinto finito · Centro: rigioca") or ("Raccogli tutti i puntini · Restano "..tostring(g.remaining or 0)..""))
  elseif g.kind=="platform" then
   local cell=20;local x0,y0=140,151
   rect(x0-3,y0-3,g.width*cell+6,15*cell+6,true);rect(x0,y0,g.width*cell,15*cell,false)
   for x=1,g.width do
    local floor=(x==8 or x==9 or x==17 or x==18) and nil or 12
    if floor then rect(x0+(x-1)*cell,y0+floor*cell,cell,cell,true) end
   end
   for _,b in ipairs({{x=5,y=10},{x=6,y=10},{x=13,y=8},{x=14,y=8}}) do rect(x0+(b.x-1)*cell,y0+b.y*cell,cell,cell,true) end
   for _,c in ipairs(g.coins or {}) do rect(x0+(c.x-1)*cell+7,y0+c.y*cell+7,7,7,true) end
   text(x0+(25-1)*cell,y0+10*cell,cell,25,"F",true)
   local py=y0+math.floor(g.y*cell)
   rect(x0+(g.x-1)*cell+2,py+2,cell-4,cell-4,true)
   text(28,582,740,14,g.over and (g.won and "Livello completato! · Centro: rigioca" or "Sei caduto · Centro: rigioca") or "←/→ cammina · Centro o ↑ salta · Back: esci")
  elseif g.kind=="memory" then
   local cell=72;local x0,y0=256,143
   for i=1,16 do
    local col=(i-1)%4;local row=math.floor((i-1)/4);local x=x0+col*cell;local y=y0+row*cell
    local focus=i==g.cursor;local open=g.revealed[i] or g.matched[i]
    rect(x-2,y-2,cell-5,cell-5,focus);rect(x,y,cell-9,cell-9,open)
    text(x+12,y+11,cell-32,30,open and tostring(g.cards[i]) or "•",open or focus,open or focus,false,38)
   end
   text(30,539,740,18,"Coppie "..tostring(g.pairs).."/8 · Mosse "..tostring(g.moves),true)
   text(28,582,740,14,g.over and "Tutte le coppie trovate · Centro: rigioca · Back: giochi" or "Frecce: sposta · Centro: gira carta · Back: esci")
  end
  if g.over then rect(218,263,364,68,true);rect(220,265,360,64,false);text(234,284,330,24,g.won and "Hai vinto!" or "Fine partita",true) end
 elseif page=="photos" then
  if state.photo_file then photo(state.photo_file,0,0,800,600)
  else text(80,280,640,26,"Nessuna foto in Casa/Foto",true) end
 elseif page=="day" then
  text(32,106,720,23,"Meteo locale · situazione attuale",true)
  local fresh=data and data.fetched_at and now-data.fetched_at<180 and now>=data.fetched_at
  if fresh then
   local c=M.currentCode(data.current)
   icon(38,146,100,c)
   text(155,151,200,55,M.number(data.current.temperature_2m).."°",true)
   text(360,158,385,29,M.condition(c),true)
   local rain=M.number(data.current.precipitation)
   local cloud=M.number(data.current.cloud_cover)
   local wind=M.number(data.current.wind_speed_10m)
   local direction=M.windDirection(data.current.wind_direction_10m)
   text(40,270,700,23,"Oggi: "..M.condition(c)..". Temperatura percepita "..M.number(data.current.apparent_temperature).."°.",false,false,false,50)
   text(40,321,700,23,"Umidità "..M.number(data.current.relative_humidity_2m).."%; copertura nuvolosa "..cloud.."%.",false,false,false,50)
   text(40,372,700,23,"Precipitazioni rilevate: "..rain.." mm. Vento "..wind.." km/h da "..direction..".",false,false,false,50)
   text(40,423,700,23,"Pressione "..M.number(data.current.pressure_msl).." hPa.",false,false,false,50)
   local idx=M.todayIndex(data,now)
   if idx then text(40,475,700,22,"Previsione del giorno: minima "..M.number(data.daily.temperature_2m_min[idx]).."°, massima "..M.number(data.daily.temperature_2m_max[idx]).."°, probabilità di pioggia "..M.number(data.daily.precipitation_probability_max[idx]).."%.",false,false,false,60) end
  else text(40,210,700,25,"Dati meteo da aggiornare. Controlla il Wi-Fi e premi Menu nella schermata Casa.") end
  text(28,582,740,14,"Su/giù: previsioni settimanali · Centro/Home: Casa")
 elseif page=="week" then
  text(32,105,720,22,"Meteo locale",true)
  if data then
   for i=1,7 do
    local y=143+(i-1)*55
    local day=data.daily.time[i]
    text(32,y,90,19,day:sub(9,10).."/"..day:sub(6,7),true)
    icon(128,y-4,39,data.daily.weather_code[i])
    text(181,y,235,18,M.condition(data.daily.weather_code[i]),false,false,false,25)
    text(421,y,135,16,"Pioggia "..M.number(data.daily.precipitation_probability_max[i]).."%")
    text(590,y,175,20,M.number(data.daily.temperature_2m_min[i]).." / "..M.number(data.daily.temperature_2m_max[i]).."°",true)
    rule(y+43,32,736)
   end
  else text(32,220,720,24,"Collega il Wi-Fi per scaricare le previsioni.") end
  text(28,582,740,14,"Su/giù: Casa · Centro/Home: Casa")
 elseif page=="agenda" then
  text(32,112,730,18,"Agenda locale")
  local entries=M.agenda(state.agenda_text,now)
  if #entries==0 then
   text(32,190,730,26,"Nessun appuntamento inserito",true)
   text(32,238,730,20,"Aggiungi un impegno nel file Agenda.txt, dentro Appunti.")
   text(32,278,730,18,"Formato: AAAA-MM-GG HH:MM | Titolo")
  else
   local offset=(state.agenda_page or 0)*5
   for i=1,5 do
    local e=entries[offset+i]
    if e then local y=151+(i-1)*75;text(32,y,730,17,e.date:sub(9,10).."/"..e.date:sub(6,7).."/"..e.date:sub(1,4).."  "..e.hour,true);text(32,y+24,730,20,e.title,false,false,false,38);rule(y+62,32,736) end
   end
  end
  text(28,582,740,14,"Centro/Home: Casa · Su/giù: appuntamenti")
 end
 return out
end
return L

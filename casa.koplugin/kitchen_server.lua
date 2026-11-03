local socket=require("socket")
local json=require("json")
local Device=require("device")
local I18N=require("casa_i18n")

local KitchenServer={}
KitchenServer.__index=KitchenServer

local function response(client,status,body,content_type)
 body=body or ""
 if content_type and content_type:find("^text/plain") then body=I18N.tr(body) end
 local message="HTTP/1.1 "..status.."\r\nContent-Type: "..(content_type or "text/html; charset=utf-8")
  .."\r\nContent-Length: "..#body.."\r\nConnection: close\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\n\r\n"..body
 pcall(function()
  client:settimeout(5)
  local sent=1
  while sent<=#message do
   local last,err,partial=client:send(message,sent)
   if last then sent=last+1 elseif partial and partial>=sent then sent=partial+1 else break end
  end
 end)
 pcall(function() client:close() end)
end

function KitchenServer:new(path)
 return setmetatable({path=path,clients={},item_seq=0},self)
end

function KitchenServer:readData()
 local f=io.open(self.path,"rb")
 local data
 if f then
  local raw=f:read("*a");f:close()
  local ok,value=pcall(json.decode,raw or "")
  if ok and type(value)=="table" then data=value end
 end
 data=data or {}
 data.timer_duration_seconds=math.max(60,math.min(86400,math.floor(tonumber(data.timer_duration_seconds) or 600)))
 data.timer_remaining_seconds=math.max(0,math.min(86400,math.floor(tonumber(data.timer_remaining_seconds) or data.timer_duration_seconds)))
 data.timer_running=data.timer_running==true
 data.timer_end_time=tonumber(data.timer_end_time) or 0
 if type(data.shopping_items)~="table" then data.shopping_items={} end
 local items={}
 for _,item in ipairs(data.shopping_items) do
  if type(item)=="table" and type(item.id)=="string" and type(item.text)=="string" then
   local value=item.text:gsub("[%z\1-\31]"," "):gsub("^%s+",""):gsub("%s+$",""):sub(1,72)
   if value~="" then items[#items+1]={id=item.id,text=value,checked=item.checked==true} end
  end
  if #items>=100 then break end
 end
 data.shopping_items=items
 return data
end

function KitchenServer:writeData(data)
 data.updated_at=os.time()
 local f=io.open(self.path..".tmp","wb")
 if not f then return false end
 f:write(json.encode(data));f:close()
 return os.rename(self.path..".tmp",self.path)~=nil
end

function KitchenServer:getData()
 local data=self:readData()
 local now=os.time()
 if data.timer_running then
  data.timer_remaining_seconds=math.max(0,data.timer_end_time-now)
  if data.timer_remaining_seconds==0 then
   data.timer_running=false;data.timer_end_time=0
   self:writeData(data)
  end
 else
  data.timer_end_time=0
 end
 return data
end

function KitchenServer:start()
 if self.listener then return true end
 local server,err=socket.bind("*",8766)
 if not server then self.error=err;return false end
 server:settimeout(0)
 self.listener=server
 self.last_activity=os.time()
 if Device:isKindle() then
  os.execute("iptables -A INPUT -i wlan0 -p tcp --dport 8766 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT >/dev/null 2>&1; iptables -A OUTPUT -o wlan0 -p tcp --sport 8766 -m conntrack --ctstate ESTABLISHED -j ACCEPT >/dev/null 2>&1")
  self.firewall_open=true
 end
 return true
end

function KitchenServer:getURL()
 local udp=socket.udp()
 local ok=udp:setpeername("1.1.1.1",53)
 local ip=ok and select(1,udp:getsockname())
 udp:close()
 if ip and ip~="0.0.0.0" then return "http://"..ip..":8766" end
end

function KitchenServer:page()
 return I18N.page("kitchen",[[<!doctype html><html lang="it"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="theme-color" content="#eff7fb"><title>KindHome · Cucina</title>
<style>
:root{color-scheme:light;--paper:#eff7fb;--surface:#fff;--ink:#203746;--muted:#587180;--line:#d5e5ed;--blue:#3a8fb8;--blue-dark:#236d94;--blue-pale:#e5f2f8;--error:#a33c35;--success:#286d55}
*{box-sizing:border-box}html{min-height:100%;background:var(--paper)}body{margin:0;min-height:100vh;padding:max(18px,env(safe-area-inset-top)) 14px max(24px,env(safe-area-inset-bottom));font:16px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:var(--ink);background:var(--paper)}main{width:min(100%,520px);margin:0 auto}.top{display:flex;align-items:center;justify-content:space-between;gap:14px;margin:3px 2px 22px}.brand{font:700 15px Georgia,serif;color:var(--blue-dark)}.online{font-size:12px;color:var(--muted)}h1{margin:0;font:600 32px/1.1 Georgia,"Times New Roman",serif;letter-spacing:-.025em}.lede{margin:8px 0 22px;color:var(--muted);font-size:14px}.section{padding:18px 0;border-top:1px solid var(--line)}.section-head{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:13px}.section h2{margin:0;font-size:17px;line-height:1.25}.timer-display{margin:4px 0 16px;text-align:center;font-variant-numeric:tabular-nums;font-size:clamp(58px,18vw,78px);line-height:1;font-weight:650;letter-spacing:-.045em}.timer-state{min-height:19px;margin:-8px 0 13px;text-align:center;color:var(--muted);font-size:13px}.timer-state[data-kind="error"],.status[data-kind="error"]{color:var(--error)}.timer-state[data-kind="success"],.status[data-kind="success"]{color:var(--success)}.controls{display:grid;grid-template-columns:1fr 1fr;gap:9px}.controls button{min-height:48px}.presets{display:grid;grid-template-columns:repeat(4,1fr);gap:8px;margin-top:10px}.preset{min-height:42px;background:var(--surface);color:var(--blue-dark);border:1px solid var(--line)}.preset[aria-pressed="true"]{background:var(--blue-pale);border-color:var(--blue);box-shadow:inset 0 0 0 1px var(--blue)}.custom-time{display:flex;align-items:center;gap:8px;margin-top:11px}.custom-time label{color:var(--muted);font-size:13px}.custom-time input{width:82px;min-height:42px}.custom-time button{min-height:42px;flex:1}.shopping-form{display:grid;grid-template-columns:1fr auto;gap:8px}.shopping-form input{min-width:0}.shopping-form button{min-width:92px}.shopping-list{list-style:none;margin:12px 0 0;padding:0}.shopping-list li{display:grid;grid-template-columns:28px 1fr 40px;align-items:center;gap:8px;min-height:48px;border-bottom:1px solid var(--line)}.shopping-list li span{overflow-wrap:anywhere}.shopping-list li.checked span{color:var(--muted);text-decoration:line-through}.check{width:24px;height:24px;accent-color:var(--blue)}.remove{width:38px;height:38px;min-height:38px;padding:0;background:transparent;color:var(--muted);font-size:20px}.empty{padding:15px 0;color:var(--muted);font-size:14px}.foot{margin-top:16px;color:var(--muted);font-size:12px}.status{min-height:20px;margin:10px 0 0;color:var(--muted);font-size:13px}
button,input{font:inherit}button{min-height:48px;padding:10px 14px;border:1px solid var(--blue);border-radius:10px;background:var(--blue);color:#fff;font-weight:650;cursor:pointer}button:hover:not(:disabled){background:var(--blue-dark);border-color:var(--blue-dark)}button:active:not(:disabled){transform:translateY(1px)}button:focus-visible,input:focus-visible{outline:3px solid #7cb9d7;outline-offset:2px}button:disabled{opacity:.55;cursor:default}input{min-height:44px;padding:9px 11px;border:1px solid #aecbd9;border-radius:9px;background:#fff;color:var(--ink)}::selection{background:#c8e4f1;color:#173a4b}input::placeholder{color:#607a88} @media(min-width:520px){body{padding-top:30px}.section{padding:22px 0}.timer-display{font-size:76px}}
</style></head><body><main><div class="top"><span class="brand">KindHome · Cucina</span><span class="online" id="connection">Collego il Kindle…</span></div><h1>Timer e spesa</h1><p class="lede">Imposta un conto alla rovescia e tieni la lista della spesa aggiornata.</p>
<section class="section" aria-labelledby="timer-title"><div class="section-head"><h2 id="timer-title">Timer</h2><span id="duration-label" class="online">10 minuti</span></div><div id="timer-display" class="timer-display" role="timer" aria-live="off">10:00</div><p id="timer-state" class="timer-state" aria-live="polite">Pronto quando vuoi.</p><div class="controls"><button id="start-pause" type="button">Avvia</button><button id="reset" class="preset" type="button">Azzera</button></div><div class="presets" aria-label="Durata preimpostata"><button class="preset" data-minutes="5" type="button">5 min</button><button class="preset" data-minutes="10" type="button">10 min</button><button class="preset" data-minutes="15" type="button">15 min</button><button class="preset" data-minutes="30" type="button">30 min</button></div><form class="custom-time" id="duration-form"><label for="minutes">Altra durata</label><input id="minutes" type="number" min="1" max="1440" step="1" inputmode="numeric" value="10"><span>min</span><button type="submit" class="preset">Imposta</button></form></section>
<section class="section" aria-labelledby="shopping-title"><div class="section-head"><h2 id="shopping-title">Lista della spesa</h2><button id="clear-checked" class="preset" type="button">Togli spuntati</button></div><form class="shopping-form" id="shopping-form"><input id="item-text" type="text" maxlength="72" autocomplete="off" placeholder="Aggiungi un prodotto…" aria-label="Prodotto da aggiungere"><button type="submit">Aggiungi</button></form><ul id="shopping-list" class="shopping-list" aria-live="polite"></ul><p id="shopping-status" class="status" role="status"></p></section><p class="foot">Le modifiche si salvano sul Kindle e compaiono nel widget quando è attivo.</p></main>
<script>
(function(){var display=document.getElementById('timer-display'),state=document.getElementById('timer-state'),durationLabel=document.getElementById('duration-label'),startPause=document.getElementById('start-pause'),minutes=document.getElementById('minutes'),list=document.getElementById('shopping-list'),shoppingStatus=document.getElementById('shopping-status'),timer={duration:600,remaining:600,running:false,end:0},items=[],saving=false;
function fmt(n){n=Math.max(0,Math.ceil(n));return String(Math.floor(n/60)).padStart(2,'0')+':'+String(n%60).padStart(2,'0')}function draw(){var remain=timer.running?Math.max(0,timer.end-Date.now()/1000):timer.remaining;display.textContent=fmt(remain);durationLabel.textContent=Math.round(timer.duration/60)+' minuti';startPause.textContent=timer.running?'Pausa':'Avvia';state.textContent=timer.running?'Timer in corso':remain===0?'Tempo scaduto':'Pronto quando vuoi.';state.dataset.kind=remain===0?'success':''}
function request(path,data){return fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)}).then(function(r){if(!r.ok)return r.json().then(function(v){throw new Error(v.error||'Operazione non riuscita')});return r.json()})}
function load(){fetch('/data',{cache:'no-store'}).then(function(r){if(!r.ok)throw new Error();return r.json()}).then(function(d){timer.duration=d.timer_duration_seconds||600;timer.remaining=d.timer_remaining_seconds==null?timer.duration:d.timer_remaining_seconds;timer.running=d.timer_running===true;timer.end=d.timer_end_time?d.timer_end_time*1000:0;items=d.shopping_items||[];draw();renderItems();document.getElementById('connection').textContent='Collegato al Kindle';}).catch(function(){document.getElementById('connection').textContent='Kindle non raggiungibile';state.dataset.kind='error';state.textContent='Controlla che Casa sia aperta e i dispositivi siano sulla stessa Wi‑Fi.'})}
function updateTimer(action,seconds){state.dataset.kind='';request('/timer',{action:action,seconds:seconds}).then(load).catch(function(e){state.dataset.kind='error';state.textContent=e.message})}
startPause.addEventListener('click',function(){updateTimer(timer.running?'pause':'start')});document.getElementById('reset').addEventListener('click',function(){updateTimer('reset')});document.querySelectorAll('[data-minutes]').forEach(function(b){b.addEventListener('click',function(){var n=Number(b.dataset.minutes);minutes.value=n;updateTimer('set',n*60)})});document.getElementById('duration-form').addEventListener('submit',function(e){e.preventDefault();var n=Math.max(1,Math.min(1440,Number(minutes.value)||10));minutes.value=n;updateTimer('set',n*60)});
function renderItems(){list.textContent='';if(!items.length){var empty=document.createElement('li');empty.className='empty';empty.textContent='La lista è vuota. Aggiungi il primo prodotto.';list.appendChild(empty);return}items.forEach(function(item){var row=document.createElement('li');if(item.checked)row.className='checked';var check=document.createElement('input');check.type='checkbox';check.className='check';check.checked=item.checked;check.setAttribute('aria-label','Segna '+item.text+' come acquistato');check.addEventListener('change',function(){request('/shopping',{action:'toggle',id:item.id,checked:check.checked}).then(load).catch(showError)});var name=document.createElement('span');name.textContent=item.text;var remove=document.createElement('button');remove.type='button';remove.className='remove';remove.textContent='×';remove.setAttribute('aria-label','Rimuovi '+item.text);remove.addEventListener('click',function(){request('/shopping',{action:'remove',id:item.id}).then(load).catch(showError)});row.append(check,name,remove);list.appendChild(row)})}
function showError(e){shoppingStatus.dataset.kind='error';shoppingStatus.textContent=e.message||'Non riesco a salvare. Riprova.'}document.getElementById('shopping-form').addEventListener('submit',function(e){e.preventDefault();var input=document.getElementById('item-text'),value=input.value.trim();if(!value)return;input.disabled=true;request('/shopping',{action:'add',text:value}).then(function(){input.value='';shoppingStatus.dataset.kind='success';shoppingStatus.textContent='Aggiunto alla lista.';load()}).catch(showError).finally(function(){input.disabled=false;input.focus()})});document.getElementById('clear-checked').addEventListener('click',function(){request('/shopping',{action:'clear_checked'}).then(load).catch(showError)});setInterval(function(){if(timer.running&&timer.end&&Date.now()/1000>=timer.end){timer.running=false;timer.remaining=0;timer.end=0;state.dataset.kind='success';state.textContent='Tempo scaduto.';request('/timer',{action:'expire'}).catch(function(){})}draw()},250);setInterval(load,5000);load()})();
</script></body></html>]])
end

function KitchenServer:handle(client,header,body)
 self.last_activity=os.time()
 local request=header:match("^([^\r\n]+)") or ""
 local method,path=request:match("^(%S+)%s+(%S+)")
 if method=="GET" and path=="/" then return response(client,"200 OK",self:page()) end
 if method=="GET" and path=="/data" then return response(client,"200 OK",json.encode(self:getData()),"application/json; charset=utf-8") end
 if method=="POST" and path=="/timer" then
  local ok,payload=pcall(json.decode,body or "")
  if not ok or type(payload)~="table" then return response(client,"400 Bad Request",json.encode({error=I18N.tr("Richiesta non valida")}),"application/json") end
  local data=self:getData();local action=payload.action
  if action=="set" then
   local seconds=math.floor(tonumber(payload.seconds) or data.timer_duration_seconds)
   if seconds<60 or seconds>86400 then return response(client,"400 Bad Request",json.encode({error=I18N.tr("Imposta una durata tra 1 minuto e 24 ore.")}),"application/json") end
   data.timer_duration_seconds=seconds;data.timer_remaining_seconds=seconds;data.timer_running=false;data.timer_end_time=0
  elseif action=="start" then
   if data.timer_remaining_seconds<=0 then data.timer_remaining_seconds=data.timer_duration_seconds end
   data.timer_end_time=os.time()+data.timer_remaining_seconds;data.timer_running=true
  elseif action=="pause" then
   data.timer_remaining_seconds=math.max(0,data.timer_end_time-os.time());data.timer_end_time=0;data.timer_running=false
  elseif action=="reset" then
   data.timer_remaining_seconds=data.timer_duration_seconds;data.timer_end_time=0;data.timer_running=false
  elseif action=="expire" then
   data.timer_remaining_seconds=0;data.timer_end_time=0;data.timer_running=false
  else return response(client,"400 Bad Request",json.encode({error=I18N.tr("Azione timer non riconosciuta.")}),"application/json") end
  if not self:writeData(data) then return response(client,"507 Insufficient Storage",json.encode({error=I18N.tr("Non riesco a salvare il timer sul Kindle.")}),"application/json") end
  return response(client,"200 OK",json.encode(self:getData()),"application/json; charset=utf-8")
 end
 if method=="POST" and path=="/shopping" then
  local ok,payload=pcall(json.decode,body or "")
  if not ok or type(payload)~="table" then return response(client,"400 Bad Request",json.encode({error=I18N.tr("Richiesta non valida")}),"application/json") end
  local data=self:getData();local action=payload.action
  if action=="add" then
   local text=type(payload.text)=="string" and payload.text:gsub("[%z\1-\31]"," "):gsub("^%s+",""):gsub("%s+$",""):sub(1,72) or ""
   if text=="" then return response(client,"400 Bad Request",json.encode({error=I18N.tr("Scrivi il nome di un prodotto.")}),"application/json") end
   if #data.shopping_items>=100 then return response(client,"400 Bad Request",json.encode({error=I18N.tr("La lista è piena: rimuovi qualche prodotto.")}),"application/json") end
   self.item_seq=self.item_seq+1
   data.shopping_items[#data.shopping_items+1]={id=tostring(os.time()).."-"..tostring(self.item_seq),text=text,checked=false}
  elseif action=="toggle" then
   for _,item in ipairs(data.shopping_items) do if item.id==payload.id then item.checked=payload.checked==true;break end end
  elseif action=="remove" then
   for i=#data.shopping_items,1,-1 do if data.shopping_items[i].id==payload.id then table.remove(data.shopping_items,i);break end end
  elseif action=="clear_checked" then
   for i=#data.shopping_items,1,-1 do if data.shopping_items[i].checked then table.remove(data.shopping_items,i) end end
  else return response(client,"400 Bad Request",json.encode({error=I18N.tr("Azione lista non riconosciuta.")}),"application/json") end
  if not self:writeData(data) then return response(client,"507 Insufficient Storage",json.encode({error=I18N.tr("Non riesco a salvare la lista sul Kindle.")}),"application/json") end
  return response(client,"200 OK",json.encode(self:getData()),"application/json; charset=utf-8")
 end
 return response(client,"404 Not Found","Pagina non trovata","text/plain; charset=utf-8")
end

function KitchenServer:poll()
 if not self.listener then return end
 local client=self.listener:accept()
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
   item.header=item.buffer:sub(1,sep-1);item.body_start=sep+4
   item.expected=tonumber(item.header:match("[Cc]ontent%-[Ll]ength:%s*(%d+)")) or 0
   if item.expected>128*1024 then response(item.socket,"413 Payload Too Large",json.encode({error=I18N.tr("Richiesta troppo grande")}),"application/json");table.remove(self.clients,i);item=nil
   elseif item.expected==0 then self:handle(item.socket,item.header,"");table.remove(self.clients,i);item=nil end
  end
  if item and item.header and #item.buffer-item.body_start+1>=item.expected then
   self:handle(item.socket,item.header,item.buffer:sub(item.body_start,item.body_start+item.expected-1));table.remove(self.clients,i);item=nil
  end
  if item and (os.time()-item.started>30 or err and err~="timeout" and not partial) then
   pcall(function() item.socket:close() end);table.remove(self.clients,i)
  end
 end
end

function KitchenServer:close()
 if self.listener then pcall(function() self.listener:close() end);self.listener=nil end
 if self.firewall_open then
  os.execute("iptables -D INPUT -i wlan0 -p tcp --dport 8766 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT >/dev/null 2>&1; iptables -D OUTPUT -o wlan0 -p tcp --sport 8766 -m conntrack --ctstate ESTABLISHED -j ACCEPT >/dev/null 2>&1")
  self.firewall_open=nil
 end
 for _,item in ipairs(self.clients) do pcall(function() item.socket:close() end) end
 self.clients={}
end

return KitchenServer

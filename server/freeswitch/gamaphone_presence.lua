--[[
  gamaphone_presence.lua

  Diffuse l'etat « Ne pas deranger » (NPD) des extensions FusionPBX comme presence SIP,
  pour que les softphones abonnes (Gamaphone) l'affichent.

  FusionPBX gere le NPD (touche du telephone synchronisee via as-feature-event, ou codes
  *78 / *79) mais ne le publie jamais comme presence de l'extension : un abonne a
  878@domaine ne le voyait pas. Ce script tourne en permanence (une seule instance),
  ecoute les evenements et :
    - publie le NPD quand il change (touche du telephone ou codes *78 / *79) ;
    - le reaffirme quand FreeSWITCH republie un autre etat pour ce poste
      (reenregistrement, fin d'appel, nouvel abonnement) ;
    - laisse passer « en communication » pendant un appel et « hors ligne » si le poste
      se deconnecte.

  Demarrer : fs_cli -x "luarun gamaphone_presence.lua"
  Arreter  : fs_cli -x "luarun gamaphone_presence.lua stop"
]]

local NAME = "gamaphone_presence"
local STOP_SUBCLASS = "gamaphone::presence::stop"
local MARK = "X-Gamaphone-Presence" -- marque nos propres evenements pour ne pas y reagir

local function log(level, message)
	freeswitch.consoleLog(level, "[" .. NAME .. "] " .. message .. "\n")
end

local function fire_stop()
	local event = freeswitch.Event("CUSTOM", STOP_SUBCLASS)
	event:fire()
end

if argv and argv[1] == "stop" then
	fire_stop()
	log("NOTICE", "arret demande")
	return
end

-- Une seule instance : arret de l'eventuelle precedente avant de demarrer.
fire_stop()
freeswitch.msleep(1500)

local dnd = {}     -- ["878@domaine"] = true
local pending = {} -- ["878@domaine"] = os.time() a partir duquel reaffirmer le NPD

local function normalize(user)
	if not user or user == "" then return nil end
	user = user:gsub("^sips?:", ""):gsub("[;>].*$", "")
	return user:lower()
end

local function publish(user, on)
	local event = freeswitch.Event("PRESENCE_IN")
	event:addHeader("proto", "sip")
	event:addHeader("event_type", "presence")
	event:addHeader("alt_event_type", "dialog")
	event:addHeader("from", user)
	event:addHeader("login", user)
	if on then
		-- « other » et non « dnd » : FreeSWITCH traduit dnd en busy, affiche Occupe.
		event:addHeader("status", "do not disturb")
		event:addHeader("rpid", "other")
	else
		event:addHeader("status", "Available")
		event:addHeader("rpid", "unknown")
	end
	event:addHeader(MARK, "1")
	event:fire()
end

local function set_dnd(user, on, origin)
	if not user then return end
	if on then
		dnd[user] = true
	else
		dnd[user] = nil
		pending[user] = nil
	end
	log("NOTICE", user .. " : NPD " .. (on and "active" or "desactive") .. " (" .. origin .. ")")
	publish(user, on)
end

-- Etat initial : extensions deja en NPD dans FusionPBX.
local function load_from_database()
	local ok, err = pcall(function()
		require "resources.functions.config"
		local Database = require "resources.functions.database"
		local dbh = Database.new("system")
		local sql = "select e.extension, e.number_alias, d.domain_name from v_extensions e " ..
			"inner join v_domains d on d.domain_uuid = e.domain_uuid " ..
			"where cast(e.do_not_disturb as text) = 'true'"
		dbh:query(sql, {}, function(row)
			local domain = (row.domain_name or ""):lower()
			if row.extension and row.extension ~= "" then
				dnd[(row.extension .. "@" .. domain):lower()] = true
			end
			if row.number_alias and row.number_alias ~= "" then
				dnd[(row.number_alias .. "@" .. domain):lower()] = true
			end
		end)
		dbh:release()
	end)
	if not ok then
		log("WARNING", "etat initial non charge depuis la base : " .. tostring(err))
	end
	local count = 0
	for user in pairs(dnd) do
		count = count + 1
		publish(user, true)
	end
	log("NOTICE", "demarre, " .. count .. " poste(s) en NPD")
end

local consumer = freeswitch.EventConsumer("PRESENCE_IN")
consumer:bind("PRESENCE_PROBE")
consumer:bind("PHONE_FEATURE_SUBSCRIBE")
consumer:bind("CUSTOM", STOP_SUBCLASS)
consumer:bind("SHUTDOWN")

load_from_database()

local running = true
while running do
	local event = consumer:pop(1, 500)
	if event then
		local name = event:getHeader("Event-Name")
		if name == "SHUTDOWN" then
			running = false
		elseif name == "CUSTOM" then
			if event:getHeader("Event-Subclass") == STOP_SUBCLASS then
				running = false
			end
		elseif name == "PHONE_FEATURE_SUBSCRIBE" then
			-- Touche NPD du telephone (synchronisation as-feature-event)
			if event:getHeader("Feature-Action") == "SetDoNotDisturb" then
				local user = normalize((event:getHeader("user") or "") .. "@" .. (event:getHeader("host") or ""))
				set_dnd(user, event:getHeader("Feature-Enabled") == "true", "touche du telephone")
			end
		elseif name == "PRESENCE_IN" then
			if not event:getHeader(MARK) then
				local proto = event:getHeader("proto")
				local from = normalize(event:getHeader("from"))
				local dnd_target = from and from:match("^dnd%+(.+)$")
				if not dnd_target and proto == "dnd" then
					dnd_target = from
				end
				if dnd_target then
					-- Codes *78 / *79 : FusionPBX allume le voyant dnd+extension
					set_dnd(dnd_target, event:getHeader("answer-state") == "confirmed", "code *78/*79")
				elseif from and dnd[from] then
					local answer = event:getHeader("answer-state")
					local status = event:getHeader("status") or ""
					if answer == "early" or answer == "confirmed" or status:find("Unregistered") then
						-- Appel en cours ou poste deconnecte : on laisse FreeSWITCH l'afficher.
						pending[from] = nil
					else
						-- FreeSWITCH vient de republier un autre etat : on reaffirme le NPD juste apres.
						pending[from] = os.time() + 1
					end
				end
			end
		elseif name == "PRESENCE_PROBE" then
			-- Nouvel abonnement : FreeSWITCH repond avec son propre etat, on reaffirme le NPD apres.
			local proto = event:getHeader("proto")
			if not proto or proto == "sip" then
				local to = normalize(event:getHeader("to"))
				if to and dnd[to] then
					pending[to] = os.time() + 1
				end
			end
		end
	end
	local now = os.time()
	for user, due in pairs(pending) do
		if now >= due then
			pending[user] = nil
			if dnd[user] then
				publish(user, true)
			end
		end
	end
end

log("NOTICE", "arrete")

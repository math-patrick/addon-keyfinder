local ADDON, ns = ...
local L = ns.L

local KF = CreateFrame("Frame")
ns.KF = KF
_G.Keyfinder = KF

----------------------------------------------------------------------
-- Constantes
----------------------------------------------------------------------
ns.BL_CLASSES = { SHAMAN = true, MAGE = true, HUNTER = true, EVOKER = true }
ns.BREZ_CLASSES = { DEATHKNIGHT = true, DRUID = true, WARLOCK = true, PALADIN = true }
ns.ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
ns.CATEGORY_DUNGEONS = GROUP_FINDER_CATEGORY_ID_DUNGEONS or 2

local DEFAULTS = {
	filters = {
		dungeons = {},        -- [challengeMapID] = true
		minLeaderScore = 0,
		minLeaderBest = 0,
		myRole = true,
		needBL = false,
		needBrez = false,
		meetReq = true,
		autoOnly = false,
		hideDeclined = true,
		onlyGain = false,     -- só grupos que sobem o seu rating
		keyMode = "any",      -- any | near | r2_6 | r7_10 | r11_13 | r14_16 | r17
		maxAge = 0,           -- minutos, 0 = qualquer
		playstyle = 0,        -- Enum.LFGEntryGeneralPlaystyle, 0 = qualquer
	},
	sort = "match",
	focus = "rating",         -- rating | balanced | safe
	rules = {},
	nextRuleID = 1,
	keyLearn = { bias = 0, n = 0 },
	-- Upgrades: nível base (0 = automático) e quantos níveis acima mostrar tudo.
	upgrade = { enabled = true, base = 0, range = 1 },
	-- Últimas escolhas do formulário de anúncio.
	-- Preenchimento da janela de anúncio da Blizzard.
	autofill = true,
	listing = { private = false, crossFaction = true },
	alerts = { sound = true, flash = true, raidWarning = true, popup = true },
	pos = nil,
}

local function CopyDefaults(src, dst)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			CopyDefaults(v, dst[k])
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

----------------------------------------------------------------------
-- Secret values (Midnight): nunca fazer conta com valor secreto.
----------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
local function safe(v)
	if v ~= nil and issecret(v) then return nil end
	return v
end
ns.safe = safe

local function clamp(v, lo, hi)
	if v < lo then return lo elseif v > hi then return hi end
	return v
end
ns.clamp = clamp

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage(msg) end
ns.Print = Print

----------------------------------------------------------------------
-- Dungeons da temporada
----------------------------------------------------------------------
-- Banner da dungeon no Diário de Aventura (o mesmo da lista de instâncias).
-- A imagem útil ocupa 174x96 de uma textura 256x128.
ns.BANNER_COORDS = { 0, 174 / 256, 0, 96 / 128 }
local function JournalBanner(instanceMapID)
	if not (instanceMapID and C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap and EJ_GetInstanceInfo) then return nil end
	local ok, jid = pcall(C_EncounterJournal.GetInstanceForGameMap, instanceMapID)
	if not ok or not jid then return nil end
	local ok2, _, _, _, buttonImage = pcall(EJ_GetInstanceInfo, jid)
	if ok2 and buttonImage and buttonImage ~= 0 then return buttonImage end
	return nil
end

function KF:LoadSeasonMaps()
	local maps, byName, byID = {}, {}, {}
	local ids = (C_ChallengeMode and C_ChallengeMode.GetMapTable and C_ChallengeMode.GetMapTable()) or {}
	for _, id in ipairs(ids) do
		local name, _, timeLimit, texture, bgTexture, instanceMapID = C_ChallengeMode.GetMapUIInfo(id)
		if name then
			local m = { id = id, name = name, texture = texture, bg = bgTexture, timeLimit = timeLimit, instanceMapID = instanceMapID }
			m.banner = JournalBanner(instanceMapID)
			maps[#maps + 1] = m
			byName[name] = m
			byID[id] = m
		end
	end
	table.sort(maps, function(a, b) return a.name < b.name end)
	self.maps, self.mapByName, self.mapByID = maps, byName, byID
	if ns.UI and ns.UI.OnMapsLoaded then ns.UI:OnMapsLoaded() end
end

function KF:ResolveMap(act, mapName)
	if mapName and self.mapByName and self.mapByName[mapName] then return self.mapByName[mapName] end
	for _, m in ipairs(self.maps or {}) do
		if act.mapID and m.instanceMapID and act.mapID == m.instanceMapID then return m end
		if act.fullName and string.find(act.fullName, m.name, 1, true) then return m end
	end
	return nil
end

function KF:NumMaps()
	local n = #(self.maps or {})
	return n > 0 and n or 8
end

----------------------------------------------------------------------
-- Modelo de pontuação por dungeon
-- Curva base (key timada): +2 = 165, +15 por nível e +15 em cada degrau
-- de affix. A curva é calibrada com as SUAS runs da temporada: o desvio
-- médio entre o que você realmente ganhou e a curva vira um ajuste fixo.
----------------------------------------------------------------------
local AFFIX_STEPS = { 4, 7, 10, 12 }

local function BaseScore(level)
	if not level or level < 2 then return 0 end
	local s = 165 + 15 * (level - 2)
	for _, t in ipairs(AFFIX_STEPS) do if level >= t then s = s + 15 end end
	return s
end

function KF:ExpectedScore(level)
	if not level or level < 2 then return 0 end
	return BaseScore(level) + (self.scoreOffset or 0)
end

function KF:LevelForScore(score)
	for lvl = 30, 2, -1 do
		if self:ExpectedScore(lvl) <= (score or 0) then return lvl end
	end
	return 2
end

----------------------------------------------------------------------
-- Jogador
----------------------------------------------------------------------
local function GetPlayerRole()
	local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
	local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
	local spec = getSpec and getSpec()
	if spec and getInfo then
		local _, specName, _, icon, role = getInfo(spec)
		return role or "DAMAGER", specName, icon
	end
	return "DAMAGER", nil, nil
end

function KF:RefreshPlayer()
	local p = self.player or {}
	local className, classFile = UnitClass("player")
	p.class, p.className = classFile, className
	p.role, p.specName, p.specIcon = GetPlayerRole()
	p.score = (C_ChallengeMode.GetOverallDungeonScore and C_ChallengeMode.GetOverallDungeonScore()) or 0
	p.best, p.maps = {}, {}
	local summary = C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary and C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
	if summary then
		if safe(summary.currentSeasonScore) then p.score = summary.currentSeasonScore end
		for _, run in ipairs(summary.runs or {}) do
			local id = safe(run.challengeModeID)
			if id then
				local m = {
					level = safe(run.bestRunLevel) or 0,
					timed = safe(run.finishedSuccess) and true or false,
					score = safe(run.mapScore) or 0,
					duration = safe(run.bestRunDurationMS) or 0,
				}
				m.timedLevel = m.timed and m.level or 0
				-- O melhor score pode ser de uma run fora do tempo; o best TIMADO vem daqui.
				if C_MythicPlus and C_MythicPlus.GetSeasonBestForMap then
					local ok, intime = pcall(C_MythicPlus.GetSeasonBestForMap, id)
					if ok and type(intime) == "table" and safe(intime.level) then
						m.timedLevel = math.max(m.timedLevel, intime.level)
					end
				end
				p.maps[id] = m
				local name = C_ChallengeMode.GetMapUIInfo(id)
				if name then p.best[name] = { level = m.level, timed = m.timed } end
			end
		end
	end

	-- Calibra a curva com as suas runs timadas.
	local sum, n = 0, 0
	for _, m in pairs(p.maps) do
		if m.timed and m.level >= 2 and m.score > 0 then
			sum = sum + (m.score - BaseScore(m.level)); n = n + 1
		end
	end
	self.scoreOffset = n > 0 and clamp(sum / n, -120, 60) or 0

	-- As 3 dungeons onde você tem menos pontos viram prioridade.
	-- Nível que você ainda precisa: o menor best timado entre as dungeons, +1.
	p.needLevel = nil
	local low
	for _, m in ipairs(self.maps or {}) do
		local t = p.maps[m.id] and p.maps[m.id].timedLevel or 0
		if t > 0 and (not low or t < low) then low = t end
	end
	if low then p.needLevel = low + 1 end

	p.weak = {}
	local list = {}
	for _, m in ipairs(self.maps or {}) do
		list[#list + 1] = { id = m.id, score = (p.maps[m.id] and p.maps[m.id].score) or 0 }
	end
	if #list >= 4 then
		table.sort(list, function(a, b) return a.score < b.score end)
		for i = 1, 3 do p.weak[list[i].id] = true end
	end

	p.hasBL = ns.BL_CLASSES[classFile] or false
	p.hasBrez = ns.BREZ_CLASSES[classFile] or false
	local _, equipped = GetAverageItemLevel()
	p.ilvl = equipped or 0

	p.keyMapID, p.keyLevel = nil, nil
	if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
		local km = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
		local kl = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
		if km and kl and kl > 0 then p.keyMapID, p.keyLevel = km, kl end
	end
	self.player = p
end

-- Progresso por dungeon, da que tem menos pontos para a que tem mais.
function KF:GetProgress()
	local p = self.player
	local out, total = {}, 0
	local baseLvl = self:LevelForScore((p.score or 0) / self:NumMaps())
	for _, m in ipairs(self.maps or {}) do
		local mine = p.maps[m.id]
		local e = { map = m, mine = mine, weak = p.weak[m.id] }
		if mine and mine.timedLevel > 0 then e.next = mine.timedLevel + 1
		elseif mine and mine.level > 0 then e.next = mine.level
		else e.next = math.max(2, baseLvl) end
		e.nextGain = math.max(0, math.floor(self:ExpectedScore(e.next) - (mine and mine.score or 0) + 0.5))
		total = total + e.nextGain
		out[#out + 1] = e
	end
	table.sort(out, function(a, b)
		local sa, sb = a.mine and a.mine.score or 0, b.mine and b.mine.score or 0
		if sa ~= sb then return sa < sb end
		return a.map.name < b.map.name
	end)
	return out, total
end

----------------------------------------------------------------------
-- Leitura de um resultado de busca
----------------------------------------------------------------------
function KF:ParseResult(id)
	local info = C_LFGList.GetSearchResultInfo(id)
	if not info or info.isDelisted then return nil end
	local actID = info.activityIDs and info.activityIDs[1] or info.activityID
	if not actID then return nil end
	local act = C_LFGList.GetActivityInfoTable(actID)
	if not act or not act.isMythicPlusActivity then return nil end

	local r = { id = id, info = info, actID = actID, act = act }
	r.leaderName = safe(info.leaderName)
	r.leaderScore = safe(info.leaderOverallDungeonScore) or 0

	local ls = info.leaderDungeonScoreInfo
	if type(ls) == "table" and ls.mapName == nil then ls = ls[1] end
	r.leaderBest = (ls and safe(ls.bestRunLevel)) or 0
	r.leaderTimed = (ls and safe(ls.finishedSuccess)) or false
	r.leaderInc = ls and safe(ls.bestLevelIncrement) or nil
	local top = info.leaderBestDungeonScoreInfo
	if type(top) == "table" and safe(top.bestRunLevel) then
		r.leaderTop = top.bestRunLevel - (safe(top.finishedSuccess) and 0 or 1)
	end
	r.map = self:ResolveMap(act, ls and safe(ls.mapName))
	r.dungeonName = (r.map and r.map.name) or act.shortName or act.fullName or "?"

	r.numMembers = safe(info.numMembers) or 0
	r.age = safe(info.age) or 0
	r.autoAccept = safe(info.autoAccept) or false
	r.reqScore = safe(info.requiredDungeonScore) or 0
	r.reqIlvl = safe(info.requiredItemLevel) or 0
	r.friends = (safe(info.numBNetFriends) or 0) + (safe(info.numCharFriends) or 0) + (safe(info.numGuildMates) or 0)
	r.playstyle = safe(info.generalPlaystyle) or 0
	r.hasSelf = safe(info.hasSelf) or false

	r.members, r.hasBL, r.hasBrez = {}, false, false
	for i = 1, r.numMembers do
		local pi = C_LFGList.GetSearchResultPlayerInfo(id, i)
		if pi then
			local class = safe(pi.classFilename)
			r.members[#r.members + 1] = {
				class = class, className = safe(pi.className), spec = safe(pi.specName),
				role = safe(pi.assignedRole) or "DAMAGER", isLeader = safe(pi.isLeader),
			}
			if class and ns.BL_CLASSES[class] then r.hasBL = true end
			if class and ns.BREZ_CLASSES[class] then r.hasBrez = true end
			if safe(pi.isLeader) then r.leaderClass = class end
		end
	end

	local counts = C_LFGList.GetSearchResultMemberCounts and C_LFGList.GetSearchResultMemberCounts(id)
	if counts then
		r.open = { TANK = safe(counts.TANK_REMAINING) or 0, HEALER = safe(counts.HEALER_REMAINING) or 0, DAMAGER = safe(counts.DAMAGER_REMAINING) or 0 }
	else
		local c = { TANK = 0, HEALER = 0, DAMAGER = 0 }
		for _, m in ipairs(r.members) do c[m.role] = (c[m.role] or 0) + 1 end
		r.open = { TANK = math.max(0, 1 - c.TANK), HEALER = math.max(0, 1 - c.HEALER), DAMAGER = math.max(0, 3 - c.DAMAGER) }
	end

	local _, appStatus, pendingStatus = C_LFGList.GetApplicationInfo(id)
	r.appStatus = pendingStatus or appStatus
	return r
end

----------------------------------------------------------------------
-- Nota de match (1-99) = mistura de três estimativas:
--   aceite : chance do líder te aceitar (seu best aqui x key, rating, utilidade)
--   ganho  : quanto de rating você sobe se timar (usa as SUAS runs da temporada)
--   timar  : chance do grupo timar (experiência do líder e a sua nesta dungeon)
-- O peso de cada parte depende do foco escolhido nos filtros.
----------------------------------------------------------------------
ns.FOCUS = {
	rating = { acc = 0.35, gain = 0.45, time = 0.20 },
	balanced = { acc = 0.40, gain = 0.30, time = 0.30 },
	safe = { acc = 0.35, gain = 0.15, time = 0.50 },
}

----------------------------------------------------------------------
-- Nível da key
-- O título do grupo (onde fica o "+21") é protegido: o addon mostra, mas
-- não consegue ler. Então o nível vem de duas fontes:
--   1) EXATO: se a busca foi feita no Localizador com um número digitado
--      (ex.: "21"), o jogo só devolve grupos com esse número no título.
--   2) ESTIMADO: média ponderada de vários sinais do líder, corrigida por
--      um ajuste que o addon aprende sozinho (comparando a estimativa com
--      buscas exatas e com a key real das runs que você entra).
----------------------------------------------------------------------
local function ReadQueryLevel()
	local panel = LFGListFrame and LFGListFrame.SearchPanel
	local box = panel and panel.SearchBox
	if not (box and box.GetText) then return nil end
	local ok, text = pcall(box.GetText, box)
	if not ok or type(text) ~= "string" or issecret(text) then return nil end
	local n = tonumber(strtrim(text):match("^%+?(%d%d?)$"))
	if n and n >= 2 and n <= 40 then return n end
	return nil
end

-- Estimativa "crua" (sem o ajuste aprendido). Retorna nível decimal,
-- quantos sinais foram usados e se o líder tem histórico nesta dungeon.
function KF:RawKeyEstimate(r)
	local sum, wsum, n = 0, 0, 0
	local function sig(v, w)
		if v and v >= 2 then sum = sum + v * w; wsum = wsum + w; n = n + 1 end
	end
	local maps = self:NumMaps()
	local x = r.leaderBest or 0
	if x >= 2 then
		if r.leaderTimed then
			-- Líder timou X aqui: costuma listar X ou empurrar X+1 (mais se timou com folga).
			sig(x + 0.5 + 0.25 * math.max(0, (r.leaderInc or 1) - 1), 3)
		else
			sig(x - 0.5, 2)
		end
	end
	-- Maior key do líder em qualquer dungeon: a key que ele tem na bolsa costuma estar perto disso.
	if (r.leaderTop or 0) >= 2 then sig(r.leaderTop - 0.5, 2) end
	-- Rating exigido: quem pede rating alto lista key alta.
	if (r.reqScore or 0) > 0 then sig(self:LevelForScore(r.reqScore / maps) + 1, 1.5) end
	if (r.leaderScore or 0) > 0 then sig(self:LevelForScore(r.leaderScore / maps) + 0.5, 1) end
	if wsum == 0 then return nil, 0 end
	local raw = sum / wsum
	local cap = math.max(x, r.leaderTop or 0)
	if cap >= 2 then raw = math.min(raw, cap + 2) end
	return raw, n
end

function KF:EstimateKey(r)
	if r.queryLevel then
		return r.queryLevel, "query", "exact", r.queryLevel, r.queryLevel
	end
	local raw, n = self:RawKeyEstimate(r)
	r.estRaw = raw
	if not raw then return nil end
	local est = math.max(2, math.floor(raw + (self.db.keyLearn.bias or 0) + 0.5))
	local hasHere = (r.leaderBest or 0) >= 2
	local conf
	if hasHere and n >= 3 and math.abs((r.leaderTop or r.leaderBest) - r.leaderBest) <= 3 then conf = "high"
	elseif hasHere or n >= 3 then conf = "medium"
	else conf = "low" end
	local spread = conf == "high" and 1 or 2
	return est, hasHere and "leader" or "rating", conf, math.max(2, est - spread), est + spread
end

-- Aprende o desvio médio (key real - estimativa crua). `w` = peso da amostra.
function KF:LearnKey(err, w)
	local k = self.db.keyLearn
	err = clamp(err, -4, 4)
	k.bias = ((k.bias or 0) * (k.n or 0) + err * w) / ((k.n or 0) + w)
	k.n = math.min(60, (k.n or 0) + w)
end

-- Seu best timado aqui menos a key: quanto isso pesa no aceite.
local ACCEPT_BY_DIFF = { [-4] = -0.45, [-3] = -0.3, [-2] = -0.15, [-1] = -0.02, [0] = 0.1, [1] = 0.15, [2] = 0.2 }

function KF:Score(r)
	local p = self.player
	local reasons = {}
	-- w = relevância do motivo (os mais relevantes aparecem primeiro)
	local function add(good, text, w) reasons[#reasons + 1] = { good = good, text = text, w = w or 10 } end

	local mine = r.map and p.maps[r.map.id]
	local est, src, conf, lo, hi = self:EstimateKey(r)
	r.est, r.estSrc, r.estConf, r.estLo, r.estHi, r.mine = est, src, conf, lo, hi, mine
	-- O palpite só entra na conta da nota. Números e frases que dependem do
	-- nível só aparecem quando ele é exato (veio da busca do jogador).
	local exact = conf == "exact"
	r.exact = exact
	local roleOpen = (r.open[p.role] or 0) > 0
	if not roleOpen then add(false, L.R_ROLE_FULL:format(L.ROLE[p.role]), 100) end

	-- 1) Ganho de rating, se timar a key estimada
	local myScore = mine and mine.score or 0
	local gain = 0
	if est then gain = math.max(0, math.floor(self:ExpectedScore(est) - myScore + 0.5)) end
	r.gain = gain
	local gainN = clamp(gain / 30, 0, 1)
	if myScore == 0 then
		add(true, L.R_NEW_DUNGEON, 60)
	elseif exact and gain >= 10 then
		add(true, L.R_UPGRADE, 40 + math.min(30, gain / 2))
	elseif exact and est then
		add(false, L.R_NO_GAIN:format(mine.level), 45)
	end
	if r.map and p.weak[r.map.id] then
		gainN = math.min(1, gainN + 0.1)
		add(true, L.R_WEAK, 28)
	end

	-- 2) Chance de aceite
	local acc = 0.6
	local myLvl = mine and mine.timedLevel or 0
	if est then
		if myLvl > 0 then
			local d = myLvl - est
			acc = acc + (ACCEPT_BY_DIFF[clamp(d, -4, 2)] or 0)
			if d >= 0 then add(true, L.R_YOU_TIMED:format(myLvl), 45)
			elseif exact and d <= -2 then add(false, L.R_YOU_BELOW:format(myLvl), 50) end
		else
			acc = acc - 0.18
			add(false, (mine and mine.level > 0) and L.R_YOU_UNTIMED or L.R_YOU_NEVER, 42)
		end
	end
	local gap = (p.score or 0) - r.leaderScore
	acc = acc + clamp(gap / 1500, -0.3, 0.1)
	if gap >= 0 then add(true, L.R_SCORE_ABOVE, 22)
	elseif gap < -400 then add(false, L.R_SCORE_HIGHER, 35) end
	if p.hasBL and not r.hasBL then acc = acc + 0.08; add(true, L.R_BRINGS_BL, 34) end
	if p.hasBrez and not r.hasBrez then acc = acc + 0.05; add(true, L.R_BRINGS_BREZ, 24) end
	if r.friends > 0 then acc = acc + 0.15; add(true, L.R_FRIENDS, 30) end
	if r.autoAccept then acc = acc + 0.25; add(true, L.R_AUTO, 32) end
	local mins = r.age / 60
	if mins > 20 then acc = acc - 0.05; add(false, L.R_STALE:format(math.floor(mins)), 15) end
	if r.reqScore > 0 and r.reqScore > (p.score or 0) then acc = 0.04; add(false, L.R_REQ_FAIL:format(r.reqScore), 90) end
	if r.reqIlvl > 0 and (p.ilvl or 0) > 0 and r.reqIlvl > p.ilvl then acc = 0.04; add(false, L.R_ILVL_FAIL:format(r.reqIlvl), 90) end
	if not roleOpen then acc = 0 end
	acc = clamp(acc, 0, 0.97)

	-- 3) Chance de timar
	local t = 0.5
	if r.leaderBest > 0 then
		if r.leaderTimed then t = t + 0.15; add(true, L.R_LEADER_TIMED:format(r.leaderBest), 33)
		else t = t - 0.08; add(false, L.R_LEADER_DEPLETED:format(r.leaderBest), 30) end
	else
		t = t - 0.15; add(false, L.R_LEADER_NONE, 30)
	end
	if est then
		if myLvl >= est then t = t + 0.15
		elseif myLvl > 0 and myLvl >= est - 1 then t = t + 0.05
		else t = t - 0.1 end
		local leaderAvg = r.leaderScore / self:NumMaps()
		local need = self:ExpectedScore(est)
		if leaderAvg >= need then t = t + 0.1
		elseif leaderAvg < need - 40 then t = t - 0.1 end
	end
	t = clamp(t, 0.05, 0.95)
	r.accept, r.timeChance = acc, t

	table.sort(reasons, function(a, b) return a.w > b.w end)

	local w = ns.FOCUS[self.db.focus] or ns.FOCUS.rating
	local s = 100 * (w.acc * acc + w.gain * gainN + w.time * t)
	if not roleOpen then s = math.min(s, 10) end
	return clamp(math.floor(s + 0.5), 1, 99), reasons
end

-- Nível de referência do jogador numa dungeon: best timado ali ou,
-- se não tiver, o nível médio que o rating dele sugere.
function KF:RefLevel(r)
	local mine = r.map and self.player.maps[r.map.id]
	if mine and mine.timedLevel > 0 then return mine.timedLevel end
	return self:LevelForScore((self.player.score or 0) / self:NumMaps())
end

ns.KEY_RANGES = {
	r2_6 = { 2, 6 }, r7_10 = { 7, 10 }, r11_13 = { 11, 13 }, r14_16 = { 14, 16 }, r17 = { 17, 99 },
}

function KF:BaseLevel()
	local u = self.db.upgrade
	if (u.base or 0) > 0 then return u.base end
	return self.player and self.player.needLevel
end

-- Mostra só keys entre o nível base e base + faixa. No nível base, só as
-- dungeons onde a key é upgrade pra você; acima dele, todas.
-- Nível da key: o número da busca do jogador, se houver; senão a estimativa
-- interna (que nunca aparece na tela). Grupo sem nenhum sinal de nível
-- (líder sem rating, sem run e sem rating exigido) fica de fora.
function KF:UpgradePasses(r)
	local u = self.db.upgrade
	if not u.enabled then return true end
	local base = self:BaseLevel()
	if not base then return true end
	local lvl = self.queryLevel or r.est
	if not lvl then return false end
	if lvl < base or lvl > base + (u.range or 0) then return false end
	if lvl > base then return true end
	local mine = r.map and self.player.maps[r.map.id]
	return (mine and mine.timedLevel or 0) < lvl
end

function KF:KeyPasses(r)
	local mode = self.db.filters.keyMode or "any"
	if mode == "any" then return true end
	if not r.est then return false end
	if mode == "near" then
		local ref = self:RefLevel(r)
		return r.est >= ref - 1 and r.est <= ref + 2
	end
	local range = ns.KEY_RANGES[mode]
	return not range or (r.est >= range[1] and r.est <= range[2])
end

-- Quantos filtros estão fora do padrão (para o rótulo do botão Filtros).
function KF:ActiveFilterCount()
	local f, n = self.db.filters, 0
	if (f.minLeaderScore or 0) > 0 then n = n + 1 end
	if (f.minLeaderBest or 0) > 0 then n = n + 1 end
	if (f.maxAge or 0) > 0 then n = n + 1 end
	if (f.playstyle or 0) > 0 then n = n + 1 end
	for _, k in ipairs({ "needBL", "needBrez", "autoOnly" }) do if f[k] then n = n + 1 end end
	return n
end

-- Grupos aos quais você está candidatado (ou convidado), para o rodapé.
-- Vem da lista de candidaturas do jogo, então inclui grupos que já saíram
-- da busca atual.
local ACTIVE_APP = { applied = true, invited = true }
function KF:GetApplied()
	local out = {}
	local ids = C_LFGList.GetApplications and C_LFGList.GetApplications() or {}
	for _, id in ipairs(ids) do
		local r = self:FindResult(id)
		if not r then
			local ok, parsed = pcall(self.ParseResult, self, id)
			if ok and parsed then r = parsed end
		end
		if r and ACTIVE_APP[r.appStatus] then out[#out + 1] = r end
	end
	return out
end

----------------------------------------------------------------------
-- Filtros e ordenação
----------------------------------------------------------------------
local DECLINED = { declined = true, declined_full = true, declined_delisted = true }
ns.DECLINED = DECLINED

function KF:Passes(r, ignoreDungeon)
	local f, p = self.db.filters, self.player
	if not ignoreDungeon and next(f.dungeons) and not (r.map and f.dungeons[r.map.id]) then return false end
	if r.leaderScore < (f.minLeaderScore or 0) then return false end
	if (f.minLeaderBest or 0) > 0 and not (r.leaderTimed and r.leaderBest >= f.minLeaderBest) then return false end
	if f.myRole and (r.open[p.role] or 0) == 0 then return false end
	if f.needBL and r.hasBL then return false end
	if f.needBrez and r.hasBrez then return false end
	if f.meetReq and r.reqScore > p.score then return false end
	if f.autoOnly and not r.autoAccept then return false end
	if f.hideDeclined and r.appStatus and DECLINED[r.appStatus] then return false end
	if (f.maxAge or 0) > 0 and r.age > f.maxAge * 60 then return false end
	if (f.playstyle or 0) > 0 and r.playstyle ~= f.playstyle then return false end
	if not self:UpgradePasses(r) then return false end
	return true
end

local SORTS = {
	match = function(a, b) if a.score ~= b.score then return a.score > b.score end return a.age < b.age end,
	gain = function(a, b) if a.gain ~= b.gain then return a.gain > b.gain end return a.score > b.score end,
	score = function(a, b) if a.leaderScore ~= b.leaderScore then return a.leaderScore > b.leaderScore end return a.score > b.score end,
	best = function(a, b) if a.leaderBest ~= b.leaderBest then return a.leaderBest > b.leaderBest end return a.score > b.score end,
	age = function(a, b) return a.age < b.age end,
	key = function(a, b) if (a.est or 0) ~= (b.est or 0) then return (a.est or 0) > (b.est or 0) end return a.score > b.score end,
	full = function(a, b) if a.numMembers ~= b.numMembers then return a.numMembers > b.numMembers end return a.score > b.score end,
}

function KF:Rebuild()
	self.rebuildPending = nil
	if not self.db then return end
	self:RefreshPlayer()
	local _, ids = C_LFGList.GetSearchResults()
	local all = {}
	-- Marca como "novo" o grupo que apareceu depois da primeira busca.
	local errSum, errN = 0, 0
	local first = self.firstSeen == nil
	self.firstSeen = self.firstSeen or {}
	local now = GetTime()
	for _, id in ipairs(ids or {}) do
		local ok, r = pcall(self.ParseResult, self, id)
		if ok and r and not r.hasSelf then
			r.queryLevel = self.queryLevel
			if self.queryLevel and self.learnPending then
				local raw = self:RawKeyEstimate(r)
				if raw then errSum, errN = errSum + (self.queryLevel - raw), errN + 1 end
			end
			r.score, r.reasons = self:Score(r)
			if not self.firstSeen[id] then self.firstSeen[id] = first and 0 or now end
			r.isNew = self.firstSeen[id] > 0 and (now - self.firstSeen[id]) < 60
			all[#all + 1] = r
		end
	end
	if errN > 0 then self:LearnKey(errSum / errN, math.min(5, errN)) end
	self.learnPending = nil
	if #all > 0 and not self.lastSearch then self.lastSearch = GetTime() end
	self.results = all
	self:ApplyFilters()
	self:CheckRules()
end

function KF:Rescore()
	self:RefreshPlayer()
	for _, r in ipairs(self.results or {}) do r.score, r.reasons = self:Score(r) end
	self:ApplyFilters()
end

function KF:ApplyFilters()
	local out, counts = {}, {}
	local anyDungeon = next(self.db.filters.dungeons) ~= nil
	for _, r in ipairs(self.results or {}) do
		-- Contagem por dungeon com todos os filtros, menos o de dungeon.
		local passesRest = self:Passes(r, true)
		if passesRest and r.map then counts[r.map.id] = (counts[r.map.id] or 0) + 1 end
		if passesRest and (not anyDungeon or (r.map and self.db.filters.dungeons[r.map.id])) then out[#out + 1] = r end
	end
	self.mapCounts = counts
	-- Grupos em que você já se candidatou ficam sempre no topo.
	local base = SORTS[self.db.sort] or SORTS.match
	table.sort(out, function(a, b)
		local pa, pb = ACTIVE_APP[a.appStatus] and 0 or 1, ACTIVE_APP[b.appStatus] and 0 or 1
		if pa ~= pb then return pa < pb end
		return base(a, b)
	end)
	self.filtered = out
	if ns.UI then ns.UI:OnDataChanged() end
end

function KF:CountGood()
	local n = 0
	for _, r in ipairs(self.filtered or {}) do if r.score >= 75 then n = n + 1 end end
	return n
end

function KF:ScheduleRebuild()
	if self.rebuildPending then return end
	self.rebuildPending = true
	C_Timer.After(0.15, function() KF:Rebuild() end)
end

function KF:FindResult(id)
	for _, r in ipairs(self.results or {}) do if r.id == id then return r end end
end

----------------------------------------------------------------------
-- Busca (precisa vir de clique ou tecla: hardware event)
----------------------------------------------------------------------
function KF:Search()
	if not (C_LFGList and C_LFGList.Search) then return end
	local filter = 0
	if Enum.LFGListFilter then
		filter = bit.bor(Enum.LFGListFilter.PvE or 0, Enum.LFGListFilter.CurrentSeason or 0)
	end
	local languages = C_LFGList.GetLanguageSearchFilter and C_LFGList.GetLanguageSearchFilter() or nil
	self.searchFailed = nil
	self.ownSearch = true
	C_LFGList.Search(ns.CATEGORY_DUNGEONS, filter, 0, languages)
end

----------------------------------------------------------------------
-- Candidaturas
----------------------------------------------------------------------
function KF:MaxApplications() return MAX_LFG_LIST_APPLICATIONS or 5 end

function KF:NumApplications()
	if C_LFGList.GetNumApplications then
		local _, active = C_LFGList.GetNumApplications()
		if active then return active end
	end
	return #(C_LFGList.GetApplications() or {})
end

-- Retorna podeCandidatar, motivo
function KF:CanApply(r)
	if not r then return false end
	if C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo() then return false, L.LISTED end
	if r.appStatus == "applied" then return false, L.APPLIED end
	if r.appStatus == "invited" then return false, L.INVITED end
	if (r.open[self.player.role] or 0) == 0 then return false, L.NO_SLOT end
	if self:NumApplications() >= self:MaxApplications() then return false, L.APP_FULL end
	return true
end

function KF:Apply(resultID)
	local role = self.player and self.player.role or GetPlayerRole()
	C_LFGList.ApplyToGroup(resultID, role == "TANK", role == "HEALER", role == "DAMAGER")
end

function KF:CancelApplication(resultID)
	C_LFGList.CancelApplication(resultID)
end

----------------------------------------------------------------------
-- Watchlist
----------------------------------------------------------------------
function KF:RuleMatches(rule, r)
	if (rule.mapID or 0) ~= 0 and not (r.map and r.map.id == rule.mapID) then return false end
	if r.leaderScore < (rule.minScore or 0) then return false end
	if (rule.minBest or 0) > 0 and not (r.leaderTimed and r.leaderBest >= rule.minBest) then return false end
	if rule.myRole and (r.open[self.player.role] or 0) == 0 then return false end
	if r.reqScore > self.player.score then return false end
	return true
end

function KF:RuleHits(rule)
	local n = 0
	for _, r in ipairs(self.results or {}) do if self:RuleMatches(rule, r) then n = n + 1 end end
	return n
end

function KF:AddRule(rule)
	rule.id = self.db.nextRuleID
	self.db.nextRuleID = self.db.nextRuleID + 1
	rule.enabled = true
	table.insert(self.db.rules, rule)
	self:CheckRules()
	if ns.UI then ns.UI:OnDataChanged() end
end

function KF:RemoveRule(id)
	for i, rule in ipairs(self.db.rules) do
		if rule.id == id then table.remove(self.db.rules, i) break end
	end
	if ns.UI then ns.UI:OnDataChanged() end
end

function KF:HasRuleForMap(mapID)
	for _, rule in ipairs(self.db.rules) do if rule.mapID == mapID then return true end end
	return false
end

function KF:MatchLine(r)
	local best = r.leaderBest > 0 and ("+" .. r.leaderBest) or L.NO_BEST
	return L.MATCH_LINE:format(r.dungeonName, r.leaderName or "?", r.leaderScore, best)
end

function KF:CheckRules()
	if #self.db.rules == 0 then return end
	self.alerted = self.alerted or {}
	for _, r in ipairs(self.results or {}) do
		local fresh = not r.appStatus or r.appStatus == "none"
		if fresh and not self.alerted[r.id] then
			for _, rule in ipairs(self.db.rules) do
				if rule.enabled and self:RuleMatches(rule, r) then
					self.alerted[r.id] = true
					self:Alert(self:MatchLine(r), r.id)
					break
				end
			end
		end
	end
end

function KF:Alert(text, resultID)
	local a = self.db.alerts
	Print(L.MATCH_CHAT:format(text))
	if a.sound then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
	if a.flash and FlashClientIcon then FlashClientIcon() end
	if a.raidWarning and RaidWarningFrame and RaidNotice_AddMessage then
		RaidNotice_AddMessage(RaidWarningFrame, "Keyfinder: " .. text, ChatTypeInfo["RAID_WARNING"])
	end
	if a.popup and not InCombatLockdown() and not StaticPopup_Visible("KEYFINDER_MATCH") then
		StaticPopup_Show("KEYFINDER_MATCH", text, nil, { resultID = resultID })
	end
end

StaticPopupDialogs["KEYFINDER_MATCH"] = {
	text = L.POPUP_TEXT,
	button1 = L.APPLY,
	button2 = L.IGNORE,
	OnAccept = function(_, data)
		if data and data.resultID then
			local r = KF:FindResult(data.resultID)
			if r and KF:CanApply(r) then KF:Apply(data.resultID) end
		end
	end,
	timeout = 45,
	whileDead = false,
	hideOnEscape = true,
	preferredIndex = 3,
}

----------------------------------------------------------------------
-- Sugestões para o anúncio (usadas no preenchimento automático da
-- janela de anúncio da Blizzard).
----------------------------------------------------------------------
-- Sua key: dungeon (challengeMapID), nível e a atividade do anúncio.
function KF:GetOwnedKeyListing()
	local activityID, groupID, level
	if C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel then
		activityID, groupID, level = C_LFGList.GetOwnedKeystoneActivityAndGroupAndLevel()
	end
	local mapID
	if activityID then
		local act = C_LFGList.GetActivityInfoTable(activityID)
		local m = act and self:ResolveMap(act, nil)
		mapID = m and m.id
	end
	mapID = mapID or (self.player and self.player.keyMapID)
	level = level or (self.player and self.player.keyLevel)
	return mapID, level, activityID, groupID
end

-- Rating mínimo sugerido para uma key: ~85% do rating de quem tima um
-- nível abaixo em todas as dungeons, arredondado e nunca acima do seu.
function KF:SuggestedRating(level)
	if not level or level < 2 then return 0 end
	local v = self:ExpectedScore(level - 1) * self:NumMaps() * 0.85
	v = math.floor(v / 50) * 50
	return math.max(0, math.min(v, math.floor((self.player.score or 0) / 50) * 50))
end

function KF:SuggestedItemLevel()
	local il = self.player and self.player.ilvl or 0
	if il <= 0 then return 0 end
	return math.max(0, math.floor((il - 10) / 5) * 5)
end

----------------------------------------------------------------------
-- Visão do líder: candidatos ao seu grupo
----------------------------------------------------------------------
local function PartyComposition()
	local comp = { roles = { TANK = 0, HEALER = 0, DAMAGER = 0 }, hasBL = false, hasBrez = false, members = {} }
	local units = { "player" }
	for i = 1, 4 do units[#units + 1] = "party" .. i end
	for _, unit in ipairs(units) do
		if UnitExists(unit) then
			local _, class = UnitClass(unit)
			class = safe(class)
			local role = safe(UnitGroupRolesAssigned(unit))
			if not role or role == "NONE" then role = unit == "player" and KF.player.role or "DAMAGER" end
			comp.roles[role] = (comp.roles[role] or 0) + 1
			if class and ns.BL_CLASSES[class] then comp.hasBL = true end
			if class and ns.BREZ_CLASSES[class] then comp.hasBrez = true end
			comp.members[#comp.members + 1] = { name = safe(UnitName(unit)), class = class, role = role, isPlayer = unit == "player" }
		end
	end
	comp.open = { TANK = math.max(0, 1 - comp.roles.TANK), HEALER = math.max(0, 1 - comp.roles.HEALER), DAMAGER = math.max(0, 3 - comp.roles.DAMAGER) }
	return comp
end

function KF:GetLeaderData()
	self:RefreshPlayer()
	local data = { applicants = {} }
	data.comp = PartyComposition()
	local p = self.player
	if p.keyMapID then
		data.keyName = C_ChallengeMode.GetMapUIInfo(p.keyMapID)
		data.keyLevel = p.keyLevel
		data.keyMapID = p.keyMapID
	end
	if not (C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo()) then return data end

	local entry = C_LFGList.GetActiveEntryInfo()
	local actID = entry and ((entry.activityIDs and entry.activityIDs[1]) or entry.activityID)
	data.entry = entry
	data.actID = actID
	data.act = actID and C_LFGList.GetActivityInfoTable(actID)
	local listedMap = data.act and self:ResolveMap(data.act, nil)
	data.listedMap = listedMap
	-- Nível de referência: sua key, se o anúncio for da dungeon dela.
	if listedMap and data.keyMapID == listedMap.id then data.refLevel = data.keyLevel end

	for _, appID in ipairs(C_LFGList.GetApplicants() or {}) do
		local ai = C_LFGList.GetApplicantInfo(appID)
		if ai then
			local a = { id = appID, status = ai.pendingApplicationStatus or ai.applicationStatus, numMembers = ai.numMembers or 1, isNew = ai.isNew, members = {} }
			for m = 1, a.numMembers do
				local name, class, locClass, _, ilvl, _, tank, healer, damage, assignedRole, relationship, dscore, _, _, _, specID, isLeaver = C_LFGList.GetApplicantMemberInfo(appID, m)
				local best = actID and C_LFGList.GetApplicantDungeonScoreForListing and C_LFGList.GetApplicantDungeonScoreForListing(appID, m, actID)
				local specName
				if specID and GetSpecializationInfoByID then specName = select(2, GetSpecializationInfoByID(specID)) end
				a.members[m] = {
					name = safe(name), class = safe(class), className = safe(locClass), ilvl = safe(ilvl) or 0,
					role = safe(assignedRole) or (tank and "TANK") or (healer and "HEALER") or "DAMAGER",
					friend = safe(relationship), score = safe(dscore) or 0, spec = specName, leaver = safe(isLeaver),
					best = best and (safe(best.bestRunLevel) or 0) or 0, timed = best and safe(best.finishedSuccess) or false,
				}
			end
			a.fit, a.tags = self:ScoreApplication(a, data)
			data.applicants[#data.applicants + 1] = a
		end
	end
	table.sort(data.applicants, function(x, y)
		local px, py = x.status == "applied" and 0 or 1, y.status == "applied" and 0 or 1
		if px ~= py then return px < py end
		return x.fit > y.fit
	end)
	return data
end

-- Candidatura inteira: um jogador ou um grupo. Para grupos, a nota é a
-- média dos membros, com bônus se todos cabem nas vagas abertas e uma
-- penalidade forte se não cabem; utilidade conta se qualquer um traz.
function KF:ScoreApplication(a, data)
	if #a.members <= 1 then
		local m = a.members[1]
		local fit, tags = self:ScoreApplicant(m, data)
		if m then m.fit, m.tags = fit, tags end
		return fit, tags
	end
	local comp = data.comp
	local open = { TANK = comp.open.TANK or 0, HEALER = comp.open.HEALER or 0, DAMAGER = comp.open.DAMAGER or 0 }
	local sum, fits, bl, brez = 0, true, false, false
	for _, m in ipairs(a.members) do
		m.fit, m.tags = self:ScoreApplicant(m, data)
		sum = sum + m.fit
		if (open[m.role] or 0) > 0 then open[m.role] = open[m.role] - 1 else fits = false end
		if m.class and ns.BL_CLASSES[m.class] then bl = true end
		if m.class and ns.BREZ_CLASSES[m.class] then brez = true end
	end
	local s = sum / #a.members
	local tags = {}
	if fits then
		s = s + 6
		tags[#tags + 1] = { good = true, text = L.A_GROUP_FITS }
	else
		s = s - 35
		tags[#tags + 1] = { good = false, text = L.A_GROUP_NOFIT }
	end
	if bl and not comp.hasBL then tags[#tags + 1] = { good = true, text = L.A_BL } end
	if brez and not comp.hasBrez then tags[#tags + 1] = { good = true, text = L.A_BREZ } end
	return clamp(math.floor(s + 0.5), 1, 99), tags
end

function KF:ScoreApplicant(m, data)
	local tags = {}
	local function tag(good, text) tags[#tags + 1] = { good = good, text = text } end
	if not m then return 0, tags end
	local p, comp = self.player, data.comp
	local s = 50
	if (comp.open[m.role] or 0) > 0 then s = s + 15 else s = s - 40; tag(false, L.A_ROLE_FULL) end
	local ref = data.refLevel
	if m.best > 0 then
		if m.timed then
			tag(true, L.A_TIMED:format(m.best))
			if ref then s = s + (m.best >= ref and 15 or (m.best >= ref - 1 and 5 or -8)) else s = s + 6 end
		else
			tag(false, L.A_DEPLETED:format(m.best))
			s = s - 2
		end
	else
		s = s - 10
	end
	local gap = m.score - p.score
	if gap >= -200 then s = s + 8 elseif gap < -500 then s = s - 8 end
	if p.ilvl > 0 and m.ilvl > 0 then s = s + math.max(-8, math.min(6, math.floor((m.ilvl - p.ilvl) * 1.5))) end
	if m.class and ns.BL_CLASSES[m.class] and not comp.hasBL then s = s + 8; tag(true, L.A_BL) end
	if m.class and ns.BREZ_CLASSES[m.class] and not comp.hasBrez then s = s + 5; tag(true, L.A_BREZ) end
	if m.friend then s = s + 5; tag(true, L.A_FRIEND) end
	if m.leaver then s = s - 12; tag(false, L.A_LEAVER) end
	return math.max(1, math.min(99, math.floor(s + 0.5))), tags
end

function KF:Invite(appID) C_LFGList.InviteApplicant(appID) end
function KF:Decline(appID) C_LFGList.DeclineApplicant(appID) end

----------------------------------------------------------------------
-- Eventos
----------------------------------------------------------------------
KF:RegisterEvent("ADDON_LOADED")
KF:RegisterEvent("PLAYER_LOGIN")
KF:SetScript("OnEvent", function(self, event, ...) if self[event] then self[event](self, ...) end end)

function KF:ADDON_LOADED(name)
	if name ~= ADDON then return end
	KeyfinderDB = KeyfinderDB or {}
	CopyDefaults(DEFAULTS, KeyfinderDB)
	self.db = KeyfinderDB
	-- "key" ordenava pelo palpite de nível; não existe mais.
	if self.db.sort == "key" or self.db.sort == "gain" then self.db.sort = "match" end
	self:UnregisterEvent("ADDON_LOADED")
end

function KF:PLAYER_LOGIN()
	self:RefreshPlayer()
	if C_MythicPlus and C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
	self:LoadSeasonMaps()
	self:RefreshPlayer()
	for _, e in ipairs({
		"PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_MAPS_UPDATE", "PLAYER_SPECIALIZATION_CHANGED",
		"LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_SEARCH_FAILED",
		"LFG_LIST_APPLICATION_STATUS_UPDATED", "LFG_LIST_APPLICANT_LIST_UPDATED", "LFG_LIST_APPLICANT_UPDATED",
		"LFG_LIST_ACTIVE_ENTRY_UPDATE", "GROUP_ROSTER_UPDATE", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_START",
	}) do self:RegisterEvent(e) end
	if ns.UI then ns.UI:OnLogin() end
end

function KF:PLAYER_ENTERING_WORLD() self:RefreshPlayer() end
function KF:CHALLENGE_MODE_MAPS_UPDATE() self:LoadSeasonMaps() end
function KF:PLAYER_SPECIALIZATION_CHANGED(unit) if unit == "player" then self:ScheduleRebuild() end end
function KF:CHALLENGE_MODE_COMPLETED()
	-- O resumo de rating demora um pouco para atualizar depois da run.
	C_Timer.After(3, function() KF:Rescore() end)
end

function KF:LFG_LIST_SEARCH_RESULTS_RECEIVED()
	self.lastSearch = GetTime()
	self.searchFailed = nil
	-- Número digitado na busca do Localizador = nível exato. Só vale para buscas
	-- feitas por lá (não sabemos se a nossa busca usa o mesmo texto).
	self.queryLevel = ReadQueryLevel()
	self.learnPending = self.queryLevel ~= nil
	self.ownSearch = nil
	self:Rebuild()
end
function KF:LFG_LIST_SEARCH_RESULT_UPDATED() self:ScheduleRebuild() end
function KF:LFG_LIST_APPLICATION_STATUS_UPDATED(resultID, newStatus)
	-- Entrou num grupo: guarda a estimativa para comparar com a key real.
	if newStatus == "inviteaccepted" then
		local r = self:FindResult(resultID)
		if r and r.estRaw and not r.queryLevel then
			self.pendingKey = { raw = r.estRaw, mapID = r.map and r.map.id, t = GetTime() }
		end
	end
	self:ScheduleRebuild()
end

function KF:CHALLENGE_MODE_START()
	local pk = self.pendingKey
	self.pendingKey = nil
	if not pk or GetTime() - pk.t > 3600 then return end
	local level = C_ChallengeMode.GetActiveKeystoneInfo and C_ChallengeMode.GetActiveKeystoneInfo()
	local mapID = C_ChallengeMode.GetActiveChallengeMapID and C_ChallengeMode.GetActiveChallengeMapID()
	if level and level > 0 and (not pk.mapID or pk.mapID == mapID) then
		self:LearnKey(level - pk.raw, 2)
	end
end
function KF:LFG_LIST_SEARCH_FAILED()
	self.searchFailed = true
	if ns.UI then ns.UI:OnDataChanged() end
end

local function LeaderChanged() if ns.UI then ns.UI:OnLeaderChanged() end end
KF.LFG_LIST_APPLICANT_LIST_UPDATED = LeaderChanged
KF.LFG_LIST_APPLICANT_UPDATED = LeaderChanged
KF.LFG_LIST_ACTIVE_ENTRY_UPDATE = LeaderChanged
KF.GROUP_ROSTER_UPDATE = LeaderChanged

----------------------------------------------------------------------
-- Pontos de entrada globais (atalhos, compartimento de addons, slash)
----------------------------------------------------------------------
function Keyfinder_Toggle() if ns.UI then ns.UI:Toggle() end end
function Keyfinder_Refresh() KF:Search() end

function Keyfinder_OnAddonCompartmentClick() Keyfinder_Toggle() end
function Keyfinder_OnAddonCompartmentEnter(_, button)
	GameTooltip:SetOwner(button or MinimapCluster or UIParent, "ANCHOR_LEFT")
	GameTooltip:SetText(L.TITLE, 1, 1, 1)
	GameTooltip:AddLine(L.TOOLTIP_HINT, nil, nil, nil, true)
	GameTooltip:Show()
end
function Keyfinder_OnAddonCompartmentLeave() GameTooltip:Hide() end

SLASH_KEYFINDER1 = "/kf"
SLASH_KEYFINDER2 = "/keyfinder"
SlashCmdList.KEYFINDER = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "buscar" or msg == "search" then
		KF:Search()
	elseif msg == "reset" then
		KF.db.pos = nil
		if ns.UI then ns.UI:ResetPosition() end
	elseif msg == "help" or msg == "ajuda" then
		Print(L.SLASH_HELP)
	else
		Keyfinder_Toggle()
	end
end

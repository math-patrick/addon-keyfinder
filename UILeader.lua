local _, ns = ...
local L, KF, W = ns.L, ns.KF, ns.W
ns.UI = ns.UI or {}
local UI = ns.UI

-- Visão de quem monta o grupo: o seu anúncio, o que falta no grupo,
-- recomendações e a lista de candidatos ordenada por encaixe.

local LEFT_W = 300
local INNER = LEFT_W - 24
local BANNER_H = 110

-- Colunas da linha de candidato, medidas a partir da borda direita.
local DECLINE_W, INVITE_W, PA_W, ILVL_W, BEST_W, RATING_W = 70, 76, 20, 40, 48, 50
local DECLINE_R = -6
local INVITE_R = DECLINE_R - DECLINE_W - 4
local PA_R = INVITE_R - INVITE_W - 8
local ILVL_R = PA_R - PA_W - 8
local BEST_R = ILVL_R - ILVL_W - 8
local RATING_R = BEST_R - BEST_W - 8
local TEXT_R = RATING_R - RATING_W - 8
local TEXT_L = 84

local function ClassList(set)
	local names = {}
	for class in pairs(set) do
		local loc = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
		names[#names + 1] = W.ClassColored(loc, class)
	end
	table.sort(names)
	return table.concat(names, ", ")
end

----------------------------------------------------------------------
-- Linha de candidato (template KeyfinderApplicantRowTemplate)
----------------------------------------------------------------------
KeyfinderApplicantRowMixin = {}

function KeyfinderApplicantRowMixin:OnLoad()
	self.Stripe = self:CreateTexture(nil, "BACKGROUND")
	self.Stripe:SetAllPoints()
	self.Stripe:SetColorTexture(0, 0, 0, 0.25)
	self.Tint = self:CreateTexture(nil, "BACKGROUND", nil, 1)
	self.Tint:SetPoint("TOPLEFT")
	self.Tint:SetPoint("BOTTOMLEFT")
	self.Tint:SetWidth(200)
	self.Rec = W.Border(self, 1, 0.82, 0, 0.7, "ARTWORK")
	self.Sep = self:CreateTexture(nil, "ARTWORK")
	self.Sep:SetPoint("BOTTOMLEFT")
	self.Sep:SetPoint("BOTTOMRIGHT")
	self.Sep:SetHeight(1)
	self.Sep:SetColorTexture(1, 1, 1, 0.06)

	self.Badge = W.Badge(self, 34)
	self.Badge:SetPoint("LEFT", 6, 0)
	self.Icon = W.Icon(self, 30)
	self.Icon:SetPoint("LEFT", 46, 0)
	self.Role = self.Icon:CreateTexture(nil, "OVERLAY")
	self.Role:SetSize(14, 14)
	self.Role:SetPoint("BOTTOMRIGHT", 4, -4)

	self.Name = W.Text(self, "GameFontHighlight", "LEFT", 13)
	self.Name:SetPoint("TOPLEFT", TEXT_L, -7)
	self.Name:SetPoint("RIGHT", self, "RIGHT", TEXT_R, 0)
	self.Sub = W.Text(self, "GameFontHighlightSmall")
	self.Sub:SetPoint("BOTTOMLEFT", TEXT_L, 8)
	self.Sub:SetPoint("RIGHT", self, "RIGHT", TEXT_R, 0)

	local function col(width, right, size)
		local fs = W.Text(self, "GameFontHighlight", "CENTER", size or 13, "OUTLINE")
		fs:SetPoint("RIGHT", self, "RIGHT", right, 0)
		fs:SetWidth(width)
		return fs
	end
	self.Rating = col(RATING_W, RATING_R)
	self.Best = col(BEST_W, BEST_R)
	self.Ilvl = col(ILVL_W, ILVL_R, 12)

	self.PA = UI:CreateParseAcademyButton(self, function() local m = self.data and self.data.members[1]; return m and m.name end)
	self.PA:SetPoint("RIGHT", self, "RIGHT", PA_R, 0)

	self.Decline = W.Button(self, L.LD_DECLINE, DECLINE_W, function() if self.data then KF:Decline(self.data.id) end end)
	self.Decline:SetPoint("RIGHT", DECLINE_R, 0)
	self.Invite = W.Button(self, L.LD_INVITE, INVITE_W, function() if self.data then KF:Invite(self.data.id) end end)
	self.Invite:SetPoint("RIGHT", INVITE_R, 0)
	self.Status = W.Text(self, "GameFontHighlightSmall", "CENTER")
	self.Status:SetPoint("RIGHT", DECLINE_R, 0)
	self.Status:SetWidth(DECLINE_W + INVITE_W + 4)
end

function KeyfinderApplicantRowMixin:Init(a)
	self.data = a
	local m = a.members[1] or {}
	local cr, cg, cb = W.MatchColor(a.fit)
	self.Badge:Set(a.fit, cr, cg, cb)
	W.Gradient(self.Tint, "HORIZONTAL", cr, cg, cb, 0.12, cr, cg, cb, 0)
	W.SetClassIcon(self.Icon.tex, m.class)
	self.Icon.border:SetColor(W.ClassColor(m.class))
	W.SetRoleIcon(self.Role, m.role)

	local name = W.ClassColored(m.name and Ambiguate(m.name, "short") or "?", m.class)
	if a.numMembers > 1 then name = name .. "  |cff808080" .. L.LD_PLUS:format(a.numMembers - 1) .. "|r" end
	if a.recommended then name = name .. "  |cffffd100" .. L.LD_RECOMMENDED .. "|r" end
	self.Name:SetText(name)

	local parts = { m.spec or m.className or "" }
	for _, t in ipairs(a.tags) do parts[#parts + 1] = (t.good and W.GOOD or W.BAD):WrapTextInColorCode(t.text) end
	self.Sub:SetText(table.concat(parts, "  ·  "))

	self.Rating:SetText(W.ScoreText(m.score or 0))
	self.Best:SetText(W.BestText(m.best, m.timed))
	local p = KF.player
	if (p.ilvl or 0) > 0 and (m.ilvl or 0) > 0 then
		local diff = math.floor(m.ilvl - p.ilvl + 0.5)
		self.Ilvl:SetText((diff >= 0 and W.GOOD or W.GRAY):WrapTextInColorCode((diff >= 0 and "+" or "") .. diff))
	else
		self.Ilvl:SetText(math.floor(m.ilvl or 0))
	end

	local pending = a.status == "applied"
	local canManage = UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") or not IsInGroup()
	self.Invite:SetShown(pending and canManage)
	self.Decline:SetShown(pending and canManage)
	self.Status:SetShown(not (pending and canManage))
	self.Status:SetText(pending and "" or (L.LD_STATUS[a.status] or ""))
	self.PA:SetShown(m.name ~= nil)
	self.Rec:SetShown(a.recommended and pending)
	self:SetAlpha((pending or a.status == "invited" or a.status == "inviteaccepted") and 1 or 0.5)
end

----------------------------------------------------------------------
-- Aba "Meu grupo"
----------------------------------------------------------------------
function UI:BuildLeader(page)
	local ld = {}
	self.leaderUI = ld

	local left = W.Panel(page)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(LEFT_W)
	local right = W.Panel(page)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 5, 0)
	right:SetPoint("BOTTOMRIGHT")

	-- Banner da dungeon anunciada
	ld.art = left:CreateTexture(nil, "ARTWORK")
	ld.art:SetPoint("TOPLEFT", 3, -3)
	ld.art:SetPoint("TOPRIGHT", -3, -3)
	ld.art:SetHeight(BANNER_H)
	local shade = left:CreateTexture(nil, "ARTWORK", nil, 1)
	shade:SetAllPoints(ld.art)
	W.Gradient(shade, "VERTICAL", 0, 0, 0, 0.95, 0, 0, 0, 0)
	local line = left:CreateTexture(nil, "ARTWORK", nil, 2)
	line:SetPoint("TOPLEFT", ld.art, "BOTTOMLEFT")
	line:SetPoint("TOPRIGHT", ld.art, "BOTTOMRIGHT")
	line:SetHeight(2)
	W.Gradient(line, "HORIZONTAL", 1, 0.82, 0, 0.8, 1, 0.82, 0, 0.05)
	ld.key = W.Text(left, "GameFontHighlightSmall", "LEFT", 11)
	ld.key:SetPoint("BOTTOMLEFT", ld.art, "BOTTOMLEFT", 10, 9)
	W.Clamp(ld.key, INNER)
	ld.title = W.Text(left, "GameFontHighlight", "LEFT", 12)
	ld.title:SetPoint("BOTTOMLEFT", ld.key, "TOPLEFT", 0, 4)
	W.Clamp(ld.title, INNER)
	ld.dungeon = W.Text(left, "GameFontNormalLarge", "LEFT", 17, "OUTLINE")
	ld.dungeon:SetPoint("BOTTOMLEFT", ld.title, "TOPLEFT", 0, 4)
	W.Clamp(ld.dungeon, INNER)

	-- Composição atual
	local y = -BANNER_H - 14
	local h = W.Section(left, L.LD_PARTY, INNER); h:SetPoint("TOPLEFT", 12, y)
	ld.slots = {}
	for i = 1, 5 do
		local s = W.Icon(left, 28)
		s:SetPoint("TOPLEFT", 12 + (i - 1) * 34, y - 18)
		s.role = s:CreateTexture(nil, "OVERLAY")
		s.role:SetSize(13, 13)
		s.role:SetPoint("BOTTOMRIGHT", 4, -4)
		s:EnableMouse(true)
		s:SetScript("OnEnter", function(self)
			if not self.info then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.info, 1, 1, 1)
			GameTooltip:Show()
		end)
		s:SetScript("OnLeave", GameTooltip_Hide)
		ld.slots[i] = s
	end
	ld.util = {}
	for i, def in ipairs(W.UTILS) do
		local ic = W.UtilIcon(left, def, 22)
		ic:SetPoint("TOPRIGHT", -12 - (2 - i) * 28, y - 21)
		ld.util[i] = ic
	end

	-- Recomendações
	y = y - 62
	h = W.Section(left, L.LD_TIPS, INNER); h:SetPoint("TOPLEFT", 12, y)
	ld.tips = {}
	for i = 1, 5 do
		local fs = W.Text(left, "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", 12, y - 18 - (i - 1) * 30)
		fs:SetWidth(INNER)
		fs:SetWordWrap(true)
		fs:SetMaxLines(2)
		fs:SetJustifyV("TOP")
		ld.tips[i] = fs
	end

	-- Resumo dos candidatos
	h = W.Section(left, L.LD_INSIGHTS, INNER); h:SetPoint("BOTTOMLEFT", 12, 64)
	ld.insight1 = W.Text(left, "GameFontHighlightSmall")
	ld.insight1:SetPoint("BOTTOMLEFT", 12, 44)
	W.Clamp(ld.insight1, INNER)
	ld.insight2 = W.Text(left, "GameFontHighlightSmall")
	ld.insight2:SetPoint("BOTTOMLEFT", 12, 28)
	W.Clamp(ld.insight2, INNER)
	ld.insight3 = W.Text(left, "GameFontHighlightSmall")
	ld.insight3:SetPoint("BOTTOMLEFT", 12, 12)
	W.Clamp(ld.insight3, INNER)

	-- Lista de candidatos
	local header = CreateFrame("Frame", nil, right)
	header:SetPoint("TOPLEFT", 4, -6)
	header:SetPoint("TOPRIGHT", -26, -6)
	header:SetHeight(16)
	local function col(text, x, width, justify, fromRight)
		local fs = W.Text(header, "GameFontNormalSmall", justify or "CENTER", 10)
		if fromRight then fs:SetPoint("RIGHT", header, "RIGHT", x, 0) else fs:SetPoint("LEFT", header, "LEFT", x, 0) end
		fs:SetWidth(width)
		fs:SetText(text)
	end
	col(L.LD_COL_FIT, 4, 38)
	col(L.LD_COL_NAME, TEXT_L, 140, "LEFT")
	col(L.LD_COL_SCORE, RATING_R, RATING_W, nil, true)
	col(L.LD_COL_BEST, BEST_R, BEST_W, nil, true)
	col(L.LD_COL_ILVL, ILVL_R, ILVL_W, nil, true)
	local hl = header:CreateTexture(nil, "ARTWORK")
	hl:SetPoint("BOTTOMLEFT", 0, -3)
	hl:SetPoint("BOTTOMRIGHT", 22, -3)
	hl:SetHeight(1)
	hl:SetColorTexture(1, 0.82, 0, 0.2)
	W.Tooltip(header, L.LD_COL_FIT, L.LD_FIT_HINT)

	local box = W.List(right, "KeyfinderApplicantRowTemplate", function(row, a) row:Init(a) end)
	box:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -5)
	box:SetPoint("BOTTOMRIGHT", -26, 5)
	ld.list = box

	local empty = CreateFrame("Frame", nil, right)
	empty:SetSize(380, 120)
	empty:SetPoint("CENTER", box, 0, 10)
	empty.icon = empty:CreateTexture(nil, "ARTWORK")
	empty.icon:SetSize(48, 48)
	empty.icon:SetPoint("TOP")
	empty.icon:SetTexture("Interface\\Icons\\achievement_guildperk_everybodysfriend")
	empty.icon:SetDesaturated(true)
	empty.icon:SetAlpha(0.5)
	empty.text = W.Text(empty, "GameFontDisable", "CENTER", 12)
	empty.text:SetPoint("TOP", empty.icon, "BOTTOM", 0, -10)
	empty.text:SetWidth(380)
	empty.text:SetWordWrap(true)
	ld.empty = empty
	self:BuildListingForm(right)
end

----------------------------------------------------------------------
-- Formulário "Anunciar grupo": tudo pré-preenchido a partir da sua key
-- e do seu personagem, e tudo editável.
----------------------------------------------------------------------
local function NumberBox(parent, width)
	local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	eb:SetSize(width, 22)
	eb:SetAutoFocus(false)
	eb:SetNumeric(true)
	eb:SetMaxLetters(5)
	eb:SetJustifyH("CENTER")
	eb:SetScript("OnEnterPressed", eb.ClearFocus)
	eb:SetScript("OnEscapePressed", eb.ClearFocus)
	-- Depois que o jogador mexe, a sugestão não sobrescreve mais.
	eb:SetScript("OnTextChanged", function(self, userInput) if userInput then self.edited = true end end)
	return eb
end

local function Label(parent, text, anchor)
	local fs = W.Text(parent, "GameFontNormalSmall", "CENTER", 10)
	fs:SetPoint("BOTTOM", anchor, "TOP", 0, 4)
	fs:SetText(text)
	return fs
end

function UI:BuildListingForm(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(400, 300)
	f:SetPoint("CENTER", 0, 10)
	f:Hide()
	self.leaderUI.form = f
	local o = KF.db.listing

	f.art = f:CreateTexture(nil, "ARTWORK")
	f.art:SetPoint("TOP")
	f.art:SetSize(400, 96)
	local shade = f:CreateTexture(nil, "ARTWORK", nil, 1)
	shade:SetAllPoints(f.art)
	W.Gradient(shade, "VERTICAL", 0, 0, 0, 0.9, 0, 0, 0, 0.1)
	W.Border(f, 1, 0.82, 0, 0.25)

	f.dungeon = W.Dropdown(f, 250, function()
		local opts = {}
		for _, m in ipairs(KF.maps or {}) do
			if f.activities and f.activities[m.id] then opts[#opts + 1] = { text = m.name, value = m.id } end
		end
		return opts
	end, function() return f.mapID end, function(v) f.mapID = v; f.userMap = true; UI:RefreshListingForm() end)
	f.dungeon:SetPoint("BOTTOM", f.art, "BOTTOM", -24, 12)
	f.key = W.Text(f, "GameFontHighlight", "LEFT", 18, "OUTLINE")
	f.key:SetPoint("LEFT", f.dungeon, "RIGHT", 10, 0)

	local y = -136
	f.ilvl = NumberBox(f, 64); f.ilvl:SetPoint("TOP", -130, y)
	Label(f, L.LIST_ILVL, f.ilvl)
	f.rating = NumberBox(f, 72); f.rating:SetPoint("TOP", -30, y)
	Label(f, L.LIST_RATING, f.rating)
	local ps = {}
	for i = 1, 4 do ps[#ps + 1] = { text = L.PS[i], value = i } end
	f.style = W.Dropdown(f, 130, ps, function() return o.playstyle end, function(v) o.playstyle = v end)
	f.style:SetPoint("TOP", 100, y + 2)
	Label(f, L.LIST_STYLE, f.style)

	y = y - 44
	local checks = { { "autoAccept", L.LIST_AUTO }, { "private", L.LIST_PRIVATE }, { "crossFaction", L.LIST_CROSS } }
	f.checks = {}
	for i, def in ipairs(checks) do
		local key = def[1]
		local cb = W.Check(f, def[2], function() return o[key] end, function(v) o[key] = v end)
		cb:SetPoint("TOPLEFT", 24 + (i - 1) * 126, y)
		f.checks[i] = cb
	end

	f.list = W.Button(f, L.LIST_BUTTON, 200, function()
		local act = f.activities and f.activities[f.mapID]
		if not act then return end
		local ok = KF:CreateListing({
			activityID = act.activityID, groupID = act.groupID,
			ilvl = tonumber(f.ilvl:GetText()) or 0, rating = tonumber(f.rating:GetText()) or 0,
			playstyle = o.playstyle, autoAccept = o.autoAccept, private = o.private, crossFaction = o.crossFaction,
		})
		if not ok then ns.Print(L.LIST_FAILED) end
	end)
	f.list:SetHeight(30)
	f.list:SetPoint("BOTTOM", 0, 14)
end

function UI:RefreshListingForm()
	local f = self.leaderUI and self.leaderUI.form
	if not f then return end
	f.activities = KF:GetDungeonActivities()
	local keyMap, keyLevel = KF:GetOwnedKeyListing()
	if not f.userMap or not f.activities[f.mapID or 0] then
		f.mapID = (keyMap and f.activities[keyMap]) and keyMap or nil
		if not f.mapID then
			for _, m in ipairs(KF.maps or {}) do if f.activities[m.id] then f.mapID = m.id break end end
		end
	end
	local map = f.mapID and KF.mapByID and KF.mapByID[f.mapID]
	UI:SetBannerArt(f.art, map, 400, 96)
	f.dungeon:Sync()

	local isKey = keyMap and f.mapID == keyMap and keyLevel
	f.key:SetText(isKey and ("|cffffd100+" .. keyLevel .. "|r") or "")
	if not f.ilvl.edited then f.ilvl:SetText(tostring(KF:SuggestedItemLevel())) end
	if not f.rating.edited then f.rating:SetText(tostring(isKey and KF:SuggestedRating(keyLevel) or 0)) end
	f.style:Sync()
	for _, cb in ipairs(f.checks) do cb:Sync() end
	f.list:SetEnabled(f.mapID ~= nil and f.activities[f.mapID] ~= nil and not (C_LFGList.HasActiveEntryInfo and C_LFGList.HasActiveEntryInfo()))
end

-- Monta as recomendações a partir da composição e dos candidatos.
local function BuildTips(data)
	local tips = {}
	local comp = data.comp
	local open = {}
	for _, role in ipairs(ns.ROLE_ORDER) do
		local n = comp.open[role] or 0
		if n > 0 then open[#open + 1] = n .. " " .. (L.ROLE[role] or role) end
	end
	if #open > 0 then tips[#tips + 1] = L.TIP_NEED:format(table.concat(open, ", ")) else tips[#tips + 1] = L.TIP_FULL end
	if not comp.hasBL then tips[#tips + 1] = L.TIP_BL:format(ClassList(ns.BL_CLASSES)) end
	if not comp.hasBrez then tips[#tips + 1] = L.TIP_BREZ:format(ClassList(ns.BREZ_CLASSES)) end
	if data.refLevel then
		tips[#tips + 1] = L.TIP_KEY:format(data.refLevel, data.refLevel - 1)
	elseif data.entry then
		tips[#tips + 1] = L.TIP_NOKEY
	end
	local req = data.entry and ns.safe(data.entry.requiredDungeonScore)
	if data.entry and not (req and req > 0) then tips[#tips + 1] = L.TIP_NOREQ end
	return tips
end

function UI:RefreshLeader()
	local ld = self.leaderUI
	if not ld then return end
	local data = KF:GetLeaderData()
	local p = KF.player

	-- Banner
	local map = data.listedMap or (data.keyMapID and KF.mapByID and KF.mapByID[data.keyMapID])
	UI:SetBannerArt(ld.art, map, LEFT_W - 6, BANNER_H)
	if data.entry then
		ld.dungeon:SetText((data.listedMap and data.listedMap.name) or (data.act and data.act.fullName) or "")
		W.SetProtectedText(ld.title, data.entry.name)
	else
		ld.dungeon:SetText(L.LD_NOT_LISTED)
		ld.title:SetText("")
	end
	if data.keyName then ld.key:SetText(L.H_KEY:format(data.keyLevel, data.keyName))
	else ld.key:SetText("|cff808080" .. L.LD_NO_KEY .. "|r") end

	-- Composição
	local comp = data.comp
	local slots = W.BuildSlots(comp.members, comp.open)
	for i, s in ipairs(ld.slots) do
		local m = slots[i]
		if not m then
			s:Hide()
		elseif m.open then
			s:Show()
			W.SetRoleIcon(s.tex, m.role)
			s.tex:SetDesaturated(true); s.tex:SetAlpha(0.4)
			s.border:SetColor(0.3, 0.3, 0.3, 1)
			s.role:Hide()
			s.info = L.OPEN_SLOT:format(L.ROLE[m.role])
		else
			s:Show()
			W.SetClassIcon(s.tex, m.class)
			s.tex:SetDesaturated(false); s.tex:SetAlpha(1)
			s.border:SetColor(W.ClassColor(m.class))
			s.role:Show()
			W.SetRoleIcon(s.role, m.role)
			s.info = W.ClassColored(m.name or "?", m.class) .. "  |cff808080" .. (L.ROLE[m.role] or "") .. "|r"
		end
	end
	for _, ic in ipairs(ld.util) do
		ic:SetState(comp[ic.def.key] and true or false, false)
	end

	-- Recomendado: o candidato de maior encaixe para cada vaga aberta.
	local bestByRole = {}
	for _, a in ipairs(data.applicants) do
		a.recommended = nil
		local m = a.members[1]
		if a.status == "applied" and m and (comp.open[m.role] or 0) > 0 then
			if not bestByRole[m.role] or a.fit > bestByRole[m.role].fit then bestByRole[m.role] = a end
		end
	end
	for _, a in pairs(bestByRole) do a.recommended = true end

	local tips = BuildTips(data)
	for i, fs in ipairs(ld.tips) do fs:SetText(tips[i] and ("|cffffd100•|r " .. tips[i]) or "") end

	-- Resumo
	local pending, roles, sum, n, timedKey = 0, { TANK = 0, HEALER = 0, DAMAGER = 0 }, 0, 0, 0
	for _, a in ipairs(data.applicants) do
		if a.status == "applied" then
			pending = pending + 1
			for _, m in ipairs(a.members) do
				roles[m.role] = (roles[m.role] or 0) + 1
				if (m.score or 0) > 0 then sum = sum + m.score; n = n + 1 end
				if data.refLevel and m.timed and (m.best or 0) >= data.refLevel then timedKey = timedKey + 1 end
			end
		end
	end
	ld.insight1:SetText(L.LD_IN_PENDING:format(pending, roles.TANK, roles.HEALER, roles.DAMAGER))
	ld.insight2:SetText(n > 0 and L.LD_IN_AVG:format(W.ScoreText(math.floor(sum / n))) or "")
	ld.insight3:SetText(data.refLevel and L.LD_IN_TIMED:format(timedKey, data.refLevel) or "")

	W.SetData(ld.list, data.applicants)
	ld.form:SetShown(not data.entry)
	if not data.entry then
		ld.empty:Hide()
		self:RefreshListingForm()
	elseif #data.applicants == 0 then
		ld.empty.text:SetText(L.LD_EMPTY); ld.empty:Show()
	else
		ld.empty:Hide()
	end
end

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
-- A linha principal mostra o primeiro jogador (ou quem lidera a
-- candidatura em grupo). Em candidaturas em grupo, cada membro extra
-- ganha uma sublinha com classe, role, rating, best e ilvl.
----------------------------------------------------------------------
local MAIN_H, SUB_H = 44, 26
ns.APPLICANT_EXTENT = function(_, a)
	local n = a and #a.members or 1
	return MAIN_H + math.max(0, n - 1) * SUB_H + (n > 1 and 4 or 0)
end

-- Ilvl do candidato, colorido em relação ao seu: verde = igual ou maior,
-- dourado = até 5 abaixo, vermelho = mais baixo que isso.
local ILVL_OK, ILVL_CLOSE, ILVL_LOW = CreateColor(0.25, 1, 0.45), CreateColor(1, 0.82, 0), CreateColor(1, 0.35, 0.35)
local function IlvlText(ilvl)
	ilvl = math.floor(ilvl or 0)
	if ilvl <= 0 then return "-" end
	local mine = KF.player and KF.player.ilvl or 0
	if mine <= 0 then return tostring(ilvl) end
	local diff = ilvl - math.floor(mine)
	local c = diff >= 0 and ILVL_OK or (diff >= -5 and ILVL_CLOSE or ILVL_LOW)
	return c:WrapTextInColorCode(tostring(ilvl))
end

local function Columns(parent, size)
	local function col(width, right)
		local fs = W.Text(parent, "GameFontHighlight", "CENTER", size, "OUTLINE")
		fs:SetPoint("RIGHT", parent, "RIGHT", right, 0)
		fs:SetWidth(width)
		return fs
	end
	return col(RATING_W, RATING_R), col(BEST_W, BEST_R), col(ILVL_W, ILVL_R)
end

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

	local main = CreateFrame("Frame", nil, self)
	main:SetPoint("TOPLEFT")
	main:SetPoint("TOPRIGHT")
	main:SetHeight(MAIN_H)
	self.Main = main

	self.Badge = W.Badge(main, 34)
	self.Badge:SetPoint("LEFT", 6, 0)
	self.Icon = W.Icon(main, 30)
	self.Icon:SetPoint("LEFT", 46, 0)
	self.Role = self.Icon:CreateTexture(nil, "OVERLAY")
	self.Role:SetSize(14, 14)
	self.Role:SetPoint("BOTTOMRIGHT", 4, -4)

	self.Name = W.Text(main, "GameFontHighlight", "LEFT", 13)
	self.Name:SetPoint("TOPLEFT", TEXT_L, -7)
	self.Name:SetPoint("RIGHT", main, "RIGHT", TEXT_R, 0)
	self.Sub = W.Text(main, "GameFontHighlightSmall")
	self.Sub:SetPoint("BOTTOMLEFT", TEXT_L, 8)
	self.Sub:SetPoint("RIGHT", main, "RIGHT", TEXT_R, 0)

	self.Rating, self.Best, self.Ilvl = Columns(main, 13)

	self.PA = UI:CreateParseAcademyButton(main, function() local m = self.data and self.data.members[1]; return m and m.name end)
	self.PA:SetPoint("RIGHT", main, "RIGHT", PA_R, 0)

	self.Decline = W.Button(main, L.LD_DECLINE, DECLINE_W, function() if self.data then KF:Decline(self.data.id) end end)
	self.Decline:SetPoint("RIGHT", DECLINE_R, 0)
	self.Invite = W.Button(main, L.LD_INVITE, INVITE_W, function() if self.data then KF:Invite(self.data.id) end end)
	self.Invite:SetPoint("RIGHT", INVITE_R, 0)
	self.Status = W.Text(main, "GameFontHighlightSmall", "CENTER")
	self.Status:SetPoint("RIGHT", DECLINE_R, 0)
	self.Status:SetWidth(DECLINE_W + INVITE_W + 4)

	-- Sublinhas para os demais membros de uma candidatura em grupo.
	self.Members = {}
	for i = 2, 5 do
		local line = CreateFrame("Frame", nil, self)
		line:SetPoint("TOPLEFT", main, "BOTTOMLEFT", 0, -(i - 2) * SUB_H)
		line:SetPoint("TOPRIGHT", main, "BOTTOMRIGHT", 0, -(i - 2) * SUB_H)
		line:SetHeight(SUB_H)
		line.guide = line:CreateTexture(nil, "ARTWORK")
		line.guide:SetColorTexture(1, 1, 1, 0.12)
		line.guide:SetSize(1, SUB_H)
		line.guide:SetPoint("LEFT", 61, 0)
		line.icon = W.Icon(line, 20)
		line.icon:SetPoint("LEFT", 52, 0)
		line.role = line.icon:CreateTexture(nil, "OVERLAY")
		line.role:SetSize(11, 11)
		line.role:SetPoint("BOTTOMRIGHT", 3, -3)
		line.name = W.Text(line, "GameFontHighlightSmall", "LEFT", 12)
		line.name:SetPoint("LEFT", TEXT_L, 0)
		line.name:SetPoint("RIGHT", line, "RIGHT", TEXT_R, 0)
		line.rating, line.best, line.ilvl = Columns(line, 12)
		line.pa = UI:CreateParseAcademyButton(line, function() return line.member and line.member.name end)
		line.pa:SetSize(16, 16)
		line.pa:SetPoint("RIGHT", line, "RIGHT", PA_R - 2, 0)
		self.Members[i] = line
	end
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
	if a.recommended then name = name .. "  |cffffd100" .. L.LD_RECOMMENDED .. "|r" end
	self.Name:SetText(name)

	local parts = { m.spec or m.className or "" }
	for _, t in ipairs(a.tags) do parts[#parts + 1] = (t.good and W.GOOD or W.BAD):WrapTextInColorCode(t.text) end
	self.Sub:SetText(table.concat(parts, "  ·  "))

	self.Rating:SetText(W.ScoreText(m.score or 0))
	self.Best:SetText(W.BestText(m.best, m.timed))
	self.Ilvl:SetText(IlvlText(m.ilvl))

	for i = 2, 5 do
		local line, mm = self.Members[i], a.members[i]
		line.member = mm
		line:SetShown(mm ~= nil)
		if mm then
			W.SetClassIcon(line.icon.tex, mm.class)
			line.icon.border:SetColor(W.ClassColor(mm.class))
			W.SetRoleIcon(line.role, mm.role)
			local n = W.ClassColored(mm.name and Ambiguate(mm.name, "short") or "?", mm.class)
			line.name:SetText(n .. "  |cff9d9d9d" .. (mm.spec or mm.className or "") .. "|r")
			line.rating:SetText(W.ScoreText(mm.score or 0))
			line.best:SetText(W.BestText(mm.best, mm.timed))
			line.ilvl:SetText(IlvlText(mm.ilvl))
			line.pa:SetShown(mm.name ~= nil)
		end
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

	local box = W.List(right, "KeyfinderApplicantRowTemplate", function(row, a) row:Init(a) end, ns.APPLICANT_EXTENT)
	box:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -5)
	box:SetPoint("BOTTOMRIGHT", -26, 5)
	ld.list = box

	-- Limpar: tira da lista quem cancelou, foi recusado ou expirou (só aqui no
	-- Keyfinder; candidaturas ativas nunca somem).
	ld.hidden = {}
	ld.clear = W.Button(right, L.LD_CLEAR, 76, function()
		for _, a in ipairs(ld.finished or {}) do ld.hidden[a.id] = true end
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		UI:RefreshLeader()
	end)
	ld.clear:SetHeight(20)
	ld.clear:SetPoint("RIGHT", header, "RIGHT", DECLINE_R, 0)
	ld.clear:Hide()

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

	-- Some com quem já saiu da disputa (cancelou, recusado, expirou...) se o
	-- jogador limpou; quem está na fila, convidado ou entrou sempre aparece.
	local ACTIVE = { applied = true, invited = true, inviteaccepted = true }
	local shown, finished = {}, {}
	for _, a in ipairs(data.applicants) do
		if ACTIVE[a.status] then
			shown[#shown + 1] = a
		elseif not ld.hidden[a.id] then
			shown[#shown + 1] = a
			finished[#finished + 1] = a
		end
	end
	ld.finished = finished
	ld.clear:SetShown(#finished > 0)
	data.applicants = shown

	W.SetData(ld.list, data.applicants)
	if not data.entry then
		ld.empty.text:SetText(L.LD_NO_ENTRY); ld.empty:Show()
	elseif #data.applicants == 0 then
		ld.empty.text:SetText(L.LD_EMPTY); ld.empty:Show()
	else
		ld.empty:Hide()
	end
end

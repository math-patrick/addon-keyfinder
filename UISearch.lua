local _, ns = ...
local L, KF, W = ns.L, ns.KF, ns.W
ns.UI = ns.UI or {}
local UI = ns.UI

local TOOLBAR_H = 30
local DETAIL_W = 280
local INNER = DETAIL_W - 24

-- Colunas da linha, medidas a partir da borda direita (sem sobreposição).
local COMP_W, LEADER_W, GAIN_W = 98, 56, 52
local COMP_RIGHT = -8
local LEADER_RIGHT = COMP_RIGHT - COMP_W - 10
local GAIN_RIGHT = LEADER_RIGHT - LEADER_W - 8
local TEXT_RIGHT = GAIN_RIGHT - GAIN_W - 8
local TEXT_LEFT = 84

-- Cor da key pela confiança: exata (dourado), alta (azul), média, baixa (cinza).
local KEY_COLORS = { exact = { 1, 0.82, 0 }, high = { 0.45, 0.78, 1 }, medium = { 0.65, 0.82, 0.95 }, low = { 0.6, 0.6, 0.6 } }
function UI.KeyColor(conf)
	local c = KEY_COLORS[conf] or KEY_COLORS.low
	return c[1], c[2], c[3]
end
function UI.KeyColorCode(conf)
	local r, g, b = UI.KeyColor(conf)
	return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

-- Ícones de utilidade (Bloodlust / battle res)
local UTIL_ICONS = {
	{ key = "hasBL", icon = "Interface\Icons\spell_nature_bloodlust", name = "BL", mine = "hasBL" },
	{ key = "hasBrez", icon = "Interface\Icons\spell_nature_reincarnation", name = "BREZ", mine = "hasBrez" },
}

local function Pct(v) return string.format("%d%%", math.floor((v or 0) * 100 + 0.5)) end

-- Preenche `tex` (w x h) com a arte da dungeon, recortando sem distorcer.
-- Prioridade: banner do Diário de Aventura > fundo da M+ > ícone.
local BANNER_ASPECT = 174 / 96
function UI:SetBannerArt(tex, map, w, h)
	if map and map.banner then
		local c = ns.BANNER_COORDS
		local l, r, t, b = c[1], c[2], c[3], c[4]
		local aspect = w / h
		if aspect > BANNER_ASPECT then
			local cut = (1 - BANNER_ASPECT / aspect) / 2 * (b - t)
			t, b = t + cut, b - cut
		else
			local cut = (1 - aspect / BANNER_ASPECT) / 2 * (r - l)
			l, r = l + cut, r - cut
		end
		tex:SetTexture(map.banner)
		tex:SetTexCoord(l, r, t, b)
	elseif map and map.bg and map.bg ~= 0 then
		tex:SetTexture(map.bg)
		tex:SetTexCoord(0, 1, 0.12, 0.88)
	else
		tex:SetTexture(map and map.texture or W.QUESTION)
		tex:SetTexCoord(0.08, 0.92, 0.3, 0.62)
	end
end

-- Cabeçalho centralizado com linhas dos dois lados (estilo Blizzard).
local function CenterHeader(parent, text, y)
	local fs = W.Text(parent, "GameFontNormalSmall", "CENTER", 11)
	fs:SetPoint("TOP", 0, y)
	fs:SetText(text)
	local side = math.max(8, (INNER - fs:GetStringWidth()) / 2 - 8)
	for _, dir in ipairs({ -1, 1 }) do
		local line = parent:CreateTexture(nil, "ARTWORK")
		line:SetColorTexture(1, 0.82, 0, 0.2)
		line:SetSize(side, 1)
		if dir < 0 then line:SetPoint("RIGHT", fs, "LEFT", -6, 0)
		else line:SetPoint("LEFT", fs, "RIGHT", 6, 0) end
	end
	return fs
end

----------------------------------------------------------------------
-- Linha de grupo (template KeyfinderGroupRowTemplate)
----------------------------------------------------------------------
KeyfinderGroupRowMixin = {}

function KeyfinderGroupRowMixin:OnLoad()
	self:RegisterForClicks("LeftButtonUp")
	self.Stripe = self:CreateTexture(nil, "BACKGROUND")
	self.Stripe:SetAllPoints()
	self.Stripe:SetColorTexture(0, 0, 0, 0.25)
	self.Tint = self:CreateTexture(nil, "BACKGROUND", nil, 1)
	self.Tint:SetPoint("TOPLEFT")
	self.Tint:SetPoint("BOTTOMLEFT")
	self.Tint:SetWidth(220)
	self.Selected = self:CreateTexture(nil, "BACKGROUND", nil, 2)
	self.Selected:SetAllPoints()
	self.Selected:SetColorTexture(1, 0.82, 0, 0.12)
	self.SelBorder = W.Border(self, 1, 0.82, 0, 0.6, "ARTWORK")
	self.Sep = self:CreateTexture(nil, "ARTWORK")
	self.Sep:SetPoint("BOTTOMLEFT")
	self.Sep:SetPoint("BOTTOMRIGHT")
	self.Sep:SetHeight(1)
	self.Sep:SetColorTexture(1, 1, 1, 0.06)
	self.FlashTex = self:CreateTexture(nil, "OVERLAY")
	self.FlashTex:SetAllPoints()
	self.FlashTex:SetColorTexture(1, 0.85, 0.35, 0.2)
	W.Flash(self.FlashTex)

	self.Badge = W.Badge(self, 34)
	self.Badge:SetPoint("LEFT", 6, 0)
	self.Icon = W.Icon(self, 30)
	self.Icon:SetPoint("LEFT", 46, 0)

	self.Title = W.Text(self, "GameFontHighlight", "LEFT", 13)
	self.Title:SetPoint("TOPLEFT", TEXT_LEFT, -7)
	self.Title:SetPoint("RIGHT", self, "RIGHT", TEXT_RIGHT, 0)
	self.Dungeon = W.Text(self, "GameFontNormalSmall")
	self.Dungeon:SetPoint("BOTTOMLEFT", TEXT_LEFT, 8)
	self.Dungeon:SetPoint("RIGHT", self, "RIGHT", TEXT_RIGHT, 0)

	local function col(width, right, size)
		local fs = W.Text(self, "GameFontHighlight", "CENTER", size or 13, "OUTLINE")
		fs:SetPoint("RIGHT", self, "RIGHT", right, 0)
		fs:SetWidth(width)
		return fs
	end
	self.Gain = col(GAIN_W, GAIN_RIGHT)
	self.Leader = col(LEADER_W, LEADER_RIGHT, 12)

	self.Slots = {}
	for i = 1, 5 do
		local t = self:CreateTexture(nil, "ARTWORK")
		t:SetSize(18, 18)
		t:SetPoint("RIGHT", self, "RIGHT", COMP_RIGHT - (5 - i) * 20, 0)
		local role = self:CreateTexture(nil, "OVERLAY")
		role:SetSize(10, 10)
		role:SetPoint("BOTTOMRIGHT", t, 3, -3)
		t.Role = role
		self.Slots[i] = t
	end
end

function KeyfinderGroupRowMixin:Init(r)
	self.data = r
	local cr, cg, cb = W.MatchColor(r.score)
	self.Badge:Set(r.score, cr, cg, cb)
	W.Gradient(self.Tint, "HORIZONTAL", cr, cg, cb, 0.14, cr, cg, cb, 0)
	self.Icon:SetIcon(r.map and r.map.texture)

	W.SetProtectedText(self.Title, r.info.name)
	local tag = r.appStatus and L.STATUS_TAG[r.appStatus]
	self.Dungeon:SetText(tag and (r.dungeonName .. "  |cff40ff70" .. tag .. "|r") or r.dungeonName)

	-- Ganho só com nível exato (nunca mostramos número baseado em palpite).
	-- Best do líder nesta dungeon (dado real do jogo).
	self.Gain:SetText(W.BestText(r.leaderBest, r.leaderTimed))
	self.Gain:SetTextColor(1, 1, 1)
	self.Leader:SetText(W.ScoreText(r.leaderScore))

	local slots = W.BuildSlots(r.members, r.open)
	local myRole = KF.player.role
	for i, tex in ipairs(self.Slots) do
		local s = slots[i]
		if not s then
			tex:Hide(); tex.Role:Hide()
		elseif s.open then
			tex:Show(); tex.Role:Hide()
			W.SetRoleIcon(tex, s.role)
			tex:SetDesaturated(s.role ~= myRole)
			tex:SetAlpha(s.role == myRole and 1 or 0.3)
		else
			tex:Show(); tex.Role:Show()
			tex:SetDesaturated(false); tex:SetAlpha(1)
			W.SetClassIcon(tex, s.class)
			W.SetRoleIcon(tex.Role, s.role)
		end
	end

	local selected = UI.selectedID == r.id
	self.Selected:SetShown(selected)
	self.SelBorder:SetShown(selected)
	self.Stripe:SetShown(not selected)

	if r.isNew and self.flashedID ~= r.id then
		self.flashedID = r.id
		self.FlashTex.flash:Play()
	end
end

function KeyfinderGroupRowMixin:OnClick()
	PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	UI:SelectResult(self.data.id)
end

function KeyfinderGroupRowMixin:OnDoubleClick()
	local r = self.data
	if r and KF:CanApply(r) then KF:Apply(r.id) end
end

function KeyfinderGroupRowMixin:OnEnter() end
function KeyfinderGroupRowMixin:OnLeave() end

----------------------------------------------------------------------
-- Aba Buscar
----------------------------------------------------------------------
function UI:BuildSearch(page)
	-- Faixa de dungeons fica na barra do topo, à direita.
	self.stripParent = self.topBar
	self:BuildDungeonStrip()
	table.insert(self.searchOnly, self.strip)

	local detail = W.Panel(page)
	detail:SetPoint("TOPRIGHT")
	detail:SetPoint("BOTTOMRIGHT")
	detail:SetWidth(DETAIL_W)

	-- Barra de ações embaixo da lista, como no Localizador da Blizzard:
	-- Filtros e Ordenar à esquerda, status no meio, Buscar à direita
	-- (na mesma linha do botão de entrar na fila do painel de detalhe).
	local tb = CreateFrame("Frame", nil, page)
	tb:SetPoint("BOTTOMLEFT")
	tb:SetPoint("BOTTOMRIGHT", detail, "BOTTOMLEFT", -5, 0)
	tb:SetHeight(TOOLBAR_H)

	local sb = W.Button(tb, "|TInterface\Common\UI-Searchbox-Icon:14:14:0:0|t " .. L.SEARCH, 116, function() KF:Search() end)
	sb:SetHeight(26)
	sb:SetPoint("RIGHT", 0, 0)
	sb.glow = sb:CreateTexture(nil, "BACKGROUND")
	sb.glow:SetPoint("TOPLEFT", -4, 4)
	sb.glow:SetPoint("BOTTOMRIGHT", 4, -4)
	sb.glow:SetColorTexture(1, 0.72, 0.15, 0.45)
	sb.glow:SetBlendMode("ADD")
	W.Pulse(sb.glow, 0.1, 0.8, 0.9)
	sb.glow:Hide()
	W.Tooltip(sb, L.SEARCH, function() return L.SEARCH_TIP:format(GetBindingKey("KEYFINDER_REFRESH") or L.W_BINDING_NONE) end)
	self.searchButton = sb

	local fb = W.Button(tb, L.FILTERS, 100, function(self)
		if MenuUtil and MenuUtil.CreateContextMenu then MenuUtil.CreateContextMenu(self, UI.FilterMenu) end
	end)
	fb:SetHeight(26)
	fb:SetPoint("LEFT", 0, 0)
	self.filterButton = fb

	self.sortDropdown = W.Dropdown(tb, 150, {
		{ text = L.SORT_MATCH, value = "match" }, { text = L.SORT_BEST, value = "best" },
		{ text = L.SORT_SCORE, value = "score" }, { text = L.SORT_AGE, value = "age" },
	}, function() return KF.db.sort end, function(v) KF.db.sort = v; KF:ApplyFilters() end)
	self.sortDropdown:SetPoint("LEFT", fb, "RIGHT", 6, 0)

	self.statusText = W.Text(tb, "GameFontHighlightSmall", "RIGHT")
	self.statusText:SetPoint("LEFT", self.sortDropdown, "RIGHT", 10, 0)
	self.statusText:SetPoint("RIGHT", sb, "LEFT", -10, 0)

	local list = W.Panel(page)
	list:SetPoint("TOPLEFT")
	list:SetPoint("BOTTOMRIGHT", tb, "TOPRIGHT", 0, 4)

	self:BuildList(list)
	self:BuildDetail(detail)
end

----------------------------------------------------------------------
-- Faixa de dungeons: um ícone por dungeon com o seu best embaixo.
-- Clique liga/desliga no filtro, botão direito deixa só aquela.
----------------------------------------------------------------------
local TILE, GAP = 40, 6

local function CreateTile(parent)
	local t = CreateFrame("Button", nil, parent)
	t:SetSize(TILE, TILE)
	t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	t.icon = t:CreateTexture(nil, "ARTWORK")
	t.icon:SetPoint("TOPLEFT", 1, -1)
	t.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	t.shade = t:CreateTexture(nil, "ARTWORK", nil, 1)
	t.shade:SetPoint("BOTTOMLEFT", t.icon)
	t.shade:SetPoint("BOTTOMRIGHT", t.icon)
	t.shade:SetHeight(18)
	W.Gradient(t.shade, "VERTICAL", 0, 0, 0, 0.95, 0, 0, 0, 0)
	t.best = W.Text(t, "GameFontHighlight", "CENTER", 11, "OUTLINE")
	t.best:SetPoint("BOTTOM", 0, 3)
	t.weak = t:CreateTexture(nil, "OVERLAY")
	t.weak:SetSize(8, 8)
	t.weak:SetPoint("TOPRIGHT", -3, -3)
	t.weak:SetTexture(W.WHITE)
	t.weak:SetVertexColor(1, 0.55, 0.1)
	local wm = t:CreateMaskTexture()
	wm:SetTexture(W.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	wm:SetAllPoints(t.weak)
	t.weak:AddMaskTexture(wm)
	-- Quantos grupos dessa dungeon passam nos filtros (última busca)
	t.countBg = t:CreateTexture(nil, "OVERLAY")
	t.countBg:SetPoint("TOPLEFT", 1, -1)
	t.countBg:SetSize(16, 13)
	t.countBg:SetColorTexture(0, 0, 0, 0.75)
	t.count = W.Text(t, "GameFontHighlightSmall", "CENTER", 10, "OUTLINE")
	t.count:SetPoint("CENTER", t.countBg, 0, 0)
	t.countBg:Hide(); t.count:Hide()
	t.border = W.Border(t, 0, 0, 0, 1)
	t.sel = W.Border(t, 1, 0.82, 0, 1, "OVERLAY", 2)
	local hl = t:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.15)
	return t
end

function UI:BuildDungeonStrip()
	local page = self.stripParent
	if not page then return end
	local f = KF.db.filters
	if not self.strip then
		local s = CreateFrame("Frame", nil, page)
		s:SetPoint("RIGHT", page, "RIGHT", -2, 0)
		s:SetHeight(TILE)
		s.tiles = {}
		-- "Todas": limpa o filtro de dungeon
		local all = CreateTile(s)
		all.icon:SetTexture("Interface\\Icons\\inv_misc_map02")
		all.best:SetText(L.F_ALL)
		all.weak:Hide()
		all:SetScript("OnClick", function()
			wipe(f.dungeons)
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			UI:SyncTiles(); KF:ApplyFilters()
		end)
		W.Tooltip(all, L.F_ALL_TIP)
		s.all = all
		self.strip = s
	end
	local s = self.strip
	local maps = KF.maps or {}
	for i, m in ipairs(maps) do
		local t = s.tiles[i]
		if not t then
			t = CreateTile(s)
			t:SetScript("OnClick", function(self, button)
				if button == "RightButton" then
					wipe(f.dungeons)
					f.dungeons[self.mapID] = true
				else
					f.dungeons[self.mapID] = (not f.dungeons[self.mapID]) or nil
				end
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				UI:SyncTiles()
				KF:ApplyFilters()
			end)
			t:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
				GameTooltip:SetText(self.mapName or "", 1, 0.82, 0)
				local mine = KF.player.maps[self.mapID]
				if mine and mine.level > 0 then
					GameTooltip:AddLine(L.TILE_BEST:format(W.BestText(mine.timedLevel > 0 and mine.timedLevel or mine.level, mine.timedLevel > 0), math.floor(mine.score)), 1, 1, 1)
				else
					GameTooltip:AddLine(L.TILE_NONE, 0.7, 0.7, 0.7)
				end
				if KF.player.weak[self.mapID] then GameTooltip:AddLine(L.TILE_WEAK, 1, 0.6, 0.2) end
				GameTooltip:AddLine(L.TILE_HINT, 0.5, 0.5, 0.5)
				GameTooltip:Show()
			end)
			t:SetScript("OnLeave", GameTooltip_Hide)
			s.tiles[i] = t
		end
		t.mapID, t.mapName = m.id, m.name
		t.icon:SetTexture(m.texture or W.QUESTION)
		t:ClearAllPoints()
		t:SetPoint("LEFT", i * (TILE + GAP), 0)
		t:Show()
	end
	for i = #maps + 1, #s.tiles do s.tiles[i]:Hide() end
	s.all:SetPoint("LEFT", 0, 0)
	s:SetWidth((#maps + 1) * TILE + #maps * GAP)
	self:SyncTiles()
end

function UI:SyncTiles()
	local s = self.strip
	if not s then return end
	local f = KF.db.filters
	local any = next(f.dungeons) ~= nil
	local p = KF.player or { maps = {}, weak = {} }
	s.all.sel:SetShown(not any)
	s.all.icon:SetDesaturated(any)
	for _, t in ipairs(s.tiles) do
		if t:IsShown() and t.mapID then
			local on = f.dungeons[t.mapID] and true or false
			t.sel:SetShown(on)
			t.icon:SetDesaturated(any and not on)
			t.icon:SetAlpha((any and not on) and 0.5 or 1)
			local mine = p.maps and p.maps[t.mapID]
			if mine and mine.timedLevel > 0 then
				t.best:SetText("|cff40ff70+" .. mine.timedLevel .. "|r")
			elseif mine and mine.level > 0 then
				t.best:SetText("|cffb0b0b0+" .. mine.level .. "|r")
			else
				t.best:SetText("|cff808080-|r")
			end
			t.weak:SetShown(p.weak and p.weak[t.mapID] or false)
			local n = KF.lastSearch and KF.mapCounts and KF.mapCounts[t.mapID] or nil
			if n then
				t.count:SetText(n > 99 and "99" or n)
				t.countBg:SetWidth(math.max(14, t.count:GetStringWidth() + 6))
				t.count:Show(); t.countBg:Show()
			else
				t.count:Hide(); t.countBg:Hide()
			end
		end
	end
	local total = 0
	for _, n in pairs(KF.mapCounts or {}) do total = total + n end
	if KF.lastSearch then
		s.all.count:SetText(total > 99 and "99" or total)
		s.all.countBg:SetWidth(math.max(14, s.all.count:GetStringWidth() + 6))
		s.all.count:Show(); s.all.countBg:Show()
	end
end

----------------------------------------------------------------------
-- Lista
----------------------------------------------------------------------
function UI:BuildList(p)
	local header = CreateFrame("Frame", nil, p)
	header:SetPoint("TOPLEFT", 4, -6)
	header:SetPoint("TOPRIGHT", -26, -6)
	header:SetHeight(16)
	local function col(text, x, width, justify, fromRight)
		local fs = W.Text(header, "GameFontNormalSmall", justify or "CENTER", 10)
		if fromRight then fs:SetPoint("RIGHT", header, "RIGHT", x, 0) else fs:SetPoint("LEFT", header, "LEFT", x, 0) end
		fs:SetWidth(width)
		fs:SetText(text)
		return fs
	end
	col(L.COL_MATCH, 4, 38)
	col(L.COL_GROUP, TEXT_LEFT, 120, "LEFT")
	col(L.COL_BEST, GAIN_RIGHT, GAIN_W, nil, true)
	col(L.COL_LEADER, LEADER_RIGHT, LEADER_W, nil, true)
	col(L.COL_COMP, COMP_RIGHT, COMP_W, nil, true)
	local line = header:CreateTexture(nil, "ARTWORK")
	line:SetPoint("BOTTOMLEFT", 0, -3)
	line:SetPoint("BOTTOMRIGHT", 22, -3)
	line:SetHeight(1)
	line:SetColorTexture(1, 0.82, 0, 0.2)
	W.Tooltip(header, L.COL_BEST, L.COL_BEST_TIP)

	local box = W.List(p, "KeyfinderGroupRowTemplate", function(row, data) row:Init(data) end)
	box:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -5)
	box:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -26, 5)
	self.groupList = box

	local empty = CreateFrame("Frame", nil, p)
	empty:SetSize(360, 120)
	empty:SetPoint("CENTER", box, 0, 10)
	empty.icon = empty:CreateTexture(nil, "ARTWORK")
	empty.icon:SetSize(48, 48)
	empty.icon:SetPoint("TOP")
	empty.icon:SetTexture("Interface\\Icons\\inv_relics_hourglass")
	empty.icon:SetDesaturated(true)
	empty.icon:SetAlpha(0.5)
	empty.text = W.Text(empty, "GameFontDisable", "CENTER", 12)
	empty.text:SetPoint("TOP", empty.icon, "BOTTOM", 0, -10)
	empty.text:SetWidth(360)
	empty.text:SetWordWrap(true)
	empty.search = W.Button(empty, "|TInterface\\Common\\UI-Searchbox-Icon:14:14:0:0|t " .. L.SEARCH, 150, function() KF:Search() end)
	empty.search:SetHeight(28)
	empty.search:SetPoint("TOP", empty.text, "BOTTOM", 0, -14)
	empty:Hide()
	self.emptyState = empty
end

----------------------------------------------------------------------
-- Painel de detalhe
----------------------------------------------------------------------
function UI:BuildDetail(p)
	local d = {}
	self.detail = d

	d.empty = CreateFrame("Frame", nil, p)
	d.empty:SetAllPoints()
	local eIcon = d.empty:CreateTexture(nil, "ARTWORK")
	eIcon:SetSize(44, 44)
	eIcon:SetPoint("CENTER", 0, 30)
	eIcon:SetTexture("Interface\\Icons\\inv_misc_spyglass_03")
	eIcon:SetAlpha(0.45)
	eIcon:SetDesaturated(true)
	local eText = W.Text(d.empty, "GameFontDisable", "CENTER", 12)
	eText:SetPoint("TOP", eIcon, "BOTTOM", 0, -10)
	eText:SetWidth(INNER - 20)
	eText:SetWordWrap(true)
	eText:SetText(L.SELECT_GROUP)

	local body = CreateFrame("Frame", nil, p)
	body:SetAllPoints()
	d.body = body

	-- Banner da dungeon (arte do Diário de Aventura), com nome, título
	-- do grupo, key e o seu best sobrepostos.
	local BANNER_H = 150
	d.art = body:CreateTexture(nil, "ARTWORK")
	d.art:SetPoint("TOPLEFT", 3, -3)
	d.art:SetPoint("TOPRIGHT", -3, -3)
	d.art:SetHeight(BANNER_H)
	d.artShade = body:CreateTexture(nil, "ARTWORK", nil, 1)
	d.artShade:SetAllPoints(d.art)
	W.Gradient(d.artShade, "VERTICAL", 0, 0, 0, 0.95, 0, 0, 0, 0)
	d.artSide = body:CreateTexture(nil, "ARTWORK", nil, 2)
	d.artSide:SetPoint("TOPLEFT", d.art)
	d.artSide:SetPoint("BOTTOMLEFT", d.art)
	d.artSide:SetWidth(DETAIL_W * 0.7)
	W.Gradient(d.artSide, "HORIZONTAL", 0, 0, 0, 0.55, 0, 0, 0, 0)
	d.artLine = body:CreateTexture(nil, "ARTWORK", nil, 3)
	d.artLine:SetPoint("TOPLEFT", d.art, "BOTTOMLEFT")
	d.artLine:SetPoint("TOPRIGHT", d.art, "BOTTOMRIGHT")
	d.artLine:SetHeight(2)
	W.Gradient(d.artLine, "HORIZONTAL", 1, 0.82, 0, 0.8, 1, 0.82, 0, 0.05)
	d.badge = W.Badge(body, 48)
	d.badge:SetPoint("BOTTOMRIGHT", d.art, "BOTTOMRIGHT", -10, 10)
	local textW = INNER - 62
	d.keyLine = W.Text(body, "GameFontHighlightSmall", "LEFT", 11)
	d.keyLine:SetPoint("BOTTOMLEFT", d.art, "BOTTOMLEFT", 10, 9)
	W.Clamp(d.keyLine, textW)
	d.title = W.Text(body, "GameFontHighlight", "LEFT", 12)
	d.title:SetPoint("BOTTOMLEFT", d.keyLine, "TOPLEFT", 0, 4)
	W.Clamp(d.title, textW)
	d.dungeon = W.Text(body, "GameFontNormalLarge", "LEFT", 17, "OUTLINE")
	d.dungeon:SetPoint("BOTTOMLEFT", d.title, "TOPLEFT", 0, 4)
	W.Clamp(d.dungeon, textW)
	local artHover = CreateFrame("Frame", nil, body)
	artHover:SetAllPoints(d.art)
	W.Tooltip(artHover, L.EST_TIP_TITLE, L.EST_TIP)

	-- As três estimativas lado a lado
	d.stats = {}
	local boxW = math.floor(INNER / 3)
	for i, label in ipairs({ L.STAT_ACCEPT, L.STAT_MINE, L.STAT_TIME }) do
		local s = CreateFrame("Frame", nil, body)
		s:SetSize(boxW, 44)
		s:SetPoint("TOPLEFT", 12 + (i - 1) * boxW, -BANNER_H - 13)
		s.value = W.Text(s, "GameFontHighlight", "CENTER", 17, "OUTLINE")
		s.value:SetPoint("TOP", 0, 0)
		s.label = W.Text(s, "GameFontDisableSmall", "CENTER", 10)
		s.label:SetPoint("TOP", s.value, "BOTTOM", 0, -3)
		W.Clamp(s.label, boxW - 4)
		s.label:SetText(label)
		s.bar = W.Bar(s, 4)
		s.bar:SetPoint("TOPLEFT", 8, -36)
		s.bar:SetPoint("TOPRIGHT", -8, -36)
		W.Tooltip(s, label, L.STAT_TIPS[i])
		d.stats[i] = s
	end

	-- Grupo
	CenterHeader(body, L.COMPOSITION, -222)
	d.members = {}
	local iconsW = 5 * 30 + 4 * 8
	for i = 1, 5 do
		local slot = W.Icon(body, 30)
		slot:SetPoint("TOPLEFT", (DETAIL_W - iconsW) / 2 + (i - 1) * 38, -240)
		slot.role = slot:CreateTexture(nil, "OVERLAY")
		slot.role:SetSize(14, 14)
		slot.role:SetPoint("BOTTOMRIGHT", 4, -4)
		slot:EnableMouse(true)
		slot:SetScript("OnEnter", function(self)
			if not self.info then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(self.info, 1, 1, 1)
			GameTooltip:Show()
		end)
		slot:SetScript("OnLeave", GameTooltip_Hide)
		d.members[i] = slot
	end
	d.util = {}
	for i, u in ipairs(UTIL_ICONS) do
		local ic = W.Icon(body, 22)
		ic:SetPoint("TOP", (i - 1.5) * 30, -276)
		ic:SetIcon(u.icon)
		ic.def = u
		ic:EnableMouse(true)
		ic:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(L[self.def.name], 1, 1, 1)
			GameTooltip:AddLine(self.tip or "", nil, nil, nil, true)
			GameTooltip:Show()
		end)
		ic:SetScript("OnLeave", GameTooltip_Hide)
		d.util[i] = ic
	end

	-- Líder
	CenterHeader(body, L.LEADER, -308)
	d.leaderPA = UI:CreateParseAcademyButton(body, function() local r = KF:FindResult(UI.selectedID); return r and r.leaderName end)
	d.leaderPA:SetPoint("TOPRIGHT", -12, -304)
	d.leader = W.Text(body, "GameFontHighlight", "CENTER", 12)
	d.leader:SetPoint("TOP", 0, -324)
	W.Clamp(d.leader, INNER)
	d.extra = W.Text(body, "GameFontDisableSmall", "CENTER")
	d.extra:SetPoint("TOP", 0, -340)
	W.Clamp(d.extra, INNER)

	-- Motivos
	CenterHeader(body, L.WHY, -364)
	d.reasons = {}
	for i = 1, 4 do
		local fs = W.Text(body, "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", 14, -380 - (i - 1) * 14)
		W.Clamp(fs, INNER - 4)
		d.reasons[i] = fs
	end

	-- Ações
	d.watch = W.Button(body, L.WATCH_THIS, 84, function()
		local r = KF:FindResult(UI.selectedID)
		if r and r.map and not KF:HasRuleForMap(r.map.id) then
			KF:AddRule({ mapID = r.map.id, minScore = math.max(0, math.floor((KF.player.score - 300) / 100) * 100), minBest = r.leaderTimed and r.leaderBest or 0, myRole = true })
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		end
	end)
	d.watch:SetHeight(28)
	d.watch:SetPoint("BOTTOMRIGHT", -12, 10)
	W.Tooltip(d.watch, L.WATCH_THIS, L.WATCH_TIP)
	d.apply = W.Button(body, L.APPLY, INNER - 84 - 6, function() UI:ApplySelected() end)
	d.apply:SetHeight(28)
	d.apply:SetPoint("BOTTOMLEFT", 12, 10)
end

function UI:SelectResult(id)
	self.selectedID = id
	self:RefreshSearch()
end

function UI:RefreshDetail()
	local d = self.detail
	if not d then return end
	local r = self.selectedID and KF:FindResult(self.selectedID)
	d.body:SetShown(r ~= nil)
	d.empty:SetShown(r == nil)
	if not r then return end
	local p = KF.player

	UI:SetBannerArt(d.art, r.map, DETAIL_W - 6, 150)
	d.badge:Set(r.score, W.MatchColor(r.score))
	d.dungeon:SetText(r.dungeonName)
	W.SetProtectedText(d.title, r.info.name)

	local acc, mineStat, tim = d.stats[1], d.stats[2], d.stats[3]
	local ar, ag, ab = W.PctColor(r.accept)
	acc.value:SetText(Pct(r.accept)); acc.value:SetTextColor(ar, ag, ab); acc.bar:SetValue(r.accept, ar, ag, ab)
	-- Seu best timado nesta dungeon (barra = pontos aqui x sua melhor dungeon).
	local mine = r.mine
	local top = 1
	for _, m in pairs(p.maps) do if m.score > top then top = m.score end end
	if mine and mine.timedLevel > 0 then
		mineStat.value:SetText("+" .. mine.timedLevel); mineStat.value:SetTextColor(0.25, 1, 0.45)
	elseif mine and mine.level > 0 then
		mineStat.value:SetText("+" .. mine.level .. "*"); mineStat.value:SetTextColor(0.7, 0.7, 0.7)
	else
		mineStat.value:SetText("-"); mineStat.value:SetTextColor(1, 0.5, 0.25)
	end
	local sr, sg, sb = W.MapScoreColor(mine and mine.score or 0)
	mineStat.bar:SetValue((mine and mine.score or 0) / top, sr, sg, sb)
	local tr, tg, tb = W.PctColor(r.timeChance)
	tim.value:SetText(Pct(r.timeChance)); tim.value:SetTextColor(tr, tg, tb); tim.bar:SetValue(r.timeChance, tr, tg, tb)

	-- Só mostra o nível quando ele é exato (veio da sua busca).
	d.keyLine:SetText(r.exact and L.KEY_EXACT_LINE:format(r.est) or "")

	-- Composição
	local slots = W.BuildSlots(r.members, r.open)
	for i, slot in ipairs(d.members) do
		local s = slots[i]
		if not s then
			slot:Hide()
		elseif s.open then
			slot:Show()
			W.SetRoleIcon(slot.tex, s.role)
			local mineRole = s.role == p.role
			slot.tex:SetDesaturated(not mineRole)
			slot.tex:SetAlpha(mineRole and 1 or 0.35)
			if mineRole then slot.border:SetColor(1, 0.82, 0, 1) else slot.border:SetColor(0.3, 0.3, 0.3, 1) end
			slot.role:Hide()
			slot.info = L.OPEN_SLOT:format(L.ROLE[s.role])
		else
			slot:Show()
			W.SetClassIcon(slot.tex, s.class)
			slot.tex:SetDesaturated(false)
			slot.tex:SetAlpha(1)
			slot.border:SetColor(W.ClassColor(s.class))
			slot.role:Show()
			W.SetRoleIcon(slot.role, s.role)
			slot.info = W.ClassColored((s.spec and (s.spec .. " ") or "") .. (s.className or "?"), s.class) .. "  |cff808080" .. (L.ROLE[s.role] or "") .. "|r"
		end
	end
	for _, ic in ipairs(d.util) do
		local has = r[ic.def.key]
		local iBring = p[ic.def.mine]
		ic.tex:SetDesaturated(not has)
		ic.tex:SetAlpha(has and 1 or 0.45)
		if has then ic.border:SetColor(0.25, 1, 0.45, 1); ic.tip = L.UTIL_HAS
		elseif iBring then ic.border:SetColor(1, 0.82, 0, 1); ic.tip = L.UTIL_YOU_BRING
		else ic.border:SetColor(1, 0.3, 0.3, 1); ic.tip = L.UTIL_MISSING end
	end

	-- Líder (uma linha) + extras só quando existem
	local leaderName = r.leaderName and Ambiguate(r.leaderName, "short") or "?"
	d.leader:SetText(W.ClassColored(leaderName, r.leaderClass) .. "   " .. W.ScoreText(r.leaderScore) .. "   " .. L.BEST_HERE:format(W.BestText(r.leaderBest, r.leaderTimed)))
	local mins = math.floor(r.age / 60)
	local extras = { mins < 1 and L.AGE_NOW or L.AGE:format(mins) }
	if r.reqScore > 0 then extras[#extras + 1] = L.REQ_SCORE:format(r.reqScore) end
	if r.reqIlvl > 0 then extras[#extras + 1] = L.REQ_ILVL:format(r.reqIlvl) end
	if (r.playstyle or 0) > 0 and L.PS[r.playstyle] then extras[#extras + 1] = L.PS[r.playstyle] end
	if r.autoAccept then extras[#extras + 1] = L.AUTO_SHORT end
	d.extra:SetText(table.concat(extras, "  ·  "))

	for i, fs in ipairs(d.reasons) do
		local reason = r.reasons[i]
		if reason then
			local c = reason.good and W.GOOD or W.BAD
			fs:SetText(c:WrapTextInColorCode((reason.good and "+ " or "- ") .. reason.text))
		else
			fs:SetText("")
		end
	end

	if r.appStatus == "applied" then
		d.apply:SetText(L.CANCEL_APP); d.apply:Enable()
	else
		local ok, why = KF:CanApply(r)
		d.apply:SetText(ok and L.APPLY_AS:format(L.ROLE[p.role]) or why or L.APPLY)
		d.apply:SetEnabled(ok)
	end
	local watched = r.map and KF:HasRuleForMap(r.map.id)
	d.watch:SetText(watched and L.WATCHING or L.WATCH_THIS)
	d.watch:SetEnabled(r.map ~= nil and not watched)
end

local function IndexOf(list, id)
	for i, r in ipairs(list or {}) do if r.id == id then return i end end
end

-- Move a seleção (setas do teclado) e mantém a linha visível.
function UI:MoveSelection(delta)
	local list = KF.filtered or {}
	if #list == 0 then return end
	local i = IndexOf(list, self.selectedID) or 0
	i = math.max(1, math.min(#list, i + delta))
	self.selectedID = list[i].id
	self:RefreshSearch()
	if self.groupList.ScrollToElementDataIndex then
		pcall(self.groupList.ScrollToElementDataIndex, self.groupList, i)
	end
end

function UI:ApplySelected()
	local r = self.selectedID and KF:FindResult(self.selectedID)
	if not r then return end
	if r.appStatus == "applied" then KF:CancelApplication(r.id)
	elseif KF:CanApply(r) then KF:Apply(r.id) end
end

function UI:RefreshSearch()
	if not self.groupList then return end
	-- O detalhe nunca fica vazio: sem seleção válida, mostra o melhor grupo.
	if not IndexOf(KF.filtered, self.selectedID) and KF.filtered and KF.filtered[1] then
		self.selectedID = KF.filtered[1].id
	end
	W.SetData(self.groupList, KF.filtered)
	local e = self.emptyState
	if not KF.lastSearch then
		e.text:SetText(L.EMPTY_NOSEARCH); e:Show()
	elseif #(KF.filtered or {}) == 0 then
		e.text:SetText(L.EMPTY_LIST); e:Show()
	else
		e:Hide()
	end
	self:SyncTiles()
	self:RefreshDetail()
end

function UI:SyncFilterControls()
	self:SyncTiles()
end

local _, ns = ...
local L, KF, W = ns.L, ns.KF, ns.W
ns.UI = ns.UI or {}
local UI = ns.UI

local FRAME_W, FRAME_H = 980, 620
local PAGE_TOP, PAGE_BOTTOM = -76, 30
ns.PAGE_W = FRAME_W - 14
ns.PAGE_H = FRAME_H + PAGE_TOP - PAGE_BOTTOM

local TAB_SEARCH, TAB_PROGRESS, TAB_WATCH, TAB_LEADER = 1, 2, 3, 4
ns.TAB_SEARCH, ns.TAB_PROGRESS, ns.TAB_WATCH = TAB_SEARCH, TAB_PROGRESS, TAB_WATCH
local HOURGLASS = "Interface\\Icons\\inv_relics_hourglass"

----------------------------------------------------------------------
-- Menu de filtros (o mesmo sistema de menus da Blizzard)
----------------------------------------------------------------------
local function ResetFilters()
	local f = KF.db.filters
	f.minLeaderScore, f.minLeaderBest, f.maxAge, f.playstyle, f.keyMode = 0, 0, 0, 0, "any"
	f.onlyGain, f.needBL, f.needBrez, f.autoOnly = false, false, false, false
	f.myRole, f.meetReq, f.hideDeclined = true, true, true
	KF:ApplyFilters()
end

local KEY_OPTIONS = {
	{ "any", "KEY_ANY" }, { "near", "KEY_NEAR" }, { "r2_6", "+2 - +6" }, { "r7_10", "+7 - +10" },
	{ "r11_13", "+11 - +13" }, { "r14_16", "+14 - +16" }, { "r17", "KEY_17" },
}

local function OptionLabel(list, value)
	for _, o in ipairs(list) do if o[1] == value then return L[o[2]] or o[2] end end
	return ""
end

local function FilterMenu(_, root)
	local f = KF.db.filters
	local function changed() KF:ApplyFilters() end
	local function radioSub(label, list, key, fmt)
		local sub = root:CreateButton(label)
		for _, o in ipairs(list) do
			local text = fmt and fmt(o) or (L[o[2]] or o[2])
			sub:CreateRadio(text, function() return f[key] == o[1] end, function() f[key] = o[1]; changed() end)
		end
	end

	root:CreateTitle(L.F_FOCUS)
	for _, o in ipairs({ { "rating", L.FOCUS_RATING }, { "balanced", L.FOCUS_BALANCED }, { "safe", L.FOCUS_SAFE } }) do
		root:CreateRadio(o[2], function() return KF.db.focus == o[1] end, function() KF.db.focus = o[1]; KF:Rescore() end)
	end

	root:CreateDivider()
	root:CreateTitle(L.F_GROUP)
	local scores = {}
	for _, v in ipairs({ 0, 1500, 2000, 2500, 3000, 3500 }) do scores[#scores + 1] = { v, v == 0 and L.ANY or (v .. "+") } end
	radioSub(L.F_LEADER_SCORE .. ": |cffffffff" .. (f.minLeaderScore > 0 and (f.minLeaderScore .. "+") or L.ANY) .. "|r", scores, "minLeaderScore")
	local bests = {}
	for _, v in ipairs({ 0, 6, 8, 10, 12, 14, 16, 18, 20 }) do bests[#bests + 1] = { v, v == 0 and L.ANY or ("+" .. v) } end
	radioSub(L.F_LEADER_BEST .. ": |cffffffff" .. (f.minLeaderBest > 0 and ("+" .. f.minLeaderBest) or L.ANY) .. "|r", bests, "minLeaderBest")
	local ages = { { 0, L.ANY }, { 5, L.MINUTES_MAX:format(5) }, { 15, L.MINUTES_MAX:format(15) }, { 30, L.MINUTES_MAX:format(30) } }
	radioSub(L.F_AGE .. ": |cffffffff" .. OptionLabel(ages, f.maxAge) .. "|r", ages, "maxAge")
	local ps = {}
	for i = 0, 4 do ps[#ps + 1] = { i, L.PS[i] } end
	radioSub(L.F_PLAYSTYLE .. ": |cffffffff" .. (L.PS[f.playstyle] or L.ANY) .. "|r", ps, "playstyle")

	root:CreateDivider()
	root:CreateTitle(L.F_SMART)
	for _, def in ipairs({
		{ "myRole", L.F_MY_ROLE }, { "meetReq", L.F_MEET_REQ },
		{ "needBL", L.F_NEED_BL }, { "needBrez", L.F_NEED_BREZ }, { "autoOnly", L.F_AUTO }, { "hideDeclined", L.F_HIDE_DECLINED },
	}) do
		local key = def[1]
		root:CreateCheckbox(def[2], function() return f[key] end, function() f[key] = not f[key]; changed() end)
	end

	root:CreateDivider()
	root:CreateDivider()
	root:CreateTitle(L.F_UPGRADES)
	local u = KF.db.upgrade
	root:CreateCheckbox(L.O_UPGRADE, function() return u.enabled end, function() u.enabled = not u.enabled; changed() end)
	local rangeSub = root:CreateButton(L.O_RANGE .. ": |cffffffff" .. UI.RangeLabel(u.range) .. "|r")
	for v = 0, 3 do
		rangeSub:CreateRadio(UI.RangeLabel(v), function() return u.range == v end, function() u.range = v; changed() end)
	end
	root:CreateButton(L.O_OPEN, function() UI:OpenOptions() end)

	root:CreateDivider()
	root:CreateButton(L.F_RESET, ResetFilters)
end

----------------------------------------------------------------------
-- Janela principal (ButtonFrameTemplate + abas PanelTabButtonTemplate)
----------------------------------------------------------------------
function UI:Create()
	if self.frame then return end
	local f = CreateFrame("Frame", "KeyfinderFrame", UIParent, "ButtonFrameTemplate")
	self.frame = f
	f:Hide()
	f:SetSize(FRAME_W, FRAME_H)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(frame)
		frame:StopMovingOrSizing()
		local point, _, relPoint, x, y = frame:GetPoint()
		KF.db.pos = { point, relPoint, x, y }
	end)
	self:ResetPosition()

	if f.SetTitle then f:SetTitle(L.TITLE) elseif f.TitleText then f.TitleText:SetText(L.TITLE) end
	self:SetPortrait(HOURGLASS)
	if f.Inset then f.Inset:Hide() end
	tinsert(UISpecialFrames, "KeyfinderFrame")

	self:BuildTopBar(f)

	self.pages = {}
	for i = 1, 4 do
		local page = CreateFrame("Frame", nil, f)
		page:SetPoint("TOPLEFT", 8, PAGE_TOP)
		page:SetPoint("BOTTOMRIGHT", -6, PAGE_BOTTOM)
		page:Hide()
		self.pages[i] = page
	end
	self:BuildSearch(self.pages[TAB_SEARCH])
	self:BuildProgress(self.pages[TAB_PROGRESS])
	self:BuildWatch(self.pages[TAB_WATCH])
	self:BuildLeader(self.pages[TAB_LEADER])

	self:BuildFooter(f)

	f.Tabs = {}
	for i, name in ipairs({ L.TAB_SEARCH, L.TAB_PROGRESS, L.TAB_WATCH, L.TAB_LEADER }) do
		local tab = CreateFrame("Button", "KeyfinderFrameTab" .. i, f, "PanelTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(name)
		if i == 1 then tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, 2)
		else tab:SetPoint("TOPLEFT", f.Tabs[i - 1], "TOPRIGHT", 3, 0) end
		tab:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			UI:SelectTab(i)
		end)
		f.Tabs[i] = tab
	end
	PanelTemplates_SetNumTabs(f, 4)

	f:SetScript("OnShow", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
		KF:RefreshPlayer()
		UI:StartTicker()
		UI:RefreshAll()
	end)
	f:SetScript("OnHide", function()
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
		UI:StopTicker()
	end)
	self:SelectTab(TAB_SEARCH)
end

function UI:SetPortrait(tex)
	local f = self.frame
	if not f or self.portraitTex == tex then return end
	self.portraitTex = tex
	if f.SetPortraitToAsset then f:SetPortraitToAsset(tex) end
end

----------------------------------------------------------------------
-- Barra do topo: quem você é (rating + key) à esquerda e a faixa de
-- dungeons à direita. As ações ficam numa barra logo acima da lista.
----------------------------------------------------------------------
UI.FilterMenu = FilterMenu

function UI:BuildTopBar(f)
	local bar = CreateFrame("Frame", nil, f)
	bar:SetPoint("TOPLEFT", 62, -26)
	bar:SetPoint("TOPRIGHT", -10, -26)
	bar:SetHeight(44)
	self.topBar = bar
	self.searchOnly = {}

	bar.rating = W.Text(bar, "GameFontNormal", "LEFT", 15)
	bar.rating:SetPoint("TOPLEFT", 4, -4)
	W.Clamp(bar.rating, 200)
	bar.key = W.Text(bar, "GameFontHighlightSmall")
	bar.key:SetPoint("TOPLEFT", bar.rating, "BOTTOMLEFT", 0, -4)
	W.Clamp(bar.key, 200)
end

----------------------------------------------------------------------
-- Rodapé: suas candidaturas (até 5 ícones)
----------------------------------------------------------------------
function UI:BuildFooter(f)
	local lbl = W.Text(f, "GameFontNormalSmall")
	lbl:SetPoint("BOTTOMLEFT", 14, 10)
	lbl:SetText(L.APPS_LABEL)
	self.appSlots = {}
	for i = 1, 5 do
		local s = W.Icon(f, 18)
		if i == 1 then s:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
		else s:SetPoint("LEFT", self.appSlots[i - 1], "RIGHT", 4, 0) end
		s:EnableMouse(true)
		s:SetScript("OnMouseUp", function(self)
			if self.result then UI:SelectTab(TAB_SEARCH); UI:SelectResult(self.result.id) end
		end)
		s:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			if self.result then
				local r = self.result
				GameTooltip:SetText(r.dungeonName, 1, 0.82, 0)
				GameTooltip:AddLine(L.STATUS_TAG[r.appStatus] or "", 0.25, 1, 0.45)
				GameTooltip:AddLine(L.APP_SLOT_HINT, 0.6, 0.6, 0.6)
			else
				GameTooltip:SetText(L.APP_SLOT_EMPTY, 0.7, 0.7, 0.7)
			end
			GameTooltip:Show()
		end)
		s:SetScript("OnLeave", GameTooltip_Hide)
		self.appSlots[i] = s
	end
	self.footHint = W.Text(f, "GameFontDisableSmall", "RIGHT")
	self.footHint:SetPoint("BOTTOMRIGHT", -14, 10)
	W.Clamp(self.footHint, 560)
end

function UI:ResetPosition()
	local f = self.frame
	if not f then return end
	f:ClearAllPoints()
	local pos = KF.db.pos
	if pos then f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) else f:SetPoint("CENTER", UIParent, "CENTER", 0, 40) end
end

function UI:SelectTab(i)
	if not self.frame then return end
	self.tab = i
	PanelTemplates_SetTab(self.frame, i)
	for idx, page in ipairs(self.pages) do page:SetShown(idx == i) end
	for _, w in ipairs(self.searchOnly) do w:SetShown(i == TAB_SEARCH) end
	self.footHint:SetText(L.FOOT_HINT[i] or "")
	self:RefreshAll()
end

function UI:Toggle()
	self:Create()
	self.frame:SetShown(not self.frame:IsShown())
end

function UI:Open(tab)
	self:Create()
	self.frame:Show()
	self.frame:Raise()
	if tab then self:SelectTab(tab) end
end

----------------------------------------------------------------------
-- Atualização
----------------------------------------------------------------------
local function Ago(t)
	local s = math.floor(GetTime() - t)
	if s < 60 then return s .. "s" end
	return math.floor(s / 60) .. "min"
end

function UI:RefreshHeader()
	if not self.frame then return end
	local bar = self.topBar
	local p = KF.player
	if p then
		self:SetPortrait(p.specIcon or HOURGLASS)
		bar.rating:SetText(L.H_RATING .. "  " .. W.ScoreText(math.floor(p.score or 0)))
		if p.keyMapID then
			local m = KF.mapByID and KF.mapByID[p.keyMapID]
			local name = (m and m.name) or C_ChallengeMode.GetMapUIInfo(p.keyMapID) or "?"
			bar.key:SetText(L.H_KEY:format(p.keyLevel, name))
		else
			bar.key:SetText("|cff808080" .. L.LD_NO_KEY .. "|r")
		end
	end

	if KF.searchFailed then
		self.statusText:SetText("|cffff5050" .. L.STATUS_FAILED .. "|r")
	elseif KF.lastSearch then
		self.statusText:SetText(self:StatusLine())
	else
		self.statusText:SetText(L.STATUS_NONE)
	end

	local n = KF:ActiveFilterCount()
	self.filterButton:SetText(n > 0 and L.FILTERS_N:format(n) or L.FILTERS)

	local sb = self.searchButton
	local stale = not KF.lastSearch or (GetTime() - KF.lastSearch) > 60
	sb.glow:SetShown(stale)
	if stale then
		if not sb.glow.pulse:IsPlaying() then sb.glow.pulse:Play() end
	else
		sb.glow.pulse:Stop()
	end

	local applied = KF:GetApplied()
	local max = KF:MaxApplications()
	for i, s in ipairs(self.appSlots) do
		local r = applied[i]
		s.result = r
		s:SetShown(i <= max)
		if r then
			s:SetIcon(r.map and r.map.texture)
			if r.appStatus == "invited" then s.border:SetColor(0.25, 1, 0.45, 1) else s.border:SetColor(1, 0.82, 0, 1) end
		else
			s.tex:SetTexture(nil)
			s.tex:SetColorTexture(0, 0, 0, 0.45)
			s.border:SetColor(0.35, 0.35, 0.35, 1)
		end
	end
end

function UI:RefreshAll()
	if not (self.frame and self.frame:IsShown()) then return end
	self:RefreshHeader()
	if self.tab == TAB_SEARCH then self:RefreshSearch()
	elseif self.tab == TAB_PROGRESS then self:RefreshProgress()
	elseif self.tab == TAB_WATCH then self:RefreshWatch()
	elseif self.tab == TAB_LEADER then self:RefreshLeader() end
end

function UI:OnDataChanged()
	self:UpdateGroupFinderButton()
	self:RefreshAll()
end
function UI:OnLeaderChanged() if self.tab == TAB_LEADER then self:RefreshAll() end end

function UI:OnMapsLoaded()
	if self.frame then
		self:BuildDungeonStrip()
		self:RefreshAll()
	end
end

function UI:StartTicker()
	self:StopTicker()
	self.ticker = C_Timer.NewTicker(1, function() UI:RefreshHeader() end)
end

function UI:StopTicker()
	if self.ticker then self.ticker:Cancel(); self.ticker = nil end
end

----------------------------------------------------------------------
-- Integração com o Localizador de Grupos da Blizzard (PVEFrame)
-- Uma aba lateral (com contador de bons matches) e um botão na barra de
-- título. Só adicionamos frames filhos; nada da Blizzard é alterado.
----------------------------------------------------------------------
function UI:AttachToGroupFinder()
	if self.pveButton or not PVEFrame then return end

	local b = CreateFrame("Button", "KeyfinderGroupFinderButton", PVEFrame)
	b:SetSize(42, 42)
	b:SetPoint("TOPLEFT", PVEFrame, "TOPRIGHT", 2, -60)
	b:SetFrameLevel(PVEFrame:GetFrameLevel() + 20)
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", -3, 3)
	bg:SetPoint("BOTTOMRIGHT", 3, -3)
	bg:SetColorTexture(0, 0, 0, 0.85)
	b.border = W.Border(b, 0.85, 0.68, 0.2, 1, "BACKGROUND")
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexture(HOURGLASS)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints(b.icon)
	hl:SetColorTexture(1, 1, 1, 0.2)
	b.glow = b:CreateTexture(nil, "OVERLAY")
	b.glow:SetTexture(W.GLOW)
	b.glow:SetBlendMode("ADD")
	b.glow:SetPoint("CENTER")
	b.glow:SetSize(80, 80)
	b.glow:SetVertexColor(0.3, 1, 0.5)
	W.Pulse(b.glow, 0.15, 0.8, 1)
	b.glow:Hide()
	b.count = W.Pill(b, 16)
	b.count:SetPoint("CENTER", b, "BOTTOMRIGHT", -2, 2)
	b.count:SetFrameLevel(b:GetFrameLevel() + 2)
	b.count.bg:SetDrawLayer("OVERLAY")
	b.count:Set(nil)
	b:SetScript("OnMouseDown", function(self) self.icon:SetPoint("TOPLEFT", 2, -2) end)
	b:SetScript("OnMouseUp", function(self) self.icon:SetPoint("TOPLEFT", 1, -1) end)
	b:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		UI:Open(TAB_SEARCH)
	end)
	W.Tooltip(b, L.TITLE, function()
		local good = KF:CountGood()
		return good > 0 and (L.PVE_TIP .. "\n\n|cff40ff70" .. L.STATUS_GOOD:format(good) .. "|r") or L.PVE_TIP
	end)
	self.pveButton = b

	local t = W.Button(PVEFrame, L.BTN_PVE, 92, function() UI:Open(TAB_SEARCH) end)
	t:SetHeight(20)
	if PVEFrame.CloseButton then t:SetPoint("RIGHT", PVEFrame.CloseButton, "LEFT", -2, 0)
	else t:SetPoint("TOPRIGHT", PVEFrame, "TOPRIGHT", -28, -1) end
	t:SetFrameLevel(PVEFrame:GetFrameLevel() + 20)
	self.pveTitleButton = t

	self:UpdateGroupFinderButton()
end

function UI:UpdateGroupFinderButton()
	local b = self.pveButton
	if not b then return end
	local good = KF:CountGood()
	if good > 0 then
		b.count:Set(tostring(good), 0.25, 1, 0.45)
		b.glow:Show()
		if not b.glow.pulse:IsPlaying() then b.glow.pulse:Play() end
	else
		b.count:Set(nil)
		b.glow.pulse:Stop()
		b.glow:Hide()
	end
end

-- O Localizador pode carregar depois do login: tenta de novo a cada addon carregado.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(self)
	if not KF.db then return end
	if PVEFrame then UI:AttachToGroupFinder() end
	if UI.pveButton then self:UnregisterAllEvents() end
end)

----------------------------------------------------------------------
-- Upgrades: texto de status e painel de opções do jogo
----------------------------------------------------------------------
function UI.RangeLabel(v)
	if (v or 0) == 0 then return L.O_RANGE_NONE end
	return L.O_RANGE_N:format(v)
end

-- Uma linha que diz o que a lista está mostrando e o que fazer.
function UI:StatusLine()
	local n = #(KF.filtered or {})
	local ago = Ago(KF.lastSearch)
	local u, q, base = KF.db.upgrade, KF.queryLevel, KF:BaseLevel()
	if u.enabled and q then
		local all = base and q > base and q <= base + (u.range or 0)
		return "|cffffd100+" .. q .. "|r  " .. (all and L.STATUS_UP_ALL or L.STATUS_UP_ONLY):format(n) .. "  ·  " .. ago
	end
	local text = L.STATUS:format(n, ago)
	if u.enabled and base then text = "|cff8cc8ff" .. L.STATUS_UP_HINT:format(base) .. "|r  ·  " .. text end
	return text
end

function UI:OpenOptions()
	if self.optionsCategory and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(self.optionsCategory:GetID())
	end
end

function UI:RegisterOptions()
	if self.optionsCategory or not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
	local ok = pcall(function()
		local cat = Settings.RegisterVerticalLayoutCategory(L.TITLE)
		local u = KF.db.upgrade
		local function hook(setting)
			if setting and setting.SetValueChangedCallback then
				setting:SetValueChangedCallback(function() KF:ApplyFilters() end)
			end
		end
		local s1 = Settings.RegisterAddOnSetting(cat, "KEYFINDER_UPGRADE_ENABLED", "enabled", u, Settings.VarType.Boolean, L.O_UPGRADE, true)
		hook(s1)
		Settings.CreateCheckbox(cat, s1, L.O_UPGRADE_TIP)

		local s2 = Settings.RegisterAddOnSetting(cat, "KEYFINDER_UPGRADE_RANGE", "range", u, Settings.VarType.Number, L.O_RANGE, 1)
		hook(s2)
		local o2 = Settings.CreateSliderOptions(0, 3, 1)
		o2:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, UI.RangeLabel)
		Settings.CreateSlider(cat, s2, o2, L.O_RANGE_TIP)

		local s3 = Settings.RegisterAddOnSetting(cat, "KEYFINDER_UPGRADE_BASE", "base", u, Settings.VarType.Number, L.O_BASE, 0)
		hook(s3)
		local o3 = Settings.CreateSliderOptions(0, 30, 1)
		o3:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
			if v == 0 then
				local auto = KF.player and KF.player.needLevel
				return auto and L.O_BASE_AUTO_N:format(auto) or L.O_BASE_AUTO
			end
			return "+" .. v
		end)
		Settings.CreateSlider(cat, s3, o3, L.O_BASE_TIP)

		Settings.RegisterAddOnCategory(cat)
		self.optionsCategory = cat
	end)
	if not ok then self.optionsCategory = nil end
end

function UI:OnLogin()
	self:RegisterOptions()
	self:Create()
	if PVEFrame then self:AttachToGroupFinder() end
end

----------------------------------------------------------------------
-- Parse Academy: abre a página do jogador no parseacademy.com.
-- Com o addon Parse Academy instalado, usa a janela dele (que sabe
-- montar o link certinho). Sem ele, monta o mesmo formato de link e
-- mostra numa caixa para copiar.
----------------------------------------------------------------------
local PA_ICON = "Interface\Icons\INV_Misc_Book_09"
local PA_SITE = "https://parseacademy.com/character/"
local PA_REGIONS = { [1] = "us", [2] = "kr", [3] = "eu", [4] = "tw", [5] = "cn" }
local ACCENTS = {
	["á"] = "a", ["à"] = "a", ["â"] = "a", ["ã"] = "a", ["ä"] = "a", ["é"] = "e", ["ê"] = "e", ["è"] = "e", ["ë"] = "e",
	["í"] = "i", ["î"] = "i", ["ï"] = "i", ["ó"] = "o", ["ô"] = "o", ["õ"] = "o", ["ö"] = "o", ["ú"] = "u", ["û"] = "u",
	["ü"] = "u", ["ç"] = "c", ["ñ"] = "n",
}

local function RealmSlug(realm)
	realm = strtrim(realm or "")
	if realm == "" then return nil end
	for k, v in pairs(ACCENTS) do realm = realm:gsub(k, v) end
	if not realm:find("%s") then
		realm = realm:gsub("(%l)(%u)", "%1 %2"):gsub("(%a)(%d)", "%1 %2")
	end
	local slug = realm:lower():gsub("['`]", ""):gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
	return slug ~= "" and slug or nil
end

local function URLEncode(s)
	return (s:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

StaticPopupDialogs["KEYFINDER_COPY_LINK"] = {
	text = L.PA_COPY,
	button1 = CLOSE or "Close",
	hasEditBox = 1,
	editBoxWidth = 320,
	OnShow = function(self, data)
		local eb = (self.GetEditBox and self:GetEditBox()) or self.editBox or self.EditBox
		if eb then eb:SetText(data or ""); eb:HighlightText(); eb:SetFocus() end
	end,
	EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
	EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function UI:OpenParseAcademy(fullName)
	if not fullName or fullName == "" then ns.Print(L.PA_NO_NAME) return end
	local pa = _G.ParseAcademy
	if pa and pa.CharacterFromName and pa.Open then
		local info, reason = pa:CharacterFromName(fullName)
		pa:Open(info, reason)
		return
	end
	local name, realm = strsplit("-", fullName, 2)
	realm = (realm and realm ~= "") and realm or (GetRealmName and GetRealmName()) or ""
	local slug = RealmSlug(realm)
	if not (name and slug) then ns.Print(L.PA_NO_NAME) return end
	local region = PA_REGIONS[GetCurrentRegion and GetCurrentRegion() or 1] or "us"
	StaticPopup_Show("KEYFINDER_COPY_LINK", nil, nil, PA_SITE .. region .. "/" .. slug .. "/" .. URLEncode(name))
end

-- Botão pequeno com o ícone do Parse Academy. getName() devolve "Nome-Reino".
function UI:CreateParseAcademyButton(parent, getName)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(20, 20)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexture(PA_ICON)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.25)
	W.Border(b, 0, 0, 0, 1)
	b:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		UI:OpenParseAcademy(getName())
	end)
	W.Tooltip(b, "Parse Academy", function()
		return _G.ParseAcademy and L.PA_TIP or L.PA_TIP_FALLBACK
	end)
	return b
end

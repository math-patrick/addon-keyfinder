local _, ns = ...
local L = ns.L

-- Fábricas finas sobre os templates nativos da Blizzard + alguns elementos
-- visuais próprios (painéis escuros, badges circulares, barras animadas).
-- Só usa texturas que existem no cliente.
local W = {}
ns.W = W

W.WHITE = "Interface\\Buttons\\WHITE8X8"
W.CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
W.GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
W.SPARK = "Interface\\CastingBar\\UI-CastingBar-Spark"
W.QUESTION = 134400 -- INV_Misc_QuestionMark

W.GOOD = CreateColor(0.12, 1, 0)
W.BAD = CreateColor(1, 0.32, 0.32)
W.GRAY = CreateColor(0.62, 0.62, 0.62)
W.GOLD = CreateColor(1, 0.82, 0)
W.BLUE = CreateColor(0.45, 0.75, 1)

----------------------------------------------------------------------
-- Básicos
----------------------------------------------------------------------
function W.Text(parent, template, justify, size, flags)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
	fs:SetJustifyH(justify or "LEFT")
	fs:SetWordWrap(false)
	if size then
		local font = fs:GetFont()
		fs:SetFont(font or STANDARD_TEXT_FONT, size, flags or "")
	end
	return fs
end

function W.Header(parent, text)
	local fs = W.Text(parent, "GameFontNormal")
	fs:SetText(text)
	return fs
end

function W.Gradient(tex, orientation, r1, g1, b1, a1, r2, g2, b2, a2)
	tex:SetTexture(W.WHITE)
	tex:SetGradient(orientation, CreateColor(r1, g1, b1, a1), CreateColor(r2, g2, b2, a2))
end

-- Borda de 1 px (ou `size`) feita com 4 texturas.
function W.Border(f, r, g, b, a, layer, size)
	size = size or 1
	local edges = {}
	local function edge(p1, p2, horiz)
		local e = f:CreateTexture(nil, layer or "BORDER", nil, 7)
		e:SetColorTexture(r, g, b, a)
		e:SetPoint(p1); e:SetPoint(p2)
		if horiz then e:SetHeight(size) else e:SetWidth(size) end
		edges[#edges + 1] = e
	end
	edge("TOPLEFT", "TOPRIGHT", true); edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
	edge("TOPLEFT", "BOTTOMLEFT", false); edge("TOPRIGHT", "BOTTOMRIGHT", false)
	local obj = { edges = edges }
	function obj:SetColor(...) for _, e in ipairs(self.edges) do e:SetColorTexture(...) end end
	function obj:SetShown(v) for _, e in ipairs(self.edges) do e:SetShown(v) end end
	return obj
end

-- Painel nativo (o mesmo "inset" das janelas da Blizzard).
function W.Panel(parent)
	return CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
end
W.Inset = W.Panel

-- Texto que nunca vaza: largura fixa, uma linha, reticências no fim.
function W.Clamp(fs, width)
	fs:SetWidth(width)
	fs:SetWordWrap(false)
	if fs.SetMaxLines then fs:SetMaxLines(1) end
	return fs
end

function W.Tooltip(frame, title, body)
	if frame.SetMouseMotionEnabled then frame:SetMouseMotionEnabled(true) end
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(type(title) == "function" and title() or title, 1, 1, 1)
		local b = type(body) == "function" and body() or body
		if b then GameTooltip:AddLine(b, nil, nil, nil, true) end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
end

-- Título de seção: texto dourado + linha.
function W.Section(parent, text, width)
	local fs = W.Text(parent, "GameFontNormalSmall", "LEFT", 11)
	fs:SetText(text)
	local line = parent:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 0.82, 0, 0.16)
	line:SetHeight(1)
	line:SetPoint("LEFT", fs, "RIGHT", 6, 0)
	line:SetWidth(math.max(4, (width or 200) - fs:GetStringWidth() - 6))
	fs.line = line
	return fs
end

function W.Pulse(region, minA, maxA, duration)
	local ag = region:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	local a = ag:CreateAnimation("Alpha")
	a:SetFromAlpha(minA); a:SetToAlpha(maxA)
	a:SetDuration(duration or 0.8)
	a:SetSmoothing("IN_OUT")
	region.pulse = ag
	return ag
end

-- Flash único (entra rápido, sai devagar).
function W.Flash(region)
	region:SetAlpha(0)
	local ag = region:CreateAnimationGroup()
	local a1 = ag:CreateAnimation("Alpha"); a1:SetFromAlpha(0); a1:SetToAlpha(1); a1:SetDuration(0.15); a1:SetOrder(1)
	local a2 = ag:CreateAnimation("Alpha"); a2:SetFromAlpha(1); a2:SetToAlpha(0); a2:SetDuration(1.1); a2:SetOrder(2)
	region.flash = ag
	return ag
end

----------------------------------------------------------------------
-- Ícone quadrado com borda preta
----------------------------------------------------------------------
function W.Icon(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetPoint("TOPLEFT", 1, -1)
	f.tex:SetPoint("BOTTOMRIGHT", -1, 1)
	f.border = W.Border(f, 0, 0, 0, 1)
	function f:SetIcon(t)
		self.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		self.tex:SetDesaturated(false)
		self.tex:SetTexture(t or W.QUESTION)
	end
	return f
end

-- Ícone redondo (máscara circular) com anel colorido.
function W.CircleIcon(parent, size)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(size, size)
	local function masked(layer, sub, inset)
		local t = f:CreateTexture(nil, layer, nil, sub)
		t:SetPoint("TOPLEFT", inset, -inset)
		t:SetPoint("BOTTOMRIGHT", -inset, inset)
		local m = f:CreateMaskTexture()
		m:SetTexture(W.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		m:SetAllPoints(t)
		t:AddMaskTexture(m)
		return t
	end
	f.ring = masked("ARTWORK", 0, 0)
	f.ring:SetTexture(W.WHITE)
	f.tex = masked("ARTWORK", 1, 2)
	function f:SetIcon(t, r, g, b)
		self.tex:SetTexture(t or W.QUESTION)
		self.ring:SetVertexColor(r or 1, g or 0.82, b or 0, 1)
	end
	return f
end

----------------------------------------------------------------------
-- Badge circular com número (nota de match / encaixe)
----------------------------------------------------------------------
function W.Badge(parent, size)
	local b = CreateFrame("Frame", nil, parent)
	b:SetSize(size, size)
	b.glow = b:CreateTexture(nil, "BACKGROUND")
	b.glow:SetTexture(W.GLOW)
	b.glow:SetBlendMode("ADD")
	b.glow:SetPoint("CENTER")
	b.glow:SetSize(size * 1.9, size * 1.9)
	b.glow:Hide()
	W.Pulse(b.glow, 0.2, 0.85, 0.9)

	local function circle(sub, inset)
		local t = b:CreateTexture(nil, "ARTWORK", nil, sub)
		t:SetPoint("TOPLEFT", inset, -inset)
		t:SetPoint("BOTTOMRIGHT", -inset, inset)
		t:SetTexture(W.WHITE)
		local m = b:CreateMaskTexture()
		m:SetTexture(W.CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
		m:SetAllPoints(t)
		t:AddMaskTexture(m)
		return t
	end
	b.ring = circle(0, 0)
	b.inner = circle(1, math.max(2, math.floor(size * 0.09)))
	b.inner:SetGradient("VERTICAL", CreateColor(0.02, 0.02, 0.03, 1), CreateColor(0.13, 0.13, 0.16, 1))
	b.text = W.Text(b, "GameFontHighlight", "CENTER", math.floor(size * 0.42), "OUTLINE")
	b.text:SetPoint("CENTER", 0, 0)

	function b:Set(value, r, g, bl)
		self.ring:SetGradient("VERTICAL", CreateColor(r * 0.5, g * 0.5, bl * 0.5, 1), CreateColor(r, g, bl, 1))
		self.text:SetText(value)
		self.text:SetTextColor(r, g, bl)
		self.glow:SetVertexColor(r, g, bl)
		local hot = type(value) == "number" and value >= 85
		self.glow:SetShown(hot)
		if hot then
			if not self.glow.pulse:IsPlaying() then self.glow.pulse:Play() end
		else
			self.glow.pulse:Stop()
		end
	end
	return b
end

----------------------------------------------------------------------
-- Pílula: etiqueta pequena colorida ("+38", "≈ +14")
----------------------------------------------------------------------
function W.Pill(parent, height)
	height = height or 16
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(height)
	f.bg = f:CreateTexture(nil, "ARTWORK")
	f.bg:SetAllPoints()
	f.bg:SetTexture(W.WHITE)
	f.text = W.Text(f, "GameFontHighlightSmall", "CENTER", height <= 14 and 9 or 10, "")
	f.text:SetPoint("CENTER", 0, 0)
	function f:Set(text, r, g, b)
		if not text then self:Hide() return end
		self:Show()
		self.text:SetText(text)
		self.text:SetTextColor(r, g, b)
		self.bg:SetVertexColor(r, g, b, 0.18)
		self:SetWidth(math.max(height * 1.6, self.text:GetStringWidth() + 12))
	end
	return f
end

----------------------------------------------------------------------
-- Barra horizontal com preenchimento animado e faísca
----------------------------------------------------------------------
function W.Bar(parent, height)
	height = height or 6
	local b = CreateFrame("Frame", nil, parent)
	b:SetHeight(height)
	b.bg = b:CreateTexture(nil, "BACKGROUND")
	b.bg:SetAllPoints()
	b.bg:SetColorTexture(1, 1, 1, 0.07)
	b.fill = b:CreateTexture(nil, "ARTWORK")
	b.fill:SetPoint("TOPLEFT")
	b.fill:SetPoint("BOTTOMLEFT")
	b.fill:SetTexture(W.WHITE)
	b.fill:SetWidth(0.5)
	b.spark = b:CreateTexture(nil, "OVERLAY")
	b.spark:SetTexture(W.SPARK)
	b.spark:SetBlendMode("ADD")
	b.spark:SetSize(10, height * 3)
	b.spark:SetPoint("CENTER", b.fill, "RIGHT", 0, 0)
	b.cur, b.target = 0, 0

	function b:Layout()
		local w = self:GetWidth() or 0
		self.fill:SetWidth(math.max(0.5, w * self.cur))
		self.spark:SetShown(self.cur > 0.02 and self.cur < 0.995)
	end
	function b:SetValue(v, r, g, bl, instant)
		v = math.max(0, math.min(1, v or 0))
		self.target = v
		if r then
			self.fill:SetGradient("HORIZONTAL", CreateColor(r * 0.4, g * 0.4, bl * 0.4, 1), CreateColor(r, g, bl, 1))
			self.spark:SetVertexColor(r, g, bl, 0.9)
		end
		if instant then self.cur = v end
		self:Layout()
	end
	b:SetScript("OnUpdate", function(self, elapsed)
		if self.cur == self.target then return end
		local d = self.target - self.cur
		if math.abs(d) < 0.003 then self.cur = self.target
		else self.cur = self.cur + d * math.min(1, elapsed * 8) end
		self:Layout()
	end)
	b:SetScript("OnSizeChanged", function(self) self:Layout() end)
	return b
end

----------------------------------------------------------------------
-- Templates nativos
----------------------------------------------------------------------
function W.Button(parent, text, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 110, 22)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

function W.Check(parent, label, get, set, tooltip)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	local fs = W.Text(cb, "GameFontHighlightSmall")
	fs:SetPoint("LEFT", cb, "RIGHT", 1, 1)
	fs:SetText(label)
	cb.label = fs
	cb:SetHitRectInsets(0, -math.min(180, fs:GetStringWidth() + 4), 0, 0)
	cb:SetScript("OnClick", function(self)
		local on = self:GetChecked() and true or false
		PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		set(on)
	end)
	if tooltip then
		cb:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText(label, 1, 1, 1)
			GameTooltip:AddLine(tooltip, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		cb:SetScript("OnLeave", GameTooltip_Hide)
	end
	function cb:Sync() self:SetChecked(get() and true or false) end
	cb:Sync()
	return cb
end

function W.Slider(parent, width, minV, maxV, step, get, set, fmt)
	local s = CreateFrame("Frame", nil, parent, "MinimalSliderWithSteppersTemplate")
	s:SetSize(width, 20)
	local formatters = {
		[MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(MinimalSliderWithSteppersMixin.Label.Right, fmt),
	}
	s:Init(get(), minV, maxV, (maxV - minV) / step, formatters)
	s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		value = math.floor(value / step + 0.5) * step
		if value ~= get() then set(value) end
	end, s)
	function s:Sync() self:SetValue(get()) end
	return s
end

function W.Dropdown(parent, width, options, get, set)
	local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dd:SetWidth(width)
	dd:SetupMenu(function(_, root)
		local opts = type(options) == "function" and options() or options
		for _, o in ipairs(opts) do
			root:CreateRadio(o.text, function() return get() == o.value end, function() set(o.value) end)
		end
	end)
	function dd:Sync() self:GenerateMenu() end
	return dd
end

-- ScrollBox + MinimalScrollBar com view linear (o mesmo par usado pelo Localizador).
-- extent (opcional): function(dataIndex, data) -> altura da linha, para listas
-- com linhas de altura variável.
function W.List(parent, template, initializer, extent)
	local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
	local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
	bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 6, 0)
	bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementInitializer(template, initializer)
	if extent and view.SetElementExtentCalculator then view:SetElementExtentCalculator(extent) end
	ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
	return box, bar, view
end

function W.SetData(box, list)
	box:SetDataProvider(CreateDataProvider(list or {}), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)
end

----------------------------------------------------------------------
-- Ícones de role e classe
----------------------------------------------------------------------
local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }

local function HasAtlas(name) return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil end

function W.SetRoleIcon(tex, role)
	tex:SetTexCoord(0, 1, 0, 1)
	local atlas = ROLE_ATLAS[role]
	if atlas and HasAtlas(atlas) then
		tex:SetAtlas(atlas)
	elseif GetTexCoordsForRole then
		tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
		tex:SetTexCoord(GetTexCoordsForRole(role))
	else
		tex:SetColorTexture(0.4, 0.4, 0.4, 1)
	end
end

function W.SetClassIcon(tex, class)
	tex:SetTexCoord(0, 1, 0, 1)
	if not class then tex:SetColorTexture(0.2, 0.2, 0.2, 1) return end
	local atlas = "classicon-" .. class:lower()
	if HasAtlas(atlas) then
		tex:SetAtlas(atlas)
	elseif CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
		tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
		tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
	else
		local c = C_ClassColor and C_ClassColor.GetClassColor(class)
		if c then tex:SetColorTexture(c.r, c.g, c.b, 1) else tex:SetColorTexture(0.5, 0.5, 0.5, 1) end
	end
end

function W.ClassColor(class)
	local c = class and C_ClassColor and C_ClassColor.GetClassColor(class)
	if c then return c.r, c.g, c.b end
	return 0.6, 0.6, 0.6
end

function W.ClassColored(text, class)
	local c = class and C_ClassColor and C_ClassColor.GetClassColor(class)
	if c and text then return c:WrapTextInColorCode(text) end
	return text or "?"
end

----------------------------------------------------------------------
-- Textos e cores de pontuação
----------------------------------------------------------------------
function W.ScoreText(score)
	score = score or 0
	local c = C_ChallengeMode.GetDungeonScoreRarityColor and C_ChallengeMode.GetDungeonScoreRarityColor(score)
	if c then return c:WrapTextInColorCode(tostring(score)) end
	return tostring(score)
end

-- Cor de pontos de UMA dungeon (escala diferente da geral).
function W.MapScoreColor(score)
	local c = C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor and C_ChallengeMode.GetSpecificDungeonOverallScoreRarityColor(score or 0)
	if not c and C_ChallengeMode.GetDungeonScoreRarityColor then c = C_ChallengeMode.GetDungeonScoreRarityColor((score or 0) * 8) end
	if c then return c.r, c.g, c.b end
	return 1, 1, 1
end

function W.BestText(level, timed)
	if not level or level <= 0 then return W.GRAY:WrapTextInColorCode(L.NO_BEST) end
	local t = "+" .. level
	return timed and W.GOOD:WrapTextInColorCode(t) or W.GRAY:WrapTextInColorCode(t .. "*")
end

-- Cor da nota de match (verde forte -> verde -> dourado -> laranja -> vermelho).
function W.MatchColor(score)
	if score >= 80 then return 0.2, 1, 0.45 end
	if score >= 65 then return 0.6, 0.95, 0.2 end
	if score >= 45 then return 1, 0.78, 0.2 end
	if score >= 25 then return 1, 0.5, 0.15 end
	return 1, 0.3, 0.3
end

-- Mesma escala para porcentagens 0..1.
function W.PctColor(v) return W.MatchColor((v or 0) * 100) end

-- Monta até 5 slots: membros (tank, healer, dps) e depois vagas abertas.
function W.BuildSlots(members, open)
	local slots = {}
	for _, role in ipairs(ns.ROLE_ORDER) do
		for _, m in ipairs(members) do if m.role == role then slots[#slots + 1] = m end end
	end
	for _, role in ipairs(ns.ROLE_ORDER) do
		for _ = 1, (open[role] or 0) do slots[#slots + 1] = { role = role, open = true } end
	end
	while #slots > 5 do table.remove(slots) end
	return slots
end

-- Escreve texto protegido (título/comentário do grupo) sem tentar lê-lo.
function W.SetProtectedText(fs, value)
	if value == nil then fs:SetText("") return end
	local ok = pcall(fs.SetText, fs, value)
	if not ok then fs:SetText("") end
end

----------------------------------------------------------------------
-- Ícone de utilidade (Bloodlust / battle res) com marca de estado:
-- verde = o grupo tem, dourado = falta e você leva, vermelho = falta.
----------------------------------------------------------------------
W.UTILS = {
	{ key = "hasBL", spell = 2825, fallback = "Interface\\Icons\\spell_nature_bloodlust", name = "BL" },
	{ key = "hasBrez", spell = 20484, fallback = "Interface\\Icons\\spell_nature_reincarnation", name = "BREZ" },
}

local function SpellIcon(id, fallback)
	local ok, tex = pcall(function()
		if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
		return GetSpellTexture and GetSpellTexture(id)
	end)
	return (ok and tex) or fallback
end

function W.UtilIcon(parent, def, size)
	local ic = W.Icon(parent, size or 22)
	ic:SetIcon(SpellIcon(def.spell, def.fallback))
	ic.def = def
	ic.mark = ic:CreateTexture(nil, "OVERLAY")
	ic.mark:SetSize(12, 12)
	ic.mark:SetPoint("BOTTOMRIGHT", 4, -4)
	ic:EnableMouse(true)
	ic:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L[self.def.name], 1, 1, 1)
		if self.tip then GameTooltip:AddLine(self.tip, nil, nil, nil, true) end
		GameTooltip:Show()
	end)
	ic:SetScript("OnLeave", GameTooltip_Hide)
	-- has: o grupo tem; bring: você leva (só conta quando falta)
	function ic:SetState(has, bring)
		self.tex:SetDesaturated(not has and not bring)
		self.tex:SetAlpha((has or bring) and 1 or 0.5)
		if has then
			self.border:SetColor(0.25, 1, 0.45, 1)
			self.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
			self.mark:SetVertexColor(1, 1, 1)
			self.tip = L.UTIL_HAS
		elseif bring then
			self.border:SetColor(1, 0.82, 0, 1)
			self.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
			self.mark:SetVertexColor(1, 0.82, 0)
			self.tip = L.UTIL_YOU_BRING
		else
			self.border:SetColor(1, 0.3, 0.3, 1)
			self.mark:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
			self.mark:SetVertexColor(1, 1, 1)
			self.tip = L.UTIL_MISSING
		end
	end
	return ic
end

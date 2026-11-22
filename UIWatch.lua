local _, ns = ...
local L, KF, W = ns.L, ns.KF, ns.W
ns.UI = ns.UI or {}
local UI = ns.UI

local LEFT_W = 580

----------------------------------------------------------------------
-- Linha de regra (template KeyfinderRuleRowTemplate)
----------------------------------------------------------------------
KeyfinderRuleRowMixin = {}

function KeyfinderRuleRowMixin:OnLoad()
	self.Stripe = self:CreateTexture(nil, "BACKGROUND")
	self.Stripe:SetAllPoints()
	self.Stripe:SetColorTexture(0, 0, 0, 0.25)
	self.Sep = self:CreateTexture(nil, "ARTWORK")
	self.Sep:SetPoint("BOTTOMLEFT")
	self.Sep:SetPoint("BOTTOMRIGHT")
	self.Sep:SetHeight(1)
	self.Sep:SetColorTexture(1, 1, 1, 0.06)
	self.Toggle = CreateFrame("CheckButton", nil, self, "UICheckButtonTemplate")
	self.Toggle:SetSize(24, 24)
	self.Toggle:SetPoint("LEFT", 4, 0)
	self.Toggle:SetScript("OnClick", function(cb)
		if self.rule then
			self.rule.enabled = cb:GetChecked() and true or false
			if self.rule.enabled then KF:CheckRules() end
			UI:OnDataChanged()
		end
	end)
	self.Icon = W.Icon(self, 22)
	self.Icon:SetPoint("LEFT", self.Toggle, "RIGHT", 4, 0)
	self.Delete = CreateFrame("Button", nil, self, "UIPanelCloseButtonNoScripts")
	self.Delete:SetSize(22, 22)
	self.Delete:SetPoint("RIGHT", -4, 0)
	self.Delete:SetScript("OnClick", function() if self.rule then KF:RemoveRule(self.rule.id) end end)
	self.Hits = W.Text(self, "GameFontHighlightSmall", "RIGHT")
	self.Hits:SetPoint("RIGHT", self.Delete, "LEFT", -8, 0)
	self.Hits:SetWidth(76)
	self.Desc = W.Text(self, "GameFontHighlight", "LEFT", 12)
	self.Desc:SetPoint("LEFT", self.Icon, "RIGHT", 8, 0)
	self.Desc:SetPoint("RIGHT", self.Hits, "LEFT", -8, 0)
end

function KeyfinderRuleRowMixin:Init(rule)
	self.rule = rule
	self.Toggle:SetChecked(rule.enabled)
	local map = (rule.mapID or 0) ~= 0 and KF.mapByID and KF.mapByID[rule.mapID]
	self.Icon:SetIcon(map and map.texture or "Interface\\Icons\\inv_misc_map02")
	local text = L.W_RULE_DESC:format(map and map.name or L.W_ANY_DUNGEON, (rule.minScore or 0) > 0 and (rule.minScore .. "+") or L.ANY,
		(rule.minBest or 0) > 0 and ("+" .. rule.minBest) or L.ANY)
	if rule.myRole then text = text .. L.W_RULE_ROLE end
	self.Desc:SetText(text)
	self.Desc:SetAlpha(rule.enabled and 1 or 0.5)
	self.Icon:SetAlpha(rule.enabled and 1 or 0.5)
	local n = KF:RuleHits(rule)
	if not rule.enabled then self.Hits:SetText("")
	elseif n > 0 then self.Hits:SetText(W.GOOD:WrapTextInColorCode(L.W_HITS:format(n)))
	else self.Hits:SetText(W.GRAY:WrapTextInColorCode(L.W_WAITING)) end
end

----------------------------------------------------------------------
-- Aba Watchlist
----------------------------------------------------------------------
function UI:BuildWatch(page)
	local left = W.Panel(page)
	left:SetPoint("TOPLEFT")
	left:SetPoint("BOTTOMLEFT")
	left:SetWidth(LEFT_W)
	local right = W.Panel(page)
	right:SetPoint("TOPLEFT", left, "TOPRIGHT", 5, 0)
	right:SetPoint("BOTTOMRIGHT")
	local rightW = ns.PAGE_W - LEFT_W - 5 - 24

	-- Construtor de regra
	local nr = { mapID = 0, minScore = 0, minBest = 0, myRole = true }
	self.newRule = nr
	local h = W.Section(left, L.W_NEW_RULE, LEFT_W - 24); h:SetPoint("TOPLEFT", 12, -12)

	local lbl = W.Text(left, "GameFontHighlightSmall"); lbl:SetPoint("TOPLEFT", 14, -34); lbl:SetText(L.W_DUNGEON)
	self.ruleDungeon = W.Dropdown(left, 240, function()
		local opts = { { text = L.W_ANY_DUNGEON, value = 0 } }
		for _, m in ipairs(KF.maps or {}) do opts[#opts + 1] = { text = m.name, value = m.id } end
		return opts
	end, function() return nr.mapID end, function(v) nr.mapID = v end)
	self.ruleDungeon:SetPoint("TOPLEFT", 12, -50)

	lbl = W.Text(left, "GameFontHighlightSmall"); lbl:SetPoint("TOPLEFT", 300, -34); lbl:SetText(L.F_LEADER_SCORE)
	self.ruleScore = W.Slider(left, 210, 0, 4000, 100, function() return nr.minScore end, function(v) nr.minScore = v end,
		function(v) return v == 0 and L.ANY or tostring(v) end)
	self.ruleScore:SetPoint("TOPLEFT", 300, -52)

	lbl = W.Text(left, "GameFontHighlightSmall"); lbl:SetPoint("TOPLEFT", 14, -86); lbl:SetText(L.F_LEADER_BEST)
	self.ruleBest = W.Slider(left, 210, 0, 25, 1, function() return nr.minBest end, function(v) nr.minBest = v end,
		function(v) return v == 0 and L.ANY or ("+" .. v) end)
	self.ruleBest:SetPoint("TOPLEFT", 12, -104)

	self.ruleRole = W.Check(left, L.F_MY_ROLE, function() return nr.myRole end, function(v) nr.myRole = v end)
	self.ruleRole:SetPoint("TOPLEFT", 296, -98)

	local add = W.Button(left, L.W_ADD, 120, function()
		KF:AddRule({ mapID = nr.mapID, minScore = nr.minScore, minBest = nr.minBest, myRole = nr.myRole })
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
	end)
	add:SetHeight(24)
	add:SetPoint("TOPRIGHT", -14, -132)

	h = W.Section(left, L.W_RULES, LEFT_W - 24); h:SetPoint("TOPLEFT", 12, -168)
	local box = W.List(left, "KeyfinderRuleRowTemplate", function(row, rule) row:Init(rule) end)
	box:SetPoint("TOPLEFT", 6, -186)
	box:SetPoint("BOTTOMRIGHT", -26, 6)
	self.ruleList = box
	local empty = W.Text(left, "GameFontDisable", "CENTER", 12)
	empty:SetPoint("CENTER", box, 0, 0)
	empty:SetWidth(420); empty:SetWordWrap(true)
	empty:SetText(L.W_NO_RULES)
	self.ruleEmpty = empty

	-- Avisos
	local a = KF.db.alerts
	h = W.Section(right, L.W_ALERTS, rightW); h:SetPoint("TOPLEFT", 12, -12)
	local y = -30
	self.alertChecks = {}
	for _, def in ipairs({ { "sound", L.W_SOUND }, { "flash", L.W_FLASH }, { "raidWarning", L.W_RAIDWARNING }, { "popup", L.W_POPUP } }) do
		local key = def[1]
		local cb = W.Check(right, def[2], function() return a[key] end, function(v) a[key] = v end)
		cb:SetPoint("TOPLEFT", 10, y)
		self.alertChecks[#self.alertChecks + 1] = cb
		y = y - 24
	end
	local test = W.Button(right, L.W_TEST, 140, function() KF:Alert(L.W_TEST_TEXT, nil) end)
	test:SetPoint("TOPLEFT", 14, y - 4)
	y = y - 44

	h = W.Section(right, L.W_BINDING, rightW); h:SetPoint("TOPLEFT", 12, y); y = y - 18
	local bt = W.Text(right, "GameFontHighlightSmall")
	bt:SetPoint("TOPLEFT", 12, y)
	bt:SetWidth(rightW)
	bt:SetWordWrap(true)
	bt:SetJustifyV("TOP")
	bt:SetText(L.W_BINDING_TEXT)
	y = y - bt:GetStringHeight() - 14
	self.bindingText = W.Text(right, "GameFontNormalSmall")
	self.bindingText:SetPoint("TOPLEFT", 12, y - 6)
	W.Clamp(self.bindingText, rightW - 120)
	local setF8 = W.Button(right, L.W_SET_F8, 100, function() UI:BindF8() end)
	setF8:SetPoint("TOPRIGHT", -14, y)
end

function UI:BindF8()
	if InCombatLockdown() then ns.Print(L.W_IN_COMBAT) return end
	local key = "F8"
	local existing = GetBindingAction(key)
	SetBinding(key, "KEYFINDER_REFRESH")
	SaveBindings(GetCurrentBindingSet())
	local replaced = (existing and existing ~= "" and existing ~= "KEYFINDER_REFRESH") and L.W_BINDING_REPLACED:format(existing) or ""
	ns.Print(L.W_BINDING_SET:format(replaced))
	self:RefreshWatch()
end

function UI:RefreshWatch()
	if not self.ruleList then return end
	W.SetData(self.ruleList, KF.db.rules)
	self.ruleEmpty:SetShown(#KF.db.rules == 0)
	local key = GetBindingKey("KEYFINDER_REFRESH")
	self.bindingText:SetText(L.W_BINDING_CUR:format(key or L.W_BINDING_NONE))
	self.ruleDungeon:Sync()
end

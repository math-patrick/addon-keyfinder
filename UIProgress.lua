local _, ns = ...
local L, KF, W = ns.L, ns.KF, ns.W
ns.UI = ns.UI or {}
local UI = ns.UI

----------------------------------------------------------------------
-- Aba Progresso: um card por dungeon com o seu best, pontos e o
-- próximo passo que mais sobe o seu rating.
----------------------------------------------------------------------
local function FindFor(mapID)
	local f = KF.db.filters
	wipe(f.dungeons)
	f.dungeons[mapID] = true
	UI:SyncFilterControls()
	UI:SelectTab(1)
	KF:Search()
	KF:ApplyFilters()
end

local function CreateCard(parent)
	local c = CreateFrame("Frame", nil, parent)
	c.art = c:CreateTexture(nil, "BACKGROUND")
	c.art:SetPoint("TOPLEFT", 1, -1)
	c.art:SetPoint("BOTTOMRIGHT", -1, 1)
	c.shade = c:CreateTexture(nil, "BACKGROUND", nil, 1)
	c.shade:SetAllPoints(c.art)
	W.Gradient(c.shade, "VERTICAL", 0.03, 0.035, 0.05, 0.98, 0.03, 0.035, 0.05, 0.35)
	c.border = W.Border(c, 1, 1, 1, 0.1)
	c.accent = c:CreateTexture(nil, "ARTWORK")
	c.accent:SetPoint("TOPLEFT", 1, -1)
	c.accent:SetPoint("TOPRIGHT", -1, -1)
	c.accent:SetHeight(2)

	c.icon = W.Icon(c, 44)
	c.icon:SetPoint("TOPLEFT", 12, -12)
	c.name = W.Text(c, "GameFontNormal", "LEFT", 14, "OUTLINE")
	c.name:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 10, -3)
	c.name:SetPoint("RIGHT", c, "RIGHT", -12, 0)
	c.sub = W.Text(c, "GameFontDisableSmall")
	c.sub:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -5)
	W.Clamp(c.sub, 90)
	c.prio = W.Pill(c, 16)
	c.prio:SetPoint("TOPRIGHT", -10, -40)

	c.best = W.Text(c, "GameFontHighlight", "LEFT", 30, "OUTLINE")
	c.best:SetPoint("TOPLEFT", 12, -68)
	c.bestLbl = W.Text(c, "GameFontDisableSmall")
	c.bestLbl:SetPoint("BOTTOMLEFT", c.best, "BOTTOMRIGHT", 8, 5)
	W.Clamp(c.bestLbl, 80)
	c.score = W.Text(c, "GameFontHighlight", "RIGHT", 20, "OUTLINE")
	c.score:SetPoint("TOPRIGHT", -12, -72)
	c.scoreLbl = W.Text(c, "GameFontDisableSmall", "RIGHT")
	c.scoreLbl:SetPoint("TOPRIGHT", c.score, "BOTTOMRIGHT", 0, -2)
	c.scoreLbl:SetText(L.P_POINTS)

	c.bar = W.Bar(c, 7)
	c.bar:SetPoint("TOPLEFT", 12, -118)
	c.bar:SetPoint("TOPRIGHT", -12, -118)

	c.nextLbl = W.Text(c, "GameFontNormalSmall", "LEFT", 11)
	c.nextLbl:SetPoint("TOPLEFT", 12, -136)
	c.nextLbl:SetText(L.P_NEXT)
	c.next = W.Text(c, "GameFontHighlight", "LEFT", 13)
	c.next:SetPoint("TOPLEFT", 12, -151)
	c.next:SetPoint("RIGHT", c, "RIGHT", -12, 0)

	c.go = W.Button(c, L.P_FIND, 150, function() if c.mapID then FindFor(c.mapID) end end)
	c.go:SetPoint("BOTTOMLEFT", 12, 12)
	c.go:SetPoint("BOTTOMRIGHT", -12, 12)
	return c
end

function UI:BuildProgress(page)
	local pr = { cards = {} }
	self.progressUI = pr

	local top = W.Panel(page)
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(60)
	pr.top = top
	pr.title = W.Text(top, "GameFontNormalLarge", "LEFT", 16)
	pr.title:SetPoint("TOPLEFT", 14, -12)
	pr.title:SetText(L.P_TITLE)
	pr.summary = W.Text(top, "GameFontHighlightSmall")
	pr.summary:SetPoint("TOPLEFT", pr.title, "BOTTOMLEFT", 0, -6)
	W.Clamp(pr.summary, 560)
	pr.potential = W.Text(top, "GameFontHighlight", "RIGHT", 24, "OUTLINE")
	pr.potential:SetPoint("TOPRIGHT", -14, -10)
	pr.potential:SetTextColor(0.25, 1, 0.45)
	pr.potLbl = W.Text(top, "GameFontDisableSmall", "RIGHT")
	pr.potLbl:SetPoint("TOPRIGHT", pr.potential, "BOTTOMRIGHT", 0, -2)
	pr.potLbl:SetText(L.P_POTENTIAL)

	pr.grid = CreateFrame("Frame", nil, page)
	pr.grid:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -6)
	pr.grid:SetPoint("BOTTOMRIGHT")
end

function UI:RefreshProgress()
	local pr = self.progressUI
	if not pr then return end
	KF:RefreshPlayer()
	local p = KF.player
	local list = KF:GetProgress()

	local timed, levels = 0, 0
	local maxScore = 1
	for _, e in ipairs(list) do
		if e.mine and e.mine.timedLevel > 0 then timed = timed + 1; levels = levels + e.mine.timedLevel end
		if e.mine and e.mine.score > maxScore then maxScore = e.mine.score end
	end
	local avg = timed > 0 and (levels / timed) or 0
	-- Nível que você ainda precisa (o mesmo do modo upgrades).
	local base = KF:BaseLevel()
	pr.summary:SetText(L.P_SUMMARY:format(W.ScoreText(math.floor(p.score or 0)), timed, #list, avg))
	pr.potential:SetText(base and ("+" .. base) or "-")

	-- Grade: 4 colunas, altura dividida pelas linhas necessárias.
	local gw, gh = ns.PAGE_W, ns.PAGE_H - 66
	local cols = 4
	local rows = math.max(1, math.ceil(#list / cols))
	local gap = 6
	local cw = math.floor((gw - (cols - 1) * gap) / cols)
	local ch = math.min(230, math.floor((gh - (rows - 1) * gap) / rows))

	for i, e in ipairs(list) do
		local c = pr.cards[i]
		if not c then c = CreateCard(pr.grid); pr.cards[i] = c end
		c:SetSize(cw, ch)
		c:ClearAllPoints()
		local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
		c:SetPoint("TOPLEFT", col * (cw + gap), -row * (ch + gap))
		c:Show()

		local m, mine = e.map, e.mine
		c.mapID = m.id
		UI:SetBannerArt(c.art, m, cw - 2, ch - 2)
		c.art:SetAlpha(0.55)
		c.icon:SetIcon(m.texture)
		c.name:SetText(m.name)
		if m.timeLimit and m.timeLimit > 0 then
			c.sub:SetText(L.P_TIMER:format(SecondsToClock and SecondsToClock(m.timeLimit) or (math.floor(m.timeLimit / 60) .. "min")))
		else
			c.sub:SetText("")
		end

		local sr, sg, sb = W.MapScoreColor(mine and mine.score or 0)
		if mine and mine.level > 0 then
			local lvl = mine.timedLevel > 0 and mine.timedLevel or mine.level
			c.best:SetText("+" .. lvl)
			if mine.timedLevel > 0 then
				c.best:SetTextColor(0.25, 1, 0.45); c.bestLbl:SetText(L.P_TIMED)
			else
				c.best:SetTextColor(0.7, 0.7, 0.7); c.bestLbl:SetText(L.P_DEPLETED)
			end
			c.score:SetText(math.floor(mine.score))
			c.score:SetTextColor(sr, sg, sb)
			c.bar:SetValue(mine.score / maxScore, sr, sg, sb)
		else
			c.best:SetText("-"); c.best:SetTextColor(0.5, 0.5, 0.5)
			c.bestLbl:SetText(L.P_NONE)
			c.score:SetText("0"); c.score:SetTextColor(0.5, 0.5, 0.5)
			c.bar:SetValue(0, 0.5, 0.5, 0.5)
		end

		local needsBase = base and (not mine or mine.timedLevel < base)
		if needsBase and not e.weak then
			c.prio:Set(L.P_NEEDS:format(base), 0.25, 1, 0.45)
			c.accent:SetColorTexture(0.25, 1, 0.45, 0.9)
			c.border:SetColor(0.25, 1, 0.45, 0.4)
		elseif e.weak then
			c.prio:Set(L.P_PRIORITY, 1, 0.6, 0.15)
			c.accent:SetColorTexture(1, 0.6, 0.15, 0.9)
			c.border:SetColor(1, 0.6, 0.15, 0.35)
		else
			c.prio:Set(nil)
			c.accent:SetColorTexture(sr, sg, sb, 0.6)
			c.border:SetColor(1, 1, 1, 0.1)
		end

		if mine and mine.timedLevel > 0 then c.next:SetText(L.P_NEXT_UP:format(e.next))
		elseif mine and mine.level > 0 then c.next:SetText(L.P_NEXT_TIME:format(e.next))
		else c.next:SetText(L.P_NEXT_START:format(e.next)) end

		local n = KF.lastSearch and KF.mapCounts and KF.mapCounts[m.id]
		c.go:SetText(n and L.P_FIND_N:format(n) or L.P_FIND)
	end
	for i = #list + 1, #pr.cards do pr.cards[i]:Hide() end
end

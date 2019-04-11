if select(2, UnitClass('player')) ~= 'MONK' then
	DisableAddOn('MonkSeeMonkDo')
	return
end

-- copy heavily accessed global functions into local scope for performance
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellCharges = _G.GetSpellCharges
local GetTime = _G.GetTime
local UnitCastingInfo = _G.UnitCastingInfo
local UnitAura = _G.UnitAura
-- end copy global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
   return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

MonkSeeMonkDo = {}
local Opt -- use this as a local table reference to MonkSeeMonkDo

SLASH_MonkSeeMonkDo1, SLASH_MonkSeeMonkDo2 = '/monk', '/msmd'
BINDING_HEADER_MSMD = 'MonkSeeMonkDo'

local function InitializeOpts()
	local function SetDefaults(t, ref)
		local k, v
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(MonkSeeMonkDo, { -- defaults
		locked = false,
		snap = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
			interrupt = 0.4,
			extra = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			extra = true,
			blizzard = false,
			color = { r = 1, g = 1, b = 1 },
		},
		hide = {
			brewmaster = false,
			mistweaver = false,
			windwalker = false
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		pot = false,
	})
end

-- specialization constants
local SPEC = {
	NONE = 0,
	BREWMASTER = 1,
	MISTWEAVER = 2,
	WINDWALKER = 3,
}

local events, glows = {}, {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

local currentSpec, currentForm, targetMode, combatStartTime = 0, 0, 0, 0

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false
}

-- list of previous GCD abilities
local PreviousGCD = {}

-- items equipped with special effects
local ItemEquipped = {
	Tier21 = 0,
	DrinkingHornCover = false,
	SalsalabimsLostTunic = false,
	StormstoutsLastGasp = false,
}

-- Azerite trait API access
local Azerite = {}

-- base mana for each level
local BaseMana = {
	145,        160,    175,    190,    205,    -- 5
	220,        235,    250,    290,    335,    -- 10
	390,        445,    510,    580,    735,    -- 15
	825,        865,    910,    950,    995,    -- 20
	1060,       1125,   1195,   1405,   1490,   -- 25
	1555,       1620,   1690,   1760,   1830,   -- 30
	2110,       2215,   2320,   2425,   2540,   -- 35
	2615,       2695,   3025,   3110,   3195,   -- 40
	3270,       3345,   3420,   3495,   3870,   -- 45
	3940,       4015,   4090,   4170,   4575,   -- 50
	4660,       4750,   4835,   5280,   5380,   -- 55
	5480,       5585,   5690,   5795,   6300,   -- 60
	6420,       6540,   6660,   6785,   6915,   -- 65
	7045,       7175,   7310,   7915,   8065,   -- 70
	8215,       8370,   8530,   8690,   8855,   -- 75
	9020,       9190,   9360,   10100,  10290,  -- 80
	10485,      10680,  10880,  11085,  11295,  -- 85
	11505,      11725,  12605,  12845,  13085,  -- 90
	13330,      13585,  13840,  14100,  14365,  -- 95
	14635,      15695,  15990,  16290,  16595,  -- 100
	16910,      17230,  17550,  17880,  18220,  -- 105
	18560,      18910,  19265,  19630,  20000,  -- 110
	35985,      42390,  48700,  54545,  59550,  -- 115
	64700,      68505,  72450,  77400,  100000  -- 120
}

local var = {
	gcd = 1.5,
	time_diff = 0,
	mana = 0,
	mana_base = 0,
	mana_max = 0,
	mana_regen = 0,
	energy = 0,
	energy_max = 100,
	energy_regen = 0,
	chi = 0,
	chi_max = 6,
	stagger = 0,
}

local msmdPanel = CreateFrame('Frame', 'msmdPanel', UIParent)
msmdPanel:SetPoint('CENTER', 0, -169)
msmdPanel:SetFrameStrata('BACKGROUND')
msmdPanel:SetSize(64, 64)
msmdPanel:SetMovable(true)
msmdPanel:Hide()
msmdPanel.icon = msmdPanel:CreateTexture(nil, 'BACKGROUND')
msmdPanel.icon:SetAllPoints(msmdPanel)
msmdPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
msmdPanel.border = msmdPanel:CreateTexture(nil, 'ARTWORK')
msmdPanel.border:SetAllPoints(msmdPanel)
msmdPanel.border:SetTexture('Interface\\AddOns\\MonkSeeMonkDo\\border.blp')
msmdPanel.border:Hide()
msmdPanel.text = msmdPanel:CreateFontString(nil, 'OVERLAY')
msmdPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
msmdPanel.text:SetTextColor(1, 1, 1, 1)
msmdPanel.text:SetAllPoints(msmdPanel)
msmdPanel.text:SetJustifyH('CENTER')
msmdPanel.text:SetJustifyV('CENTER')
msmdPanel.swipe = CreateFrame('Cooldown', nil, msmdPanel, 'CooldownFrameTemplate')
msmdPanel.swipe:SetAllPoints(msmdPanel)
msmdPanel.dimmer = msmdPanel:CreateTexture(nil, 'BORDER')
msmdPanel.dimmer:SetAllPoints(msmdPanel)
msmdPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
msmdPanel.dimmer:Hide()
msmdPanel.targets = msmdPanel:CreateFontString(nil, 'OVERLAY')
msmdPanel.targets:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
msmdPanel.targets:SetPoint('BOTTOMRIGHT', msmdPanel, 'BOTTOMRIGHT', -1.5, 3)
msmdPanel.button = CreateFrame('Button', 'msmdPanelButton', msmdPanel)
msmdPanel.button:SetAllPoints(msmdPanel)
msmdPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local msmdPreviousPanel = CreateFrame('Frame', 'msmdPreviousPanel', UIParent)
msmdPreviousPanel:SetFrameStrata('BACKGROUND')
msmdPreviousPanel:SetSize(64, 64)
msmdPreviousPanel:Hide()
msmdPreviousPanel:RegisterForDrag('LeftButton')
msmdPreviousPanel:SetScript('OnDragStart', msmdPreviousPanel.StartMoving)
msmdPreviousPanel:SetScript('OnDragStop', msmdPreviousPanel.StopMovingOrSizing)
msmdPreviousPanel:SetMovable(true)
msmdPreviousPanel.icon = msmdPreviousPanel:CreateTexture(nil, 'BACKGROUND')
msmdPreviousPanel.icon:SetAllPoints(msmdPreviousPanel)
msmdPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
msmdPreviousPanel.border = msmdPreviousPanel:CreateTexture(nil, 'ARTWORK')
msmdPreviousPanel.border:SetAllPoints(msmdPreviousPanel)
msmdPreviousPanel.border:SetTexture('Interface\\AddOns\\MonkSeeMonkDo\\border.blp')
local msmdCooldownPanel = CreateFrame('Frame', 'msmdCooldownPanel', UIParent)
msmdCooldownPanel:SetSize(64, 64)
msmdCooldownPanel:SetFrameStrata('BACKGROUND')
msmdCooldownPanel:Hide()
msmdCooldownPanel:RegisterForDrag('LeftButton')
msmdCooldownPanel:SetScript('OnDragStart', msmdCooldownPanel.StartMoving)
msmdCooldownPanel:SetScript('OnDragStop', msmdCooldownPanel.StopMovingOrSizing)
msmdCooldownPanel:SetMovable(true)
msmdCooldownPanel.icon = msmdCooldownPanel:CreateTexture(nil, 'BACKGROUND')
msmdCooldownPanel.icon:SetAllPoints(msmdCooldownPanel)
msmdCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
msmdCooldownPanel.border = msmdCooldownPanel:CreateTexture(nil, 'ARTWORK')
msmdCooldownPanel.border:SetAllPoints(msmdCooldownPanel)
msmdCooldownPanel.border:SetTexture('Interface\\AddOns\\MonkSeeMonkDo\\border.blp')
msmdCooldownPanel.cd = CreateFrame('Cooldown', nil, msmdCooldownPanel, 'CooldownFrameTemplate')
msmdCooldownPanel.cd:SetAllPoints(msmdCooldownPanel)
local msmdInterruptPanel = CreateFrame('Frame', 'msmdInterruptPanel', UIParent)
msmdInterruptPanel:SetFrameStrata('BACKGROUND')
msmdInterruptPanel:SetSize(64, 64)
msmdInterruptPanel:Hide()
msmdInterruptPanel:RegisterForDrag('LeftButton')
msmdInterruptPanel:SetScript('OnDragStart', msmdInterruptPanel.StartMoving)
msmdInterruptPanel:SetScript('OnDragStop', msmdInterruptPanel.StopMovingOrSizing)
msmdInterruptPanel:SetMovable(true)
msmdInterruptPanel.icon = msmdInterruptPanel:CreateTexture(nil, 'BACKGROUND')
msmdInterruptPanel.icon:SetAllPoints(msmdInterruptPanel)
msmdInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
msmdInterruptPanel.border = msmdInterruptPanel:CreateTexture(nil, 'ARTWORK')
msmdInterruptPanel.border:SetAllPoints(msmdInterruptPanel)
msmdInterruptPanel.border:SetTexture('Interface\\AddOns\\MonkSeeMonkDo\\border.blp')
msmdInterruptPanel.cast = CreateFrame('Cooldown', nil, msmdInterruptPanel, 'CooldownFrameTemplate')
msmdInterruptPanel.cast:SetAllPoints(msmdInterruptPanel)
local msmdExtraPanel = CreateFrame('Frame', 'msmdExtraPanel', UIParent)
msmdExtraPanel:SetFrameStrata('BACKGROUND')
msmdExtraPanel:SetSize(64, 64)
msmdExtraPanel:Hide()
msmdExtraPanel:RegisterForDrag('LeftButton')
msmdExtraPanel:SetScript('OnDragStart', msmdExtraPanel.StartMoving)
msmdExtraPanel:SetScript('OnDragStop', msmdExtraPanel.StopMovingOrSizing)
msmdExtraPanel:SetMovable(true)
msmdExtraPanel.icon = msmdExtraPanel:CreateTexture(nil, 'BACKGROUND')
msmdExtraPanel.icon:SetAllPoints(msmdExtraPanel)
msmdExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
msmdExtraPanel.border = msmdExtraPanel:CreateTexture(nil, 'ARTWORK')
msmdExtraPanel.border:SetAllPoints(msmdExtraPanel)
msmdExtraPanel.border:SetTexture('Interface\\AddOns\\MonkSeeMonkDo\\border.blp')

-- Start Auto AoE

local targetModes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.BREWMASTER] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	},
	[SPEC.MISTWEAVER] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	},
	[SPEC.WINDWALKER] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	},
}

local function SetTargetMode(mode)
	if mode == targetMode then
		return
	end
	targetMode = min(mode, #targetModes[currentSpec])
	var.enemy_count = targetModes[currentSpec][targetMode][1]
	msmdPanel.targets:SetText(targetModes[currentSpec][targetMode][2])
end
MonkSeeMonkDo_SetTargetMode = SetTargetMode

function ToggleTargetMode()
	local mode = targetMode + 1
	SetTargetMode(mode > #targetModes[currentSpec] and 1 or mode)
end
MonkSeeMonkDo_ToggleTargetMode = ToggleTargetMode

local function ToggleTargetModeReverse()
	local mode = targetMode - 1
	SetTargetMode(mode < 1 and #targetModes[currentSpec] or mode)
end
MonkSeeMonkDo_ToggleTargetModeReverse = ToggleTargetModeReverse

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		['120651'] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local _, _, _, _, _, unitId = strsplit('-', guid)
	if unitId and self.ignored_units[unitId] then
		self.blacklist[guid] = var.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = var.time
	if update and new then
		self:update()
	end
end

function autoAoe:remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = var.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:update()
	end
end

function autoAoe:clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		SetTargetMode(1)
		return
	end
	var.enemy_count = count
	for i = #targetModes[currentSpec], 1, -1 do
		if count >= targetModes[currentSpec][i][1] then
			SetTargetMode(i)
			var.enemy_count = count
			return
		end
	end
end

function autoAoe:purge()
	local update, guid, t
	for guid, t in next, self.targets do
		if var.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if var.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability.add(spellId, buff, player, spellId2)
	local ability = {
		spellId = spellId,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		mana_cost = 0,
		energy_cost = 0,
		chi_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		velocity = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, Ability)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function Ability:usable()
	if not self.known then
		return false
	end
	if currentSpec == SPEC.MISTWEAVER then
		if self:manaCost() > var.mana then
			return false
		end
	else
		if self:energyCost() > var.energy then
			return false
		end
		if currentSpec == SPEC.WINDWALKER and self:chiCost() > var.chi then
			return false
		end
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	return self:ready()
end

function Ability:remains()
	if self:traveling() then
		return self:duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - var.time - var.execute_remains, 0)
		end
	end
	return 0
end

function Ability:refreshable()
	if self.buff_duration > 0 then
		return self:remains() < self:duration() * 0.3
	end
	return self:down()
end

function Ability:up()
	if self:traveling() or self:casting() then
		return true
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return false
		end
		if self:match(id) then
			return expires == 0 or expires - var.time > var.execute_remains
		end
	end
end

function Ability:down()
	return not self:up()
end

function Ability:setVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if var.time - self.travel_start[Target.guid] < 40 / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - (var.time - var.time_diff) > var.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:up() and 1 or 0
end

function Ability:cooldownDuration()
	return self.hasted_cooldown and (var.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (var.time - start) - var.execute_remains)
end

function Ability:stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			return (expires == 0 or expires - var.time > var.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:chiCost()
	return self.chi_cost
end

function Ability:manaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * var.mana_base) or 0
end

function Ability:energyCost()
	return self.energy_cost
end

function Ability:charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:chargesFractional()
	local charges, maxCharges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= maxCharges then
		return charges
	end
	return charges + ((max(0, var.time - recharge_start + var.execute_remains)) / recharge_time)
end

function Ability:fullRechargeTime()
	local charges, maxCharges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= maxCharges then
		return 0
	end
	return (maxCharges - charges - 1) * recharge_time + (recharge_time - (var.time - recharge_start) - var.execute_remains)
end

function Ability:maxCharges()
	local _, maxCharges = GetSpellCharges(self.spellId)
	return maxCharges or 0
end

function Ability:duration()
	return self.hasted_duration and (var.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return var.ability_casting == self
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and var.gcd or 0
	end
	return castTime / 1000
end

function Ability:tickTime()
	return self.hasted_ticks and (var.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:previous()
	if self:casting() or self:channeling() then
		return true
	end
	return PreviousGCD[1] == self or var.last_ability == self
end

function Ability:combo()
	return self.triggers_combo and var.last_combo_ability ~= self
end

function Ability:azeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:autoAoe(removeUnaffected)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {}
	}
end

function Ability:recordTargetHit(guid)
	self.auto_aoe.targets[guid] = var.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:updateTargetsHit()
	if self.auto_aoe.start_time and var.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:clear()
		end
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:purge()
	local now = var.time - var.time_diff
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= now then
				ability:removeAura(guid)
			end
		end
	end
end

function trackAuras:remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:removeAura(guid)
	end
end

function Ability:trackAuras()
	self.aura_targets = {}
end

function Ability:applyAura(timeStamp, guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = timeStamp + self:duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:refreshAura(timeStamp, guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(timeStamp, guid)
		return
	end
	local remains = aura.expires - timeStamp
	local duration = self:duration()
	aura.expires = timeStamp + min(duration * 1.3, remains + duration)
end

function Ability:removeAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Monk Abilities
---- Multiple Specializations
local Resuscitate = Ability.add(115178)
local SpearHandStrike = Ability.add(116705, false, true)
SpearHandStrike.cooldown_duration = 15
SpearHandStrike.triggers_gcd = false
------ Talents
local HealingElixir = Ability.add(122281, true, true)
HealingElixir.cooldown_duration = 30
HealingElixir.requires_charge = true
------ Procs
---- Brewmaster
local BlackoutStrike = Ability.add(205523, false, true)
BlackoutStrike.cooldown_duration = 3
local BreathOfFire = Ability.add(115181, false, true, 123725)
BreathOfFire.cooldown_duration = 15
BreathOfFire.buff_duration = 16
BreathOfFire:autoAoe(true)
local ExpelHarm = Ability.add(115072, true, true)
ExpelHarm.energy_cost = 15
ExpelHarm.requires_charge = true
local IronskinBrew = Ability.add(115308, true, true)
IronskinBrew.hasted_cooldown = true
IronskinBrew.cooldown_duration = 15
IronskinBrew.buff_duration = 7
IronskinBrew.triggers_gcd = false
local KegSmash = Ability.add(121253, false, true)
KegSmash.hasted_cooldown = true
KegSmash.cooldown_duration = 8
KegSmash.buff_duration = 15
KegSmash.energy_cost = 40
KegSmash:autoAoe(true)
local PurifyingBrew = Ability.add(119582, true, true)
PurifyingBrew.hasted_cooldown = true
PurifyingBrew.cooldown_duration = 15
PurifyingBrew.triggers_gcd = false
local Stagger = Ability.add(115069, false, true)
Stagger.auraTarget = 'player'
Stagger.tick_interval = 0.5
Stagger.buff_duration = 10
local TigerPalmBM = Ability.add(100780, false, true)
TigerPalmBM.energy_cost = 25
------ Talents
local BlackoutCombo = Ability.add(196736, true, true, 228563)
BlackoutCombo.buff_duration = 15
local BlackOxBrew = Ability.add(115399, false, false)
BlackOxBrew.cooldown_duration = 90
BlackOxBrew.triggers_gcd = false
local InvokeNiuzaoTheBlackOx = Ability.add(132578, true, true)
InvokeNiuzaoTheBlackOx.cooldown_duration = 180
InvokeNiuzaoTheBlackOx.buff_duration = 45
local LightBrewing = Ability.add(196721, false, true)
local RushingJadeWindBM = Ability.add(116847, true, true, 148187)
RushingJadeWindBM.buff_duration = 9
RushingJadeWindBM.cooldown_duration = 6
RushingJadeWindBM.hasted_duration = true
RushingJadeWindBM.hasted_cooldown = true
RushingJadeWindBM:autoAoe(true)
local SpecialDelivery = Ability.add(196730, false, true)
------ Procs
local ElusiveBrawler = Ability.add(195630, true, true)
ElusiveBrawler.buff_duration = 10
---- Mistweaver

------ Talents

------ Procs

---- Windwalker
local BlackoutKick = Ability.add(100784, false, true)
BlackoutKick.chi_cost = 1
BlackoutKick.triggers_combo = true
local CracklingJadeLightning = Ability.add(117952, false, true)
CracklingJadeLightning.energy_cost = 20
CracklingJadeLightning.triggers_combo = true
local Disable = Ability.add(116095, false, true)
Disable.energy_cost = 15
local FistsOfFury = Ability.add(113656, false, true, 117418)
FistsOfFury.chi_cost = 3
FistsOfFury.buff_duration = 4
FistsOfFury.cooldown_duration = 24
FistsOfFury.hasted_duration = true
FistsOfFury.hasted_cooldown = true
FistsOfFury.triggers_combo = true
FistsOfFury:autoAoe()
local FlyingSerpentKick = Ability.add(101545, false, false, 123586)
FlyingSerpentKick.cooldown_duration = 25
FlyingSerpentKick.triggers_combo = true
FlyingSerpentKick:autoAoe()
local MarkOfTheCrane = Ability.add(228287, false, true)
MarkOfTheCrane.buff_duration = 15
local RisingSunKick = Ability.add(107428, false, true, 185099)
RisingSunKick.chi_cost = 2
RisingSunKick.cooldown_duration = 10
RisingSunKick.hasted_cooldown = true
RisingSunKick.triggers_combo = true
local SpinningCraneKick = Ability.add(101546, true, true, 107270)
SpinningCraneKick.chi_cost = 3
SpinningCraneKick.buff_duration = 1.5
SpinningCraneKick.hasted_duration = true
SpinningCraneKick.triggers_combo = true
SpinningCraneKick:autoAoe(true)
local StormEarthAndFire = Ability.add(137639, true, true)
StormEarthAndFire.buff_duration = 15
StormEarthAndFire.cooldown_duration = 90
StormEarthAndFire.requires_charge = true
local TigerPalm = Ability.add(100780, false, true)
TigerPalm.chi_cost = -2
TigerPalm.energy_cost = 50
TigerPalm.triggers_combo = true
local TouchOfDeath = Ability.add(115080, false, true)
TouchOfDeath.cooldown_duration = 120
TouchOfDeath.buff_duration = 8
TouchOfDeath.triggers_combo = true
local TouchOfKarma = Ability.add(122470, true, true, 125174)
TouchOfKarma.cooldown_duration = 90
TouchOfKarma.triggers_gcd = false
TouchOfKarma.buff_duration = 10
------ Talents
local ChiBurst = Ability.add(123986, false, true, 148135)
ChiBurst.cooldown_duration = 30
ChiBurst.triggers_combo = true
ChiBurst:autoAoe()
local ChiWave = Ability.add(115098, false, true)
ChiWave.cooldown_duration = 15
ChiWave.triggers_combo = true
local EnergizingElixir = Ability.add(115288, false, true)
EnergizingElixir.cooldown_duration = 60
local FistOfTheWhiteTiger = Ability.add(261947, false, true, 261977)
FistOfTheWhiteTiger.cooldown_duration = 24
FistOfTheWhiteTiger.energy_cost = 40
FistOfTheWhiteTiger.chi_cost = -3
FistOfTheWhiteTiger.triggers_combo = true
local HitCombo = Ability.add(196740, true, true, 196741)
HitCombo.buff_duration = 10
local InvokeXuenTheWhiteTiger = Ability.add(123904, false, true)
InvokeXuenTheWhiteTiger.cooldown_duration = 180
InvokeXuenTheWhiteTiger.buff_duration = 45
local LegSweep = Ability.add(119381, false, true)
LegSweep.cooldown_duration = 60
local RushingJadeWind = Ability.add(116847, true, true)
RushingJadeWind.chi_cost = 1
RushingJadeWind.buff_duration = 6
RushingJadeWind.cooldown_duration = 6
RushingJadeWind.hasted_duration = true
RushingJadeWind.hasted_cooldown = true
RushingJadeWind.triggers_combo = true
local Serenity = Ability.add(152173, true, true)
Serenity.cooldown_duration = 90
Serenity.buff_duration = 12
local WhirlingDragonPunch = Ability.add(152175, false, true, 158221)
WhirlingDragonPunch.cooldown_duration = 24
WhirlingDragonPunch.hasted_cooldown = true
WhirlingDragonPunch.triggers_combo = true
WhirlingDragonPunch:autoAoe(true)
------ Procs
local BlackoutKickProc = Ability.add(116768, true, true)
BlackoutKickProc.buff_duration = 15
-- Azerite Traits
local DanceOfChiJi = Ability.add(286585, true, true, 286587)
DanceOfChiJi.buff_duration = 15
local SwiftRoundhouse = Ability.add(277669, true, true, 278710)
SwiftRoundhouse.buff_duration = 12
-- Racials
local ArcaneTorrent = Ability.add(129597, true, false) -- Blood Elf
-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems = {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem.add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon
	}
	setmetatable(item, InventoryItem)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		charges = max(charges, self.maxCharges)
	end
	return charges
end

function InventoryItem:count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:cooldown()
	local startTime, duration = GetItemCooldown(self.itemId)
	return startTime == 0 and 0 or duration - (var.time - startTime)
end

function InventoryItem:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function InventoryItem:usable(seconds)
	if self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

-- Inventory Items
local FlaskOfTheCurrents = InventoryItem.add(152638)
FlaskOfTheCurrents.buff = Ability.add(251836, true, true)
local FlaskOfEndlessFathoms = InventoryItem.add(152693)
FlaskOfEndlessFathoms.buff = Ability.add(251837, true, true)
local BattlePotionOfAgility = InventoryItem.add(163223)
BattlePotionOfAgility.buff = Ability.add(279152, true, true)
BattlePotionOfAgility.buff.triggers_gcd = false
local BattlePotionOfIntellect = InventoryItem.add(163222)
BattlePotionOfIntellect.buff = Ability.add(279151, true, true)
BattlePotionOfIntellect.buff.triggers_gcd = false
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:initialize()
	self.locations = {}
	self.traits = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:update()
	local _, loc, tinfo, tslot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			tinfo = C_AzeriteEmpoweredItem.GetAllTierInfo(loc)
			for _, tslot in next, tinfo do
				if tslot.azeritePowerIDs then
					for _, pid in next, tslot.azeritePowerIDs do
						if C_AzeriteEmpoweredItem.IsPowerSelected(loc, pid) then
							self.traits[pid] = 1 + (self.traits[pid] or 0)
							pinfo = C_AzeriteEmpoweredItem.GetPowerInfo(pid)
							if pinfo and pinfo.spellID then
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
end

-- End Azerite Trait API

-- Start Helpful Functions

local function Health()
	return var.health
end

local function HealthMax()
	return var.health_max
end

local function HealthPct()
	return var.health / var.health_max * 100
end

local function Chi()
	return var.chi
end

local function ChiDeficit()
	return var.chi_max - var.chi
end

local function Energy()
	return var.energy
end

local function EnergyMax()
	return var.energy_max
end

local function EnergyDeficit()
	return var.energy_max - var.energy
end

local function EnergyRegen()
	return var.energy_regen
end

local function EnergyTimeToMax()
	local deficit = var.energy_max - var.energy
	if deficit <= 0 then
		return 0
	end
	return deficit / var.energy_regen
end

local function HasteFactor()
	return var.haste_factor
end

local function GCD()
	return var.gcd
end

local function Enemies()
	return var.enemy_count
end

local function TimeInCombat()
	if combatStartTime > 0 then
		return var.time - combatStartTime
	end
	return 0
end

local function BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Druid Pet - Core Hound)
			id == 160452 or -- Netherwinds (Druid Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Druid Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

local function TargetIsStunnable()
	if Target.player then
		return true
	end
	if Target.boss then
		return false
	end
	if var.instance == 'raid' then
		return false
	end
	if Target.healthMax > var.health_max * 10 then
		return false
	end
	return true
end

-- End Helpful Functions

-- Start Ability Modifications

function Ability:chiCost()
	if self.chi_cost > 0 and Serenity:up() then
		return 0
	end
	return self.chi_cost
end

function BlackoutKick:chiCost()
	if BlackoutKickProc:up() then
		return 0
	end
	return Ability.chiCost(self)
end

function SpinningCraneKick:chiCost()
	if DanceOfChiJi:up() then
		return 0
	end
	return Ability.chiCost(self)
end

function WhirlingDragonPunch:usable()
	if FistsOfFury:ready() or RisingSunKick:ready() then
		return false
	end
	return Ability.usable(self)
end

function Stagger:remains()
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == 124273 or id == 124274 or id == 124275 then
			return max(0, expires - var.time)
		end
	end
	return 0
end

function Stagger:ticks_remaining()
	local remains = self:remains()
	if remains <= 0 then
		return 0
	end
	return ceil(remains / self.tick_interval)
end

function Stagger:tick()
	if var.stagger <= 0 then
		return 0
	end
	return var.stagger / max(1, self:ticks_remaining() + (combatStartTime > 0 and -1 or 1))
end

function Stagger:tick_pct()
	return self:tick() / var.health * 100
end

function Stagger:light()
	return self:tick_pct() < 3.5
end

function Stagger:moderate()
	local pct = self:tick_pct()
	return between(pct, 3.5, 6.5)
end

function Stagger:heavy()
	return self:tick_pct() > 6.5
end

function PurifyingBrew:duration()
	local duration = Ability.duration(self)
	if LightBrewing.known then
		duration = duration - 3
	end
	return duration
end
IronskinBrew.duration = PurifyingBrew.duration

-- End Ability Modifications

local function UseCooldown(ability, overwrite, always)
	if always or (Opt.cooldown and (not Opt.boss_only or Target.boss) and (not var.cd or overwrite)) then
		var.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not var.extra or overwrite then
		var.extra = ability
	end
end

local function Pool(ability, extra)
	var.pool_energy = ability:energyCost() + (extra or 0)
	return ability
end

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.BREWMASTER] = {},
	[SPEC.MISTWEAVER] = {},
	[SPEC.WINDWALKER] = {},
}

APL[SPEC.BREWMASTER].main = function(self)
	if TimeInCombat() == 0 then
		if ChiBurst:usable() then
			UseCooldown(ChiBurst)
		end
		if RushingJadeWindBM:usable() and RushingJadeWindBM:down() then
			return RushingJadeWindBM
		end
		if ChiWave:usable() then
			return ChiWave
		end
	end
--[[
actions+=/invoke_niuzao_the_black_ox,if=target.time_to_die>25
# Ironskin Brew priority whenever it took significant damage and ironskin brew buff is missing (adjust the health.max coefficient according to intensity of damage taken), and to dump excess charges before BoB.
actions+=/ironskin_brew,if=buff.blackout_combo.down&incoming_damage_1999ms>(health.max*0.1+stagger.last_tick_damage_4)&buff.elusive_brawler.stack<2&!buff.ironskin_brew.up
actions+=/ironskin_brew,if=cooldown.brews.charges_fractional>1&cooldown.black_ox_brew.remains<3
# Purifying behaviour is based on normalization (iE the late expression triggers if stagger size increased over the last 30 ticks or 15 seconds).
actions+=/purifying_brew,if=stagger.pct>(6*(3-(cooldown.brews.charges_fractional)))&(stagger.last_tick_damage_1>((0.02+0.001*(3-cooldown.brews.charges_fractional))*stagger.last_tick_damage_30))
# Black Ox Brew is currently used to either replenish brews based on less than half a brew charge available, or low energy to enable Keg Smash
actions+=/black_ox_brew,if=cooldown.brews.charges_fractional<0.5
actions+=/black_ox_brew,if=(energy+(energy.regen*cooldown.keg_smash.remains))<40&buff.blackout_combo.down&cooldown.keg_smash.up
# Offensively, the APL prioritizes KS on cleave, BoS else, with energy spenders and cds sorted below
actions+=/keg_smash,if=spell_targets>=2
actions+=/tiger_palm,if=talent.rushing_jade_wind.enabled&buff.blackout_combo.up&buff.rushing_jade_wind.up
actions+=/tiger_palm,if=(talent.invoke_niuzao_the_black_ox.enabled|talent.special_delivery.enabled)&buff.blackout_combo.up
actions+=/blackout_strike
actions+=/keg_smash
actions+=/rushing_jade_wind,if=buff.rushing_jade_wind.down
actions+=/breath_of_fire,if=buff.blackout_combo.down&(buff.bloodlust.down|(buff.bloodlust.up&&dot.breath_of_fire_dot.refreshable))
actions+=/chi_burst
actions+=/chi_wave
actions+=/tiger_palm,if=!talent.blackout_combo.enabled&cooldown.keg_smash.remains>gcd&(energy+(energy.regen*(cooldown.keg_smash.remains+gcd)))>=65
actions+=/arcane_torrent,if=energy<31
actions+=/rushing_jade_wind
]]
	if InvokeNiuzaoTheBlackOx:usable() and Target.timeToDie > 25 then
		UseCooldown(InvokeNiuzaoTheBlackOx)
	elseif ExpelHarm:usable() and HealthPct() < 40 and ExpelHarm:charges() >= 3 then
		UseCooldown(ExpelHarm)
	elseif HealingElixir:usable() and (HealthPct() < 60 or (HealthPct() < 80 and HealingElixir:chargesFractional() > 1.5)) then
		UseCooldown(HealingElixir)
	end
	if PurifyingBrew:usable() and (Stagger:heavy() or (Stagger:moderate() and PurifyingBrew:chargesFractional() >= (PurifyingBrew:maxCharges() - 0.5) and IronskinBrew:remains() >= IronskinBrew:duration() * 2.5)) then
		UseExtra(PurifyingBrew)
	end
	if IronskinBrew:usable() and BlackoutCombo:down() and ElusiveBrawler:stack() < 2 and IronskinBrew:chargesFractional() >= (IronskinBrew:up() and (IronskinBrew:maxCharges() - 0.5) or 1.5) and IronskinBrew:remains() < IronskinBrew:duration() * 2 then
		UseExtra(IronskinBrew)
	end
	if BlackOxBrew:usable() then
		if Stagger:heavy() and PurifyingBrew:chargesFractional() <= 0.5 then
			UseCooldown(BlackOxBrew)
		elseif (Energy() + (EnergyRegen() * KegSmash:cooldown())) < 40 and BlackoutCombo:down() and KegSmash:ready() then
			UseCooldown(BlackOxBrew)
		end
	end
	if KegSmash:usable() then
		if ItemEquipped.StormstoutsLastGasp then
			if KegSmash:charges() == 2 then
				return KegSmash
			end
		elseif Enemies() >= 2 then
			return KegSmash
		end
	end
	if BlackoutCombo.known and TigerPalmBM:usable() and BlackoutCombo:up() then
		if RushingJadeWindBM.known and RushingJadeWindBM:up() then
			return TigerPalmBM
		end
		if InvokeNiuzaoTheBlackOx.known or SpecialDelivery.known then
			return TigerPalmBM
		end
	end
	if ItemEquipped.SalsalabimsLostTunic and Enemies() >= 2 and BreathOfFire:usable() and KegSmash:ready(GCD()) and KegSmash:ticking() > 0 then
		return BreathOfFire
	end
	if ItemEquipped.StormstoutsLastGasp and KegSmash:chargesFractional() > 1.75 then
		return KegSmash
	end
	if BlackoutStrike:usable() then
		return BlackoutStrike
	end
	if not ItemEquipped.StormstoutsLastGasp and KegSmash:usable() then
		return KegSmash
	end
	if RushingJadeWindBM:usable() and RushingJadeWindBM:down() then
		return RushingJadeWindBM
	end
	if ExpelHarm:usable() and HealthPct() < 70 and ExpelHarm:charges() >= 5 then
		UseCooldown(ExpelHarm)
	end
	if BreathOfFire:usable() and BlackoutCombo:down() and KegSmash:ticking() > 0 and (Enemies() >= 2 or BreathOfFire:refreshable()) then
		return BreathOfFire
	end
	if RushingJadeWindBM:usable() and RushingJadeWindBM:remains() < 1.5 and (Enemies() > 1 or Target.timeToDie > 3) then
		return RushingJadeWindBM
	end
	if ChiBurst:usable() then
		UseCooldown(ChiBurst)
	end
	if ChiWave:usable() then
		return ChiWave
	end
	if not ItemEquipped.StormstoutsLastGasp and KegSmash:ready(0.5) and (Enemies() >= 2 or KegSmash:cooldown() < BlackoutStrike:cooldown()) then
		return Pool(KegSmash)
	end
	if BlackoutStrike:ready(0.5) then
		return BlackoutStrike
	end
	if ItemEquipped.SalsalabimsLostTunic and KegSmash:usable() then
		return KegSmash
	end
	if not BlackoutCombo.known and TigerPalmBM:usable() and (Energy() + (EnergyRegen() * (KegSmash:cooldown() + GCD()))) >= 75 then
		return TigerPalmBM
	end
	if ExpelHarm:usable() and HealthPct() < 80 and ExpelHarm:charges() >= 3 then
		UseCooldown(ExpelHarm)
	end
	if RushingJadeWindBM:usable() and (Enemies() > 1 or Target.timeToDie > (RushingJadeWindBM:remains() + 2)) then
		return RushingJadeWindBM
	end
	if BreathOfFire:usable() and BlackoutCombo:down() and KegSmash:ticking() > 0 then
		return BreathOfFire
	end
	if ArcaneTorrent:usable() and Energy() < 31 then
		UseCooldown(ArcaneTorrent)
	end
end

APL[SPEC.MISTWEAVER].main = function(self)

end

APL[SPEC.WINDWALKER].main = function(self)
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/potion
actions.precombat+=/chi_burst,if=(!talent.serenity.enabled|!talent.fist_of_the_white_tiger.enabled)
actions.precombat+=/chi_wave

]]
	if TimeInCombat() == 0 then
		if Opt.pot and not InArenaOrBattleground() then
			if FlaskOfTheCurrents:usable() and FlaskOfTheCurrents.buff:remains() < 300 then
				UseCooldown(FlaskOfTheUndertow)
			end
			if BattlePotionOfAgility:usable() then
				UseCooldown(BattlePotionOfAgility)
			end
		end
		if ChiBurst:usable() and not (Serenity.known or FistOfTheWhiteTiger.known) then
			return ChiBurst
		end
		if ChiWave:usable() then
			return ChiWave
		end
		if FlyingSerpentKick:usable() then
			UseCooldown(FlyingSerpentKick)
		end
	end
--[[
# Touch of Karma on cooldown, if Good Karma is enabled equal to 100% of maximum health
actions+=/touch_of_karma,interval=90,pct_health=0.5
# Potion if Serenity or Storm, Earth, and Fire are up or you are running serenity and a main stat trinket procs, or you are under the effect of bloodlust, or target time to die is greater or equal to 60
actions+=/potion,if=buff.serenity.up|buff.storm_earth_and_fire.up|(!talent.serenity.enabled&trinket.proc.agility.react)|buff.bloodlust.react|target.time_to_die<=60
actions+=/call_action_list,name=serenity,if=buff.serenity.up
actions+=/fist_of_the_white_tiger,if=(energy.time_to_max<1|(talent.serenity.enabled&cooldown.serenity.remains<2))&chi.max-chi>=3
actions+=/tiger_palm,target_if=min:debuff.mark_of_the_crane.remains,if=(energy.time_to_max<1|(talent.serenity.enabled&cooldown.serenity.remains<2))&chi.max-chi>=2&!prev_gcd.1.tiger_palm
actions+=/call_action_list,name=cd
# Call the ST action list if there are 2 or less enemies
actions+=/call_action_list,name=st,if=active_enemies<3
# Call the AoE action list if there are 3 or more enemies
actions+=/call_action_list,name=aoe,if=active_enemies>=3
]]
	if Opt.pot and BattlePotionOfAgility:usable() and (Serenity:up() or StormEarthAndFire:up() or BloodlustActive() or Target.timeToDie <= 60) then
		UseCooldown(BattlePotionOfAgility)
	end
	if Serenity.known and Serenity:up() then
		local apl = self:serenity()
		if apl then return apl end
	end
	if FistOfTheWhiteTiger:usable() and ChiDeficit() >= 3 and (EnergyTimeToMax() < 1 or (Serenity.known and Serenity:ready(2)))  then
		return FistOfTheWhiteTiger
	end
	if TigerPalm:usable() and TigerPalm:combo() and ChiDeficit() >= 2 and (EnergyTimeToMax() < 1 or (Serenity.known and Serenity:ready(2))) then
		return TigerPalm
	end
	self:cd()
	if Enemies() >= 3 then
		local apl = self:aoe()
		if apl then return apl end
	end
	return self:st()
end

APL[SPEC.WINDWALKER].serenity = function(self)
--[[
# Serenity priority
actions.serenity=rising_sun_kick,target_if=min:debuff.mark_of_the_crane.remains,if=active_enemies<3|prev_gcd.1.spinning_crane_kick
actions.serenity+=/fists_of_fury,if=(buff.bloodlust.up&prev_gcd.1.rising_sun_kick)|buff.serenity.remains<1|(active_enemies>1&active_enemies<5)
actions.serenity+=/spinning_crane_kick,if=!prev_gcd.1.spinning_crane_kick&(active_enemies>=3|(active_enemies=2&prev_gcd.1.blackout_kick))
actions.serenity+=/blackout_kick,target_if=min:debuff.mark_of_the_crane.remains
]]
	if RisingSunKick:usable() and RisingSunKick:combo() and (Enemies() < 3 or SpinningCraneKick:previous()) then
		return RisingSunKick
	end
	if FistsOfFury:usable() and ((BloodlustActive() and RisingSunKick:previous()) or Serenity:remains() < 1 or between(Enemies(), 2, 4)) then
		return FistsOfFury
	end
	if SpinningCraneKick:usable() and SpinningCraneKick:combo() and Enemies() >= (BlackoutKick:previous() and 2 or 3) then
		return SpinningCraneKick
	end
	if BlackoutKick:usable() and BlackoutKick:combo() then
		return BlackoutKick
	end
end

APL[SPEC.WINDWALKER].cd = function(self)
--[[
# Cooldowns
actions.cd=invoke_xuen_the_white_tiger
actions.cd+=/use_item,name=variable_intensity_gigavolt_oscillating_reactor
actions.cd+=/blood_fury
actions.cd+=/berserking
# Use Arcane Torrent if you are missing at least 1 Chi and won't cap energy within 0.5 seconds
actions.cd+=/arcane_torrent,if=chi.max-chi>=1&energy.time_to_max>=0.5
actions.cd+=/lights_judgment
actions.cd+=/fireblood
actions.cd+=/ancestral_call
actions.cd+=/touch_of_death,if=target.time_to_die>9
actions.cd+=/storm_earth_and_fire,if=cooldown.storm_earth_and_fire.charges=2|(cooldown.fists_of_fury.remains<=6&chi>=3&cooldown.rising_sun_kick.remains<=1)|target.time_to_die<=15
actions.cd+=/serenity,if=cooldown.rising_sun_kick.remains<=2|target.time_to_die<=12
]]
	if InvokeXuenTheWhiteTiger:usable() then
		UseCooldown(InvokeXuenTheWhiteTiger)
	end
	if ArcaneTorrent:usable() and ChiDeficit() >= 1 and EnergyTimeToMax() >= 0.5 and (not Serenity.known or Serenity:down()) and (RisingSunKick:ready(1) or FistsOfFury:ready(1)) then
		UseExtra(ArcaneTorrent)
	end
	if TouchOfDeath:usable() and TouchOfDeath:combo() and TouchOfDeath:down() and Target.timeToDie > 9 then
		UseExtra(TouchOfDeath)
	end
	if StormEarthAndFire:usable() and (Target.timeToDie <= 15 or StormEarthAndFire:charges() >= 2 or (FistsOfFury:ready(6) and Chi() >= 3 and RisingSunKick:ready(1))) then
		UseCooldown(StormEarthAndFire)
	end
	if Serenity:usable() and (Target.timeToDie <= 12 or RisingSunKick:ready(2)) then
		UseCooldown(Serenity)
	end
end

APL[SPEC.WINDWALKER].st = function(self)
--[[
actions.st=whirling_dragon_punch
actions.st+=/rising_sun_kick,target_if=min:debuff.mark_of_the_crane.remains,if=chi>=5
actions.st+=/fists_of_fury,if=energy.time_to_max>3
actions.st+=/rising_sun_kick,target_if=min:debuff.mark_of_the_crane.remains
actions.st+=/spinning_crane_kick,if=!prev_gcd.1.spinning_crane_kick&buff.dance_of_chiji.up
actions.st+=/rushing_jade_wind,if=buff.rushing_jade_wind.down&active_enemies>1
actions.st+=/fist_of_the_white_tiger,if=chi<=2
actions.st+=/energizing_elixir,if=chi<=3&energy<50
actions.st+=/blackout_kick,target_if=min:debuff.mark_of_the_crane.remains,if=!prev_gcd.1.blackout_kick&(cooldown.rising_sun_kick.remains>3|chi>=3)&(cooldown.fists_of_fury.remains>4|chi>=4|(chi=2&prev_gcd.1.tiger_palm))&buff.swift_roundhouse.stack<2
actions.st+=/chi_wave
actions.st+=/chi_burst,if=chi.max-chi>=1&active_enemies=1|chi.max-chi>=2
actions.st+=/tiger_palm,target_if=min:debuff.mark_of_the_crane.remains,if=!prev_gcd.1.tiger_palm&chi.max-chi>=2
actions.st+=/flying_serpent_kick,if=prev_gcd.1.blackout_kick&chi>3&buff.swift_roundhouse.stack<2,interrupt=1
]]
	if WhirlingDragonPunch:usable() then
		return WhirlingDragonPunch
	end
	if RisingSunKick:usable() and RisingSunKick:combo() and Chi() >= 5 then
		return RisingSunKick
	end
	if FistsOfFury:usable() and EnergyTimeToMax() > 3 then
		return FistsOfFury
	end
	if RisingSunKick:usable() and RisingSunKick:combo() then
		return RisingSunKick
	end
	if DanceOfChiJi.known and SpinningCraneKick:usable() and SpinningCraneKick:combo() and DanceOfChiJi:up() then
		return SpinningCraneKick
	end
	if RushingJadeWind:usable() and RushingJadeWind:combo() and Enemies() > 1 then
		return RushingJadeWind
	end
	if FistOfTheWhiteTiger:usable() and Chi() <= 2 then
		return FistOfTheWhiteTiger
	end
	if EnergizingElixir:usable() and Chi() <= 3 and Energy() < 50 then
		UseCooldown(EnergizingElixir)
	end
	if BlackoutKick:usable() and BlackoutKick:combo() and (RisingSunKick:cooldown() > 3 or Chi() >= 3) and (FistsOfFury:cooldown() > 4 or Chi() >= (TigerPalm:previous() and 2 or 4)) and SwiftRoundhouse:stack() < 2 then
		return BlackoutKick
	end
	if ChiWave:usable() then
		UseCooldown(ChiWave)
	end
	if ChiBurst:usable() and ChiDeficit() >= min(Enemies(), 2) then
		UseCooldown(ChiBurst)
	end
	if TigerPalm:usable() and TigerPalm:combo() and ChiDeficit() >= 2 then
		return TigerPalm
	end
	if FlyingSerpentKick:usable() and BlackoutKick:previous() and Chi() > 3 and SwiftRoundhouse:stack() < 2 then
		UseCooldown(FlyingSerpentKick)
	end
end

APL[SPEC.WINDWALKER].aoe = function(self)
--[[
# Actions.AoE is intended for use with Hectic_Add_Cleave and currently needs to be optimized
actions.aoe=rising_sun_kick,target_if=min:debuff.mark_of_the_crane.remains,if=(talent.whirling_dragon_punch.enabled&cooldown.whirling_dragon_punch.remains<5)&cooldown.fists_of_fury.remains>3
actions.aoe+=/whirling_dragon_punch
actions.aoe+=/energizing_elixir,if=!prev_gcd.1.tiger_palm&chi<=1&energy<50
actions.aoe+=/fists_of_fury,if=energy.time_to_max>3
actions.aoe+=/rushing_jade_wind,if=buff.rushing_jade_wind.down
actions.aoe+=/spinning_crane_kick,if=!prev_gcd.1.spinning_crane_kick&(((chi>3|cooldown.fists_of_fury.remains>6)&(chi>=5|cooldown.fists_of_fury.remains>2))|energy.time_to_max<=3)
actions.aoe+=/chi_burst,if=chi<=3
actions.aoe+=/fist_of_the_white_tiger,if=chi.max-chi>=3
actions.aoe+=/tiger_palm,target_if=min:debuff.mark_of_the_crane.remains,if=chi.max-chi>=2&(!talent.hit_combo.enabled|!prev_gcd.1.tiger_palm)
actions.aoe+=/chi_wave
actions.aoe+=/flying_serpent_kick,if=buff.bok_proc.down,interrupt=1
actions.aoe+=/blackout_kick,target_if=min:debuff.mark_of_the_crane.remains,if=!prev_gcd.1.blackout_kick&(buff.bok_proc.up|(talent.hit_combo.enabled&prev_gcd.1.tiger_palm&chi<4))
]]
	if WhirlingDragonPunch.known and RisingSunKick:usable() and RisingSunKick:combo() and WhirlingDragonPunch:ready(5) and FistsOfFury:cooldown() > 3 then
		return RisingSunKick
	end
	if WhirlingDragonPunch:usable() then
		return WhirlingDragonPunch
	end
	if EnergizingElixir:usable() and not TigerPalm:previous() and Chi() <= 1 and Energy() < 50 then
		UseCooldown(EnergizingElixir)
	end
	if FistsOfFury:usable() and EnergyTimeToMax() > 3 then
		return FistsOfFury
	end
	if RushingJadeWind:usable() and RushingJadeWind:combo() and RushingJadeWind:down() then
		return RushingJadeWind
	end
	if SpinningCraneKick:usable() and SpinningCraneKick:combo() and (((Chi() > 3 or FistsOfFury:cooldown() > 6) and (Chi() >= 5 or FistsOfFury:cooldown() > 2)) or EnergyTimeToMax() <= 3) then
		return SpinningCraneKick
	end
	if ChiBurst:usable() and Chi() <= 3 then
		UseCooldown(ChiBurst)
	end
	if FistOfTheWhiteTiger:usable() and ChiDeficit() >= 3 then
		return FistOfTheWhiteTiger
	end
	if TigerPalm:usable() and ChiDeficit() >= 2 and (not HitCombo.known or TigerPalm:combo()) then
		return TigerPalm
	end
	if ChiWave:usable() then
		UseCooldown(ChiWave)
	end
	if FlyingSerpentKick:usable() and BlackoutKickProc:down() then
		UseCooldown(FlyingSerpentKick)
	end
	if BlackoutKick:usable() and BlackoutKick:combo() and (BlackoutKickProc:up() or (HitCombo.known and TigerPalm:previous() and Chi() < 4)) then
		return BlackoutKick
	end
end

APL.Interrupt = function(self)
	if SpearHandStrike:usable() then
		return SpearHandStrike
	end
	if LegSweep:usable() then
		return LegSweep
	end
end

-- End Action Priority Lists

local function UpdateInterrupt()
	local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
	if not start then
		_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
	end
	if not start or notInterruptible then
		var.interrupt = nil
		msmdInterruptPanel:Hide()
		return
	end
	var.interrupt = APL.Interrupt()
	if var.interrupt then
		msmdInterruptPanel.icon:SetTexture(var.interrupt.icon)
		msmdInterruptPanel.icon:Show()
		msmdInterruptPanel.border:Show()
	else
		msmdInterruptPanel.icon:Hide()
		msmdInterruptPanel.border:Hide()
	end
	msmdInterruptPanel:Show()
	msmdInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
end

local function DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end

hooksecurefunc('ActionButton_ShowOverlayGlow', DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

local function UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #glows do
		glow = glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
	end
end

local function CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			glows[#glows + 1] = glow
		end
	end
	for i = 1, 12 do
		GenerateGlow(_G['ActionButton' .. i])
		GenerateGlow(_G['MultiBarLeftButton' .. i])
		GenerateGlow(_G['MultiBarRightButton' .. i])
		GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
		GenerateGlow(_G['MultiBarBottomRightButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['PetActionButton' .. i])
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	end
	if Dominos then
		for i = 1, 60 do
			GenerateGlow(_G['DominosActionButton' .. i])
		end
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['LUIBarBottom' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarLeft' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
	end
	UpdateGlowColorAndScale()
end

local function UpdateGlows()
	local glow, icon, i
	for i = 1, #glows do
		glow = glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and var.main and icon == var.main.icon) or
			(Opt.glow.cooldown and var.cd and icon == var.cd.icon) or
			(Opt.glow.interrupt and var.interrupt and icon == var.interrupt.icon) or
			(Opt.glow.extra and var.extra and icon == var.extra.icon)
			) then
			if not glow:IsVisible() then
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function events:ACTIONBAR_SLOT_CHANGED()
	UpdateGlows()
end

local function ShouldHide()
	return (currentSpec == SPEC.NONE or
		   (currentSpec == SPEC.BREWMASTER and Opt.hide.brewmaster) or
		   (currentSpec == SPEC.MISTWEAVER and Opt.hide.mistweaver) or
		   (currentSpec == SPEC.WINDWALKER and Opt.hide.windwalker))
end

local function Disappear()
	msmdPanel:Hide()
	msmdPanel.icon:Hide()
	msmdPanel.border:Hide()
	msmdPanel.text:Hide()
	msmdCooldownPanel:Hide()
	msmdInterruptPanel:Hide()
	msmdExtraPanel:Hide()
	var.main, var.last_main = nil
	var.cd, var.last_cd = nil
	var.interrupt = nil
	var.extra, var.last_extra = nil
	UpdateGlows()
end

local function Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true
		end
	end
	return false
end

local function UpdateDraggable()
	msmdPanel:EnableMouse(Opt.aoe or not Opt.locked)
	if Opt.aoe then
		msmdPanel.button:Show()
	else
		msmdPanel.button:Hide()
	end
	if Opt.locked then
		msmdPanel:SetScript('OnDragStart', nil)
		msmdPanel:SetScript('OnDragStop', nil)
		msmdPanel:RegisterForDrag(nil)
		msmdPreviousPanel:EnableMouse(false)
		msmdCooldownPanel:EnableMouse(false)
		msmdInterruptPanel:EnableMouse(false)
		msmdExtraPanel:EnableMouse(false)
	else
		if not Opt.aoe then
			msmdPanel:SetScript('OnDragStart', msmdPanel.StartMoving)
			msmdPanel:SetScript('OnDragStop', msmdPanel.StopMovingOrSizing)
			msmdPanel:RegisterForDrag('LeftButton')
		end
		msmdPreviousPanel:EnableMouse(true)
		msmdCooldownPanel:EnableMouse(true)
		msmdInterruptPanel:EnableMouse(true)
		msmdExtraPanel:EnableMouse(true)
	end
end

local function SnapAllPanels()
	msmdPreviousPanel:ClearAllPoints()
	msmdPreviousPanel:SetPoint('BOTTOMRIGHT', msmdPanel, 'BOTTOMLEFT', -10, -5)
	msmdCooldownPanel:ClearAllPoints()
	msmdCooldownPanel:SetPoint('BOTTOMLEFT', msmdPanel, 'BOTTOMRIGHT', 10, -5)
	msmdInterruptPanel:ClearAllPoints()
	msmdInterruptPanel:SetPoint('TOPLEFT', msmdPanel, 'TOPRIGHT', 16, 25)
	msmdExtraPanel:ClearAllPoints()
	msmdExtraPanel:SetPoint('TOPRIGHT', msmdPanel, 'TOPLEFT', -16, 25)
end

local resourceAnchor = {}

local ResourceFramePoints = {
	['blizzard'] = {
		[SPEC.BREWMASTER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.MISTWEAVER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 18 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.WINDWALKER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 18 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		}
	},
	['kui'] = {
		[SPEC.BREWMASTER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.MISTWEAVER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.WINDWALKER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		}
	},
}

local function OnResourceFrameHide()
	if Opt.snap then
		msmdPanel:ClearAllPoints()
	end
end

local function OnResourceFrameShow()
	if Opt.snap then
		msmdPanel:ClearAllPoints()
		local p = ResourceFramePoints[resourceAnchor.name][currentSpec][Opt.snap]
		msmdPanel:SetPoint(p[1], resourceAnchor.frame, p[2], p[3], p[4])
		SnapAllPanels()
	end
end

local function HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		resourceAnchor.name = 'kui'
		resourceAnchor.frame = KuiNameplatesPlayerAnchor
	else
		resourceAnchor.name = 'blizzard'
		resourceAnchor.frame = ClassNameplateManaBarFrame
	end
	resourceAnchor.frame:HookScript("OnHide", OnResourceFrameHide)
	resourceAnchor.frame:HookScript("OnShow", OnResourceFrameShow)
end

local function UpdateAlpha()
	msmdPanel:SetAlpha(Opt.alpha)
	msmdPreviousPanel:SetAlpha(Opt.alpha)
	msmdCooldownPanel:SetAlpha(Opt.alpha)
	msmdInterruptPanel:SetAlpha(Opt.alpha)
	msmdExtraPanel:SetAlpha(Opt.alpha)
end

local function UpdateTargetHealth()
	timer.health = 0
	Target.health = UnitHealth('target')
	table.remove(Target.healthArray, 1)
	Target.healthArray[15] = Target.health
	Target.timeToDieMax = Target.health / UnitHealthMax('player') * 15
	Target.healthPercentage = Target.healthMax > 0 and (Target.health / Target.healthMax * 100) or 100
	Target.healthLostPerSec = (Target.healthArray[1] - Target.health) / 3
	Target.timeToDie = Target.healthLostPerSec > 0 and min(Target.timeToDieMax, Target.health / Target.healthLostPerSec) or Target.timeToDieMax
end

local function UpdateDisplay()
	timer.display = 0
	local text = false

	if Opt.dimmer then
		if not var.main then
			msmdPanel.dimmer:Hide()
		elseif var.main.spellId and IsUsableSpell(var.main.spellId) then
			msmdPanel.dimmer:Hide()
		elseif var.main.itemId and IsUsableItem(var.main.itemId) then
			msmdPanel.dimmer:Hide()
		else
			msmdPanel.dimmer:Show()
		end
	end
	if var.pool_energy then
		local deficit = var.pool_energy - UnitPower('player', 3)
		if deficit > 0 then
			msmdPanel.text:SetText(format('POOL %d', deficit))
			text = true
		end
	end
	if Serenity.known then
		local remains = Serenity:remains()
		if remains > 0 then
			if not msmdPanel.serenityOverlayOn then
				msmdPanel.serenityOverlayOn = true
				msmdPanel.border:SetTexture('Interface\\AddOns\\MonkSeeMonkDo\\serenity.blp')
			end
			msmdPanel.text:SetText(format('%.1f', remains))
			text = true
		elseif msmdPanel.serenityOverlayOn then
			msmdPanel.serenityOverlayOn = false
			msmdPanel.border:SetTexture('Interface\\AddOns\\MonkSeeMonkDo\\border.blp')
		end
	end
	msmdPanel.text:SetShown(text)
end

local function UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	var.time = GetTime()
	var.last_main = var.main
	var.last_cd = var.cd
	var.last_extra = var.extra
	var.main =  nil
	var.cd = nil
	var.extra = nil
	var.pool_energy = nil
	start, duration = GetSpellCooldown(61304)
	var.gcd_remains = start > 0 and duration - (var.time - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	var.ability_casting = abilities.bySpellId[spellId]
	var.execute_remains = max(remains and (remains / 1000 - var.time) or 0, var.gcd_remains)
	var.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	var.health = UnitHealth('player')
	var.health_max = UnitHealthMax('player')

	if currentSpec == SPEC.MISTWEAVER then
		var.gcd = 1.5 * var.haste_factor
		var.mana_regen = GetPowerRegen()
		var.mana = UnitPower('player', 0) + (var.mana_regen * var.execute_remains)
		if var.ability_casting then
			var.mana = var.mana - var.ability_casting:manaCost()
		end
		var.mana = min(max(var.mana, 0), var.mana_max)
	else
		var.gcd = 1
		var.energy_regen = GetPowerRegen()
		var.energy = UnitPower('player', 3) + (var.energy_regen * var.execute_remains)
		var.energy = min(max(var.energy, 0), var.energy_max)
		if currentSpec == SPEC.WINDWALKER then
			var.chi = UnitPower('player', 12)
		else
			var.stagger = UnitStagger('player')
		end
	end

	trackAuras:purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:updateTargetsHit()
		end
		autoAoe:purge()
	end

	var.main = APL[currentSpec]:main()
	if var.main ~= var.last_main then
		if var.main then
			msmdPanel.icon:SetTexture(var.main.icon)
			msmdPanel.icon:Show()
			msmdPanel.border:Show()
		else
			msmdPanel.icon:Hide()
			msmdPanel.border:Hide()
		end
	end
	if var.cd ~= var.last_cd then
		if var.cd then
			msmdCooldownPanel.icon:SetTexture(var.cd.icon)
			msmdCooldownPanel:Show()
		else
			msmdCooldownPanel:Hide()
		end
	end
	if var.extra ~= var.last_extra then
		if var.extra then
			msmdExtraPanel.icon:SetTexture(var.extra.icon)
			msmdExtraPanel:Show()
		else
			msmdExtraPanel:Hide()
		end
	end
	if Opt.interrupt then
		UpdateInterrupt()
	end
	UpdateGlows()
	UpdateDisplay()
end

local function UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local start, duration
		local _, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
			if start <= 0 then
				return msmdPanel.swipe:Hide()
			end
		end
		msmdPanel.swipe:SetCooldown(start, duration)
		msmdPanel.swipe:Show()
	end
end

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and powerType == 'CHI' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:ADDON_LOADED(name)
	if name == 'MonkSeeMonkDo' then
		Opt = MonkSeeMonkDo
		if not Opt.frequency then
			print('It looks like this is your first time running MonkSeeMonkDo, why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_MonkSeeMonkDo1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] MonkSeeMonkDo is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitializeOpts()
		Azerite:initialize()
		UpdateDraggable()
		UpdateAlpha()
		SnapAllPanels()
		msmdPanel:SetScale(Opt.scale.main)
		msmdPreviousPanel:SetScale(Opt.scale.previous)
		msmdCooldownPanel:SetScale(Opt.scale.cooldown)
		msmdInterruptPanel:SetScale(Opt.scale.interrupt)
		msmdExtraPanel:SetScale(Opt.scale.extra)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	var.time = GetTime()
	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:remove(dstGUID)
		end
		return
	end
	if Opt.auto_aoe and (eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED') then
		if dstGUID == var.player then
			autoAoe:add(srcGUID, true)
		elseif srcGUID == var.player and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:add(dstGUID, true)
		end
	end
	if srcGUID ~= var.player or not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_HEAL' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end
	local castedAbility = abilities.bySpellId[spellId]
	if not castedAbility then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName, spellId))
		return
	end
--[[ DEBUG ]
	print(format('EVENT %s TRACK CHECK FOR %s ID %d', eventType, spellName, spellId))
	if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' or eventType == 'SPELL_PERIODIC_DAMAGE' or eventType == 'SPELL_DAMAGE' then
		print(format('%s: %s - time: %.2f - time since last: %.2f', eventType, spellName, timeStamp, timeStamp - (castedAbility.last_trigger or timeStamp)))
		castedAbility.last_trigger = timeStamp
	end
--[ DEBUG ]]
	var.time_diff = var.time - timeStamp
	UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		var.last_ability = castedAbility
		if castedAbility.triggers_gcd then
			PreviousGCD[10] = nil
			table.insert(PreviousGCD, 1, castedAbility)
		end
		if castedAbility.travel_start then
			castedAbility.travel_start[dstGUID] = var.time
		end
		if currentSpec == SPEC.WINDWALKER then
			if not castedAbility.triggers_combo then
				return
			end
			var.last_combo_ability = castedAbility
		end
		if Opt.previous and msmdPanel:IsVisible() then
			msmdPreviousPanel.ability = castedAbility
			msmdPreviousPanel.border:SetTexture('Interface\\AddOns\\MonkSeeMonkDo\\border.blp')
			msmdPreviousPanel.icon:SetTexture(castedAbility.icon)
			msmdPreviousPanel:Show()
		end
		return
	end
	if castedAbility.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			castedAbility:applyAura(timeStamp, dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			castedAbility:refreshAura(timeStamp, dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			castedAbility:removeAura(dstGUID)
		end
	end
	if dstGUID ~= var.player and (eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH') then
		if castedAbility.travel_start and castedAbility.travel_start[dstGUID] then
			castedAbility.travel_start[dstGUID] = nil
		end
		if Opt.auto_aoe then
			if missType == 'EVADE' or missType == 'IMMUNE' then
				autoAoe:remove(dstGUID)
			elseif castedAbility.auto_aoe then
				castedAbility:recordTargetHit(dstGUID)
			elseif eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
				if castedAbility == MarkOfTheCrane then
					autoAoe:add(dstGUID, true)
				end
			end
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and msmdPanel:IsVisible() and castedAbility == msmdPreviousPanel.ability then
			msmdPreviousPanel.border:SetTexture('Interface\\AddOns\\MonkSeeMonkDo\\misseffect.blp')
		end
	end
end

local function UpdateTargetInfo()
	Disappear()
	if ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		Target.guid = nil
		Target.boss = false
		Target.player = false
		Target.hostile = true
		Target.healthMax = 0
		local i
		for i = 1, 15 do
			Target.healthArray[i] = 0
		end
		if Opt.always_on then
			UpdateTargetHealth()
			UpdateCombat()
			msmdPanel:Show()
			return true
		end
		if Opt.previous and combatStartTime == 0 then
			msmdPreviousPanel:Hide()
		end
		return
	end
	if guid ~= Target.guid then
		Target.guid = guid
		local i
		for i = 1, 15 do
			Target.healthArray[i] = UnitHealth('target')
		end
	end
	Target.level = UnitLevel('target')
	Target.healthMax = UnitHealthMax('target')
	Target.player = UnitIsPlayer('target')
	if Target.player then
		Target.boss = false
	elseif Target.level == -1 then
		Target.boss = true
	elseif var.instance == 'party' and Target.level >= UnitLevel('player') + 2 then
		Target.boss = true
	else
		Target.boss = false
	end
	Target.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if Target.hostile or Opt.always_on then
		UpdateTargetHealth()
		UpdateCombat()
		msmdPanel:Show()
		return true
	end
end

function events:PLAYER_TARGET_CHANGED()
	UpdateTargetInfo()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:PLAYER_REGEN_DISABLED()
	combatStartTime = GetTime()
end

function events:PLAYER_REGEN_ENABLED()
	combatStartTime = 0
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.travel_start do
			ability.travel_start[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:clear()
		autoAoe:update()
	end
	if var.last_ability then
		var.last_ability = nil
		msmdPreviousPanel:Hide()
	end
end

local function UpdateAbilityData()
	local _, ability
	for _, ability in next, abilities.all do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = (IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) or Azerite.traits[ability.spellId]) and true or false
	end
	if currentSpec == SPEC.MISTWEAVER then
		var.mana_base = BaseMana[UnitLevel('player')]
		var.mana_max = UnitPowerMax('player', 0)
	elseif currentSpec == SPEC.WINDWALKER then
		var.chi_max = UnitPowerMax('player', 12)
		var.energy_max = UnitPowerMax('player', 3)
		BlackoutKickProc.known = true
		MarkOfTheCrane.known = true
		if Serenity.known then
			StormEarthAndFire.known = false
		end
	end
	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				abilities.velocity[#abilities.velocity + 1] = ability
			end
			if ability.auto_aoe then
				abilities.autoAoe[#abilities.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				abilities.trackAuras[#abilities.trackAuras + 1] = ability
			end
		end
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	Azerite:update()
	UpdateAbilityData()
	ItemEquipped.Tier21 = (Equipped(152142, 5) and 1 or 0) + (Equipped(152142, 5) and 1 or 0) + (Equipped(152143, 15) and 1 or 0) + (Equipped(152144, 10) and 1 or 0) + (Equipped(152145, 1) and 1 or 0) + (Equipped(152146, 7) and 1 or 0) + (Equipped(152147, 3) and 1 or 0)
	ItemEquipped.DrinkingHornCover = Equipped(137097, 9)
	ItemEquipped.SalsalabimsLostTunic = Equipped(137016, 5)
	ItemEquipped.StormstoutsLastGasp = Equipped(151788, 3)
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName == 'player' then
		currentSpec = GetSpecialization() or 0
		Azerite:update()
		UpdateAbilityData()
		local _, i
		for i = 1, #inventoryItems do
			inventoryItems[i].name, _, _, _, _, _, _, _, _, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId)
		end
		msmdPreviousPanel.ability = nil
		PreviousGCD = {}
		SetTargetMode(1)
		UpdateTargetInfo()
		events:PLAYER_REGEN_ENABLED()
	end
end

function events:PLAYER_ENTERING_WORLD()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	if #glows == 0 then
		CreateOverlayGlows()
		HookResourceFrame()
	end
	local _
	_, var.instance = IsInInstance()
	var.player = UnitGUID('player')
end

msmdPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			ToggleTargetMode()
		elseif button == 'RightButton' then
			ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			SetTargetMode(1)
		end
	end
end)

msmdPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UpdateCombat()
	end
	if timer.display >= 0.05 then
		UpdateDisplay()
	end
	if timer.health >= 0.2 then
		UpdateTargetHealth()
	end
end)

msmdPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	msmdPanel:RegisterEvent(event)
end

function SlashCmdList.MonkSeeMonkDo(msg, editbox)
	msg = { strsplit(' ', strlower(msg)) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UpdateDraggable()
		end
		return print('MonkSeeMonkDo - Locked: ' .. (Opt.locked and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
			else
				Opt.snap = false
				msmdPanel:ClearAllPoints()
			end
			OnResourceFrameShow()
		end
		return print('MonkSeeMonkDo - Snap to Blizzard combat resources frame: ' .. (Opt.snap and ('|cFF00C000' .. Opt.snap) or '|cFFC00000Off'))
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				msmdPreviousPanel:SetScale(Opt.scale.previous)
			end
			return print('MonkSeeMonkDo - Previous ability icon scale set to: |cFFFFD000' .. Opt.scale.previous .. '|r times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				msmdPanel:SetScale(Opt.scale.main)
			end
			return print('MonkSeeMonkDo - Main ability icon scale set to: |cFFFFD000' .. Opt.scale.main .. '|r times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				msmdCooldownPanel:SetScale(Opt.scale.cooldown)
			end
			return print('MonkSeeMonkDo - Cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.cooldown .. '|r times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				msmdInterruptPanel:SetScale(Opt.scale.interrupt)
			end
			return print('MonkSeeMonkDo - Interrupt ability icon scale set to: |cFFFFD000' .. Opt.scale.interrupt .. '|r times')
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				msmdExtraPanel:SetScale(Opt.scale.extra)
			end
			return print('MonkSeeMonkDo - Extra cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.extra .. '|r times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return print('MonkSeeMonkDo - Action button glow scale set to: |cFFFFD000' .. Opt.scale.glow .. '|r times')
		end
		return print('MonkSeeMonkDo - Default icon scale options: |cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UpdateAlpha()
		end
		return print('MonkSeeMonkDo - Icon transparency set to: |cFFFFD000' .. Opt.alpha * 100 .. '%|r')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
			UpdateHealthArray()
		end
		return print('MonkSeeMonkDo - Calculation frequency: Every |cFFFFD000' .. Opt.frequency .. '|r seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UpdateGlows()
			end
			return print('MonkSeeMonkDo - Glowing ability buttons (main icon): ' .. (Opt.glow.main and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UpdateGlows()
			end
			return print('MonkSeeMonkDo - Glowing ability buttons (cooldown icon): ' .. (Opt.glow.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UpdateGlows()
			end
			return print('MonkSeeMonkDo - Glowing ability buttons (interrupt icon): ' .. (Opt.glow.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UpdateGlows()
			end
			return print('MonkSeeMonkDo - Glowing ability buttons (extra icon): ' .. (Opt.glow.extra and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UpdateGlows()
			end
			return print('MonkSeeMonkDo - Blizzard default proc glow: ' .. (Opt.glow.blizzard and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UpdateGlowColorAndScale()
			end
			return print('MonkSeeMonkDo - Glow color:', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return print('MonkSeeMonkDo - Possible glow options: |cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('MonkSeeMonkDo - Previous ability icon: ' .. (Opt.previous and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('MonkSeeMonkDo - Show the MonkSeeMonkDo UI without a target: ' .. (Opt.always_on and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return print('MonkSeeMonkDo - Use MonkSeeMonkDo for cooldown management: ' .. (Opt.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
			if not Opt.spell_swipe then
				msmdPanel.swipe:Hide()
			end
		end
		return print('MonkSeeMonkDo - Spell casting swipe animation: ' .. (Opt.spell_swipe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
			if not Opt.dimmer then
				msmdPanel.dimmer:Hide()
			end
		end
		return print('MonkSeeMonkDo - Dim main ability icon when you don\'t have enough resources to use it: ' .. (Opt.dimmer and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return print('MonkSeeMonkDo - Red border around previous ability when it fails to hit: ' .. (Opt.miss_effect and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			MonkSeeMonkDo_SetTargetMode(1)
			UpdateDraggable()
		end
		return print('MonkSeeMonkDo - Allow clicking main ability icon to toggle amount of targets (disables moving): ' .. (Opt.aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return print('MonkSeeMonkDo - Only use cooldowns on bosses: ' .. (Opt.boss_only and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'b') then
				Opt.hide.brewmaster = not Opt.hide.brewmaster
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('MonkSeeMonkDo - Brewmaster specialization: |cFFFFD000' .. (Opt.hide.brewmaster and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'm') then
				Opt.hide.mistweaver = not Opt.hide.mistweaver
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('MonkSeeMonkDo - Mistweaver specialization: |cFFFFD000' .. (Opt.hide.mistweaver and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'w') then
				Opt.hide.windwalker = not Opt.hide.windwalker
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('MonkSeeMonkDo - Windwalker specialization: |cFFFFD000' .. (Opt.hide.windwalker and '|cFFC00000Off' or '|cFF00C000On'))
			end
		end
		return print('MonkSeeMonkDo - Possible hidespec options: |cFFFFD000brewmaster|r/|cFFFFD000mistweaver|r/|cFFFFD000windwalker|r - toggle disabling MonkSeeMonkDo for specializations')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return print('MonkSeeMonkDo - Show an icon for interruptable spells: ' .. (Opt.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return print('MonkSeeMonkDo - Automatically change target mode on AoE spells: ' .. (Opt.auto_aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return print('MonkSeeMonkDo - Length of time target exists in auto AoE after being hit: |cFFFFD000' .. Opt.auto_aoe_ttl .. '|r seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return print('MonkSeeMonkDo - Show Battle potions in cooldown UI: ' .. (Opt.pot and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'reset' then
		msmdPanel:ClearAllPoints()
		msmdPanel:SetPoint('CENTER', 0, -169)
		SnapAllPanels()
		return print('MonkSeeMonkDo - Position has been reset to default')
	end
	print('MonkSeeMonkDo (version: |cFFFFD000' .. GetAddOnMetadata('MonkSeeMonkDo', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the MonkSeeMonkDo UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the MonkSeeMonkDo UI to the Blizzard combat resources frame',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the MonkSeeMonkDo UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the MonkSeeMonkDo UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.05 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the MonkSeeMonkDo UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use MonkSeeMonkDo for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000brewmaster|r/|cFFFFD000mistweaver|r/|cFFFFD000windwalker|r - toggle disabling MonkSeeMonkDo for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show Battle potions in cooldown UI',
		'|cFFFFD000reset|r - reset the location of the MonkSeeMonkDo UI to default',
	} do
		print('  ' .. SLASH_MonkSeeMonkDo1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Contact |cFF00FF96Netizen|cFFFFD000-Zul\'jin|r or |cFFFFD000Spy#1955|r (the author of this addon)')
end

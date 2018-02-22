if select(2, UnitClass('player')) ~= 'MONK' then
	DisableAddOn('MonkSeeMonkDo')
	return
end

-- useful functions
local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
   return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

MonkSeeMonkDo = {}

SLASH_MonkSeeMonkDo1, SLASH_MonkSeeMonkDo2 = '/monk', '/msmd'
BINDING_HEADER_MSMD = 'MonkSeeMonkDo'

local function InitializeVariables()
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
			touch = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			touch = true,
			blizzard = false,
			color = { r = 1, g = 1, b = 1 }
		},
		hide = {
			brewmaster = false,
			mistweaver = false,
			windwalker = false
		},
		alpha = 1,
		frequency = 0.05,
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
		healthstone = true,
		pot = false
	})
end

-- specialization constants
local SPEC = {
	NONE = 0,
	BREWMASTER = 1,
	MISTWEAVER = 2,
	WINDWALKER = 3
}

local events, glows = {}, {}

local abilityTimer, currentSpec, targetMode, combatStartTime = 0, 0, 0, 0

-- list of targets detected in AoE proximity
local Targets = {}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false
}

-- list of previous GCD abilities
local PreviousGCD = {}

-- tier set equipped pieces count
local Tier = {
	T19P = 0,
	T20P = 0,
	T21P = 0
}

-- legendary item equipped
local ItemEquipped = {
	DrinkingHornCover = false,
	TheEmperorsCapacitor = false,
	HiddenMastersForbiddenTouch = false,
	SephuzsSecret = false
}

local var = {
	gcd = 0
}

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
	}
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
msmdPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 14, 'OUTLINE')
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
msmdPreviousPanel:SetPoint('BOTTOMRIGHT', msmdPanel, 'BOTTOMLEFT', -10, -5)
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
msmdCooldownPanel:SetPoint('BOTTOMLEFT', msmdPanel, 'BOTTOMRIGHT', 10, -5)
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
msmdInterruptPanel:SetPoint('TOPLEFT', msmdPanel, 'TOPRIGHT', 16, 25)
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
local msmdTouchPanel = CreateFrame('Frame', 'msmdTouchPanel', UIParent)
msmdTouchPanel:SetPoint('TOPRIGHT', msmdPanel, 'TOPLEFT', -16, 25)
msmdTouchPanel:SetFrameStrata('BACKGROUND')
msmdTouchPanel:SetSize(64, 64)
msmdTouchPanel:Hide()
msmdTouchPanel:RegisterForDrag('LeftButton')
msmdTouchPanel:SetScript('OnDragStart', msmdTouchPanel.StartMoving)
msmdTouchPanel:SetScript('OnDragStop', msmdTouchPanel.StopMovingOrSizing)
msmdTouchPanel:SetMovable(true)
msmdTouchPanel.icon = msmdTouchPanel:CreateTexture(nil, 'BACKGROUND')
msmdTouchPanel.icon:SetAllPoints(msmdTouchPanel)
msmdTouchPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
msmdTouchPanel.border = msmdTouchPanel:CreateTexture(nil, 'ARTWORK')
msmdTouchPanel.border:SetAllPoints(msmdTouchPanel)
msmdTouchPanel.border:SetTexture('Interface\\AddOns\\MonkSeeMonkDo\\border.blp')

-- Start Abilities

local Ability, abilities, abilityBySpellId, abilitiesAutoAoe = {}, {}, {}, {}
Ability.__index = Ability

function Ability.add(spellId, buff, player, spellId2)
	local ability = {
		spellId = spellId,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		usable_moving = true,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		known = false,
		energy_cost = 0,
		chi_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		auraTarget = buff == 'pet' and 'pet' or buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, Ability)
	abilities[#abilities + 1] = ability
	abilityBySpellId[spellId] = ability
	return ability
end

function Ability:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function Ability:usable(seconds)
	if self:energyCost() > var.energy then
		return false
	end
	if self:chiCost() > var.chi then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	if not self.usable_moving and GetUnitSpeed('player') ~= 0 then
		return false
	end
	return self:ready(seconds)
end

function Ability:remains()
	if self.buff_duration > 0 and self:casting() then
		return self:duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == self.spellId or id == self.spellId2 then
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
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return false
		end
		if id == self.spellId or id == self.spellId2 then
			return expires == 0 or expires - var.time > var.execute_remains
		end
	end
end

function Ability:down()
	return not self:up()
end

function Ability:cooldownDuration()
	return self.hasted_cooldown and (var.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self:cooldownDuration()
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
		_, _, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == self.spellId or id == self.spellId2 then
			return (expires == 0 or expires - var.time > var.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:energyCost()
	return self.energy_cost > 0 and (self.energy_cost / 100 * var.energy_max) or 0
end

function Ability:chiCost()
	return self.chi_cost
end

function Ability:charges()
	return GetSpellCharges(self.spellId) or 0
end

function Ability:duration()
	return self.hasted_duration and (var.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return var.cast_ability == self
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

function Ability:previous()
	if self:channeling() then
		return true
	end
	if var.cast_ability then
		return var.cast_ability == self
	end
	return PreviousGCD[1] == self or var.last_ability == self
end

function Ability:setAutoAoe(enabled)
	if enabled and not self.auto_aoe then
		self.auto_aoe = true
		self.first_hit_time = nil
		self.targets_hit = {}
		abilitiesAutoAoe[#abilitiesAutoAoe + 1] = self
	end
	if not enabled and self.auto_aoe then
		self.auto_aoe = nil
		self.first_hit_time = nil
		self.targets_hit = nil
		local i
		for i = 1, #abilitiesAutoAoe do
			if abilitiesAutoAoe[i] == self then
				abilitiesAutoAoe[i] = nil
				break
			end
		end
	end
end

function Ability:recordTargetHit(guid)
	local t = GetTime()
	self.targets_hit[guid] = t
	Targets[guid] = t
	if not self.first_hit_time then
		self.first_hit_time = t
	end
end

local function AutoAoeUpdateTargetMode()
	local count, i = 0
	for i in next, Targets do
		count = count + 1
	end
	if count <= 1 then
		MonkSeeMonkDo_SetTargetMode(1)
		return
	end
	for i = #targetModes[currentSpec], 1, -1 do
		if count >= targetModes[currentSpec][i][1] then
			MonkSeeMonkDo_SetTargetMode(i)
			return
		end
	end
end

local function AutoAoeRemoveTarget(guid)
	if Targets[guid] then
		Targets[guid] = nil
		AutoAoeUpdateTargetMode()
	end
end

function Ability:updateTargetsHit()
	if self.first_hit_time and GetTime() - self.first_hit_time >= 0.3 then
		self.first_hit_time = nil
		local guid
		for guid in next, Targets do
			if not self.targets_hit[guid] then
				Targets[guid] = nil
			end
		end
		for guid in next, self.targets_hit do
			self.targets_hit[guid] = nil
		end
		AutoAoeUpdateTargetMode()
	end
end

-- Monk Abilities
---- Multiple Specializations
local Resuscitate = Ability.add(115178) -- used for GCD
------ Talents

------ Procs
local SephuzsSecret = Ability.add(208052, true, true)
SephuzsSecret.cooldown_duration = 30
---- Brewmaster

------ Talents

------ Procs

---- Mistweaver

------ Talents

------ Procs

---- Windwalker
local BlackoutKick = Ability.add(100784, false, true)
BlackoutKick.chi_cost = 1
local CracklingJadeLightning = Ability.add(117952, false, true)
CracklingJadeLightning.energy_cost = 20
CracklingJadeLightning.usable_moving = false
local Disable = Ability.add(116095, false, true)
Disable.energy_cost = 15
local FistsOfFury = Ability.add(113656, false, true, 117418)
FistsOfFury.chi_cost = 3
FistsOfFury.buff_duration = 4
FistsOfFury.cooldown_duration = 24
FistsOfFury.hasted_duration = true
FistsOfFury.hasted_cooldown = true
FistsOfFury:setAutoAoe(true)
local MarkOfTheCrane = Ability.add(228287, false, true)
MarkOfTheCrane.buff_duration = 15
local RisingSunKick = Ability.add(107428, false, true)
RisingSunKick.chi_cost = 2
RisingSunKick.cooldown_duration = 10
RisingSunKick.hasted_cooldown = true
local SpearHandStrike = Ability.add(116705, false, true)
SpearHandStrike.cooldown_duration = 15
SpearHandStrike.triggers_gcd = false
local SpinningCraneKick = Ability.add(101546, true, true, 107270)
SpinningCraneKick.chi_cost = 3
SpinningCraneKick.buff_duration = 1.5
SpinningCraneKick.hasted_duration = true
SpinningCraneKick:setAutoAoe(true)
local StormEarthAndFire = Ability.add(137639, true, true)
StormEarthAndFire.buff_duration = 15
StormEarthAndFire.cooldown_duration = 90
StormEarthAndFire.hasted_cooldown = true
local StrikeOfTheWindlord = Ability.add(205320, false, true, 205414)
StrikeOfTheWindlord.chi_cost = 2
StrikeOfTheWindlord.cooldown_duration = 40
StrikeOfTheWindlord:setAutoAoe(true)
local TigerPalm = Ability.add(100780, false, true)
TigerPalm.chi_cost = -2
TigerPalm.energy_cost = 50
local TouchOfDeath = Ability.add(115080, false, true)
TouchOfDeath.cooldown_duration = 120
TouchOfDeath.buff_duration = 8
local TouchOfKarma = Ability.add(122470, true, true, 125174)
TouchOfKarma.cooldown_duration = 90
TouchOfKarma.triggers_gcd = false
TouchOfKarma.buff_duration = 10
------ Talents
local ChiBurst = Ability.add(123986, false, true)
ChiBurst.cooldown_duration = 30
ChiBurst.usable_moving = false
local ChiWave = Ability.add(115098, false, true)
ChiWave.cooldown_duration = 15
local EnergizingElixir = Ability.add(115288, false, true)
EnergizingElixir.cooldown_duration = 60
EnergizingElixir.triggers_gcd = false
local HitCombo = Ability.add(196740, true, true, 196741)
HitCombo.buff_duration = 10
local InvokeXuenTheWhiteTiger = Ability.add(123904, false, true)
InvokeXuenTheWhiteTiger.cooldown_duration = 180
InvokeXuenTheWhiteTiger.buff_duration = 45
local LegSweep = Ability.add(119381, false, true)
LegSweep.cooldown_duration = 45
local RushingJadeWind = Ability.add(116847, true, true)
RushingJadeWind.chi_cost = 1
RushingJadeWind.buff_duration = 6
RushingJadeWind.cooldown_duration = 6
RushingJadeWind.hasted_duration = true
RushingJadeWind.hasted_cooldown = true
local Serenity = Ability.add(152173, true, true)
Serenity.cooldown_duration = 90
Serenity.buff_duration = 8
Serenity.hasted_cooldown = true
Serenity.triggers_gcd = false
local WhirlingDragonPunch = Ability.add(152175, false, true, 158221)
WhirlingDragonPunch.cooldown_duration = 24
WhirlingDragonPunch.hasted_cooldown = true
WhirlingDragonPunch:setAutoAoe(true)
------ Procs
local BlackoutKickProc = Ability.add(116768, true, true)
BlackoutKickProc.buff_duration = 15
local PressurePoint = Ability.add(247255, true, true)
PressurePoint.buff_duration = 5
-- Tier Bonuses & Legendaries
local HiddenMastersForbiddenTouch = Ability.add(213114, true, true)
local TheEmperorsCapacitor = Ability.add(235054, true, true)
-- Racials
local ArcaneTorrent = Ability.add(129597, true, false) -- Blood Elf
ArcaneTorrent.chi_cost = -1
ArcaneTorrent.triggers_gcd = false
-- Potion Effects
local ProlongedPower = Ability.add(229206, true, true)
ProlongedPower.triggers_gcd = false
-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem = {}
InventoryItem.__index = InventoryItem

function InventoryItem.add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon
	}
	setmetatable(item, InventoryItem)
	return item
end

function InventoryItem:charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		charges = max(charges, self.max_charges)
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
local PotionOfProlongedPower = InventoryItem.add(142117)

-- End Inventory Items

-- Start Helpful Functions

local function GetExecuteEnergyRegen()
	return var.energy_regen * var.execute_remains - (var.cast_ability and var.cast_ability:energyCost() or 0)
end

local function GetAvailableChi()
	local chi = UnitPower('player', SPELL_POWER_CHI)
	if var.cast_ability then
		chi = min(var.chi_max, max(0, chi - var.cast_ability:chiCost()))
	end
	return chi
end

local function Energy()
	return var.energy
end

local function EnergyDeficit()
	return var.energy_max - var.energy
end

local function EnergyRegen()
	return var.energy_regen
end

local function EnergyMax()
	return var.energy_max
end

local function EnergyTimeToMax()
	local deficit = var.energy_max - var.energy
	if deficit <= 0 then
		return 0
	end
	return deficit / var.energy_regen
end

local function Chi()
	return var.chi
end

local function ChiDeficit()
	return var.chi_max - var.chi
end

local function HasteFactor()
	return var.haste_factor
end

local function GCD()
	return var.gcd
end

local function Enemies()
	return targetModes[currentSpec][targetMode][1]
end

local function TimeInCombat()
	return combatStartTime > 0 and var.time - combatStartTime or 0
end

local function BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if id == 2825 or id == 32182 or id == 80353 or id == 90355 or id == 160452 or id == 146555 then
			return true
		end
	end
end

local function TargetIsStunnable()
	if Target.boss then
		return false
	end
	if UnitHealthMax('target') > UnitHealthMax('player') * 25 then
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

function WhirlingDragonPunch:usable()
	if FistsOfFury:ready() or RisingSunKick:ready() then
		return false
	end
	return Ability.usable(self)
end

function SephuzsSecret:cooldown()
	if not self.cooldown_start then
		return 0
	end
	if var.time >= self.cooldown_start + self.cooldown_duration then
		self.cooldown_start = nil
		return 0
	end
	return self.cooldown_duration - (var.time - self.cooldown_start)
end

function TheEmperorsCapacitor:stack()
	if CracklingJadeLightning:previous() then
		return 0
	end
	return Ability.stack(self)
end

function CracklingJadeLightning:energyCost()
	local cost = Ability.energyCost(self)
	cost = cost - (cost * TheEmperorsCapacitor:stack() * .05)
	return cost
end

-- End Ability Modifications

local function UpdateVars()
	local _, start, duration, remains, hp, hp_lost, spellId
	var.last_main = var.main
	var.last_cd = var.cd
	var.last_touch = var.touch
	var.main =  nil
	var.cd = nil
	var.touch = nil
	var.time = GetTime()
	if currentSpec == SPEC.MISTWEAVER then
		var.gcd = 1.5 - (1.5 * (UnitSpellHaste('player') / 100))
	else
		var.gcd = 1.0
	end
	start, duration = GetSpellCooldown(Resuscitate.spellId)
	var.gcd_remains = start > 0 and duration - (var.time - start) or 0
	_, _, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	var.cast_ability = abilityBySpellId[spellId]
	var.execute_remains = max(remains and (remains / 1000 - var.time) or 0, var.gcd_remains)
	var.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	var.energy_regen = GetPowerRegen()
	var.execute_regen = GetExecuteEnergyRegen()
	var.energy_max = UnitPowerMax('player', SPELL_POWER_ENERGY)
	var.energy = min(var.energy_max, floor(UnitPower('player', SPELL_POWER_ENERGY) + var.execute_regen))
	var.chi_max = UnitPowerMax('player', SPELL_POWER_CHI)
	var.chi = GetAvailableChi()
	hp = UnitHealth('target')
	table.remove(Target.healthArray, 1)
	Target.healthArray[#Target.healthArray + 1] = hp
	Target.timeToDieMax = hp / UnitHealthMax('player') * 5
	Target.healthPercentage = Target.guid == 0 and 100 or (hp / UnitHealthMax('target') * 100)
	hp_lost = Target.healthArray[1] - hp
	Target.timeToDie = hp_lost > 0 and min(Target.timeToDieMax, hp / (hp_lost / 3)) or Target.timeToDieMax
end

local function UseCooldown(ability, overwrite, always)
	if always or (MonkSeeMonkDo.cooldown and (not MonkSeeMonkDo.boss_only or Target.boss) and (not var.cd or overwrite)) then
		var.cd = ability
	end
end

local function UseTouch(ability, overwrite)
	if not var.touch or overwrite then
		var.touch = ability
	end
end

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = function() end
}

APL[SPEC.BREWMASTER] = function()
	if TimeInCombat() == 0 then
		if MonkSeeMonkDo.pot and PotionOfProlongedPower:usable() then
			UseCooldown(PotionOfProlongedPower)
		end
	end
end

APL[SPEC.MISTWEAVER] = function()
	if TimeInCombat() == 0 then
		if MonkSeeMonkDo.pot and PotionOfProlongedPower:usable() then
			UseCooldown(PotionOfProlongedPower)
		end
	end
end

APL[SPEC.WINDWALKER] = function()
	if TimeInCombat() == 0 then
		if MonkSeeMonkDo.pot and PotionOfProlongedPower:usable() then
			UseCooldown(PotionOfProlongedPower)
		end
		if ChiBurst.known and ChiBurst:usable() then
			return ChiBurst
		end
		if ChiWave.known and ChiWave:usable() then
			return ChiWave
		end
	end
	if MonkSeeMonkDo.pot and PotionOfProlongedPower:usable() and (Serenity:up() or StormEarthAndFire:up() or BloodlustActive() or Target.timeToDie <= 60) then
		UseCooldown(PotionOfProlongedPower)
	end
	if TouchOfDeath:usable() and TouchOfDeath:down() and not TouchOfDeath:previous() and Target.timeToDie < 12 and Target.timeToDie > 8 then
		UseTouch(TouchOfDeath)
	end
	if Serenity.known then
		if Serenity:up() then
			local serenity = APL.WW_SERENITY()
			if serenity then
				return serenity
			end
		elseif Serenity:usable() and Serenity:down() and (StrikeOfTheWindlord:ready(8) or FistsOfFury:ready(4) or RisingSunKick:ready(1)) then
			if TigerPalm:usable() and not (TigerPalm:previous() or EnergizingElixir:previous()) and Energy() >= EnergyMax() and Chi() < 1 then
				return TigerPalm
			end
			UseCooldown(Serenity)
		end
	else
		local sef
		if StormEarthAndFire:up() or StormEarthAndFire:charges() == 2 then
			sef = APL.WW_SEF()
		elseif StormEarthAndFire:charges() == 1 then
			if ItemEquipped.DrinkingHornCover then
				if ((StrikeOfTheWindlord:ready(18) and FistsOfFury:ready(12) and Chi() >= 3 and RisingSunKick:ready(1)) or Target.timeToDie <= 25 or TouchOfDeath:cooldown() > 112) then
					sef = APL.WW_SEF()
				end
			else
				if ((StrikeOfTheWindlord:ready(14) and FistsOfFury:ready(6) and Chi() >= 3 and RisingSunKick:ready(1)) or Target.timeToDie <= 15 or TouchOfDeath:cooldown() > 112) then
					sef = APL.WW_SEF()
				end
			end
		end
		if sef then
			return sef
		end
	end
	if Enemies() > 3 then
		return APL.WW_AOE()
	end
	return APL.WW_ST()
end

APL.WW_SERENITY = function()
	APL.WW_CD()
	if RisingSunKick:usable() and Enemies() < 3 then
		return RisingSunKick
	end
	if StrikeOfTheWindlord:usable() then
		return StrikeOfTheWindlord
	end
	if FistsOfFury:usable() and not ItemEquipped.DrinkingHornCover and ((RisingSunKick:previous() and StrikeOfTheWindlord:cooldown() > 4 * HasteFactor()) or (StrikeOfTheWindlord:previous() and PreviousGCD[2] == RisingSunKick)) then
		return FistsOfFury
	end
	if BlackoutKick:usable() and not BlackoutKick:previous() and Enemies() < 2 and (StrikeOfTheWindlord:previous() or FistsOfFury:previous()) then
		return BlackoutKick
	end
	if FistsOfFury:usable() and (RisingSunKick:cooldown() > 1 or Enemies() > 1) and (not ItemEquipped.DrinkingHornCover or BloodlustActive() or (ItemEquipped.DrinkingHornCover and Tier.T20P >= 4 and PressurePoint:remains() < 2)) then
		return FistsOfFury
	end
	if SpinningCraneKick:usable() and not SpinningCraneKick:previous() and Enemies() >= 3 then
		return SpinningCraneKick
	end
	if RushingJadeWind.known and RushingJadeWind:usable() and not RushingJadeWind:previous() and RushingJadeWind:down() and Serenity:remains() > 4 then
		return RushingJadeWind
	end
	if RisingSunKick:usable() then
		return RisingSunKick
	end
	if RushingJadeWind.known and RushingJadeWind:usable() and not RushingJadeWind:previous() and RushingJadeWind:down() and Enemies() > 1 then
		return RushingJadeWind
	end
	if SpinningCraneKick:usable() and not SpinningCraneKick:previous() then
		return SpinningCraneKick
	end
	if BlackoutKick:usable() and not BlackoutKick:previous() then
		return BlackoutKick
	end
end

APL.WW_SEF = function()
	if TigerPalm:usable() and MarkOfTheCrane:down() and not (TigerPalm:previous() or EnergizingElixir:previous()) and Energy() >= EnergyMax() and Chi() < 1 then
		return TigerPalm
	end
	APL.WW_CD()
	if StormEarthAndFire:down() and StormEarthAndFire:usable() then
		UseCooldown(StormEarthAndFire)
	end
end

APL.WW_CD = function()
	if InvokeXuenTheWhiteTiger.known and InvokeXuenTheWhiteTiger:usable() then
		UseCooldown(InvokeXuenTheWhiteTiger)
	end
	if ArcaneTorrent.known and ArcaneTorrent:usable() and Chi() < 3 and (not Serenity.known or Serenity:down()) and (RisingSunKick:ready(1) or StrikeOfTheWindlord:ready(1) or FistsOfFury:ready(1)) then
		UseCooldown(ArcaneTorrent)
	end
	if TouchOfDeath:usable() and TouchOfDeath:down() and not TouchOfDeath:previous() and Target.timeToDie > 8 then
		if Serenity.known and Serenity:ready(3) and (StrikeOfTheWindlord:ready(11) or FistsOfFury:ready(7) or RisingSunKick:ready(4)) then
			UseTouch(TouchOfDeath)
		end
		if ItemEquipped.HiddenMastersForbiddenTouch and HiddenMastersForbiddenTouch:up() then
			UseTouch(TouchOfDeath)
		end
	end
end

APL.WW_ST = function()
	APL.WW_CD()
	if EnergizingElixir.known and EnergizingElixir:usable() and not TigerPalm:previous() and Chi() <= 1 and (RisingSunKick:ready() or StrikeOfTheWindlord:ready() or Energy() < 50) then
		UseCooldown(EnergizingElixir)
	end
	if BlackoutKick:usable() and Tier.T21P >= 4 and not BlackoutKick:previous() and BlackoutKickProc:up() and ChiDeficit() >= 1 then
		return BlackoutKick
	end
	if TigerPalm:usable() and not (TigerPalm:previous() or EnergizingElixir:previous()) and EnergyTimeToMax() <= 1 and ChiDeficit() >= 2 then
		return TigerPalm
	end
	if StrikeOfTheWindlord:usable() and (not Serenity.known or Serenity:cooldown() >= 10) then
		return StrikeOfTheWindlord
	end
	if WhirlingDragonPunch.known and WhirlingDragonPunch:usable() then
		return WhirlingDragonPunch
	end
	if RisingSunKick:usable() and ((Chi() >= 3 and Energy() >= 40) or Chi() >= 5) and (not Serenity.known or Serenity:cooldown() >= 6) then
		return RisingSunKick
	end
	if FistsOfFury:usable() and EnergyTimeToMax() > 2 then
		if Serenity.known then
			if not ItemEquipped.DrinkingHornCover and not Serenity:ready(5) then
				return FistsOfFury
			end
			if ItemEquipped.DrinkingHornCover and (not Serenity:ready(15) or Serenity:ready(4)) then
				return FistsOfFury
			end
		else
			return FistsOfFury
		end
	end
	if FistsOfFury:usable() and Chi() <= 5 and not RisingSunKick:ready(3.5) then
		return FistsOfFury
	end
	if RisingSunKick:usable() and (not Serenity.known or Serenity:cooldown() >= 5) then
		return RisingSunKick
	end
	if Tier.T21P >= 4 then
		if BlackoutKick:usable() and not BlackoutKick:previous() and ChiDeficit() >= 1 and (Tier.T19P < 2 or Serenity.known) then
			return BlackoutKick
		end
		if SpinningCraneKick:usable() and not SpinningCraneKick:previous() and (Enemies() >= 3 or (ChiDeficit() >= 0 and BlackoutKickProc:up())) then
			return SpinningCraneKick
		end
	end
	if TigerPalm:usable() and not TigerPalm:previous() and FistsOfFury:ready(GCD()) and Chi() < FistsOfFury:chiCost() then
		if Serenity.known then
			if not ItemEquipped.DrinkingHornCover and not Serenity:ready(4) then
				return TigerPalm
			end
			if ItemEquipped.DrinkingHornCover and (not Serenity:ready(14) or Serenity:ready(3)) then
				return TigerPalm
			end
		else
			return TigerPalm
		end
	end
	if ItemEquipped.TheEmperorsCapacitor and CracklingJadeLightning:usable() and EnergyTimeToMax() > 3 and (TheEmperorsCapacitor:stack() >= 19 or (Serenity.known and TheEmperorsCapacitor:stack() >= 14 and Serenity:ready(13))) then
		return CracklingJadeLightning
	end
	if SpinningCraneKick:usable() and Enemies() >= 3 and not SpinningCraneKick:previous() then
		return SpinningCraneKick
	end
	if RushingJadeWind.known and RushingJadeWind:usable() and not RushingJadeWind:previous() and ChiDeficit() > 1 then
		return RushingJadeWind
	end
	if BlackoutKick:usable() and not BlackoutKick:previous() and (Chi() > 1 or BlackoutKickProc:up() or (EnergizingElixir.known and EnergizingElixir:cooldown() < FistsOfFury:cooldown())) and (((RisingSunKick:cooldown() > 1 and StrikeOfTheWindlord:cooldown() > 1) or Chi() > 4) and (FistsOfFury:cooldown() > 1 or Chi() > 2) or TigerPalm:previous()) then
		return BlackoutKick
	end
	if not Serenity.known and TouchOfDeath:usable() and Target.timeToDie > 8 and TouchOfDeath:down() and not TouchOfDeath:previous() and Chi() >= 2 then
		UseTouch(TouchOfDeath)
	end
	if ChiWave.known and ChiWave:usable() and Chi() <= 3 and EnergyTimeToMax() > 1 and (RisingSunKick:cooldown() >= 5 or WhirlingDragonPunch:cooldown() >= 5) then
		UseCooldown(ChiWave)
	end
	if ChiBurst.known and ChiBurst:usable() and Chi() <= 3 and EnergyTimeToMax() > 1 and (RisingSunKick:cooldown() >= 5 or WhirlingDragonPunch:cooldown() >= 5) then
		UseCooldown(ChiBurst)
	end
	if TigerPalm:usable() and not (TigerPalm:previous() or EnergizingElixir:previous()) and (ChiDeficit() >= 2 or EnergyTimeToMax() < 3) then
		return TigerPalm
	end
	if ChiWave.known and ChiWave:usable() then
		UseCooldown(ChiWave)
	end
	if ChiBurst.known and ChiBurst:usable() then
		UseCooldown(ChiBurst)
	end
	if not Serenity.known and TouchOfDeath:usable() and Target.timeToDie > 8 and TouchOfDeath:down() and not TouchOfDeath:previous() then
		UseTouch(TouchOfDeath)
	end
	if Chi() == 0 and TigerPalm:usable() then
		return TigerPalm
	end
end

APL.WW_AOE = function()
	APL.WW_CD()
	if EnergizingElixir.known and EnergizingElixir:usable() and not TigerPalm:previous() and Chi() <= 1 and (RisingSunKick:ready() or StrikeOfTheWindlord:ready() or Energy() < 50) then
		UseCooldown(EnergizingElixir)
	end
	if FistsOfFury:usable() and EnergyTimeToMax() > 2 then
		if Serenity.known then
			if not ItemEquipped.DrinkingHornCover and not Serenity:ready(5) then
				return FistsOfFury
			end
			if ItemEquipped.DrinkingHornCover and (not Serenity:ready(15) or Serenity:ready(4)) then
				return FistsOfFury
			end
		else
			return FistsOfFury
		end
	end
	if FistsOfFury:usable() and Chi() <= 5 and not RisingSunKick:ready(3.5) then
		return FistsOfFury
	end
	if WhirlingDragonPunch.known and WhirlingDragonPunch:usable() then
		return WhirlingDragonPunch
	end
	if StrikeOfTheWindlord:usable() and (not Serenity.known or Serenity:cooldown() >= 10) then
		return StrikeOfTheWindlord
	end
	if WhirlingDragonPunch.known and RisingSunKick:usable() and not RisingSunKick:previous() and WhirlingDragonPunch:cooldown() > GCD() and FistsOfFury:cooldown() > GCD() then
		return RisingSunKick
	end
	if TigerPalm:usable() and not TigerPalm:previous() and FistsOfFury:ready(GCD()) and Chi() < FistsOfFury:chiCost() then
		if Serenity.known then
			if not ItemEquipped.DrinkingHornCover and not Serenity:ready(4) then
				return TigerPalm
			end
			if ItemEquipped.DrinkingHornCover and (not Serenity:ready(14) or Serenity:ready(3)) then
				return TigerPalm
			end
		else
			return TigerPalm
		end
	end
	if RushingJadeWind.known and RushingJadeWind:usable() and not RushingJadeWind:previous() and ChiDeficit() > 1 then
		return RushingJadeWind
	end
	if ChiBurst.known and ChiBurst:usable() then
		UseCooldown(ChiBurst)
	end
	if SpinningCraneKick:usable() and not SpinningCraneKick:previous() then
		return SpinningCraneKick
	end
	if BlackoutKick:usable() and not BlackoutKick:previous() then
		if Tier.T21P >= 4 and ChiDeficit() >= 1 and (Tier.T19P < 2 or Serenity.known) then
			return BlackoutKick
		end
		if (Chi() > 1 or BlackoutKickProc:up() or (EnergizingElixir.known and EnergizingElixir:cooldown() < FistsOfFury:cooldown())) and (((RisingSunKick:cooldown() > 1 and StrikeOfTheWindlord:cooldown() > 1) or Chi() > 4) and (FistsOfFury:cooldown() > 1 or Chi() > 2) or TigerPalm:previous()) then
			return BlackoutKick
		end
	end
	if ItemEquipped.TheEmperorsCapacitor and CracklingJadeLightning:usable() and EnergyTimeToMax() > 3 and (TheEmperorsCapacitor:stack() >= 19 or (Serenity.known and TheEmperorsCapacitor:stack() >= 14 and Serenity:ready(13))) then
		return CracklingJadeLightning
	end
	if BlackoutKick:usable() and Tier.T21P >= 4 and not BlackoutKick:previous() and BlackoutKickProc:up() and ChiDeficit() >= 1 then
		return BlackoutKick
	end
	if not Serenity.known and TouchOfDeath:usable() and Target.timeToDie > 8 and TouchOfDeath:down() and not TouchOfDeath:previous() and Chi() >= 2 then
		UseTouch(TouchOfDeath)
	end
	if TigerPalm:usable() and not (TigerPalm:previous() or EnergizingElixir:previous()) and (ChiDeficit() >= 2 or EnergyTimeToMax() < 3) then
		return TigerPalm
	end
	if ChiWave.known and ChiWave:usable() then
		UseCooldown(ChiWave)
	end
	if not Serenity.known and TouchOfDeath:usable() and Target.timeToDie > 8 and TouchOfDeath:down() and not TouchOfDeath:previous() then
		UseTouch(TouchOfDeath)
	end
	if Chi() == 0 and TigerPalm:usable() then
		return TigerPalm
	end
end

APL.Interrupt = function()
	if SpearHandStrike.known and SpearHandStrike:usable() then
		return SpearHandStrike
	end
	if ArcaneTorrent.known and ArcaneTorrent:ready() then
		return ArcaneTorrent
	end
end

-- End Action Priority Lists

local function UpdateInterrupt()
	local _, _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
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
	if not MonkSeeMonkDo.glow.blizzard then
		actionButton.overlay:Hide()
	end
end

hooksecurefunc('ActionButton_ShowOverlayGlow', DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

local function UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = MonkSeeMonkDo.glow.color.r
	local g = MonkSeeMonkDo.glow.color.g
	local b = MonkSeeMonkDo.glow.color.b
	for i = 1, #glows do
		glow = glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * MonkSeeMonkDo.scale.glow, h * 0.2 * MonkSeeMonkDo.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * MonkSeeMonkDo.scale.glow, -h * 0.2 * MonkSeeMonkDo.scale.glow)
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
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	elseif ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	else
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
		if Dominos then
			for i = 1, 60 do
				GenerateGlow(_G['DominosActionButton' .. i])
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
			(MonkSeeMonkDo.glow.main and var.main and icon == var.main.icon) or
			(MonkSeeMonkDo.glow.cooldown and var.cd and icon == var.cd.icon) or
			(MonkSeeMonkDo.glow.interrupt and var.interrupt and icon == var.interrupt.icon) or
			(MonkSeeMonkDo.glow.touch and var.touch and icon == var.touch.icon)
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

function events:PLAYER_LOGIN()
	CreateOverlayGlows()
end

local function ShouldHide()
	return (currentSpec == SPEC.NONE or
		   (currentSpec == SPEC.BREWMASTER and MonkSeeMonkDo.hide.brewmaster) or
		   (currentSpec == SPEC.MISTWEAVER and MonkSeeMonkDo.hide.mistweaver) or
		   (currentSpec == SPEC.WINDWALKER and MonkSeeMonkDo.hide.windwalker))

end

local function Disappear()
	msmdPanel:Hide()
	msmdPanel.icon:Hide()
	msmdPanel.border:Hide()
	msmdPreviousPanel:Hide()
	msmdCooldownPanel:Hide()
	msmdInterruptPanel:Hide()
	msmdTouchPanel:Hide()
	var.main, var.last_main = nil
	var.cd, var.last_cd = nil
	var.interrupt = nil
	var.touch, var.last_touch = nil
	UpdateGlows()
end

function MonkSeeMonkDo_ToggleTargetMode()
	local mode = targetMode + 1
	MonkSeeMonkDo_SetTargetMode(mode > #targetModes[currentSpec] and 1 or mode)
end

function MonkSeeMonkDo_ToggleTargetModeReverse()
	local mode = targetMode - 1
	MonkSeeMonkDo_SetTargetMode(mode < 1 and #targetModes[currentSpec] or mode)
end

function MonkSeeMonkDo_SetTargetMode(mode)
	targetMode = min(mode, #targetModes[currentSpec])
	msmdPanel.targets:SetText(targetModes[currentSpec][targetMode][2])
end

function Equipped(name, slot)
	local function SlotMatches(name, slot)
		local ilink = GetInventoryItemLink('player', slot)
		if ilink then
			local iname = ilink:match('%[(.*)%]')
			return (iname and iname:find(name))
		end
		return false
	end
	if slot then
		return SlotMatches(name, slot)
	end
	local i
	for i = 1, 19 do
		if SlotMatches(name, i) then
			return true
		end
	end
	return false
end

function EquippedTier(name)
	local slot = { 1, 3, 5, 7, 10, 15 }
	local equipped, i = 0
	for i = 1, #slot do
		if Equipped(name, slot) then
			equipped = equipped + 1
		end
	end
	return equipped
end

local function UpdateDraggable()
	msmdPanel:EnableMouse(MonkSeeMonkDo.aoe or not MonkSeeMonkDo.locked)
	if MonkSeeMonkDo.aoe then
		msmdPanel.button:Show()
	else
		msmdPanel.button:Hide()
	end
	if MonkSeeMonkDo.locked then
		msmdPanel:SetScript('OnDragStart', nil)
		msmdPanel:SetScript('OnDragStop', nil)
		msmdPanel:RegisterForDrag(nil)
		msmdPreviousPanel:EnableMouse(false)
		msmdCooldownPanel:EnableMouse(false)
		msmdInterruptPanel:EnableMouse(false)
		msmdTouchPanel:EnableMouse(false)
	else
		if not MonkSeeMonkDo.aoe then
			msmdPanel:SetScript('OnDragStart', msmdPanel.StartMoving)
			msmdPanel:SetScript('OnDragStop', msmdPanel.StopMovingOrSizing)
			msmdPanel:RegisterForDrag('LeftButton')
		end
		msmdPreviousPanel:EnableMouse(true)
		msmdCooldownPanel:EnableMouse(true)
		msmdInterruptPanel:EnableMouse(true)
		msmdTouchPanel:EnableMouse(true)
	end
end

local function OnResourceFrameHide()
	if MonkSeeMonkDo.snap then
		msmdPanel:ClearAllPoints()
	end
end

local function OnResourceFrameShow()
	if MonkSeeMonkDo.snap then
		msmdPanel:ClearAllPoints()
		if MonkSeeMonkDo.snap == 'above' then
			msmdPanel:SetPoint('BOTTOM', NamePlatePlayerResourceFrame, 'TOP', 0, 18)
		elseif MonkSeeMonkDo.snap == 'below' then
			msmdPanel:SetPoint('TOP', NamePlatePlayerResourceFrame, 'BOTTOM', 0, -4)
		end
	end
end

NamePlatePlayerResourceFrame:HookScript("OnHide", OnResourceFrameHide)
NamePlatePlayerResourceFrame:HookScript("OnShow", OnResourceFrameShow)

local function UpdateSerenityOverlay()
	local remains = Serenity:remains()
	if remains > 0 then
		if not msmdPanel.serenityOverlayOn then
			msmdPanel.serenityOverlayOn = true
			msmdPanel.border:SetTexture('Interface\\AddOns\\MonkSeeMonkDo\\serenity.blp')
		end
		msmdPanel.text:SetText(format('%.1f', remains))
	elseif msmdPanel.serenityOverlayOn then
		msmdPanel.serenityOverlayOn = false
		msmdPanel.border:SetTexture('Interface\\AddOns\\MonkSeeMonkDo\\border.blp')
		msmdPanel.text:SetText()
	end
end

local function UpdateAlpha()
	msmdPanel:SetAlpha(MonkSeeMonkDo.alpha)
	msmdPreviousPanel:SetAlpha(MonkSeeMonkDo.alpha)
	msmdCooldownPanel:SetAlpha(MonkSeeMonkDo.alpha)
	msmdInterruptPanel:SetAlpha(MonkSeeMonkDo.alpha)
	msmdTouchPanel:SetAlpha(MonkSeeMonkDo.alpha)
end

local function UpdateHealthArray()
	Target.healthArray = {}
	local i
	for i = 1, floor(3 / MonkSeeMonkDo.frequency) do
		Target.healthArray[i] = 0
	end
end

local function UpdateCombat()
	abilityTimer = 0
	UpdateVars()
	var.main = APL[currentSpec]()
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
	if var.touch ~= var.last_touch then
		if var.touch then
			msmdTouchPanel.icon:SetTexture(var.touch.icon)
			msmdTouchPanel:Show()
		else
			msmdTouchPanel:Hide()
		end
	end
	if MonkSeeMonkDo.dimmer then
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
	if MonkSeeMonkDo.interrupt then
		UpdateInterrupt()
	end
	if Serenity.known then
		UpdateSerenityOverlay()
	end
	UpdateGlows()
end

function events:SPELL_UPDATE_COOLDOWN()
	if MonkSeeMonkDo.spell_swipe then
		local start, duration
		local _, _, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(Resuscitate.spellId)
			if start <= 0 then
				return msmdPanel.swipe:Hide()
			end
		end
		msmdPanel.swipe:SetCooldown(start, duration)
		msmdPanel.swipe:Show()
	end
end

function events:ADDON_LOADED(name)
	if name == 'MonkSeeMonkDo' then
		if not MonkSeeMonkDo.frequency then
			print('It looks like this is your first time running MonkSeeMonkDo, why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_MonkSeeMonkDo1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] MonkSeeMonkDo is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitializeVariables()
		UpdateHealthArray()
		UpdateDraggable()
		UpdateAlpha()
		msmdPanel:SetScale(MonkSeeMonkDo.scale.main)
		msmdPreviousPanel:SetScale(MonkSeeMonkDo.scale.previous)
		msmdCooldownPanel:SetScale(MonkSeeMonkDo.scale.cooldown)
		msmdInterruptPanel:SetScale(MonkSeeMonkDo.scale.interrupt)
		msmdTouchPanel:SetScale(MonkSeeMonkDo.scale.touch)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED(timeStamp, eventType, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags, dstRaidFlags, spellId, spellName)
	if MonkSeeMonkDo.auto_aoe and (eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL') then
		AutoAoeRemoveTarget(dstGUID)
	end
	if srcGUID ~= UnitGUID('player') then
		return
	end
	if eventType == 'SPELL_CAST_SUCCESS' then
		local castedAbility = abilityBySpellId[spellId]
		if castedAbility then
			var.last_ability = castedAbility
			if var.last_ability.triggers_gcd then
				PreviousGCD[10] = nil
				table.insert(PreviousGCD, 1, castedAbility)
			end
			if MonkSeeMonkDo.previous and msmdPanel:IsVisible() then
				msmdPreviousPanel.border:SetTexture('Interface\\AddOns\\MonkSeeMonkDo\\border.blp')
				msmdPreviousPanel.icon:SetTexture(var.last_ability.icon)
				msmdPreviousPanel:Show()
			end
		end
		return
	end
	if eventType == 'SPELL_MISSED' then
		if MonkSeeMonkDo.previous and msmdPanel:IsVisible() and MonkSeeMonkDo.miss_effect and var.last_ability and spellId == var.last_ability.spellId then
			msmdPreviousPanel.border:SetTexture('Interface\\AddOns\\MonkSeeMonkDo\\misseffect.blp')
		end
		return
	end
	if eventType == 'SPELL_DAMAGE' then
		if MonkSeeMonkDo.auto_aoe then
			local i
			for i = 1, #abilitiesAutoAoe do
				if spellId == abilitiesAutoAoe[i].spellId or spellId == abilitiesAutoAoe[i].spellId2 then
					abilitiesAutoAoe[i]:recordTargetHit(dstGUID)
				end
			end
		end
		return
	end
	if eventType == 'SPELL_AURA_APPLIED' then
		if spellId == SephuzsSecret.spellId then
			SephuzsSecret.cooldown_start = GetTime()
			return
		end
		return
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
		Target.hostile = true
		local i
		for i = 1, #Target.healthArray do
			Target.healthArray[i] = 0
		end
		if MonkSeeMonkDo.always_on then
			UpdateCombat()
			msmdPanel:Show()
			return true
		end
		return
	end
	if guid ~= Target.guid then
		Target.guid = UnitGUID('target')
		local i
		for i = 1, #Target.healthArray do
			Target.healthArray[i] = UnitHealth('target')
		end
	end
	Target.level = UnitLevel('target')
	Target.boss = Target.level == -1 or (Target.level >= UnitLevel('player') + 2 and not UnitInRaid('player'))
	Target.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if Target.hostile or MonkSeeMonkDo.always_on then
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
	if MonkSeeMonkDo.auto_aoe then
		local guid
		for guid in next, Targets do
			Targets[guid] = nil
		end
		MonkSeeMonkDo_SetTargetMode(1)
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	Tier.T19P = EquippedTier(" of Enveloped Dissonance")
	Tier.T20P = EquippedTier("Xuen's ")
	Tier.T21P = EquippedTier(" of Chi'Ji")
	ItemEquipped.DrinkingHornCover = Equipped("Drinking Horn Cover")
	ItemEquipped.TheEmperorsCapacitor = Equipped("The Emperor's Capacitor")
	ItemEquipped.HiddenMastersForbiddenTouch = Equipped("Hidden Master's Forbidden Touch")
	ItemEquipped.SephuzsSecret = Equipped("Sephuz's Secret")
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName == 'player' then
		local i
		for i = 1, #abilities do
			abilities[i].name, _, abilities[i].icon = GetSpellInfo(abilities[i].spellId)
			abilities[i].known = IsPlayerSpell(abilities[i].spellId) or (abilities[i].spellId2 and IsPlayerSpell(abilities[i].spellId2))
		end
		currentSpec = GetSpecialization() or 0
		MonkSeeMonkDo_SetTargetMode(1)
		UpdateTargetInfo()
	end
end

function events:PLAYER_ENTERING_WORLD()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	if #glows == 0 then
		CreateOverlayGlows()
	end
	UpdateVars()
end

msmdPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			MonkSeeMonkDo_ToggleTargetMode()
		elseif button == 'RightButton' then
			MonkSeeMonkDo_ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			MonkSeeMonkDo_SetTargetMode(1)
		end
	end
end)

msmdPanel:SetScript('OnUpdate', function(self, elapsed)
	abilityTimer = abilityTimer + elapsed
	if abilityTimer >= MonkSeeMonkDo.frequency then
		if MonkSeeMonkDo.auto_aoe then
			local i
			for i = 1, #abilitiesAutoAoe do
				abilitiesAutoAoe[i]:updateTargetsHit()
			end
		end
		UpdateCombat()
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
			MonkSeeMonkDo.locked = msg[2] == 'on'
			UpdateDraggable()
		end
		return print('MonkSeeMonkDo - Locked: ' .. (MonkSeeMonkDo.locked and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				MonkSeeMonkDo.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				MonkSeeMonkDo.snap = 'below'
			else
				MonkSeeMonkDo.snap = false
				msmdPanel:ClearAllPoints()
			end
			OnResourceFrameShow()
		end
		return print('MonkSeeMonkDo - Snap to Blizzard combat resources frame: ' .. (MonkSeeMonkDo.snap and ('|cFF00C000' .. MonkSeeMonkDo.snap) or '|cFFC00000Off'))
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				MonkSeeMonkDo.scale.previous = tonumber(msg[3]) or 0.7
				msmdPreviousPanel:SetScale(MonkSeeMonkDo.scale.previous)
			end
			return print('MonkSeeMonkDo - Previous ability icon scale set to: |cFFFFD000' .. MonkSeeMonkDo.scale.previous .. '|r times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				MonkSeeMonkDo.scale.main = tonumber(msg[3]) or 1
				msmdPanel:SetScale(MonkSeeMonkDo.scale.main)
			end
			return print('MonkSeeMonkDo - Main ability icon scale set to: |cFFFFD000' .. MonkSeeMonkDo.scale.main .. '|r times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				MonkSeeMonkDo.scale.cooldown = tonumber(msg[3]) or 0.7
				msmdCooldownPanel:SetScale(MonkSeeMonkDo.scale.cooldown)
			end
			return print('MonkSeeMonkDo - Cooldown ability icon scale set to: |cFFFFD000' .. MonkSeeMonkDo.scale.cooldown .. '|r times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				MonkSeeMonkDo.scale.interrupt = tonumber(msg[3]) or 0.4
				msmdInterruptPanel:SetScale(MonkSeeMonkDo.scale.interrupt)
			end
			return print('MonkSeeMonkDo - Interrupt ability icon scale set to: |cFFFFD000' .. MonkSeeMonkDo.scale.interrupt .. '|r times')
		end
		if startsWith(msg[2], 'to') then
			if msg[3] then
				MonkSeeMonkDo.scale.touch = tonumber(msg[3]) or 0.4
				msmdTouchPanel:SetScale(MonkSeeMonkDo.scale.touch)
			end
			return print('MonkSeeMonkDo - Touch cooldown ability icon scale set to: |cFFFFD000' .. MonkSeeMonkDo.scale.touch .. '|r times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				MonkSeeMonkDo.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return print('MonkSeeMonkDo - Action button glow scale set to: |cFFFFD000' .. MonkSeeMonkDo.scale.glow .. '|r times')
		end
		return print('MonkSeeMonkDo - Default icon scale options: |cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000pet 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			MonkSeeMonkDo.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UpdateAlpha()
		end
		return print('MonkSeeMonkDo - Icon transparency set to: |cFFFFD000' .. MonkSeeMonkDo.alpha * 100 .. '%|r')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			MonkSeeMonkDo.frequency = tonumber(msg[2]) or 0.05
			UpdateHealthArray()
		end
		return print('MonkSeeMonkDo - Calculation frequency: Every |cFFFFD000' .. MonkSeeMonkDo.frequency .. '|r seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				MonkSeeMonkDo.glow.main = msg[3] == 'on'
				UpdateGlows()
			end
			return print('MonkSeeMonkDo - Glowing ability buttons (main icon): ' .. (MonkSeeMonkDo.glow.main and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'cd' then
			if msg[3] then
				MonkSeeMonkDo.glow.cooldown = msg[3] == 'on'
				UpdateGlows()
			end
			return print('MonkSeeMonkDo - Glowing ability buttons (cooldown icon): ' .. (MonkSeeMonkDo.glow.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				MonkSeeMonkDo.glow.interrupt = msg[3] == 'on'
				UpdateGlows()
			end
			return print('MonkSeeMonkDo - Glowing ability buttons (interrupt icon): ' .. (MonkSeeMonkDo.glow.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'to') then
			if msg[3] then
				MonkSeeMonkDo.glow.touch = msg[3] == 'on'
				UpdateGlows()
			end
			return print('MonkSeeMonkDo - Glowing ability buttons (touch cooldown icon): ' .. (MonkSeeMonkDo.glow.touch and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				MonkSeeMonkDo.glow.blizzard = msg[3] == 'on'
				UpdateGlows()
			end
			return print('MonkSeeMonkDo - Blizzard default proc glow: ' .. (MonkSeeMonkDo.glow.blizzard and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'color' then
			if msg[5] then
				MonkSeeMonkDo.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				MonkSeeMonkDo.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				MonkSeeMonkDo.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UpdateGlowColorAndScale()
			end
			return print('MonkSeeMonkDo - Glow color:', '|cFFFF0000' .. MonkSeeMonkDo.glow.color.r, '|cFF00FF00' .. MonkSeeMonkDo.glow.color.g, '|cFF0000FF' .. MonkSeeMonkDo.glow.color.b)
		end
		return print('MonkSeeMonkDo - Possible glow options: |cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000pet|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			MonkSeeMonkDo.previous = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('MonkSeeMonkDo - Previous ability icon: ' .. (MonkSeeMonkDo.previous and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'always' then
		if msg[2] then
			MonkSeeMonkDo.always_on = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('MonkSeeMonkDo - Show the MonkSeeMonkDo UI without a target: ' .. (MonkSeeMonkDo.always_on and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'cd' then
		if msg[2] then
			MonkSeeMonkDo.cooldown = msg[2] == 'on'
		end
		return print('MonkSeeMonkDo - Use MonkSeeMonkDo for cooldown energygement: ' .. (MonkSeeMonkDo.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			MonkSeeMonkDo.spell_swipe = msg[2] == 'on'
			if not MonkSeeMonkDo.spell_swipe then
				msmdPanel.swipe:Hide()
			end
		end
		return print('MonkSeeMonkDo - Spell casting swipe animation: ' .. (MonkSeeMonkDo.spell_swipe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			MonkSeeMonkDo.dimmer = msg[2] == 'on'
			if not MonkSeeMonkDo.dimmer then
				msmdPanel.dimmer:Hide()
			end
		end
		return print('MonkSeeMonkDo - Dim main ability icon when you don\'t have enough energy to use it: ' .. (MonkSeeMonkDo.dimmer and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'miss' then
		if msg[2] then
			MonkSeeMonkDo.miss_effect = msg[2] == 'on'
		end
		return print('MonkSeeMonkDo - Red border around previous ability when it fails to hit: ' .. (MonkSeeMonkDo.miss_effect and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			MonkSeeMonkDo.aoe = msg[2] == 'on'
			MonkSeeMonkDo_SetTargetMode(1)
			UpdateDraggable()
		end
		return print('MonkSeeMonkDo - Allow clicking main ability icon to toggle amount of targets (disables moving): ' .. (MonkSeeMonkDo.aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			MonkSeeMonkDo.boss_only = msg[2] == 'on'
		end
		return print('MonkSeeMonkDo - Only use cooldowns on bosses: ' .. (MonkSeeMonkDo.boss_only and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'b') then
				MonkSeeMonkDo.hide.brewmaster = not MonkSeeMonkDo.hide.brewmaster
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('MonkSeeMonkDo - Brewmaster specialization: |cFFFFD000' .. (MonkSeeMonkDo.hide.brewmaster and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'm') then
				MonkSeeMonkDo.hide.mistweaver = not MonkSeeMonkDo.hide.mistweaver
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('MonkSeeMonkDo - Mistweaver specialization: |cFFFFD000' .. (MonkSeeMonkDo.hide.mistweaver and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'w') then
				MonkSeeMonkDo.hide.windwalker = not MonkSeeMonkDo.hide.windwalker
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('MonkSeeMonkDo - Windwalker specialization: |cFFFFD000' .. (MonkSeeMonkDo.hide.windwalker and '|cFFC00000Off' or '|cFF00C000On'))
			end
		end
		return print('MonkSeeMonkDo - Possible hidespec options: |cFFFFD000brewmaster|r/|cFFFFD000mistweaver|r/|cFFFFD000windwalker|r - toggle disabling MonkSeeMonkDo for specializations')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			MonkSeeMonkDo.interrupt = msg[2] == 'on'
		end
		return print('MonkSeeMonkDo - Show an icon for interruptable spells: ' .. (MonkSeeMonkDo.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'auto' then
		if msg[2] then
			MonkSeeMonkDo.auto_aoe = msg[2] == 'on'
		end
		return print('MonkSeeMonkDo - Automatically change target mode on AoE spells: ' .. (MonkSeeMonkDo.auto_aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			MonkSeeMonkDo.pot = msg[2] == 'on'
		end
		return print('MonkSeeMonkDo - Show Prolonged Power potions in cooldown UI: ' .. (MonkSeeMonkDo.pot and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'reset' then
		msmdPanel:ClearAllPoints()
		msmdPanel:SetPoint('CENTER', 0, -169)
		msmdPreviousPanel:ClearAllPoints()
		msmdPreviousPanel:SetPoint('BOTTOMRIGHT', msmdPanel, 'BOTTOMLEFT', -10, -5)
		msmdCooldownPanel:ClearAllPoints()
		msmdCooldownPanel:SetPoint('BOTTOMLEFT', msmdPanel, 'BOTTOMRIGHT', 10, -5)
		msmdInterruptPanel:ClearAllPoints()
		msmdInterruptPanel:SetPoint('TOPLEFT', msmdPanel, 'TOPRIGHT', 16, 25)
		msmdTouchPanel:ClearAllPoints()
		msmdTouchPanel:SetPoint('TOPRIGHT', msmdPanel, 'TOPLEFT', -16, 25)
		return print('MonkSeeMonkDo - Position has been reset to default')
	end
	print('MonkSeeMonkDo (version: |cFFFFD000' .. GetAddOnMetadata('MonkSeeMonkDo', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the MonkSeeMonkDo UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the MonkSeeMonkDo UI to the Blizzard combat resources frame',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000touch|r/|cFFFFD000glow|r - adjust the scale of the MonkSeeMonkDo UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the MonkSeeMonkDo UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.05 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000touch|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the MonkSeeMonkDo UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use MonkSeeMonkDo for cooldown energygement',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough energy to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000brewmaster|r/|cFFFFD000mistweaver|r/|cFFFFD000windwalker|r - toggle disabling MonkSeeMonkDo for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'pot |cFF00C000on|r/|cFFC00000off|r - show Prolonged Power potions in cooldown UI',
		'|cFFFFD000reset|r - reset the location of the MonkSeeMonkDo UI to default',
	} do
		print('  ' .. SLASH_MonkSeeMonkDo1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Contact |cFF00FF96Fisticuffs|cFFFFD000-Mal\'Ganis|r or |cFFFFD000Spy#1955|r (the author of this addon)')
end

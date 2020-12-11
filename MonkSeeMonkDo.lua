local ADDON = 'MonkSeeMonkDo'
if select(2, UnitClass('player')) ~= 'MONK' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

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

SLASH_MonkSeeMonkDo1, SLASH_MonkSeeMonkDo2 = '/msmd', '/monk'
BINDING_HEADER_MONKSEEMONKDO = ADDON

local function InitOpts()
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
			windwalker = false,
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
		cd_ttd = 8,
		pot = false,
		trinket = true,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

-- specialization constants
local SPEC = {
	NONE = 0,
	BREWMASTER = 1,
	MISTWEAVER = 2,
	WINDWALKER = 3,
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	target_mode = 0,
	group_size = 1,
	gcd = 1.5,
	health = 0,
	health_max = 0,
	mana = 0,
	mana_max = 100,
	mana_regen = 0,
	energy = 0,
	energy_max = 100,
	energy_regen = 0,
	chi = 0,
	chi_max = 5,
	stagger = 0,
	moving = false,
	movement_speed = 100,
	last_swing_taken = 0,
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[165581] = true, -- Crest of Pa'ku (Horde)
		[174044] = true, -- Humming Black Dragonscale (parachute)
	},
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health_array = {},
	hostile = false,
	estimated_range = 30,
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
msmdPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
msmdPanel.border:Hide()
msmdPanel.dimmer = msmdPanel:CreateTexture(nil, 'BORDER')
msmdPanel.dimmer:SetAllPoints(msmdPanel)
msmdPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
msmdPanel.dimmer:Hide()
msmdPanel.swipe = CreateFrame('Cooldown', nil, msmdPanel, 'CooldownFrameTemplate')
msmdPanel.swipe:SetAllPoints(msmdPanel)
msmdPanel.text = CreateFrame('Frame', nil, msmdPanel)
msmdPanel.text:SetAllPoints(msmdPanel)
msmdPanel.text.tl = msmdPanel.text:CreateFontString(nil, 'OVERLAY')
msmdPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
msmdPanel.text.tl:SetPoint('TOPLEFT', msmdPanel, 'TOPLEFT', 2.5, -3)
msmdPanel.text.tl:SetJustifyH('LEFT')
msmdPanel.text.tr = msmdPanel.text:CreateFontString(nil, 'OVERLAY')
msmdPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
msmdPanel.text.tr:SetPoint('TOPRIGHT', msmdPanel, 'TOPRIGHT', -2.5, -3)
msmdPanel.text.tr:SetJustifyH('RIGHT')
msmdPanel.text.bl = msmdPanel.text:CreateFontString(nil, 'OVERLAY')
msmdPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
msmdPanel.text.bl:SetPoint('BOTTOMLEFT', msmdPanel, 'BOTTOMLEFT', 2.5, 3)
msmdPanel.text.bl:SetJustifyH('LEFT')
msmdPanel.text.br = msmdPanel.text:CreateFontString(nil, 'OVERLAY')
msmdPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
msmdPanel.text.br:SetPoint('BOTTOMRIGHT', msmdPanel, 'BOTTOMRIGHT', -2.5, 3)
msmdPanel.text.br:SetJustifyH('RIGHT')
msmdPanel.text.center = msmdPanel.text:CreateFontString(nil, 'OVERLAY')
msmdPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
msmdPanel.text.center:SetAllPoints(msmdPanel.text)
msmdPanel.text.center:SetJustifyH('CENTER')
msmdPanel.text.center:SetJustifyV('CENTER')
msmdPanel.button = CreateFrame('Button', nil, msmdPanel)
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
msmdPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
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
msmdCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
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
msmdInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
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
msmdExtraPanel.border:SetTexture(ADDON_PATH .. 'border.blp')

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.BREWMASTER] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
	[SPEC.MISTWEAVER] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
	[SPEC.WINDWALKER] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes[self.spec])
	self.enemies = self.target_modes[self.spec][self.target_mode][1]
	msmdPanel.text.br:SetText(self.target_modes[self.spec][self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes[self.spec] and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes[self.spec] or mode)
end

-- Target Mode Keybinding Wrappers
function MonkSeeMonkDo_SetTargetMode(mode)
	Player:SetTargetMode(mode)
end

function MonkSeeMonkDo_ToggleTargetMode()
	Player:ToggleTargetMode()
end

function MonkSeeMonkDo_ToggleTargetModeReverse()
	Player:ToggleTargetModeReverse()
end

-- End AoE

-- Start Auto AoE

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if unitId and self.ignored_units[tonumber(unitId)] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function autoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function autoAoe:Clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes[Player.spec], 1, -1 do
		if count >= Player.target_modes[Player.spec][i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function autoAoe:Purge()
	local update, guid, t
	for guid, t in next, self.targets do
		if Player.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if Player.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
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
		max_range = 40,
		velocity = 0,
		last_used = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if Player.spec == SPEC.MISTWEAVER then
		if self:ManaCost() > Player.mana then
			return false
		end
	else
		if not pool and self:EnergyCost() > Player.energy then
			return false
		end
		if Player.spec == SPEC.WINDWALKER and self:ChiCost() > Player.chi then
			return false
		end
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains()
	if self:Casting() or self:Traveling() then
		return self:Duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up()
	return self:Remains() > 0
end

function Ability:Down()
	return not self:Up()
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:Traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if Player.time - self.travel_start[Target.guid] < self.max_range / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:Up() and 1 or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:ManaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana_max) or 0
end

function Ability:EnergyCost()
	return self.energy_cost
end

function Ability:ChiCost()
	return self.chi_cost
end

function Ability:Charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
end

function Ability:Channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:CastEnergyRegen()
	return Player.energy_regen * self:CastTime() - self:EnergyCost()
end

function Ability:WontCapEnergy(reduction)
	return (Player.energy + self:CastEnergyRegen()) < (Player.energy_max - (reduction or 5))
end

function Ability:Previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {}
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	else
		self.auto_aoe.trigger = 'SPELL_DAMAGE'
	end
end

function Ability:RecordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:UpdateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:Update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:Duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration = self:Duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:RefreshAuraAll()
	local guid, aura, remains
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Monk Abilities
---- Multiple Specializations
local BlackoutKick = Ability:Add({205523, 100784}, false, true)
BlackoutKick.chi_cost = 1
BlackoutKick.triggers_combo = true
local CracklingJadeLightning = Ability:Add(117952, false, true)
CracklingJadeLightning.energy_cost = 20
CracklingJadeLightning.triggers_combo = true
local ExpelHarm = Ability:Add(322101, false, true)
ExpelHarm.mana_cost = 3
ExpelHarm.energy_cost = 15
ExpelHarm.triggers_combo = true
local FortifyingBrew = Ability:Add({243435, 115203}, true, true, 120954)
FortifyingBrew.buff_duration = 15
FortifyingBrew.cooldown_duration = 180
local LegSweep = Ability:Add(119381, false, true)
LegSweep.cooldown_duration = 60
local Resuscitate = Ability:Add(115178)
Resuscitate.mana_cost = 0.8
local RisingSunKick = Ability:Add(107428, false, true, 185099)
RisingSunKick.mana_cost = 1.5
RisingSunKick.chi_cost = 2
RisingSunKick.hasted_cooldown = true
RisingSunKick.triggers_combo = true
local SpearHandStrike = Ability:Add(116705, false, true)
SpearHandStrike.cooldown_duration = 15
SpearHandStrike.triggers_gcd = false
local SpinningCraneKick = Ability:Add({322729, 101546}, true, true, 107270)
SpinningCraneKick.mana_cost = 1
SpinningCraneKick.chi_cost = 2
SpinningCraneKick.triggers_combo = true
SpinningCraneKick:AutoAoe(true)
local TigerPalm = Ability:Add(100780, false, true)
TigerPalm.triggers_combo = true
------ Talents
local ChiBurst = Ability:Add(123986, false, true, 148135)
ChiBurst.cooldown_duration = 30
ChiBurst.triggers_combo = true
ChiBurst:AutoAoe()
local ChiWave = Ability:Add(115098, false, true)
ChiWave.cooldown_duration = 15
ChiWave.triggers_combo = true
local HealingElixir = Ability:Add(122281, true, true)
HealingElixir.cooldown_duration = 30
HealingElixir.requires_charge = true
local RushingJadeWind = Ability:Add(116847, true, true)
RushingJadeWind.cooldown_duration = 6
RushingJadeWind.buff_duration = 9
RushingJadeWind.chi_cost = 1
RushingJadeWind.hasted_duration = true
RushingJadeWind.hasted_cooldown = true
RushingJadeWind.triggers_combo = true
RushingJadeWind.damage = Ability:Add(148187, false, true)
RushingJadeWind.damage:AutoAoe(true)
------ Procs
---- Brewmaster
local BreathOfFire = Ability:Add(115181, false, true, 123725)
BreathOfFire.cooldown_duration = 15
BreathOfFire.buff_duration = 16
BreathOfFire:AutoAoe()
local CelestialBrew = Ability:Add(322507, true, true)
CelestialBrew.buff_duration = 8
CelestialBrew.cooldown_duration = 60
local Clash = Ability:Add(324312, false, true)
Clash.cooldown_duration = 30
local GiftOfTheOx = Ability:Add(124502, true, true, 124506)
GiftOfTheOx.buff_duration = 30
GiftOfTheOx.count = 0
GiftOfTheOx.lowhp = Ability:Add(124503, true, true)
GiftOfTheOx.expire = Ability:Add(178173, true, true)
GiftOfTheOx.pickup = Ability:Add(124507, true, true)
local KegSmash = Ability:Add(121253, false, true)
KegSmash.cooldown_duration = 8
KegSmash.buff_duration = 15
KegSmash.energy_cost = 40
KegSmash.hasted_cooldown = true
KegSmash:AutoAoe()
local PurifyingBrew = Ability:Add(119582, true, true)
PurifyingBrew.hasted_cooldown = true
PurifyingBrew.cooldown_duration = 20
PurifyingBrew.triggers_gcd = false
local Shuffle = Ability:Add(322120, true, true, 215479)
Shuffle.buff_duration = 3
local Stagger = Ability:Add(115069, false, true)
Stagger.auraTarget = 'player'
Stagger.tick_interval = 0.5
Stagger.buff_duration = 10
local ZenMeditation = Ability:Add(115176, true, true)
ZenMeditation.buff_duration = 8
ZenMeditation.cooldown_duration = 300
------ Talents
local BlackoutCombo = Ability:Add(196736, true, true, 228563)
BlackoutCombo.buff_duration = 15
local BlackOxBrew = Ability:Add(115399, false, false)
BlackOxBrew.cooldown_duration = 120
BlackOxBrew.triggers_gcd = false
local InvokeNiuzaoTheBlackOx = Ability:Add(132578, true, true)
InvokeNiuzaoTheBlackOx.cooldown_duration = 180
InvokeNiuzaoTheBlackOx.buff_duration = 45
local SpecialDelivery = Ability:Add(196730, false, true)
local Spitfire = Ability:Add(242580, true, true, 242581)
Spitfire.buff_duration = 2
------ Procs
local ElusiveBrawler = Ability:Add(117906, true, true, 195630) -- Mastery
ElusiveBrawler.buff_duration = 10
local PurifiedChi = Ability:Add(325092, true, true) -- Purifying Brew buff
PurifiedChi.buff_duration = 15
---- Mistweaver

------ Talents

------ Procs

---- Windwalker
local Disable = Ability:Add(116095, false, true)
Disable.energy_cost = 15
local FistsOfFury = Ability:Add(113656, false, true, 117418)
FistsOfFury.cooldown_duration = 24
FistsOfFury.buff_duration = 4
FistsOfFury.chi_cost = 3
FistsOfFury.hasted_cooldown = true
FistsOfFury.hasted_duration = true
FistsOfFury.triggers_combo = true
FistsOfFury:AutoAoe()
local FlyingSerpentKick = Ability:Add(101545, false, false, 123586)
FlyingSerpentKick.cooldown_duration = 25
FlyingSerpentKick.triggers_combo = true
FlyingSerpentKick:AutoAoe()
local InvokeXuenTheWhiteTiger = Ability:Add(123904, false, true)
InvokeXuenTheWhiteTiger.cooldown_duration = 120
InvokeXuenTheWhiteTiger.buff_duration = 24
local MarkOfTheCrane = Ability:Add(228287, false, true)
MarkOfTheCrane.buff_duration = 15
local StormEarthAndFire = Ability:Add(137639, true, true)
StormEarthAndFire.cooldown_duration = 90
StormEarthAndFire.buff_duration = 15
StormEarthAndFire.requires_charge = true
local TouchOfDeath = Ability:Add(322109, false, true)
TouchOfDeath.cooldown_duration = 180
TouchOfDeath.triggers_combo = true
local TouchOfKarma = Ability:Add(122470, true, true, 125174)
TouchOfKarma.cooldown_duration = 90
TouchOfKarma.buff_duration = 10
TouchOfKarma.triggers_gcd = false
------ Talents
local DanceOfChiJi = Ability:Add(325201, true, true, 325202)
DanceOfChiJi.buff_duration = 15
local EnergizingElixir = Ability:Add(115288, false, true)
EnergizingElixir.cooldown_duration = 60
local FistOfTheWhiteTiger = Ability:Add(261947, false, true, 261977)
FistOfTheWhiteTiger.cooldown_duration = 30
FistOfTheWhiteTiger.energy_cost = 40
FistOfTheWhiteTiger.triggers_combo = true
local HitCombo = Ability:Add(196740, true, true, 196741)
HitCombo.buff_duration = 10
local Serenity = Ability:Add(152173, true, true)
Serenity.cooldown_duration = 90
Serenity.buff_duration = 12
local WhirlingDragonPunch = Ability:Add(152175, false, true, 158221)
WhirlingDragonPunch.cooldown_duration = 24
WhirlingDragonPunch.hasted_cooldown = true
WhirlingDragonPunch.triggers_combo = true
WhirlingDragonPunch:AutoAoe(true)
------ Procs
BlackoutKick.free = Ability:Add(116768, true, true)
BlackoutKick.free.buff_duration = 15
local ComboStrikes = Ability:Add(115636, true, true) -- Mastery
-- Covenant abilities
local BonedustBrew = Ability:Add(325216, false, true) -- Necrolord
BonedustBrew.cooldown_duration = 60
BonedustBrew.buff_duration = 10
local FaelineStomp = Ability:Add(327104, true, true) -- Night Fae
FaelineStomp.cooldown_duration = 30
FaelineStomp.mana_cost = 4
FaelineStomp.triggers_combo = true
FaelineStomp:AutoAoe()
local FallenOrder = Ability:Add(310454, true, true) -- Venthyr
FallenOrder.cooldown_duration = 180
FallenOrder.buff_duration = 24
FallenOrder.mana_cost = 2
local WeaponsOfOrder = Ability:Add(310454, true, true) -- Kyrian
WeaponsOfOrder.cooldown_duration = 120
WeaponsOfOrder.buff_duration = 30
WeaponsOfOrder.mana_cost = 5
-- Soulbind conduits
local CalculatedStrikes = Ability:Add(336526, true, true)
CalculatedStrikes.conduit_id = 19
-- Legendary effects
local CharredPassions = Ability:Add(338138, true, true, 338140)
CharredPassions.buff_duration = 8
CharredPassions.bonus_id = 7076
local JadeIgnition = Ability:Add(337483, true, true, 337571) -- Chi Energy
JadeIgnition.buff_duration = 45
JadeIgnition.bonus_id = 7071
local LastEmperorsCapacitor = Ability:Add(337292, true, true, 337291) -- The Emperor's Capacitor
LastEmperorsCapacitor.bonus_id = 7069
local StormstoutsLastKeg = Ability:Add(337288, true, true)
StormstoutsLastKeg.bonus_id = 7077
-- PvP talents

-- Racials

-- Trinket effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:Cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
end

function InventoryItem:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function InventoryItem:Equipped()
	return self.equip_slot and true
end

function InventoryItem:Usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:Equipped() and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

-- Inventory Items
local GreaterFlaskOfEndlessFathoms = InventoryItem:Add(168652)
GreaterFlaskOfEndlessFathoms.buff = Ability:Add(298837, true, true)
local GreaterFlaskOfTheCurrents = InventoryItem:Add(168651)
GreaterFlaskOfTheCurrents.buff = Ability:Add(298836, true, true)
local PotionOfUnbridledFury = InventoryItem:Add(169299)
PotionOfUnbridledFury.buff = Ability:Add(300714, true, true)
PotionOfUnbridledFury.buff.triggers_gcd = false
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Player API

function Player:Enemies()
	return self.enemies
end

function Player:Health()
	return self.health
end

function Player:HealthMax()
	return self.health_max
end

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:Energy()
	return self.energy
end

function Player:EnergyRegen()
	return self.energy_regen
end

function Player:EnergyDeficit(energy)
	return (energy or self.energy_max) - self.energy
end

function Player:EnergyTimeToMax(energy)
	local deficit = self:EnergyDeficit(energy)
	if deficit <= 0 then
		return 0
	end
	return deficit / self:EnergyRegen()
end

function Player:Chi()
	return self.chi
end

function Player:ChiDeficit()
	return self.chi_max - self.chi
end

function Player:UnderAttack()
	return (Player.time - self.last_swing_taken) < 3
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	return 0
end

function Player:BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if not id then
			return false
		elseif (
			id == 2825 or   -- Bloodlust (Horde Monk)
			id == 32182 or  -- Heroism (Alliance Monk)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID, slot
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId)
	local i, id, link, item
	for i = 1, 19 do
		link = GetInventoryItemLink('player', i)
		if link then
			item = link:match('Hitem:%d+:([%d:]+)')
			if item then
				for id in item:gmatch('(%d+)') do
					if tonumber(id) == bonusId then
						return true
					end
				end
			end
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateAbilities()
	self.mana_max = UnitPowerMax('player', 0)
	self.energy_max = UnitPowerMax('player', 3)
	self.chi_max = UnitPowerMax('player', 12)

	local _, ability, spellId

	for _, ability in next, abilities.all do
		ability.known = false
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) then
				ability.known = true
				break
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) then
			ability.known = false -- spell is locked, do not mark as known
		end
		if ability.bonus_id then -- used for checking Legendary crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.conduit_id then
			ability.known = C_Soulbinds.IsConduitInstalledInSoulbind(C_Soulbinds.GetActiveSoulbindID(), ability.conduit_id)
		end
	end

	if self.spec == SPEC.BREWMASTER then
		BlackoutKick.cooldown_duration = 4
		BlackoutKick.hasted_cooldown = false
		ExpelHarm.cooldown_duration = 5
		RisingSunKick.cooldown_duration = 10
		SpinningCraneKick.energy_cost = 25
		TigerPalm.energy_cost = 25
	elseif self.spec == SPEC.MISTWEAVER then
		BlackoutKick.cooldown_duration = 3
		BlackoutKick.hasted_cooldown = true
		ExpelHarm.cooldown_duration = 15
		RisingSunKick.cooldown_duration = 12
		SpinningCraneKick.energy_cost = 0
		TigerPalm.energy_cost = 0
	elseif self.spec == SPEC.WINDWALKER then
		BlackoutKick.cooldown_duration = 0
		BlackoutKick.hasted_cooldown = false
		BlackoutKick.free.known = true
		ExpelHarm.cooldown_duration = 15
		MarkOfTheCrane.known = true
		RisingSunKick.cooldown_duration = 10
		SpinningCraneKick.energy_cost = 0
		TigerPalm.energy_cost = 50
	end
	GiftOfTheOx.lowhp.known = GiftOfTheOx.known
	GiftOfTheOx.expire.known = GiftOfTheOx.known
	GiftOfTheOx.pickup.known = GiftOfTheOx.known
	if Serenity.known then
		StormEarthAndFire.known = false
	end
	RushingJadeWind.damage.known = RushingJadeWind.known

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

-- End Player API

-- Start Target API

function Target:UpdateHealth()
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	table.remove(self.health_array, 1)
	self.health_array[25] = self.health
	self.timeToDieMax = self.health / Player.health_max * 15
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.health_array[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	if UI:ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = UnitLevel('player')
		self.hostile = true
		local i
		for i = 1, 25 do
			self.health_array[i] = 0
		end
		self:UpdateHealth()
		if Opt.always_on then
			UI:UpdateCombat()
			msmdPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			msmdPreviousPanel:Hide()
		end
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		local i
		for i = 1, 25 do
			self.health_array[i] = UnitHealth('target')
		end
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self:UpdateHealth()
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= UnitLevel('player') + 3) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health_max > Player.health_max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		msmdPanel:Show()
		return true
	end
end

-- End Target API

-- Start Ability Modifications

function Ability:Combo()
	return self.triggers_combo and ComboStrikes.last_ability ~= self
end

function Ability:ChiCost()
	if self.chi_cost > 0 and Serenity:Up() then
		return 0
	end
	return self.chi_cost
end

function BlackoutKick:ChiCost()
	if BlackoutKick.free:Up() then
		return 0
	end
	return Ability.ChiCost(self)
end

function SpinningCraneKick:ChiCost()
	if DanceOfChiJi:Up() then
		return 0
	end
	return Ability.ChiCost(self)
end

function ChiBurst:ChiCost()
	return Ability.ChiCost(self) - min(2, Player:Enemies())
end

function WhirlingDragonPunch:Usable()
	if FistsOfFury:Ready() or RisingSunKick:Ready() then
		return false
	end
	return Ability.Usable(self)
end

function TouchOfDeath:Usable()
	if Target.healthPercentage >= 15 and (Target.player or Target.health > Player.health) then
		return false
	end
	return Ability.Usable(self)
end

function GiftOfTheOx:Charges()
	return self.count
end

function Stagger:Remains()
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		elseif id == 124273 or id == 124274 or id == 124275 then
			return max(0, expires - Player.ctime)
		end
	end
	return 0
end

function Stagger:TicksRemaining()
	local remains = self:Remains()
	if remains <= 0 then
		return 0
	end
	return ceil(remains / self.tick_interval)
end

function Stagger:Tick()
	if Player.stagger <= 0 then
		return 0
	end
	return Player.stagger / max(1, self:TicksRemaining() + (Player.combat_start > 0 and -1 or 1))
end

function Stagger:TickPct()
	return self:Tick() / Player.health * 100
end

function Stagger:Light()
	return self:TickPct() < 2.5
end

function Stagger:Moderate()
	return between(self:TickPct(), 2.5, 5)
end

function Stagger:Heavy()
	return self:TickPct() > 5
end

function LegSweep:Usable()
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self)
end

function InvokeXuenTheWhiteTiger:Remains()
	local _, i, start, duration, icon
	for i = 1, 4 do
		_, _, start, duration, icon = GetTotemInfo(i)
		if icon and icon == self.icon then
			return max(0, duration - (Player.ctime - start) - Player.execute_remains)
		end
	end
	if (Player.time - self.last_used) < 1 then -- assume full duration immediately when cast
		return self.buff_duration
	end
	return 0
end
InvokeNiuzaoTheBlackOx.Remains = InvokeXuenTheWhiteTiger.Remains

-- End Ability Modifications

local function UseCooldown(ability, overwrite)
	if Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not Player.extra or overwrite then
		Player.extra = ability
	end
end

local function Pool(ability, extra)
	Player.pool_energy = ability:EnergyCost() + (extra or 0)
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
	if Player:TimeInCombat() == 0 then
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheCurrents:Usable() and GreaterFlaskOfTheCurrents.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
		if ChiBurst:Usable() then
			UseCooldown(ChiBurst)
		end
		if Clash:Usable() then
			UseCooldown(Clash)
		end
		if RushingJadeWind:Usable() then
			return RushingJadeWind
		end
		if ChiWave:Usable() then
			return ChiWave
		end
	end
--[[
actions+=/invoke_niuzao_the_black_ox,if=target.time_to_die>25
actions+=/touch_of_death,if=target.health.pct<=15
actions+=/weapons_of_order
actions+=/fallen_order
actions+=/bonedust_brew
actions+=/purifying_brew
# Black Ox Brew is currently used to either replenish brews based on less than half a brew charge available, or low energy to enable Keg Smash
actions+=/black_ox_brew,if=cooldown.purifying_brew.charges_fractional<0.5
actions+=/black_ox_brew,if=(energy+(energy.regen*cooldown.keg_smash.remains))<40&buff.blackout_combo.down&cooldown.keg_smash.up
# Offensively, the APL prioritizes KS on cleave, BoS else, with energy spenders and cds sorted below
actions+=/keg_smash,if=spell_targets>=2
actions+=/faeline_stomp,if=spell_targets>=2
# cast KS at top prio during WoO buff
actions+=/keg_smash,if=buff.weapons_of_order.up
# Celestial Brew priority whenever it took significant damage (adjust the health.max coefficient according to intensity of damage taken), and to dump excess charges before BoB.
actions+=/celestial_brew,if=buff.blackout_combo.down&incoming_damage_1999ms>(health.max*0.1+stagger.last_tick_damage_4)&buff.elusive_brawler.stack<2
actions+=/tiger_palm,if=talent.rushing_jade_wind.enabled&buff.blackout_combo.up&buff.rushing_jade_wind.up
actions+=/breath_of_fire,if=buff.charred_passions.down&runeforge.charred_passions.equipped
actions+=/blackout_kick
actions+=/keg_smash
actions+=/faeline_stomp
actions+=/rushing_jade_wind,if=buff.rushing_jade_wind.down
actions+=/spinning_crane_kick,if=buff.charred_passions.up
actions+=/breath_of_fire,if=buff.blackout_combo.down&(buff.bloodlust.down|(buff.bloodlust.up&dot.breath_of_fire_dot.refreshable))
actions+=/chi_burst
actions+=/chi_wave
actions+=/spinning_crane_kick,if=active_enemies>=3&cooldown.keg_smash.remains>gcd&(energy+(energy.regen*(cooldown.keg_smash.remains+execute_time)))>=65&(!talent.spitfire.enabled|!runeforge.charred_passions.equipped)
actions+=/tiger_palm,if=!talent.blackout_combo.enabled&cooldown.keg_smash.remains>gcd&(energy+(energy.regen*(cooldown.keg_smash.remains+gcd)))>=65
actions+=/arcane_torrent,if=energy<31
actions+=/rushing_jade_wind
]]
	Player.use_cds = Opt.cooldown and (Target.boss or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd))
	if HealingElixir:Usable() and (Player:HealthPct() < 60 or (Player:HealthPct() < 80 and HealingElixir:ChargesFractional() > 1.5)) then
		UseCooldown(HealingElixir)
	end
	if TouchOfDeath:Usable() and (Stagger:Heavy() or Stagger:Moderate()) then
		UseCooldown(TouchOfDeath)
	end
	if FortifyingBrew:Usable() and Player:HealthPct() < 15 then
		UseCooldown(FortifyingBrew)
	end
	if Player.use_cds or InvokeNiuzaoTheBlackOx:Up() then
		if InvokeNiuzaoTheBlackOx:Usable() and (Stagger:Heavy() or Stagger:Moderate()) and (Player.enemies >= 3 or Target.timeToDie > 25) then
			UseCooldown(InvokeNiuzaoTheBlackOx)
		elseif WeaponsOfOrder:Usable() then
			UseCooldown(WeaponsOfOrder)
		elseif FallenOrder:Usable() then
			UseCooldown(FallenOrder)
		end
	end
	if Player.use_cds or Player:Enemies() > 1 or InvokeNiuzaoTheBlackOx:Up() then
		if BonedustBrew:Usable() then
			UseCooldown(BonedustBrew)
		end
	end
	if PurifyingBrew:Usable() and (Stagger:Heavy() or (Stagger:Moderate() and (PurifyingBrew:ChargesFractional() >= (PurifyingBrew:MaxCharges() - 0.5) or CelestialBrew:Up() or CelestialBrew:Ready()))) then
		UseExtra(PurifyingBrew)
	end
	if BlackOxBrew:Usable() and not CelestialBrew:Ready() and (Stagger:Heavy() or Stagger:Moderate()) then
		if PurifyingBrew:ChargesFractional() < 0.5 then
			UseExtra(BlackOxBrew)
		elseif (Player:Energy() + (Player:EnergyRegen() * KegSmash:Cooldown())) < 40 and (not BlackoutCombo.known or BlackoutCombo:Down()) and KegSmash:Ready() then
			UseExtra(BlackOxBrew)
		end
	end
	if KegSmash:Usable() then
		if StormstoutsLastKeg.known then
			if KegSmash:FullRechargeTime() < Player.gcd then
				return KegSmash
			end
		elseif Player:Enemies() >= 2 or (KegSmash:Down() and BreathOfFire:Down() and BreathOfFire:Ready(Player.gcd)) then
			return KegSmash
		end
	end
	if FaelineStomp:Usable() and Player:Enemies() >= 2 then
		UseCooldown(FaelineStomp)
	end
	if WeaponsOfOrder.known and KegSmash:Usable() and WeaponsOfOrder:Up() then
		return KegSmash
	end
	if CelestialBrew:Usable() and (not BlackoutCombo.known or BlackoutCombo:Down()) and ElusiveBrawler:Stack() < 2 then
		UseExtra(CelestialBrew)
	end
	if BlackoutCombo.known and RushingJadeWind.known and TigerPalm:Usable() and BlackoutCombo:Up() and RushingJadeWind:Up() then
		return TigerPalm
	end
	if BreathOfFire:Usable() and ((CharredPassions.known and CharredPassions:Down()) or ((not CharredPassions.known or CharredPassions:Down()) and Player:Enemies() >= 3 and BreathOfFire:Down() and KegSmash:Up())) then
		return BreathOfFire
	end
	if not StormstoutsLastKeg.known and KegSmash:Usable() then
		return KegSmash
	end
	if BlackoutKick:Usable() then
		return BlackoutKick
	end
	if StormstoutsLastKeg.known and KegSmash:Usable() and KegSmash:FullRechargeTime() < 1.5 then
		return KegSmash
	end
	if FaelineStomp:Usable() then
		UseCooldown(FaelineStomp)
	end
	if RushingJadeWind:Usable() and RushingJadeWind:Down() then
		return RushingJadeWind
	end
	if CharredPassions.known and SpinningCraneKick:Usable() and CharredPassions:Up() then
		return SpinningCraneKick
	end
	if BreathOfFire:Usable() and BlackoutCombo:Down() and (not Player:BloodlustActive() or Player:BloodlustActive() and BreathOfFire:Refreshable()) then
		return BreathOfFire
	end
	if BlackoutKick:Usable(0.5) and (Player:Enemies() < 3 or BlackoutKick:Cooldown() < KegSmash:Cooldown()) then
		return BlackoutKick
	end
	if KegSmash:Usable(0.5, true) then
		return Pool(KegSmash)
	end
	if ExpelHarm:Usable() and Player:HealthPct() < 70 and GiftOfTheOx.count >= 4 then
		return ExpelHarm
	end
	if ChiBurst:Usable() then
		UseCooldown(ChiBurst)
	end
	if ChiWave:Usable() then
		return ChiWave
	end
	if SpinningCraneKick:Usable() and Player:Enemies() >= 3 and not KegSmash:Ready(Player.gcd) and (Player:Energy() + (Player:EnergyRegen() * (KegSmash:Cooldown() + 1.5))) >= 65 and (not Spitfire.known or not CharredPassions.known) and (Stagger:Light() or PurifyingBrew:ChargesFractional() > 0.8 or (BlackOxBrew.known and BlackOxBrew:Ready())) then
		return SpinningCraneKick
	end
	if not BlackoutCombo.known and TigerPalm:Usable() and not KegSmash:Ready(Player.gcd) and (Player:Energy() + (Player:EnergyRegen() * (KegSmash:Cooldown() + Player.gcd))) >= 65 then
		return TigerPalm
	end
	if ExpelHarm:Usable() and Player:HealthPct() < 80 and GiftOfTheOx.count >= 2 then
		return ExpelHarm
	end
	if RushingJadeWind:Usable() then
		return RushingJadeWind
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
actions.precombat+=/variable,name=xuen_on_use_trinket,op=set,value=0
actions.precombat+=/chi_burst
actions.precombat+=/chi_wave,if=!talent.energizing_elixir.enabled
]]
	if Player:TimeInCombat() == 0 then
		Player.opener_done = false
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheCurrents:Usable() and GreaterFlaskOfTheCurrents.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
		if ChiBurst:Usable() and Player:ChiDeficit() >= min(2, Player:Enemies()) then
			UseCooldown(ChiBurst)
		end
		if ChiWave:Usable() and not EnergizingElixir.known then
			return ChiWave
		end
		if FlyingSerpentKick:Usable() then
			UseCooldown(FlyingSerpentKick)
		end
	end
--[[
actions=auto_attack
actions+=/spear_hand_strike,if=target.debuff.casting.react
actions+=/variable,name=opener_done,op=set,value=1,if=chi>=5|pet.xuen_the_white_tiger.active
actions+=/variable,name=hold_xuen,op=set,value=cooldown.invoke_xuen_the_white_tiger.remains>fight_remains|fight_remains<120&fight_remains>cooldown.serenity.remains&cooldown.serenity.remains>10
actions+=/potion,if=(buff.serenity.up|buff.storm_earth_and_fire.up)&pet.xuen_the_white_tiger.active|fight_remains<=60
actions+=/call_action_list,name=serenity,if=buff.serenity.up
actions+=/call_action_list,name=weapons_of_order,if=buff.weapons_of_order.up
actions+=/call_action_list,name=opener,if=!variable.opener_done
actions+=/fist_of_the_white_tiger,target_if=min:debuff.mark_of_the_crane.remains,if=chi.max-chi>=3&(energy.time_to_max<1|energy.time_to_max<4&cooldown.fists_of_fury.remains<1.5|cooldown.weapons_of_order.remains<2)
actions+=/expel_harm,if=chi.max-chi>=1&(energy.time_to_max<1|cooldown.serenity.remains<2|energy.time_to_max<4&cooldown.fists_of_fury.remains<1.5|cooldown.weapons_of_order.remains<2)
actions+=/tiger_palm,target_if=min:debuff.mark_of_the_crane.remains,if=combo_strike&chi.max-chi>=2&(energy.time_to_max<1|cooldown.serenity.remains<2|energy.time_to_max<4&cooldown.fists_of_fury.remains<1.5|cooldown.weapons_of_order.remains<2)
actions+=/call_action_list,name=cd_sef,if=!talent.serenity.enabled
actions+=/call_action_list,name=cd_serenity,if=talent.serenity.enabled
actions+=/call_action_list,name=st,if=active_enemies<3
actions+=/call_action_list,name=aoe,if=active_enemies>=3
]]
	Player.use_cds = Opt.cooldown and (Target.boss or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd))
	Player.hold_xuen = not Player.use_cds or not InvokeXuenTheWhiteTiger:Ready(Target.timeToDie) or (Serenity.known and Target.timeToDie < 120 and Target.timeToDie > Serenity:Cooldown() and not Serenity:Ready(10))
	if FortifyingBrew:Usable() and Player:HealthPct() < 15 then
		UseCooldown(FortifyingBrew)
	end
	if Opt.pot and Target.boss and not Player:InArenaOrBattleground() and PotionOfUnbridledFury:Usable() and (((Serenity:Up() or StormEarthAndFire:Up()) and InvokeXuenTheWhiteTiger:Up()) or Target.timeToDie <= 60) then
		UseCooldown(PotionOfUnbridledFury)
	end
	local apl
	if Serenity.known and Serenity:Up() then
		apl = self:serenity()
		if apl then return apl end
	end
	if WeaponsOfOrder.known and WeaponsOfOrder:Up() then
		apl = self:weapons_of_order()
		if apl then return apl end
	end
	if not Player.opener_done then
		if Player:Chi() >= 5 or InvokeXuenTheWhiteTiger:Up() then
			Player.opener_done = true
		else
			apl = self:opener()
			if apl then return apl end
		end
	end
	if FistOfTheWhiteTiger:Usable() and Player:ChiDeficit() >= 3 and (Player:EnergyTimeToMax() < 1 or (Player:EnergyTimeToMax() < 4 and FistsOfFury:Ready(1.5)) or (WeaponsOfOrder.known and WeaponsOfOrder:Ready(2))) then
		return FistOfTheWhiteTiger
	end
	if ExpelHarm:Usable() and Player:ChiDeficit() >= 1 and (Player:EnergyTimeToMax() < 1 or (Serenity.known and Serenity:Ready(2)) or (Player:EnergyTimeToMax() < 4 and FistsOfFury:Ready(1.5)) or (WeaponsOfOrder.known and WeaponsOfOrder:Ready(2))) then
		return ExpelHarm
	end
	if TigerPalm:Usable() and TigerPalm:Combo() and Player:ChiDeficit() >= 2 and (Player:EnergyTimeToMax() < 1 or (Serenity.known and Serenity:Ready(2)) or (Player:EnergyTimeToMax() < 4 and FistsOfFury:Ready(1.5)) or (WeaponsOfOrder.known and WeaponsOfOrder:Ready(2))) then
		return TigerPalm
	end
	if Serenity.known then
		self:cd_serenity()
	else
		self:cd_sef()
	end
	if Player:Enemies() >= 3 then
		return self:aoe()
	end
	return self:st()
end

APL[SPEC.WINDWALKER].serenity = function(self)
--[[
actions.serenity=fists_of_fury,if=buff.serenity.remains<1
actions.serenity+=/use_item,name=darkmoon_deck_voracity
actions.serenity+=/spinning_crane_kick,if=combo_strike&(active_enemies>=3|active_enemies>1&!cooldown.rising_sun_kick.up)
actions.serenity+=/rising_sun_kick,target_if=min:debuff.mark_of_the_crane.remains,if=combo_strike
actions.serenity+=/fists_of_fury,if=active_enemies>=3
actions.serenity+=/spinning_crane_kick,if=combo_strike&buff.dance_of_chiji.up
actions.serenity+=/blackout_kick,target_if=min:debuff.mark_of_the_crane.remains,if=combo_strike&buff.weapons_of_order_ww.up&cooldown.rising_sun_kick.remains>2
actions.serenity+=/fist_of_the_white_tiger,interrupt=1
actions.serenity+=/spinning_crane_kick,if=combo_strike&debuff.bonedust_brew.up
actions.serenity+=/fist_of_the_white_tiger,target_if=min:debuff.mark_of_the_crane.remains,if=chi<3
actions.serenity+=/blackout_kick,target_if=min:debuff.mark_of_the_crane.remains,if=combo_strike
actions.serenity+=/spinning_crane_kick
]]
	if FistsOfFury:Usable() and Serenity:Remains() < 1 then
		return FistsOfFury
	end
	if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and (Player:Enemies() >= 3 or (Player:Enemies() > 1 and RisingSunKick:Ready())) then
		return SpinningCraneKick
	end
	if RisingSunKick:Usable() and RisingSunKick:Combo() then
		return RisingSunKick
	end
	if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and DanceOfChiJi:Up() then
		return SpinningCraneKick
	end
	if WeaponsOfOrder.known and BlackoutKick:Usable() and BlackoutKick:Combo() and WeaponsOfOrder:Up() and not RisingSunKick:Ready(2) then
		return BlackoutKick
	end
	--[[
	if FistOfTheWhiteTiger:Usable() then
		return FistOfTheWhiteTiger
	end
	]]
	if BonedustBrew.known and SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and BonedustBrew:Up() then
		return SpinningCraneKick
	end
	if FistOfTheWhiteTiger:Usable() and Player:Chi() < 3 then
		return FistOfTheWhiteTiger
	end
	if BlackoutKick:Usable() and BlackoutKick:Combo() then
		return BlackoutKick
	end
	if SpinningCraneKick:Usable() then
		return SpinningCraneKick
	end
end

APL[SPEC.WINDWALKER].weapons_of_order = function(self)
--[[
actions.weapons_of_order=call_action_list,name=cd_sef,if=!talent.serenity.enabled
actions.weapons_of_order+=/call_action_list,name=cd_serenity,if=talent.serenity.enabled
actions.weapons_of_order+=/energizing_elixir,if=chi.max-chi>=2&energy.time_to_max>3
actions.weapons_of_order+=/rising_sun_kick,target_if=min:debuff.mark_of_the_crane.remains
actions.weapons_of_order+=/spinning_crane_kick,if=combo_strike&buff.dance_of_chiji.up
actions.weapons_of_order+=/fists_of_fury,if=active_enemies>=2&buff.weapons_of_order_ww.remains<1
actions.weapons_of_order+=/whirling_dragon_punch,if=active_enemies>=2
actions.weapons_of_order+=/spinning_crane_kick,if=combo_strike&active_enemies>=3&buff.weapons_of_order_ww.up
actions.weapons_of_order+=/blackout_kick,target_if=min:debuff.mark_of_the_crane.remains,if=combo_strike&active_enemies<=2
actions.weapons_of_order+=/whirling_dragon_punch
actions.weapons_of_order+=/fists_of_fury,interrupt=1,if=buff.storm_earth_and_fire.up&raid_event.adds.in>cooldown.fists_of_fury.duration*0.6
actions.weapons_of_order+=/spinning_crane_kick,if=combo_strike&buff.chi_energy.stack>30-5*active_enemies
actions.weapons_of_order+=/fist_of_the_white_tiger,target_if=min:debuff.mark_of_the_crane.remains,if=chi<3
actions.weapons_of_order+=/expel_harm,if=chi.max-chi>=1
actions.weapons_of_order+=/chi_burst,if=chi.max-chi>=(1+active_enemies>1)
actions.weapons_of_order+=/tiger_palm,target_if=min:debuff.mark_of_the_crane.remains+(debuff.recently_rushing_tiger_palm.up*20),if=(!talent.hit_combo.enabled|combo_strike)&chi.max-chi>=2
actions.weapons_of_order+=/chi_wave
actions.weapons_of_order+=/blackout_kick,target_if=min:debuff.mark_of_the_crane.remains,if=chi>=3|buff.weapons_of_order_ww.up
actions.weapons_of_order+=/flying_serpent_kick,interrupt=1,if=(prev_gcd.1.tiger_palm&chi.max-chi>=2)|(prev_gcd.1.blackout_kick&(chi>=1|buff.bok_proc.up))
actions.weapons_of_order+=/spinning_crane_kick,if=combo_strike&chi>=4&cooldown.rising_sun_kick.remains>2&cooldown.fists_of_fury.remains>2
]]
	if Serenity.known then
		self:cd_serenity()
	else
		self:cd_sef()
	end
	if EnergizingElixir:Usable() and Player:ChiDeficit() >= 2 and Player:EnergyTimeToMax() > 3 then
		UseCooldown(EnergizingElixir)
	end
	if RisingSunKick:Usable() then
		return RisingSunKick
	end
	if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and DanceOfChiJi:Up() then
		return SpinningCraneKick
	end
	if Player:Enemies() >= 2 then
		if FistsOfFury:Usable() and WeaponsOfOrder:Remains() < 1 then
			return FistsOfFury
		end
		if WhirlingDragonPunch:Usable() then
			return WhirlingDragonPunch
		end
		if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and Player:Enemies() >= 3 and WeaponsOfOrder:Up() then
			return SpinningCraneKick
		end
	end
	if BlackoutKick:Usable() and BlackoutKick:Combo() and Player:Enemies() <= 2 then
		return BlackoutKick
	end
	if WhirlingDragonPunch:Usable() then
		return WhirlingDragonPunch
	end
	if StormEarthAndFire.known and FistsOfFury:Usable() and StormEarthAndFire:Up() then
		return FistsOfFury
	end
	if JadeIgnition.known and SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and JadeIgnition:Stack() > (30 - 5 * Player:Enemies()) then
		return SpinningCraneKick
	end
	if FistOfTheWhiteTiger:Usable() and Player:Chi() < 3 then
		return FistOfTheWhiteTiger
	end
	if ExpelHarm:Usable() and Player:ChiDeficit() >= 1 then
		return ExpelHarm
	end
	if ChiBurst:Usable() and Player:ChiDeficit() >= min(2, Player:Enemies()) then
		UseCooldown(ChiBurst)
	end
	if TigerPalm:Usable() and (TigerPalm:Combo() or not HitCombo.known) and Player:ChiDeficit() >= 2 then
		return TigerPalm
	end
	if ChiWave:Usable() then
		return ChiWave
	end
	if BlackoutKick:Usable() and (Player:Chi() >= 3 or WeaponsOfOrder:Up()) then
		return BlackoutKick
	end
	if TigerPalm:Usable(0, true) and (TigerPalm:Combo() or not HitCombo.known) and Player:ChiDeficit() >= 2 then
		return Pool(TigerPalm)
	end
	if FlyingSerpentKick:Usable() and ((TigerPalm:Previous() and Player:ChiDeficit() >= 2) or (BlackoutKick:Previous() and BlackoutKick:Usable())) then
		UseCooldown(FlyingSerpentKick)
	end
	if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and Player:Chi() >= 4 and not (FistsOfFury:Ready(2) or RisingSunKick:Ready(2)) then
		return SpinningCraneKick
	end
end

APL[SPEC.WINDWALKER].opener = function(self)
--[[
actions.opener=fist_of_the_white_tiger,target_if=min:debuff.mark_of_the_crane.remains,if=chi.max-chi>=3
actions.opener+=/expel_harm,if=talent.chi_burst.enabled&chi.max-chi>=3
actions.opener+=/tiger_palm,target_if=min:debuff.mark_of_the_crane.remains+(debuff.recently_rushing_tiger_palm.up*20),if=combo_strike&chi.max-chi>=2
actions.opener+=/chi_wave,if=chi.max-chi=2
actions.opener+=/expel_harm,if=chi.max-chi>=1
actions.opener+=/tiger_palm,target_if=min:debuff.mark_of_the_crane.remains+(debuff.recently_rushing_tiger_palm.up*20),if=chi.max-chi>=2
]]
	if FistOfTheWhiteTiger:Usable() and Player:ChiDeficit() >= 3 then
		return FistOfTheWhiteTiger
	end
	if ChiBurst.known and ExpelHarm:Usable() and Player:ChiDeficit() >= 3 then
		return ExpelHarm
	end
	if TigerPalm:Usable() and TigerPalm:Combo() and Player:ChiDeficit() >= 2 then
		return TigerPalm
	end
	if ChiWave:Usable() and Player:ChiDeficit() == 2 then
		return ChiWave
	end
	if ExpelHarm:Usable() and Player:ChiDeficit() >= 1 then
		return ExpelHarm
	end
	if TigerPalm:Usable() and Player:ChiDeficit() >= 2 then
		return TigerPalm
	end
end

APL[SPEC.WINDWALKER].cd_serenity = function(self)
--[[
actions.cd_serenity=variable,name=serenity_burst,op=set,value=cooldown.serenity.remains<1|pet.xuen_the_white_tiger.active&cooldown.serenity.remains>30|fight_remains<20
actions.cd_serenity+=/invoke_xuen_the_white_tiger,if=!variable.hold_xuen|fight_remains<25
actions.cd_serenity+=/touch_of_death,if=fight_remains>180|pet.xuen_the_white_tiger.active|fight_remains<10
actions.cd_serenity+=/touch_of_karma,if=fight_remains>90|pet.xuen_the_white_tiger.active|fight_remains<10
actions.cd_serenity+=/weapons_of_order,if=cooldown.rising_sun_kick.remains<execute_time
actions.cd_serenity+=/faeline_stomp
actions.cd_serenity+=/fallen_order
actions.cd_serenity+=/bonedust_brew
actions.cd_serenity+=/serenity,if=cooldown.rising_sun_kick.remains<2|fight_remains<15
]]
	--Player.serenity_burst = Serenity:Ready(1) or (InvokeXuenTheWhiteTiger:Up() and not Serenity:Ready(30)) or Target.timeToDie < 20
	if Player.use_cds and InvokeXuenTheWhiteTiger:Usable() and (not Player.hold_xuen or Target.timeToDie < 25) then
		UseCooldown(InvokeXuenTheWhiteTiger)
	end
	if TouchOfDeath:Usable() and TouchOfDeath:Combo() and (InvokeXuenTheWhiteTiger:Up() or Target.timeToDie < 10 or Target.timeToDie > 180) then
		UseExtra(TouchOfDeath)
	end
	if TouchOfKarma:Usable() and Player:UnderAttack() and (InvokeXuenTheWhiteTiger:Up() or Target.timeToDie < 10 or Target.timeToDie > 90) then
		UseExtra(TouchOfKarma)
	end
	if Player.use_cds or Player:Enemies() > 1 then
		if FaelineStomp:Usable() and FaelineStomp:Combo() then
			UseCooldown(FaelineStomp)
		end
		if BonedustBrew:Usable() then
			UseCooldown(BonedustBrew)
		end
	end
	if Player.use_cds or InvokeXuenTheWhiteTiger:Up() then
		if WeaponsOfOrder:Usable() and RisingSunKick:Ready(Player.gcd) then
			UseCooldown(WeaponsOfOrder)
		end
		if FallenOrder:Usable() then
			UseCooldown(FallenOrder)
		end
		if Serenity:Usable() and (RisingSunKick:Ready(2) or Target.timeToDie < 15) then
			UseCooldown(Serenity)
		end
	end
end

APL[SPEC.WINDWALKER].cd_sef = function(self)
--[[
actions.cd_sef=invoke_xuen_the_white_tiger,if=!variable.hold_xuen|fight_remains<25
actions.cd_sef+=/touch_of_death,if=buff.storm_earth_and_fire.down&pet.xuen_the_white_tiger.active|fight_remains<10|fight_remains>180
actions.cd_sef+=/weapons_of_order,if=(raid_event.adds.in>45|raid_event.adds.up)&cooldown.rising_sun_kick.remains<execute_time
actions.cd_sef+=/faeline_stomp,if=combo_strike&(raid_event.adds.in>10|raid_event.adds.up)
actions.cd_sef+=/fallen_order,if=raid_event.adds.in>30|raid_event.adds.up
actions.cd_sef+=/bonedust_brew,if=raid_event.adds.in>50|raid_event.adds.up,line_cd=60
actions.cd_sef+=/storm_earth_and_fire,if=cooldown.storm_earth_and_fire.charges=2|fight_remains<20|(raid_event.adds.remains>15|!covenant.kyrian&((raid_event.adds.in>cooldown.storm_earth_and_fire.full_recharge_time|!raid_event.adds.exists)&(cooldown.invoke_xuen_the_white_tiger.remains>cooldown.storm_earth_and_fire.full_recharge_time|variable.hold_xuen))&cooldown.fists_of_fury.remains<=9&chi>=2&cooldown.whirling_dragon_punch.remains<=12)
actions.cd_sef+=/storm_earth_and_fire,if=covenant.kyrian&(buff.weapons_of_order.up|(fight_remains<cooldown.weapons_of_order.remains|cooldown.weapons_of_order.remains>cooldown.storm_earth_and_fire.full_recharge_time)&cooldown.fists_of_fury.remains<=9&chi>=2&cooldown.whirling_dragon_punch.remains<=12)
actions.cd_sef+=/touch_of_karma,if=fight_remains>159|pet.xuen_the_white_tiger.active|variable.hold_xuen
]]
	if Player.use_cds and InvokeXuenTheWhiteTiger:Usable() and (not Player.hold_xuen or Target.timeToDie < 25) then
		UseCooldown(InvokeXuenTheWhiteTiger)
	end
	if TouchOfDeath:Usable() and TouchOfDeath:Combo() and ((StormEarthAndFire:Down() and InvokeXuenTheWhiteTiger:Up()) or Target.timeToDie < 10 or Target.timeToDie > 180) then
		UseExtra(TouchOfDeath)
	end
	if Player.use_cds or Player:Enemies() > 1 then
		if FaelineStomp:Usable() and FaelineStomp:Combo() then
			UseCooldown(FaelineStomp)
		end
		if BonedustBrew:Usable() then
			UseCooldown(BonedustBrew)
		end
	end
	if Player.use_cds or InvokeXuenTheWhiteTiger:Up() then
		if WeaponsOfOrder:Usable() and RisingSunKick:Ready(Player.gcd) then
			UseCooldown(WeaponsOfOrder)
		end
		if FallenOrder:Usable() then
			UseCooldown(FallenOrder)
		end
		if StormEarthAndFire:Usable() and StormEarthAndFire:Down() then
			if Target.timeToDie < 20 or StormEarthAndFire:Charges() >= 2 then
				UseCooldown(StormEarthAndFire)
			end
			if WeaponsOfOrder.known then
				if WeaponsOfOrder:Up() or ((WeaponsOfOrder:Ready(Target.timeToDie) or not WeaponsOfOrder:Ready(StormEarthAndFire:FullRechargeTime())) and FistsOfFury:Ready(9) and Player:Chi() >= 2 and (not WhirlingDragonPunch.known or WhirlingDragonPunch:Ready(12))) then
					UseCooldown(StormEarthAndFire)
				end
			else
				if (Player.hold_xuen or not InvokeXuenTheWhiteTiger:Ready(StormEarthAndFire:FullRechargeTime())) and FistsOfFury:Ready(9) and Player:Chi() >= 2 and (not WhirlingDragonPunch.known or WhirlingDragonPunch:Ready(12)) then
					UseCooldown(StormEarthAndFire)
				end
			end
		end
	end
	if TouchOfKarma:Usable() and Player:UnderAttack() and (Target.timeToDie > 159 or InvokeXuenTheWhiteTiger:Up() or Player.hold_xuen) then
		UseExtra(TouchOfKarma)
	end
end

APL[SPEC.WINDWALKER].st = function(self)
--[[
actions.st=whirling_dragon_punch,if=raid_event.adds.in>cooldown.whirling_dragon_punch.duration*0.8|raid_event.adds.up
actions.st+=/energizing_elixir,if=chi.max-chi>=2&energy.time_to_max>3|chi.max-chi>=4&(energy.time_to_max>2|!prev_gcd.1.tiger_palm)
actions.st+=/spinning_crane_kick,if=combo_strike&buff.dance_of_chiji.up&(raid_event.adds.in>buff.dance_of_chiji.remains-2|raid_event.adds.up)
actions.st+=/rising_sun_kick,target_if=min:debuff.mark_of_the_crane.remains,if=cooldown.serenity.remains>1|!talent.serenity.enabled
actions.st+=/fists_of_fury,if=(raid_event.adds.in>cooldown.fists_of_fury.duration*0.8|raid_event.adds.up)&(energy.time_to_max>execute_time-1|chi.max-chi<=1|buff.storm_earth_and_fire.remains<execute_time+1)|fight_remains<execute_time+1
actions.st+=/crackling_jade_lightning,if=buff.the_emperors_capacitor.stack>19&energy.time_to_max>execute_time-1&cooldown.rising_sun_kick.remains>execute_time|buff.the_emperors_capacitor.stack>14&(cooldown.serenity.remains<5&talent.serenity.enabled|cooldown.weapons_of_order.remains<5&covenant.kyrian|fight_remains<5)
actions.st+=/rushing_jade_wind,if=buff.rushing_jade_wind.down&active_enemies>1
actions.st+=/fist_of_the_white_tiger,target_if=min:debuff.mark_of_the_crane.remains,if=chi<3
actions.st+=/expel_harm,if=chi.max-chi>=1
actions.st+=/chi_burst,if=chi.max-chi>=1&active_enemies=1&raid_event.adds.in>20|chi.max-chi>=2&active_enemies>=2
actions.st+=/chi_wave
actions.st+=/tiger_palm,target_if=min:debuff.mark_of_the_crane.remains+(debuff.recently_rushing_tiger_palm.up*20),if=combo_strike&chi.max-chi>=2&buff.storm_earth_and_fire.down
actions.st+=/spinning_crane_kick,if=combo_strike&buff.chi_energy.stack>30-5*active_enemies&buff.storm_earth_and_fire.down&(cooldown.rising_sun_kick.remains>2&cooldown.fists_of_fury.remains>2|cooldown.rising_sun_kick.remains<3&cooldown.fists_of_fury.remains>3&chi>3|cooldown.rising_sun_kick.remains>3&cooldown.fists_of_fury.remains<3&chi>4|chi.max-chi<=1&energy.time_to_max<2)|combo_strike&buff.chi_energy.stack>10&fight_remains<7
actions.st+=/blackout_kick,target_if=min:debuff.mark_of_the_crane.remains,if=combo_strike&(talent.serenity.enabled&cooldown.serenity.remains<3|cooldown.rising_sun_kick.remains>1&cooldown.fists_of_fury.remains>1|cooldown.rising_sun_kick.remains<3&cooldown.fists_of_fury.remains>3&chi>2|cooldown.rising_sun_kick.remains>3&cooldown.fists_of_fury.remains<3&chi>3|chi>5|buff.bok_proc.up)
actions.st+=/tiger_palm,target_if=min:debuff.mark_of_the_crane.remains+(debuff.recently_rushing_tiger_palm.up*20),if=combo_strike&chi.max-chi>=2
actions.st+=/flying_serpent_kick,interrupt=1,if=(prev_gcd.1.tiger_palm&chi.max-chi>=2)|(prev_gcd.1.blackout_kick&(chi>=1|buff.bok_proc.up))
actions.st+=/blackout_kick,target_if=min:debuff.mark_of_the_crane.remains,if=combo_strike&cooldown.fists_of_fury.remains<3&chi=2&prev_gcd.1.tiger_palm&energy.time_to_50<1
actions.st+=/blackout_kick,target_if=min:debuff.mark_of_the_crane.remains,if=combo_strike&energy.time_to_max<2&(chi.max-chi<=1|prev_gcd.1.tiger_palm)
actions.st+=/spinning_crane_kick,if=combo_strike&chi>=4&cooldown.rising_sun_kick.remains>2&cooldown.fists_of_fury.remains>2
]]
	if WhirlingDragonPunch:Usable() then
		return WhirlingDragonPunch
	end
	if EnergizingElixir:Usable() and ((Player:ChiDeficit() >= 2 and Player:EnergyTimeToMax() > 3) or (Player:ChiDeficit() >= 4 and (Player:EnergyTimeToMax() > 2 or not TigerPalm:Previous()))) then
		UseCooldown(EnergizingElixir)
	end
	if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and DanceOfChiJi:Up() then
		return SpinningCraneKick
	end
	if RisingSunKick:Usable() and (not Serenity.known or not Serenity:Ready(1)) then
		return RisingSunKick
	end
	if FistsOfFury:Usable() and (Player:EnergyTimeToMax() > (4 * Player.haste_factor - 1) or Player:ChiDeficit() <= 1 or StormEarthAndFire:Remains() < (4 * Player.haste_factor + 1) or Target.timeToDie < (4 * Player.haste_factor + 1)) then
		return FistsOfFury
	end
	if LastEmperorsCapacitor.known and CracklingJadeLightning:Usable() and ((LastEmperorsCapacitor:Stack() > 19 and Player:EnergyTimeToMax() > (4 * Player.haste_factor - 1) and not RisingSunKick:Ready(4 * Player.haste_factor)) or (LastEmperorsCapacitor:Stack() > 14 and ((Serenity.known and Serenity:Ready(5)) or (WeaponsOfOrder.known and WeaponsOfOrder:Ready(5)) or Target.timeToDie < 5))) then
		return CracklingJadeLightning
	end
	if RushingJadeWind:Usable() and RushingJadeWind:Down() and Player:Enemies() > 1 then
		return RushingJadeWind
	end
	if FistOfTheWhiteTiger:Usable() and Player:Chi() < 3 then
		return FistOfTheWhiteTiger
	end
	if ExpelHarm:Usable() and Player:ChiDeficit() >= 1 then
		return ExpelHarm
	end
	if ChiBurst:Usable() and Player:ChiDeficit() >= min(2, Player:Enemies()) then
		UseCooldown(ChiBurst)
	end
	if ChiWave:Usable() then
		return ChiWave
	end
	if TigerPalm:Usable() and TigerPalm:Combo() and Player:ChiDeficit() >= 2 and StormEarthAndFire:Down() then
		return TigerPalm
	end
	if JadeIgnition.known and SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and ((JadeIgnition:Stack() > (30 - 5 * Player:Enemies()) and StormEarthAndFire:Down() and ((not RisingSunKick:Ready(2) and not FistsOfFury:Ready(2)) or (RisingSunKick:Ready(3) and not FistsOfFury:Ready(3) and Player:Chi() > 3) or (not RisingSunKick:Ready(3) and FistsOfFury:Ready(3) and Player:Chi() > 4) or (Player:ChiDeficit() <= 1 and Player:EnergyTimeToMax() < 2))) or (JadeIgnition:Stack() > 10 and Target.timeToDie < 7)) then
		return SpinningCraneKick
	end
	if BlackoutKick:Usable() and BlackoutKick:Combo() and ((Serenity.known and Serenity:Ready(3)) or (not RisingSunKick:Ready(1) and not FistsOfFury:Ready(1)) or (RisingSunKick:Ready(3) and not FistsOfFury:Ready(3) and Player:Chi() > 2) or (not RisingSunKick:Ready(3) and FistsOfFury:Ready(3) and Player:Chi() > 3) or Player:Chi() > 5 or BlackoutKick.free:Up()) then
		return BlackoutKick
	end
	if TigerPalm:Usable() and TigerPalm:Combo() and Player:ChiDeficit() >= 2 then
		return TigerPalm
	end
	if FlyingSerpentKick:Usable() and ((TigerPalm:Previous() and Player:ChiDeficit() >= 2) or (BlackoutKick:Previous() and BlackoutKick:Usable())) then
		UseCooldown(FlyingSerpentKick)
	end
	if BlackoutKick:Usable() and BlackoutKick:Combo() and ((FistsOfFury:Ready(3) and Player:Chi() == 2 and TigerPalm:Previous() and Player:EnergyTimeToMax(50) < 1) or (Player:EnergyTimeToMax() < 2 and (Player:ChiDeficit() <= 1 or TigerPalm:Previous()))) then
		return BlackoutKick
	end
	if TigerPalm:Usable(0, true) and TigerPalm:Combo() and Player:ChiDeficit() >= 2 then
		return Pool(TigerPalm)
	end
	if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and Player:Chi() >= 4 and not (FistsOfFury:Ready(2) or RisingSunKick:Ready(2)) then
		return SpinningCraneKick
	end
end

APL[SPEC.WINDWALKER].aoe = function(self)
--[[
actions.aoe=whirling_dragon_punch
actions.aoe+=/energizing_elixir,if=chi.max-chi>=2&energy.time_to_max>2|chi.max-chi>=4
actions.aoe+=/spinning_crane_kick,if=combo_strike(&buff.dance_of_chiji.up|debuff.bonedust_brew.up)
actions.aoe+=/fists_of_fury,if=energy.time_to_max>execute_time|chi.max-chi<=1
actions.aoe+=/rising_sun_kick,target_if=min:debuff.mark_of_the_crane.remains,if=(talent.whirling_dragon_punch.enabled&cooldown.rising_sun_kick.duration>cooldown.whirling_dragon_punch.remains+4)&(cooldown.fists_of_fury.remains>3|chi>=5)
actions.aoe+=/rushing_jade_wind,if=buff.rushing_jade_wind.down
actions.aoe+=/spinning_crane_kick,if=combo_strike&((cooldown.bonedust_brew.remains>2&(chi>3|cooldown.fists_of_fury.remains>6)&(chi>=5|cooldown.fists_of_fury.remains>2))|energy.time_to_max<=3)
actions.aoe+=/expel_harm,if=chi.max-chi>=1
actions.aoe+=/fist_of_the_white_tiger,target_if=min:debuff.mark_of_the_crane.remains,if=chi.max-chi>=3
actions.aoe+=/chi_burst,if=chi.max-chi>=2
actions.aoe+=/crackling_jade_lightning,if=buff.the_emperors_capacitor.stack>19&energy.time_to_max>execute_time-1&cooldown.fists_of_fury.remains>execute_time
actions.aoe+=/tiger_palm,target_if=min:debuff.mark_of_the_crane.remains+(debuff.recently_rushing_tiger_palm.up*20),if=chi.max-chi>=2&(!talent.hit_combo.enabled|combo_strike)
actions.aoe+=/chi_wave,if=combo_strike
actions.aoe+=/flying_serpent_kick,interrupt=1,if=(prev_gcd.1.tiger_palm&chi.max-chi>=2)|(prev_gcd.1.blackout_kick&(chi>=1|buff.bok_proc.up))|(prev_gcd.1.spinning_crane_kick&(chi>=2|buff.dance_of_chiji.up))
actions.aoe+=/blackout_kick,target_if=min:debuff.mark_of_the_crane.remains,if=combo_strike&(buff.bok_proc.up|talent.hit_combo.enabled&prev_gcd.1.tiger_palm&chi=2&cooldown.fists_of_fury.remains<3|chi.max-chi<=1&prev_gcd.1.spinning_crane_kick&energy.time_to_max<3)
actions.aoe+=/spinning_crane_kick,if=combo_strike&chi>=3
]]
	if WhirlingDragonPunch:Usable() then
		return WhirlingDragonPunch
	end
	if EnergizingElixir:Usable() and ((Player:ChiDeficit() >= 2 and Player:EnergyTimeToMax() > 2) or Player:ChiDeficit() >= 4) then
		UseCooldown(EnergizingElixir)
	end
	if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and (DanceOfChiJi:Up() or BonedustBrew:Up()) then
		return SpinningCraneKick
	end
	if FistsOfFury:Usable() and (Player:EnergyTimeToMax() > (4 * Player.haste_factor) or Player:ChiDeficit() <= 1) then
		return FistsOfFury
	end
	if WhirlingDragonPunch.known and RisingSunKick:Usable() and (10 * Player.haste_factor) > (WhirlingDragonPunch:Cooldown() + 4) and (not FistsOfFury:Ready(3) or Player:Chi() >= 5) then
		return RisingSunKick
	end
	if RushingJadeWind:Usable() then
		return RushingJadeWind
	end
	if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and ((not BonedustBrew.known or BonedustBrew:Cooldown() > 2 and (Player:Chi() > 3 or not FistsOfFury:Ready(6)) and (Player:Chi() >= 5 or not FistsOfFury:Ready(2))) or Player:EnergyTimeToMax() < 3) then
		return SpinningCraneKick
	end
	if ExpelHarm:Usable() and Player:ChiDeficit() >= 1 then
		return ExpelHarm
	end
	if FistOfTheWhiteTiger:Usable() and Player:ChiDeficit() >= 3 then
		return FistOfTheWhiteTiger
	end
	if ChiBurst:Usable() and Player:ChiDeficit() >= 2 then
		UseCooldown(ChiBurst)
	end
	if LastEmperorsCapacitor.known and CracklingJadeLightning:Usable() and LastEmperorsCapacitor:Stack() > 19 and Player:EnergyTimeToMax() > (4 * Player.haste_factor - 1) and not FistsOfFury:Ready(4 * Player.haste_factor) then
		return CracklingJadeLightning
	end
	if TigerPalm:Usable() and (TigerPalm:Combo() or not HitCombo.known) and Player:ChiDeficit() >= 2 then
		return TigerPalm
	end
	if ChiWave:Usable() and ChiWave:Combo() then
		return ChiWave
	end
	if FlyingSerpentKick:Usable() and ((TigerPalm:Previous() and Player:ChiDeficit() >= 2) or (BlackoutKick:Previous() and BlackoutKick:Usable()) or (SpinningCraneKick:Previous() and SpinningCraneKick:Usable())) then
		UseCooldown(FlyingSerpentKick)
	end
	if BlackoutKick:Usable() and BlackoutKick:Combo() and (BlackoutKick.free:Up() or (HitCombo.known and TigerPalm:Previous() and Player:Chi() == 2 and FistsOfFury:Ready(3)) or (Player:ChiDeficit() <= 1 and SpinningCraneKick:Previous() and Player:EnergyTimeToMax() < 3)) then
		return BlackoutKick
	end
	if TigerPalm:Usable(0, true) and TigerPalm:Combo() and Player:ChiDeficit() >= 2 then
		return Pool(TigerPalm)
	end
	if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and Player:Chi() >= 3 then
		return SpinningCraneKick
	end
end

APL.Interrupt = function(self)
	if SpearHandStrike:Usable() then
		return SpearHandStrike
	end
	if LegSweep:Usable() then
		return LegSweep
	end
end

-- End Action Priority Lists

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
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

function UI:CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			self.glows[#self.glows + 1] = glow
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
	UI:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon, i
	for i = 1, #self.glows do
		glow = self.glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
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

function UI:UpdateDraggable()
	msmdPanel:EnableMouse(Opt.aoe or not Opt.locked)
	msmdPanel.button:SetShown(Opt.aoe)
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

function UI:UpdateAlpha()
	msmdPanel:SetAlpha(Opt.alpha)
	msmdPreviousPanel:SetAlpha(Opt.alpha)
	msmdCooldownPanel:SetAlpha(Opt.alpha)
	msmdInterruptPanel:SetAlpha(Opt.alpha)
	msmdExtraPanel:SetAlpha(Opt.alpha)
end

function UI:UpdateScale()
	msmdPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	msmdPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	msmdCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	msmdInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	msmdExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

function UI:SnapAllPanels()
	msmdPreviousPanel:ClearAllPoints()
	msmdPreviousPanel:SetPoint('TOPRIGHT', msmdPanel, 'BOTTOMLEFT', -3, 40)
	msmdCooldownPanel:ClearAllPoints()
	msmdCooldownPanel:SetPoint('TOPLEFT', msmdPanel, 'BOTTOMRIGHT', 3, 40)
	msmdInterruptPanel:ClearAllPoints()
	msmdInterruptPanel:SetPoint('BOTTOMLEFT', msmdPanel, 'TOPRIGHT', 3, -21)
	msmdExtraPanel:ClearAllPoints()
	msmdExtraPanel:SetPoint('BOTTOMRIGHT', msmdPanel, 'TOPLEFT', -3, -21)
end

UI.anchor_points = {
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[SPEC.BREWMASTER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.MISTWEAVER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.WINDWALKER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.BREWMASTER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -3 }
		},
		[SPEC.MISTWEAVER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
		[SPEC.WINDWALKER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		msmdPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap and UI.anchor.points then
		local p = UI.anchor.points[Player.spec][Opt.snap]
		msmdPanel:ClearAllPoints()
		msmdPanel:SetPoint(p[1], UI.anchor.frame, p[2], p[3], p[4])
		UI:SnapAllPanels()
	end
end

function UI:HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		self.anchor.points = self.anchor_points.kui
		self.anchor.frame = KuiNameplatesPlayerAnchor
	else
		self.anchor.points = self.anchor_points.blizzard
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateManaBar()
	end
	if self.anchor.frame then
		self.anchor.frame:HookScript('OnHide', self.OnResourceFrameHide)
		self.anchor.frame:HookScript('OnShow', self.OnResourceFrameShow)
	end
end

function UI:ShouldHide()
	return (Player.spec == SPEC.NONE or
		   (Player.spec == SPEC.BREWMASTER and Opt.hide.brewmaster) or
		   (Player.spec == SPEC.MISTWEAVER and Opt.hide.mistweaver) or
		   (Player.spec == SPEC.WINDWALKER and Opt.hide.windwalker))
end

function UI:Disappear()
	msmdPanel:Hide()
	msmdPanel.icon:Hide()
	msmdPanel.border:Hide()
	msmdCooldownPanel:Hide()
	msmdInterruptPanel:Hide()
	msmdExtraPanel:Hide()
	Player.main = nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	timer.display = 0
	local dim, text_center, text_tl
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	if Player.pool_energy then
		local deficit = Player.pool_energy - UnitPower('player', 3)
		if deficit > 0 then
			text_center = format('POOL %d', deficit)
			dim = Opt.dimmer
		end
	end
	if Serenity.known and Player.serenity_remains > 0 then
		if not msmdPanel.serenityOverlayOn then
			msmdPanel.serenityOverlayOn = true
			msmdPanel.border:SetTexture(ADDON_PATH .. 'serenity.blp')
		end
		text_center = format('%.1f', Player.serenity_remains)
	elseif msmdPanel.serenityOverlayOn then
		msmdPanel.serenityOverlayOn = false
		msmdPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
	end
	if GiftOfTheOx.known then
		text_tl = GiftOfTheOx.count
	end
	msmdPanel.dimmer:SetShown(dim)
	msmdPanel.text.center:SetText(text_center)
	msmdPanel.text.tl:SetText(text_tl)
	--msmdPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
end

function UI:UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId, speed, max_speed
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.main =  nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	Player.pool_energy = nil
	start, duration = GetSpellCooldown(61304)
	Player.gcd_remains = start > 0 and duration - (Player.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	Player.ability_casting = abilities.bySpellId[spellId]
	Player.execute_remains = max(remains and (remains / 1000 - Player.ctime) or 0, Player.gcd_remains)
	Player.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	Player.health = UnitHealth('player')
	Player.health_max = UnitHealthMax('player')
	if Player.spec == SPEC.MISTWEAVER then
		Player.gcd = 1.5 * Player.haste_factor
		Player.mana_regen = GetPowerRegen()
		Player.mana = UnitPower('player', 0) + (Player.mana_regen * Player.execute_remains)
		if Player.ability_casting then
			Player.mana = Player.mana - Player.ability_casting:ManaCost()
		end
		Player.mana = min(max(Player.mana, 0), Player.mana_max)
	else
		Player.gcd = 1
		Player.energy_regen = GetPowerRegen()
		Player.energy = UnitPower('player', 3) + (Player.energy_regen * Player.execute_remains)
		if Player.ability_casting then
			Player.energy = Player.energy - Player.ability_casting:EnergyCost()
		end
		Player.energy = min(max(Player.energy, 0), Player.energy_max)
		if Player.spec == SPEC.BREWMASTER then
			Player.stagger = UnitStagger('player')
		else
			Player.chi = UnitPower('player', 12)
			if Player.ability_casting then
				Player.chi = Player.chi - Player.ability_casting:ChiCost()
			end
			Player.chi = min(max(Player.chi, 0), Player.chi_max)
			if Serenity.known then
				Player.serenity_remains = Serenity:Remains()
			end
		end
	end
	speed, max_speed = GetUnitSpeed('player')
	Player.moving = speed ~= 0
	Player.movement_speed = max_speed / 7 * 100

	trackAuras:Purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end

	Player.main = APL[Player.spec]:main()
	if Player.main then
		msmdPanel.icon:SetTexture(Player.main.icon)
	end
	if Player.cd then
		msmdCooldownPanel.icon:SetTexture(Player.cd.icon)
	end
	if Player.extra then
		msmdExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local ends, notInterruptible
		_, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			msmdInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			msmdInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		msmdInterruptPanel.icon:SetShown(Player.interrupt)
		msmdInterruptPanel.border:SetShown(Player.interrupt)
		msmdInterruptPanel:SetShown(start and not notInterruptible)
	end
	msmdPanel.icon:SetShown(Player.main)
	msmdPanel.border:SetShown(Player.main)
	msmdCooldownPanel:SetShown(Player.cd)
	msmdExtraPanel:SetShown(Player.extra)
	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = MonkSeeMonkDo
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_MonkSeeMonkDo1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:Remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:Remove(dstGUID)
		end
	end
	if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
		if dstGUID == Player.guid then
			Player.last_swing_taken = Player.time
		end
		if Opt.auto_aoe then
			if dstGUID == Player.guid then
				autoAoe:Add(srcGUID, true)
			elseif srcGUID == Player.guid and not (missType == 'EVADE' or missType == 'IMMUNE') then
				autoAoe:Add(dstGUID, true)
			end
		end
	end

	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_ABSORBED' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_ENERGIZE' or
	   eventType == 'SPELL_HEAL' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UI:UpdateCombatWithin(0.05)

	if GiftOfTheOx.known then
		if eventType == 'SPELL_CAST_SUCCESS' then
			if ability == GiftOfTheOx or ability == GiftOfTheOx.lowhp then
				GiftOfTheOx.count = GiftOfTheOx.count + 1
			elseif ability == ExpelHarm then
				GiftOfTheOx.count = 0
			end
		elseif eventType == 'SPELL_HEAL' then
			if ability == GiftOfTheOx.expire or ability == GiftOfTheOx.pickup then
				GiftOfTheOx.count = max(0, GiftOfTheOx.count - 1)
			end
		end
	end
	if eventType == 'SPELL_CAST_SUCCESS' then
		Player.last_ability = ability
		ability.last_used = Player.time
		if ability.triggers_gcd then
			Player.previous_gcd[10] = nil
			table.insert(Player.previous_gcd, 1, ability)
		end
		if ability.travel_start then
			ability.travel_start[dstGUID] = Player.time
		end
		if Opt.previous and msmdPanel:IsVisible() then
			msmdPreviousPanel.ability = ability
			msmdPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
			msmdPreviousPanel.icon:SetTexture(ability.icon)
			msmdPreviousPanel:Show()
		end
		if ComboStrikes.known and ability.triggers_combo then
			ComboStrikes.last_ability = ability
		end
		return
	end

	if dstGUID == Player.guid then
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (eventType == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and eventType == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		elseif ability == MarkOfTheCrane and (eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH') then
			autoAoe:Add(dstGUID, true)
		end
	end
	if eventType == 'SPELL_ABSORBED' or eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if ability.travel_start and ability.travel_start[dstGUID] then
			ability.travel_start[dstGUID] = nil
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and msmdPanel:IsVisible() and ability == msmdPreviousPanel.ability then
			msmdPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
		end
	end
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.last_swing_taken = 0
	Target.estimated_range = 30
	Player.previous_gcd = {}
	Player.opener_done = false
	if Player.last_ability then
		Player.last_ability = nil
		msmdPreviousPanel:Hide()
	end
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
		autoAoe:Clear()
		autoAoe:Update()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	local _, i, equipType, hasCooldown
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	for _, i in next, Trinket do -- use custom APL lines for these trinkets
		if Trinket1.itemId == i.itemId then
			Trinket1.itemId = 0
		end
		if Trinket2.itemId == i.itemId then
			Trinket2.itemId = 0
		end
	end
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Player:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	GiftOfTheOx.count = 0
	msmdPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Target:Update()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
	UI.OnResourceFrameShow()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		msmdPanel.swipe:SetCooldown(start, duration)
	end
end

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and powerType == 'CHI' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:GROUP_ROSTER_UPDATE()
	Player.group_size = min(max(GetNumGroupMembers(), 1), 10)
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:PLAYER_ENTERING_WORLD()
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	events:GROUP_ROSTER_UPDATE()
end

msmdPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Player:ToggleTargetMode()
		elseif button == 'RightButton' then
			Player:ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Player:SetTargetMode(1)
		end
	end
end)

msmdPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

msmdPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	msmdPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local ChatFrame_OnHyperlinkShow_Original = ChatFrame_OnHyperlinkShow
function ChatFrame_OnHyperlinkShow(chatFrame, link, ...)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		return BattleTagInviteFrame_Show(linkData)
	end
	return ChatFrame_OnHyperlinkShow_Original(chatFrame, link, ...)
end

local function Status(desc, opt, ...)
	local opt_view
	if type(opt) == 'string' then
		if opt:sub(1, 2) == '|c' then
			opt_view = opt
		else
			opt_view = '|cFFFFD000' .. opt .. '|r'
		end
	elseif type(opt) == 'number' then
		opt_view = '|cFFFFD000' .. opt .. '|r'
	else
		opt_view = opt and '|cFF00C000On|r' or '|cFFC00000Off|r'
	end
	print(ADDON, '-', desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
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
			UI.OnResourceFrameShow()
		end
		return Status('Snap to the Personal Resource Display frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UI:UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UI:UpdateAlpha()
		end
		return Status('Icon transparency', Opt.alpha * 100 .. '%')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return Status('Calculation frequency (max time to wait between each update): Every', Opt.frequency, 'seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			Target:Update()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			Target:Update()
		end
		return Status('Show the ' .. ADDON .. ' UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use ' .. ADDON .. ' for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
		end
		return Status('Dim main ability icon when you don\'t have enough resources to use it', Opt.dimmer)
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return Status('Red border around previous ability when it fails to hit', Opt.miss_effect)
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Player:SetTargetMode(1)
			UI:UpdateDraggable()
		end
		return Status('Allow clicking main ability icon to toggle amount of targets (disables moving)', Opt.aoe)
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return Status('Only use cooldowns on bosses', Opt.boss_only)
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'b') then
				Opt.hide.brewmaster = not Opt.hide.brewmaster
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Brewmaster specialization', not Opt.hide.brewmaster)
			end
			if startsWith(msg[2], 'm') then
				Opt.hide.mistweaver = not Opt.hide.mistweaver
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Mistweaver specialization', not Opt.hide.mistweaver)
			end
			if startsWith(msg[2], 'w') then
				Opt.hide.windwalker = not Opt.hide.windwalker
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Windwalker specialization', not Opt.hide.windwalker)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000brewmaster|r/|cFFFFD000mistweaver|r/|cFFFFD000windwalker|r')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return Status('Show an icon for interruptable spells', Opt.interrupt)
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return Status('Automatically change target mode on AoE spells', Opt.auto_aoe)
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return Status('Length of time target exists in auto AoE after being hit', Opt.auto_aoe_ttl, 'seconds')
	end
	if msg[1] == 'ttd' then
		if msg[2] then
			Opt.cd_ttd = tonumber(msg[2]) or 8
		end
		return Status('Minimum enemy lifetime to use cooldowns on (ignored on bosses)', Opt.cd_ttd, 'seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return Status('Show flasks and battle potions in cooldown UI', Opt.pot)
	end
	if startsWith(msg[1], 'tri') then
		if msg[2] then
			Opt.trinket = msg[2] == 'on'
		end
		return Status('Show on-use trinkets in cooldown UI', Opt.trinket)
	end
	if msg[1] == 'reset' then
		msmdPanel:ClearAllPoints()
		msmdPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000brewmaster|r/|cFFFFD000mistweaver|r/|cFFFFD000windwalker|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_MonkSeeMonkDo1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands

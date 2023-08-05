local ADDON = 'MonkSeeMonkDo'
if select(2, UnitClass('player')) ~= 'MONK' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetSpellCharges = _G.GetSpellCharges
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = _G.UnitAura
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitSpellHaste = _G.UnitSpellHaste
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function clamp(n, min, max)
	return (n < min and min) or (n > max and max) or n
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

SLASH_MonkSeeMonkDo1, SLASH_MonkSeeMonkDo2, SLASH_MonkSeeMonkDo3 = '/msmd', '/monk', '/monksee'
BINDING_HEADER_MONKSEEMONKDO = ADDON

local function InitOpts()
	local function SetDefaults(t, ref)
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
			animation = false,
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
		cd_ttd = 10,
		pot = false,
		trinket = true,
		heal_threshold = 60,
		defensives = true,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local Events = {}

-- player ability template
local Ability = {}
Ability.__index = Ability

-- classified player abilities
local Abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- timers for updating combat/display/hp info
local Timer = {
	combat = 0,
	display = 0,
	health = 0,
}

-- specialization constants
local SPEC = {
	NONE = 0,
	BREWMASTER = 1,
	MISTWEAVER = 2,
	WINDWALKER = 3,
}

-- action priority list container
local APL = {
	[SPEC.NONE] = {},
	[SPEC.BREWMASTER] = {},
	[SPEC.MISTWEAVER] = {},
	[SPEC.WINDWALKER] = {},
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	spec = 0,
	group_size = 1,
	target_mode = 0,
	gcd = 1.5,
	gcd_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	movement_speed = 100,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	mana = {
		current = 0,
		deficit = 0,
		max = 100,
		regen = 0,
	},
	energy = {
		current = 0,
		regen = 0,
		max = 100,
		deficit = 100,
	},
	chi = {
		current = 0,
		deficit = 0,
		max = 5,
	},
	stagger = {
		current = 0,
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	channel = {
		chained = false,
		start = 0,
		ends = 0,
		remains = 0,
		tick_count = 0,
		tick_interval = 0,
		ticks = 0,
		ticks_remain = 0,
		ticks_extra = 0,
		interruptible = false,
		early_chainable = false,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		last_taken = 0,
	},
	set_bonus = {
		t29 = 0, -- Wrappings of the Waking Fist
		t30 = 0, -- Fangs of the Vermillion Forge
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[190958] = true, -- Soleah's Secret Technique
		[193757] = true, -- Ruby Whelp Shell
		[202612] = true, -- Screaming Black Dragonscale
		[203729] = true, -- Ominous Chromatic Essence
	},
	main_freecast = false,
	major_cd_remains = 0,
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
}

local msmdPanel = CreateFrame('Frame', 'msmdPanel', UIParent)
msmdPanel:SetPoint('CENTER', 0, -169)
msmdPanel:SetFrameStrata('BACKGROUND')
msmdPanel:SetSize(64, 64)
msmdPanel:SetMovable(true)
msmdPanel:SetUserPlaced(true)
msmdPanel:RegisterForDrag('LeftButton')
msmdPanel:SetScript('OnDragStart', msmdPanel.StartMoving)
msmdPanel:SetScript('OnDragStop', msmdPanel.StopMovingOrSizing)
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
msmdPanel.swipe:SetDrawBling(false)
msmdPanel.swipe:SetDrawEdge(false)
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
msmdPreviousPanel:SetMovable(true)
msmdPreviousPanel:SetUserPlaced(true)
msmdPreviousPanel:RegisterForDrag('LeftButton')
msmdPreviousPanel:SetScript('OnDragStart', msmdPreviousPanel.StartMoving)
msmdPreviousPanel:SetScript('OnDragStop', msmdPreviousPanel.StopMovingOrSizing)
msmdPreviousPanel:Hide()
msmdPreviousPanel.icon = msmdPreviousPanel:CreateTexture(nil, 'BACKGROUND')
msmdPreviousPanel.icon:SetAllPoints(msmdPreviousPanel)
msmdPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
msmdPreviousPanel.border = msmdPreviousPanel:CreateTexture(nil, 'ARTWORK')
msmdPreviousPanel.border:SetAllPoints(msmdPreviousPanel)
msmdPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
local msmdCooldownPanel = CreateFrame('Frame', 'msmdCooldownPanel', UIParent)
msmdCooldownPanel:SetFrameStrata('BACKGROUND')
msmdCooldownPanel:SetSize(64, 64)
msmdCooldownPanel:SetMovable(true)
msmdCooldownPanel:SetUserPlaced(true)
msmdCooldownPanel:RegisterForDrag('LeftButton')
msmdCooldownPanel:SetScript('OnDragStart', msmdCooldownPanel.StartMoving)
msmdCooldownPanel:SetScript('OnDragStop', msmdCooldownPanel.StopMovingOrSizing)
msmdCooldownPanel:Hide()
msmdCooldownPanel.icon = msmdCooldownPanel:CreateTexture(nil, 'BACKGROUND')
msmdCooldownPanel.icon:SetAllPoints(msmdCooldownPanel)
msmdCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
msmdCooldownPanel.border = msmdCooldownPanel:CreateTexture(nil, 'ARTWORK')
msmdCooldownPanel.border:SetAllPoints(msmdCooldownPanel)
msmdCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
msmdCooldownPanel.dimmer = msmdCooldownPanel:CreateTexture(nil, 'BORDER')
msmdCooldownPanel.dimmer:SetAllPoints(msmdCooldownPanel)
msmdCooldownPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
msmdCooldownPanel.dimmer:Hide()
msmdCooldownPanel.swipe = CreateFrame('Cooldown', nil, msmdCooldownPanel, 'CooldownFrameTemplate')
msmdCooldownPanel.swipe:SetAllPoints(msmdCooldownPanel)
msmdCooldownPanel.swipe:SetDrawBling(false)
msmdCooldownPanel.swipe:SetDrawEdge(false)
msmdCooldownPanel.text = msmdCooldownPanel:CreateFontString(nil, 'OVERLAY')
msmdCooldownPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
msmdCooldownPanel.text:SetAllPoints(msmdCooldownPanel)
msmdCooldownPanel.text:SetJustifyH('CENTER')
msmdCooldownPanel.text:SetJustifyV('CENTER')
local msmdInterruptPanel = CreateFrame('Frame', 'msmdInterruptPanel', UIParent)
msmdInterruptPanel:SetFrameStrata('BACKGROUND')
msmdInterruptPanel:SetSize(64, 64)
msmdInterruptPanel:SetMovable(true)
msmdInterruptPanel:SetUserPlaced(true)
msmdInterruptPanel:RegisterForDrag('LeftButton')
msmdInterruptPanel:SetScript('OnDragStart', msmdInterruptPanel.StartMoving)
msmdInterruptPanel:SetScript('OnDragStop', msmdInterruptPanel.StopMovingOrSizing)
msmdInterruptPanel:Hide()
msmdInterruptPanel.icon = msmdInterruptPanel:CreateTexture(nil, 'BACKGROUND')
msmdInterruptPanel.icon:SetAllPoints(msmdInterruptPanel)
msmdInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
msmdInterruptPanel.border = msmdInterruptPanel:CreateTexture(nil, 'ARTWORK')
msmdInterruptPanel.border:SetAllPoints(msmdInterruptPanel)
msmdInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
msmdInterruptPanel.swipe = CreateFrame('Cooldown', nil, msmdInterruptPanel, 'CooldownFrameTemplate')
msmdInterruptPanel.swipe:SetAllPoints(msmdInterruptPanel)
msmdInterruptPanel.swipe:SetDrawBling(false)
msmdInterruptPanel.swipe:SetDrawEdge(false)
local msmdExtraPanel = CreateFrame('Frame', 'msmdExtraPanel', UIParent)
msmdExtraPanel:SetFrameStrata('BACKGROUND')
msmdExtraPanel:SetSize(64, 64)
msmdExtraPanel:SetMovable(true)
msmdExtraPanel:SetUserPlaced(true)
msmdExtraPanel:RegisterForDrag('LeftButton')
msmdExtraPanel:SetScript('OnDragStart', msmdExtraPanel.StartMoving)
msmdExtraPanel:SetScript('OnDragStop', msmdExtraPanel.StopMovingOrSizing)
msmdExtraPanel:Hide()
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
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.MISTWEAVER] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.WINDWALKER] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
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

function AutoAoe:Add(guid, update)
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

function AutoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function AutoAoe:Clear()
	for _, ability in next, Abilities.autoAoe do
		ability.auto_aoe.start_time = nil
		for guid in next, ability.auto_aoe.targets do
			ability.auto_aoe.targets[guid] = nil
		end
	end
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
	self:Update()
end

function AutoAoe:Update()
	local count = 0
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

function AutoAoe:Purge()
	local update
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

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_react = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rank = 0,
		mana_cost = 0,
		energy_cost = 0,
		chi_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
	}
	setmetatable(ability, self)
	Abilities.all[#Abilities.all + 1] = ability
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
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if Player.spec == SPEC.MISTWEAVER then
		if self:ManaCost() > Player.mana.current then
			return false
		end
	else
		if not pool and self:EnergyCost() > Player.energy.current then
			return false
		end
		if Player.spec == SPEC.WINDWALKER and self:ChiCost() > Player.chi.current then
			return false
		end
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains(offGCD)
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(0, expires - Player.ctime - (offGCD and 0 or Player.execute_remains))
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

function Ability:Up(...)
	return self:Remains(...) > 0
end

function Ability:Down(...)
	return self:Remains(...) <= 0
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.traveling = {}
	else
		self.traveling = nil
		self.velocity = 0
	end
end

function Ability:Traveling(all)
	if not self.traveling then
		return 0
	end
	local count = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity + (self.travel_delay or 0)
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > (self.off_gcd and 0 or Player.execute_remains) then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	local remains = duration - (Player.ctime - start)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and count or 0
		end
	end
	return 0
end

function Ability:ManaCost()
	return self.mana_cost > 0 and (self.mana_cost / 100 * Player.mana.max) or 0
end

function Ability:EnergyCost()
	return self.energy_cost
end

function Ability:ChiCost()
	return self.chi_cost
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + (self.off_gcd and 0 or Player.execute_remains))) / recharge_time)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return recharge_time
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.cast.ability == self
end

function Ability:Channeling()
	return Player.channel.ability == self
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return 0
	end
	return castTime / 1000
end

function Ability:CastEnergyRegen()
	return Player.energy.regen * self:CastTime() - self:EnergyCost()
end

function Ability:WontCapEnergy(reduction)
	return (Player.energy.current + self:CastRegen()) < (Player.energy.max - (reduction or 5))
end

function Ability:Previous(n)
	local i = n or 1
	if Player.cast.ability then
		if i == 1 then
			return Player.cast.ability == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:UsedWithin(seconds)
	return self.last_used >= (Player.time - seconds)
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
		trigger = 'SPELL_DAMAGE',
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	elseif trigger == 'cast' then
		self.auto_aoe.trigger = 'SPELL_CAST_SUCCESS'
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
		self.auto_aoe.target_count = 0
		if self.auto_aoe.remove then
			for guid in next, AutoAoe.targets do
				AutoAoe.targets[guid] = nil
			end
		end
		for guid in next, self.auto_aoe.targets do
			AutoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		AutoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		AutoAoe:Add(dstGUID, true)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if Opt.previous then
		msmdPreviousPanel.ability = self
		msmdPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		msmdPreviousPanel.icon:SetTexture(self.icon)
		msmdPreviousPanel:SetShown(msmdPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event, missType)
	if self.traveling then
		local oldest
		for guid, cast in next, self.traveling do
			if Player.time - cast.start >= self.max_range / self.velocity + (self.travel_delay or 0) + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = floor(clamp(self.velocity * max(0, Player.time - oldest.start - (self.travel_delay or 0)), 0, self.max_range))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(clamp(self.velocity * (Player.time - self.range_est_start - (self.travel_delay or 0)), 5, self.max_range))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and msmdPreviousPanel.ability == self then
		msmdPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, Abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	for _, ability in next, Abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid] or {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + duration))
	return aura
end

function Ability:RefreshAuraAll()
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + duration))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

--[[
Note: To get talent_node value for a talent, hover over talent and use macro:
/dump GetMouseFocus():GetNodeID()
]]

-- Monk Abilities
---- Class
------ Baseline

------ Talents
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
------ Talents
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
------ Talents
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
local StrikeOfTheWindlord = Ability:Add(392983, false, true, 395519)
StrikeOfTheWindlord.buff_duration = 6
StrikeOfTheWindlord.cooldown_duration = 40
StrikeOfTheWindlord.chi_cost = 2
StrikeOfTheWindlord.triggers_combo = true
local BonedustBrew = Ability:Add(386276, false, true)
BonedustBrew.cooldown_duration = 60
BonedustBrew.buff_duration = 10
local FaelineStomp = Ability:Add(388193, true, true, 388207)
FaelineStomp.cooldown_duration = 30
FaelineStomp.mana_cost = 4
FaelineStomp.triggers_combo = true
FaelineStomp:AutoAoe()
local LastEmperorsCapacitor = Ability:Add(392989, true, true, 393039)
------ Procs
BlackoutKick.free = Ability:Add(116768, true, true)
BlackoutKick.free.buff_duration = 15
local ComboStrikes = Ability:Add(115636, true, true) -- Mastery
-- Racials

-- PvP talents

-- Trinket Effects

-- Class cooldowns
local PowerInfusion = Ability:Add(10060, true)
PowerInfusion.buff_duration = 20
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
		charges = max(self.max_charges, charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(1, count)
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

-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.trackAuras)
	for _, ability in next, self.all do
		if ability.known then
			self.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				self.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				self.velocity[#self.velocity + 1] = ability
			end
			if ability.auto_aoe then
				self.autoAoe[#self.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				self.trackAuras[#self.trackAuras + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

function Player:EnergyTimeToMax(energy)
	local deficit = (energy or self.energy.max) - self.energy.current
	if deficit <= 0 then
		return 0
	end
	return deficit / self.energy.regen
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.cast.ability and self.cast.ability.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
end

function Player:BloodlustActive()
	local _, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if not id then
			return false
		elseif (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 381301 or -- Feral Hide Drums (Leatherworking)
			id == 390386    -- Fury of the Aspects (Evoker)
		) then
			return true
		end
	end
end

function Player:Dazed()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HARMFUL')
		if not id then
			return false
		elseif (
			id == 1604 -- Dazed (hit from behind)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	for i = (slot or 1), (slot or 19) do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId, slot)
	local link, item
	for i = (slot or 1), (slot or 19) do
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

function Player:UpdateTime(timeStamp)
	self.ctime = GetTime()
	if timeStamp then
		self.time_diff = self.ctime - timeStamp
	end
	self.time = self.ctime - self.time_diff
end

function Player:UpdateKnown()
	self.mana.max = UnitPowerMax('player', 0)
	self.chi.max = UnitPowerMax('player', 12)

	local node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.rank = 0
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.talent_node and configId then
			node = C_Traits.GetNodeInfo(configId, ability.talent_node)
			if node then
				ability.rank = node.activeRank
				ability.known = ability.rank > 0
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsUsableSpell(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
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
	if GiftOfTheOx.known then
		GiftOfTheOx.lowhp.known = true
		GiftOfTheOx.expire.known = true
		GiftOfTheOx.pickup.known = true
	end
	if Serenity.known then
		StormEarthAndFire.known = false
	end
	RushingJadeWind.damage.known = RushingJadeWind.known

	Abilities:Update()

	if APL[self.spec].precombat_variables then
		APL[self.spec]:precombat_variables()
	end
end

function Player:UpdateChannelInfo()
	local channel = self.channel
	local _, _, _, start, ends, _, _, spellId = UnitChannelInfo('player')
	if not spellId then
		channel.ability = nil
		channel.chained = false
		channel.start = 0
		channel.ends = 0
		channel.tick_count = 0
		channel.tick_interval = 0
		channel.ticks = 0
		channel.ticks_remain = 0
		channel.ticks_extra = 0
		channel.interrupt_if = nil
		channel.interruptible = false
		channel.early_chain_if = nil
		channel.early_chainable = false
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if ability and ability == channel.ability then
		channel.chained = true
	else
		channel.ability = ability
	end
	channel.ticks = 0
	channel.start = start / 1000
	channel.ends = ends / 1000
	if ability and ability.tick_interval then
		channel.tick_interval = ability:TickTime()
	else
		channel.tick_interval = channel.ends - channel.start
	end
	channel.tick_count = (channel.ends - channel.start) / channel.tick_interval
	if channel.chained then
		channel.ticks_extra = channel.tick_count - floor(channel.tick_count)
	else
		channel.ticks_extra = 0
	end
	channel.ticks_remain = channel.tick_count
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == self.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, start, ends, duration, spellId, speed, max_speed
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.wait_time = nil
	self.pool_energy = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, start, ends, _, _, _, spellId = UnitCastingInfo('player')
	if spellId then
		self.cast.ability = Abilities.bySpellId[spellId]
		self.cast.start = start / 1000
		self.cast.ends = ends / 1000
		self.cast.remains = self.cast.ends - self.ctime
	else
		self.cast.ability = nil
		self.cast.start = 0
		self.cast.ends = 0
		self.cast.remains = 0
	end
	self.execute_remains = max(self.cast.remains, self.gcd_remains)
	if self.channel.tick_count > 1 then
		self.channel.ticks = ((self.ctime - self.channel.start) / self.channel.tick_interval) - self.channel.ticks_extra
		self.channel.ticks_remain = (self.channel.ends - self.ctime) / self.channel.tick_interval
	end
	if self.spec == SPEC.MISTWEAVER then
		self.gcd = 1.5 * self.haste_factor
		self.mana.regen = GetPowerRegenForPowerType(0)
		self.mana.current = UnitPower('player', 0) + (self.mana.regen * self.execute_remains)
		if self.cast.ability then
			self.mana.current = self.mana.current - self.cast.ability:ManaCost()
		end
		self.mana.current = clamp(self.mana.current, 0, self.mana.max)
	else
		self.gcd = 1.0
		self.energy.regen = GetPowerRegenForPowerType(3)
		self.energy.max = UnitPowerMax('player', 3)
		self.energy.current = UnitPower('player', 3) + (self.energy.regen * self.execute_remains)
		self.energy.current = clamp(self.energy.current, 0, self.energy.max)
		self.energy.deficit = self.energy.max - self.energy.current
		if self.spec == SPEC.BREWMASTER then
			self.stagger.current = UnitStagger('player')
		else
			self.chi.current = UnitPower('player', 12)
			if self.cast.ability and self.cast.ability.chi_cost then
				self.chi.current = self.chi.current - self.cast.ability:ChiCost()
			end
			self.chi.current = clamp(self.chi.current, 0, self.chi.max)
			self.chi.deficit = self.chi.max - self.chi.current
		end
	end
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self:UpdateThreat()

	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	self.major_cd_remains = (StormEarthAndFire.known and StormEarthAndFire:Remains()) or (Serenity.known and Serenity:Remains()) or 0

	self.main = APL[self.spec]:Main()

	if self.channel.interrupt_if then
		self.channel.interruptible = self.channel.ability ~= self.main and self.channel.interrupt_if()
	end
	if self.channel.early_chain_if then
		self.channel.early_chainable = self.channel.ability == self.main and self.channel.early_chain_if()
	end
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	msmdPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
	_, self.instance = IsInInstance()
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player Functions

-- Start Target Functions

function Target:UpdateHealth(reset)
	Timer.health = 0
	self.health.current = UnitHealth('target')
	self.health.max = UnitHealthMax('target')
	if self.health.current <= 0 then
		self.health.current = Player.health.max
		self.health.max = self.health.current
	end
	if reset then
		for i = 1, 25 do
			self.health.history[i] = self.health.current
		end
	else
		table.remove(self.health.history, 1)
		self.health.history[25] = self.health.current
	end
	self.timeToDieMax = self.health.current / Player.health.max * 10
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec) or self.timeToDieMax
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = Player.level
		self.hostile = false
		self:UpdateHealth(true)
		if Opt.always_on then
			UI:UpdateCombat()
			msmdPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			msmdPreviousPanel:Hide()
		end
		return UI:Disappear()
	end
	if guid ~= self.guid then
		self.guid = guid
		self:UpdateHealth(true)
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= Player.level + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health.max > Player.health.max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		msmdPanel:Show()
		return true
	end
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self.health.current - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

-- End Target Functions

-- Start Ability Modifications

function Ability:Combo()
	return self.triggers_combo and ComboStrikes.last_ability ~= self
end

function Ability:ChiCost()
	local cost = self.chi_cost
	if cost > 0 then
		if Serenity.known and Serenity:Up() then
			cost = 0
		end
	end
	return cost
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
	if Target.healthPercentage >= 15 and (Target.player or Target.health.current > Player.health.current) then
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
	if Player.stagger.current <= 0 then
		return 0
	end
	return Player.stagger.current / max(1, self:TicksRemaining() + (Player.combat_start > 0 and -1 or 1))
end

function Stagger:TickPct()
	return self:Tick() / Player.health.current * 100
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
	if (Player.time - self.last_used) < 1 then -- assume full duration immediately when cast
		return self.buff_duration
	end
	local _, i, start, duration, icon
	for i = 1, 4 do
		_, _, start, duration, icon = GetTotemInfo(i)
		if icon and icon == self.icon then
			return max(0, duration - (Player.ctime - start) - Player.execute_remains)
		end
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

local function WaitFor(ability, wait_time)
	Player.wait_time = wait_time and (Player.ctime + wait_time) or (Player.ctime + ability:Cooldown())
	return ability
end

local function Pool(ability, extra)
	Player.pool_energy = ability:EnergyCost() + (extra or 0)
	return ability
end

-- Begin Action Priority Lists

APL[SPEC.NONE].Main = function(self)
end

APL[SPEC.BREWMASTER].Main = function(self)
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
actions+=/bonedust_brew
actions+=/purifying_brew
# Black Ox Brew is currently used to either replenish brews based on less than half a brew charge available, or low energy to enable Keg Smash
actions+=/black_ox_brew,if=cooldown.purifying_brew.charges_fractional<0.5
actions+=/black_ox_brew,if=(energy+(energy.regen*cooldown.keg_smash.remains))<40&buff.blackout_combo.down&cooldown.keg_smash.up
# Offensively, the APL prioritizes KS on cleave, BoS else, with energy spenders and cds sorted below
actions+=/keg_smash,if=spell_targets>=2
actions+=/faeline_stomp,if=spell_targets>=2
# cast KS at top prio during WoO buff
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
	Player.use_cds = Opt.cooldown and (Target.boss or Target.player or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd) or InvokeNiuzaoTheBlackOx:Up()
	if HealingElixir:Usable() and (Player.health.pct < 60 or (Player.health.pct < 80 and HealingElixir:ChargesFractional() > 1.5)) then
		UseCooldown(HealingElixir)
	end
	if TouchOfDeath:Usable() and (Stagger:Heavy() or Stagger:Moderate()) then
		UseCooldown(TouchOfDeath)
	end
	if FortifyingBrew:Usable() and Player.health.pct < 15 then
		UseCooldown(FortifyingBrew)
	end
	if Player.use_cds then
		if InvokeNiuzaoTheBlackOx:Usable() and (Stagger:Heavy() or Stagger:Moderate()) and (Player.enemies >= 3 or Target.timeToDie > 25) then
			UseCooldown(InvokeNiuzaoTheBlackOx)
		end
	end
	if Player.use_cds or Player:Enemies() > 1 then
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
	if CelestialBrew:Usable() and (not BlackoutCombo.known or BlackoutCombo:Down()) and ElusiveBrawler:Stack() < 2 then
		UseExtra(CelestialBrew)
	end
	if BlackoutCombo.known and RushingJadeWind.known and TigerPalm:Usable() and BlackoutCombo:Up() and RushingJadeWind:Up() then
		return TigerPalm
	end
	if BreathOfFire:Usable() and ((CharredPassions.known and CharredPassions:Down()) or ((ScaldingBrew.known or ((not CharredPassions.known or CharredPassions:Down()) and Player:Enemies() >= 3)) and BreathOfFire:Down() and KegSmash:Up())) then
		return BreathOfFire
	end
	if KegSmash:Usable() and not StormstoutsLastKeg.known then
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
	if ExpelHarm:Usable() and Player.health.pct < 70 and GiftOfTheOx.count >= 4 then
		return ExpelHarm
	end
	if ChiBurst:Usable() then
		UseCooldown(ChiBurst)
	end
	if ChiWave:Usable() then
		return ChiWave
	end
	if ExpelHarm:Usable() and Player.health.pct < 80 and GiftOfTheOx.count >= 2 then
		return ExpelHarm
	end
	if SpinningCraneKick:Usable() and Player:Enemies() >= 3 and not KegSmash:Ready(Player.gcd) and (Player:Energy() + (Player:EnergyRegen() * (KegSmash:Cooldown() + 1.5))) >= 65 and (not Spitfire.known or not CharredPassions.known) and (Stagger:Light() or PurifyingBrew:ChargesFractional() > 0.8 or (BlackOxBrew.known and BlackOxBrew:Ready())) then
		return SpinningCraneKick
	end
	if not BlackoutCombo.known and TigerPalm:Usable() and not KegSmash:Ready(Player.gcd) and (Player:Energy() + (Player:EnergyRegen() * (KegSmash:Cooldown() + Player.gcd))) >= 65 then
		return TigerPalm
	end
	if ExpelHarm:Usable() and Player.health.pct < 90 then
		return ExpelHarm
	end
	if RushingJadeWind:Usable() then
		return RushingJadeWind
	end
end

APL[SPEC.MISTWEAVER].Main = function(self)

end

APL[SPEC.WINDWALKER].Main = function(self)
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
		if ChiBurst:Usable() and Player.chi.deficit >= min(2, Player:Enemies()) then
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
actions+=/call_action_list,name=opener,if=!variable.opener_done
actions+=/fist_of_the_white_tiger,target_if=min:debuff.mark_of_the_crane.remains,if=chi.max-chi>=3&(energy.time_to_max<1|energy.time_to_max<4&cooldown.fists_of_fury.remains<1.5)
actions+=/expel_harm,if=chi.max-chi>=1&(energy.time_to_max<1|cooldown.serenity.remains<2|energy.time_to_max<4&cooldown.fists_of_fury.remains<1.5)
actions+=/tiger_palm,target_if=min:debuff.mark_of_the_crane.remains,if=combo_strike&chi.max-chi>=2&(energy.time_to_max<1|cooldown.serenity.remains<2|energy.time_to_max<4&cooldown.fists_of_fury.remains<1.5)
actions+=/call_action_list,name=cd_sef,if=!talent.serenity.enabled
actions+=/call_action_list,name=cd_serenity,if=talent.serenity.enabled
actions+=/call_action_list,name=st,if=active_enemies<3
actions+=/call_action_list,name=aoe,if=active_enemies>=3
]]
	Player.use_cds = Opt.cooldown and (Target.boss or (not Opt.boss_only and Target.timeToDie > Opt.cd_ttd) or InvokeXuenTheWhiteTiger:Up() or Player.major_cd_remains > 0
	Player.hold_xuen = not Player.use_cds or not InvokeXuenTheWhiteTiger:Ready(Target.timeToDie) or (Serenity.known and Target.timeToDie < 120 and Target.timeToDie > Serenity:Cooldown() and not Serenity:Ready(10))
	if FortifyingBrew:Usable() and Player.health.pct < 15 then
		UseCooldown(FortifyingBrew)
	end
	local apl
	if Serenity.known and Serenity:Up() then
		apl = self:serenity()
		if apl then return apl end
	end
	if not Player.opener_done then
		if Player.chi.current >= 5 or InvokeXuenTheWhiteTiger:Up() then
			Player.opener_done = true
		else
			apl = self:opener()
			if apl then return apl end
		end
	end
	if FistOfTheWhiteTiger:Usable() and Player.chi.deficit >= 3 and (Player:EnergyTimeToMax() < 1 or (Player:EnergyTimeToMax() < 4 and FistsOfFury:Ready(1.5))) then
		return FistOfTheWhiteTiger
	end
	if ExpelHarm:Usable() and Player.chi.deficit >= 1 and (Player:EnergyTimeToMax() < 1 or (Serenity.known and Serenity:Ready(2)) or (Player:EnergyTimeToMax() < 4 and FistsOfFury:Ready(1.5))) then
		return ExpelHarm
	end
	if TigerPalm:Usable() and TigerPalm:Combo() and Player.chi.deficit >= 2 and (Player:EnergyTimeToMax() < 1 or (Serenity.known and Serenity:Ready(2)) or (Player:EnergyTimeToMax() < 4 and FistsOfFury:Ready(1.5))) then
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
	if BonedustBrew.known and SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and BonedustBrew:Up() then
		return SpinningCraneKick
	end
	if StrikeOfTheWindlord:Usable() and StrikeOfTheWindlord:Combo() then
		UseCooldown(StrikeOfTheWindlord)
	end
	if FistOfTheWhiteTiger:Usable() and Player.chi.current < 3 then
		return FistOfTheWhiteTiger
	end
	if BlackoutKick:Usable() and BlackoutKick:Combo() then
		return BlackoutKick
	end
	if SpinningCraneKick:Usable() then
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
	if FistOfTheWhiteTiger:Usable() and Player.chi.deficit >= 3 then
		return FistOfTheWhiteTiger
	end
	if ChiBurst.known and ExpelHarm:Usable() and Player.chi.deficit >= 3 then
		return ExpelHarm
	end
	if TigerPalm:Usable() and TigerPalm:Combo() and Player.chi.deficit >= 2 then
		return TigerPalm
	end
	if ChiWave:Usable() and Player.chi.deficit == 2 then
		return ChiWave
	end
	if ExpelHarm:Usable() and Player.chi.deficit >= 1 then
		return ExpelHarm
	end
	if TigerPalm:Usable() and Player.chi.deficit >= 2 then
		return TigerPalm
	end
end

APL[SPEC.WINDWALKER].cd_serenity = function(self)
--[[
actions.cd_serenity=variable,name=serenity_burst,op=set,value=cooldown.serenity.remains<1|pet.xuen_the_white_tiger.active&cooldown.serenity.remains>30|fight_remains<20
actions.cd_serenity+=/invoke_xuen_the_white_tiger,if=!variable.hold_xuen|fight_remains<25
actions.cd_serenity+=/touch_of_death,if=fight_remains>180|pet.xuen_the_white_tiger.active|fight_remains<10
actions.cd_serenity+=/touch_of_karma,if=fight_remains>90|pet.xuen_the_white_tiger.active|fight_remains<10
actions.cd_serenity+=/faeline_stomp
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
	if Player.use_cds then
		if Serenity:Usable() and (RisingSunKick:Ready(2) or Target.timeToDie < 15) then
			UseCooldown(Serenity)
		end
	end
end

APL[SPEC.WINDWALKER].cd_sef = function(self)
--[[
actions.cd_sef=invoke_xuen_the_white_tiger,if=!variable.hold_xuen|fight_remains<25
actions.cd_sef+=/touch_of_death,if=buff.storm_earth_and_fire.down&pet.xuen_the_white_tiger.active|fight_remains<10|fight_remains>180
actions.cd_sef+=/faeline_stomp,if=combo_strike&(raid_event.adds.in>10|raid_event.adds.up)
actions.cd_sef+=/bonedust_brew,if=raid_event.adds.in>50|raid_event.adds.up,line_cd=60
actions.cd_sef+=/storm_earth_and_fire,if=cooldown.storm_earth_and_fire.charges=2|fight_remains<20|raid_event.adds.remains>15
actions.cd_sef+=/storm_earth_and_fire,if=((raid_event.adds.in>cooldown.storm_earth_and_fire.full_recharge_time|!raid_event.adds.exists)&(cooldown.invoke_xuen_the_white_tiger.remains>cooldown.storm_earth_and_fire.full_recharge_time|variable.hold_xuen))&cooldown.fists_of_fury.remains<=9&chi>=2&cooldown.whirling_dragon_punch.remains<=12
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
	if Player.use_cds then
		if StormEarthAndFire:Usable() and StormEarthAndFire:Down() then
			if (Target.boss and Target.timeToDie < 20) or StormEarthAndFire:Charges() >= 2 then
				UseCooldown(StormEarthAndFire)
			end
			if (Player.hold_xuen or not InvokeXuenTheWhiteTiger:Ready(StormEarthAndFire:FullRechargeTime())) and FistsOfFury:Ready(9) and Player.chi.current >= 2 and (not WhirlingDragonPunch.known or WhirlingDragonPunch:Ready(12)) then
				UseCooldown(StormEarthAndFire)
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
actions.st+=/crackling_jade_lightning,if=buff.the_emperors_capacitor.stack>19&energy.time_to_max>execute_time-1&cooldown.rising_sun_kick.remains>execute_time|buff.the_emperors_capacitor.stack>14&(cooldown.serenity.remains<5&talent.serenity.enabled|fight_remains<5)
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
	if EnergizingElixir:Usable() and ((Player.chi.deficit >= 2 and Player:EnergyTimeToMax() > 3) or (Player.chi.deficit >= 4 and (Player:EnergyTimeToMax() > 2 or not TigerPalm:Previous()))) then
		UseCooldown(EnergizingElixir)
	end
	if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and DanceOfChiJi:Up() then
		return SpinningCraneKick
	end
	if RisingSunKick:Usable() and (not Serenity.known or not Serenity:Ready(1)) then
		return RisingSunKick
	end
	if FistsOfFury:Usable() and (Player:EnergyTimeToMax() > (4 * Player.haste_factor - 1) or Player.chi.deficit <= 1 or StormEarthAndFire:Remains() < (4 * Player.haste_factor + 1) or Target.timeToDie < (4 * Player.haste_factor + 1)) then
		return FistsOfFury
	end
	if LastEmperorsCapacitor.known and CracklingJadeLightning:Usable() and ((LastEmperorsCapacitor:Stack() > 19 and Player:EnergyTimeToMax() > (4 * Player.haste_factor - 1) and not RisingSunKick:Ready(4 * Player.haste_factor)) or (LastEmperorsCapacitor:Stack() > 14 and ((Serenity.known and Serenity:Ready(5)) or Target.timeToDie < 5))) then
		return CracklingJadeLightning
	end
	if RushingJadeWind:Usable() and RushingJadeWind:Down() and Player:Enemies() > 1 then
		return RushingJadeWind
	end
	if FistOfTheWhiteTiger:Usable() and Player.chi.current < 3 then
		return FistOfTheWhiteTiger
	end
	if ExpelHarm:Usable() and Player.chi.deficit >= 1 then
		return ExpelHarm
	end
	if ChiBurst:Usable() and Player.chi.deficit >= min(2, Player:Enemies()) then
		UseCooldown(ChiBurst)
	end
	if ChiWave:Usable() then
		return ChiWave
	end
	if TigerPalm:Usable() and TigerPalm:Combo() and Player.chi.deficit >= 2 and StormEarthAndFire:Down() then
		return TigerPalm
	end
	if BlackoutKick:Usable() and BlackoutKick:Combo() and ((Serenity.known and Serenity:Ready(3)) or (not RisingSunKick:Ready(1) and not FistsOfFury:Ready(1)) or (RisingSunKick:Ready(3) and not FistsOfFury:Ready(3) and Player.chi.current > 2) or (not RisingSunKick:Ready(3) and FistsOfFury:Ready(3) and Player.chi.current > 3) or Player.chi.current > 5 or BlackoutKick.free:Up()) then
		return BlackoutKick
	end
	if StrikeOfTheWindlord:Usable() and StrikeOfTheWindlord:Combo() then
		UseCooldown(StrikeOfTheWindlord)
	end
	if TigerPalm:Usable() and TigerPalm:Combo() and Player.chi.deficit >= 2 then
		return TigerPalm
	end
	if FlyingSerpentKick:Usable() and ((TigerPalm:Previous() and Player.chi.deficit >= 2) or (BlackoutKick:Previous() and BlackoutKick:Usable())) then
		UseCooldown(FlyingSerpentKick)
	end
	if BlackoutKick:Usable() and BlackoutKick:Combo() and ((FistsOfFury:Ready(3) and Player.chi.current == 2 and TigerPalm:Previous() and Player:EnergyTimeToMax(50) < 1) or (Player:EnergyTimeToMax() < 2 and (Player.chi.deficit <= 1 or TigerPalm:Previous()))) then
		return BlackoutKick
	end
	if TigerPalm:Usable(0, true) and TigerPalm:Combo() and Player.chi.deficit >= 2 then
		return Pool(TigerPalm)
	end
	if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and Player.chi.current >= 4 and not (FistsOfFury:Ready(2) or RisingSunKick:Ready(2)) then
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
	if EnergizingElixir:Usable() and ((Player.chi.deficit >= 2 and Player:EnergyTimeToMax() > 2) or Player.chi.deficit >= 4) then
		UseCooldown(EnergizingElixir)
	end
	if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and (DanceOfChiJi:Up() or BonedustBrew:Up()) then
		return SpinningCraneKick
	end
	if StrikeOfTheWindlord:Usable() and StrikeOfTheWindlord:Combo() then
		UseCooldown(StrikeOfTheWindlord)
	end
	if FistsOfFury:Usable() and (Player:EnergyTimeToMax() > (4 * Player.haste_factor) or Player.chi.deficit <= 1) then
		return FistsOfFury
	end
	if WhirlingDragonPunch.known and RisingSunKick:Usable() and (10 * Player.haste_factor) > (WhirlingDragonPunch:Cooldown() + 4) and (not FistsOfFury:Ready(3) or Player.chi.current >= 5) then
		return RisingSunKick
	end
	if RushingJadeWind:Usable() then
		return RushingJadeWind
	end
	if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and ((not BonedustBrew.known or BonedustBrew:Cooldown() > 2 and (Player.chi.current > 3 or not FistsOfFury:Ready(6)) and (Player.chi.current >= 5 or not FistsOfFury:Ready(2))) or Player:EnergyTimeToMax() < 3) then
		return SpinningCraneKick
	end
	if ExpelHarm:Usable() and Player.chi.deficit >= 1 then
		return ExpelHarm
	end
	if FistOfTheWhiteTiger:Usable() and Player.chi.deficit >= 3 then
		return FistOfTheWhiteTiger
	end
	if ChiBurst:Usable() and Player.chi.deficit >= 2 then
		UseCooldown(ChiBurst)
	end
	if LastEmperorsCapacitor.known and CracklingJadeLightning:Usable() and LastEmperorsCapacitor:Stack() > 19 and Player:EnergyTimeToMax() > (4 * Player.haste_factor - 1) and not FistsOfFury:Ready(4 * Player.haste_factor) then
		return CracklingJadeLightning
	end
	if TigerPalm:Usable() and (TigerPalm:Combo() or not HitCombo.known) and Player.chi.deficit >= 2 then
		return TigerPalm
	end
	if ChiWave:Usable() and ChiWave:Combo() then
		return ChiWave
	end
	if FlyingSerpentKick:Usable() and ((TigerPalm:Previous() and Player.chi.deficit >= 2) or (BlackoutKick:Previous() and BlackoutKick:Usable()) or (SpinningCraneKick:Previous() and SpinningCraneKick:Usable())) then
		UseCooldown(FlyingSerpentKick)
	end
	if BlackoutKick:Usable() and BlackoutKick:Combo() and (BlackoutKick.free:Up() or (HitCombo.known and TigerPalm:Previous() and Player.chi.current == 2 and FistsOfFury:Ready(3)) or (Player.chi.deficit <= 1 and SpinningCraneKick:Previous() and Player:EnergyTimeToMax() < 3)) then
		return BlackoutKick
	end
	if TigerPalm:Usable(0, true) and TigerPalm:Combo() and Player.chi.deficit >= 2 then
		return Pool(TigerPalm)
	end
	if SpinningCraneKick:Usable() and SpinningCraneKick:Combo() and Player.chi.current >= 3 then
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

-- Start UI Functions

function UI.DenyOverlayGlow(actionButton)
	if Opt.glow.blizzard then
		return
	end
	local alert = actionButton.SpellActivationAlert
	if not alert then
		return
	end
	if alert.ProcStartAnim:IsPlaying() then
		alert.ProcStartAnim:Stop()
	end
	alert:Hide()
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r, g, b = Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.ProcStartFlipbook:SetVertexColor(r, g, b)
		glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
	end
end

function UI:DisableOverlayGlows()
	if LibStub and LibStub.GetLibrary and not Opt.glow.blizzard then
		local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
		if lib then
			lib.ShowOverlayGlow = function(self)
				return
			end
		end
	end
end

function UI:CreateOverlayGlows()
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.ProcStartAnim:Play() -- will bug out if ProcLoop plays first
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
	local glow, icon
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
				glow:Show()
				if Opt.glow.animation then
					glow.ProcStartAnim:Play()
				else
					glow.ProcLoop:Play()
				end
			end
		elseif glow:IsVisible() then
			if glow.ProcStartAnim:IsPlaying() then
				glow.ProcStartAnim:Stop()
			end
			if glow.ProcLoop:IsPlaying() then
				glow.ProcLoop:Stop()
			end
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	msmdPanel:EnableMouse(draggable or Opt.aoe)
	msmdPanel.button:SetShown(Opt.aoe)
	msmdPreviousPanel:EnableMouse(draggable)
	msmdCooldownPanel:EnableMouse(draggable)
	msmdInterruptPanel:EnableMouse(draggable)
	msmdExtraPanel:EnableMouse(draggable)
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
			['below'] = { 'TOP', 'BOTTOM', 0, -32 },
		},
		[SPEC.MISTWEAVER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -32 },
		},
		[SPEC.WINDWALKER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -32 },
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.BREWMASTER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[SPEC.MISTWEAVER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[SPEC.WINDWALKER] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
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
	Timer.display = 0
	local border, dim, dim_cd, border, text_center, text_tl, text_tr, text_cd, color_center

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.main then
		if Player.main.requires_react then
			local react = Player.main:React()
			if react > 0 then
				text_center = format('%.1f', react)
			end
		end
		if Player.main_freecast then
			border = 'freecast'
		end
	end
	if Player.cd then
		if Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd = format('%.1f', react)
			end
		end
	end
	if Player.wait_time then
		local deficit = Player.wait_time - GetTime()
		if deficit > 0 then
			text_center = format('WAIT\n%.1fs', deficit)
			dim = Opt.dimmer
		end
	end
	if Player.pool_energy then
		local deficit = Player.pool_energy - UnitPower('player', 3)
		if deficit > 0 then
			text_center = format('POOL\n%d', deficit)
			dim = Opt.dimmer
		end
	end
	if Player.channel.tick_count > 0 then
		dim = Opt.dimmer
		if Player.channel.tick_count > 1 then
			local ctime = GetTime()
			local channel = Player.channel
			channel.ticks = ((ctime - channel.start) / channel.tick_interval) - channel.ticks_extra
			channel.ticks_remain = (channel.ends - ctime) / channel.tick_interval
			text_center = format('TICKS\n%.1f', max(0, channel.ticks))
			if channel.ability == Player.main then
				if channel.ticks_remain < 1 or channel.early_chainable then
					dim = false
					text_center = 'CHAIN'
					color_center = 'green'
				end
			elseif channel.interruptible then
				dim = false
			end
		end
	end
	if Player.major_cd_remains > 0 then
		text_tr = format('%.1fs', Player.major_cd_remains)
		if Serenity.known then
			border = 'serenity'
		end
	end
	if GiftOfTheOx.known then
		text_tl = GiftOfTheOx.count
	end
	if color_center ~= msmdPanel.text.center.color then
		msmdPanel.text.center.color = color_center
		if color_center == 'green' then
			msmdPanel.text.center:SetTextColor(0, 1, 0, 1)
		elseif color_center == 'red' then
			msmdPanel.text.center:SetTextColor(1, 0, 0, 1)
		else
			msmdPanel.text.center:SetTextColor(1, 1, 1, 1)
		end
	end
	if border ~= msmdPanel.border.overlay then
		msmdPanel.border.overlay = border
		msmdPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	msmdPanel.dimmer:SetShown(dim)
	msmdPanel.text.center:SetText(text_center)
	msmdPanel.text.tl:SetText(text_tl)
	msmdPanel.text.tr:SetText(text_tr)
	--msmdPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	msmdCooldownPanel.text:SetText(text_cd)
	msmdCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		msmdPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.mana_cost > 0 and Player.main:ManaCost() == 0) or (Player.main.energy_cost > 0 and Player.main:EnergyCost() == 0) or (Player.main.chi_cost > 0 and Player.main:ChiCost() == 0) or (Player.main.Free and Player.main:Free())
	end
	if Player.cd then
		msmdCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local start, duration = GetSpellCooldown(Player.cd.spellId)
			msmdCooldownPanel.swipe:SetCooldown(start, duration)
		end
	end
	if Player.extra then
		msmdExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			msmdInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			msmdInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		msmdInterruptPanel.icon:SetShown(Player.interrupt)
		msmdInterruptPanel.border:SetShown(Player.interrupt)
		msmdInterruptPanel:SetShown(start and not notInterruptible)
	end
	if Opt.previous and msmdPreviousPanel.ability then
		if (Player.time - msmdPreviousPanel.ability.last_used) > 10 then
			msmdPreviousPanel.ability = nil
			msmdPreviousPanel:Hide()
		end
	end

	msmdPanel.icon:SetShown(Player.main)
	msmdPanel.border:SetShown(Player.main)
	msmdCooldownPanel:SetShown(Player.cd)
	msmdExtraPanel:SetShown(Player.extra)

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - Timer.combat > seconds then
		Timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI Functions

-- Start Event Handling

function Events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = MonkSeeMonkDo
		local firstRun = not Opt.frequency
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		if firstRun then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_MonkSeeMonkDo1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
	end
end

CombatEvent.TRIGGER = function(timeStamp, event, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
	Player:UpdateTime(timeStamp)
	local e = event
	if (
	   e == 'UNIT_DESTROYED' or
	   e == 'UNIT_DISSIPATES' or
	   e == 'SPELL_INSTAKILL' or
	   e == 'PARTY_KILL')
	then
		e = 'UNIT_DIED'
	elseif (
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_ENERGIZE' or
	   e == 'SPELL_PERIODIC_DAMAGE' or
	   e == 'SPELL_MISSED' or
	   e == 'SPELL_AURA_APPLIED' or
	   e == 'SPELL_AURA_REFRESH' or
	   e == 'SPELL_AURA_REMOVED')
	then
		e = 'SPELL'
	end
	if CombatEvent[e] then
		return CombatEvent[e](event, srcGUID, dstGUID, ...)
	end
end

CombatEvent.UNIT_DIED = function(event, srcGUID, dstGUID)
	trackAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability.CastFailed and ability:CastFailed(dstGUID, missType)
	elseif event == 'SPELL_ENERGIZE' then
		return ability.Energize and ability:Energize(missType, overCap, powerType)
	end
	if ability.aura_targets then
		if event == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif event == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif event == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if dstGUID == Player.guid then
		if event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
			ability.last_gained = Player.time
		end
		return -- ignore buffs beyond here
	end
	if Opt.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not ability.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (event == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function Events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function Events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function Events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth('player')
		Player.health.max = UnitHealthMax('player')
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function Events:UNIT_POWER_UPDATE(unitId, powerType)
	if unitId == 'player' and powerType == 'CHI' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
Events.UNIT_SPELLCAST_FAILED = Events.UNIT_SPELLCAST_STOP
Events.UNIT_SPELLCAST_INTERRUPTED = Events.UNIT_SPELLCAST_STOP

function Events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function Events:UNIT_SPELLCAST_CHANNEL_UPDATE(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:UpdateChannelInfo()
	end
end
Events.UNIT_SPELLCAST_CHANNEL_START = Events.UNIT_SPELLCAST_CHANNEL_UPDATE
Events.UNIT_SPELLCAST_CHANNEL_STOP = Events.UNIT_SPELLCAST_CHANNEL_UPDATE

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		msmdPreviousPanel:Hide()
	end
	for _, ability in next, Abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		AutoAoe:Clear()
	end
end

function Events:PLAYER_EQUIPMENT_CHANGED()
	local _, equipType, hasCooldown
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

	Player.set_bonus.t29 = (Player:Equipped(200360) and 1 or 0) + (Player:Equipped(200362) and 1 or 0) + (Player:Equipped(200363) and 1 or 0) + (Player:Equipped(200364) and 1 or 0) + (Player:Equipped(200365) and 1 or 0)
	Player.set_bonus.t30 = (Player:Equipped(202504) and 1 or 0) + (Player:Equipped(202505) and 1 or 0) + (Player:Equipped(202506) and 1 or 0) + (Player:Equipped(202507) and 1 or 0) + (Player:Equipped(202509) and 1 or 0)

	Player:UpdateKnown()
end

function Events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	msmdPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:UPDATE_SHAPESHIFT_FORM()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end

function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
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

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function Events:GROUP_ROSTER_UPDATE()
	Player.group_size = clamp(GetNumGroupMembers(), 1, 40)
end

function Events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() Events:PLAYER_EQUIPMENT_CHANGED() end)
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
	Timer.combat = Timer.combat + elapsed
	Timer.display = Timer.display + elapsed
	Timer.health = Timer.health + elapsed
	if Timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if Timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if Timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

msmdPanel:SetScript('OnEvent', function(self, event, ...) Events[event](self, ...) end)
for event in next, Events do
	msmdPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local SetHyperlink = ItemRefTooltip.SetHyperlink
ItemRefTooltip.SetHyperlink = function(self, link)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		BattleTagInviteFrame_Show(linkData)
		return
	end
	SetHyperlink(self, link)
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
		if Opt.aoe or Opt.snap then
			Status('Warning', 'Panels cannot be moved when aoe or snap are enabled!')
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
				Opt.locked = true
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
				Opt.locked = true
			else
				Opt.snap = false
				Opt.locked = false
				msmdPanel:ClearAllPoints()
			end
			UI:UpdateDraggable()
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
			Opt.alpha = clamp(tonumber(msg[2]) or 100, 0, 100) / 100
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
		if startsWith(msg[2], 'anim') then
			if msg[3] then
				Opt.glow.animation = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Use extended animation (shrinking circle)', Opt.glow.animation)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = clamp(tonumber(msg[3]) or 0, 0, 1)
				Opt.glow.color.g = clamp(tonumber(msg[4]) or 0, 0, 1)
				Opt.glow.color.b = clamp(tonumber(msg[5]) or 0, 0, 1)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, |cFFFFD000animation|r, and |cFFFFD000color')
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
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Brewmaster specialization', not Opt.hide.brewmaster)
			end
			if startsWith(msg[2], 'm') then
				Opt.hide.mistweaver = not Opt.hide.mistweaver
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Mistweaver specialization', not Opt.hide.mistweaver)
			end
			if startsWith(msg[2], 'w') then
				Opt.hide.windwalker = not Opt.hide.windwalker
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
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
			Opt.cd_ttd = tonumber(msg[2]) or 10
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
	if startsWith(msg[1], 'he') then
		if msg[2] then
			Opt.heal_threshold = clamp(tonumber(msg[2]) or 60, 0, 100)
		end
		return Status('Health percentage threshold to recommend self healing spells', Opt.heal_threshold .. '%')
	end
	if startsWith(msg[1], 'de') then
		if msg[2] then
			Opt.defensives = msg[2] == 'on'
		end
		return Status('Show defensives/emergency heals in extra UI', Opt.defensives)
	end
	if msg[1] == 'reset' then
		msmdPanel:ClearAllPoints()
		msmdPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r/|cFFFFD000animation|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
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
		'heal |cFFFFD000[percent]|r - health percentage threshold to recommend self healing spells (default is 60%, 0 to disable)',
		'defensives |cFF00C000on|r/|cFFC00000off|r - show defensives/emergency heals in extra UI',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_MonkSeeMonkDo1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands

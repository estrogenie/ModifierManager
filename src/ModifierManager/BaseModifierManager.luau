-- Connected Discord-GitHub | Discord: naturalvalkyrie (515834258896715788) | Roblox: NaturalValkyrie (1023948619)
--!strict
-- shared base both managers inherit from with metatables holds all the actual stat logic
local Signal = require(script.Parent.Packages.Signal)
local Trove = require(script.Parent.Packages.Trove)
local Types = require(script.Parent.Types)
local Calculator = require(script.Parent.Calculator)

export type ModifierType = Types.ModifierType
export type StackingRule = Types.StackingRule
export type Modifier = Types.Modifier
export type StatStack = Types.StatStack
export type ExpirationEntry = Types.ExpirationEntry
export type ModifierConfig = Types.ModifierConfig
export type StatSyncData = Types.StatSyncData
export type StackKey = Types.StackKey
export type StackMap = Types.StackMap
export type SignalMap = Types.SignalMap
export type TagMap = Types.TagMap
export type BaseModifierManagerImpl = Types.BaseModifierManagerData

local VALID_MODIFIER_TYPES: { [string]: boolean } = {
	Additive = true,
	Multiplicative = true,
	Override = true,
}

local VALID_STACKING_RULES: { [string]: boolean } = {
	Stack = true,
	Replace = true,
	Highest = true,
	Refresh = true,
}

local BaseModifierManager = {}
BaseModifierManager.__index = BaseModifierManager

BaseModifierManager.VALID_MODIFIER_TYPES = VALID_MODIFIER_TYPES
BaseModifierManager.VALID_STACKING_RULES = VALID_STACKING_RULES

function BaseModifierManager.new(): BaseModifierManagerImpl
	-- all the state stacks signals tag index expiry queue lazy removals trove and cleanup timer
	local self: BaseModifierManagerImpl = setmetatable({
		stacks = {},
		signals = {},
		tagIndex = {},
		expirationQueue = {},
		pendingRemovals = {},
		trove = Trove.new(),
		scheduledCleanupThread = nil,
	}, BaseModifierManager) :: any

	return self
end

-- order matters here SO kill the timer first so it cant fire while were mid destroy then drop the signals trove and tables
function BaseModifierManager.Destroy(self: BaseModifierManagerImpl)
	if self.scheduledCleanupThread then
		task.cancel(self.scheduledCleanupThread)
	end
	(self :: any).scheduledCleanupThread = nil

	for _, signalMap in self.signals do
		for _, signal in signalMap do
			signal:Destroy()
		end
	end

	self.trove:Destroy()
	self.signals = {}
	self.stacks = {}
	self.tagIndex = {}
	self.expirationQueue = {}
	self.pendingRemovals = {}
end

-- enforces the category.statname format every path follows splitting on the dot and erroring if its not exactly two parts
function BaseModifierManager.ValidateStatPath(_self: BaseModifierManagerImpl, statPath: string): (string, string)
	if type(statPath) ~= "string" or statPath == "" then
		error("statPath must be a non-empty string")
	end

	local parts = string.split(statPath, ".")
	if #parts ~= 2 then
		error(`Invalid statPath format: "{statPath}". Expected "Category.StatName"`)
	end

	return parts[1], parts[2]
end

-- one timer pointed at whatever expires soonest instead of checking every frame
function BaseModifierManager.ScheduleNextCleanup(self: BaseModifierManagerImpl)
	if self.scheduledCleanupThread then
		task.cancel(self.scheduledCleanupThread)
	end
	(self :: any).scheduledCleanupThread = nil

	if #self.expirationQueue == 0 then
		return
	end

	-- soonest to expire is always at the front so thats what we aim the timer at
	local nextEntry = self.expirationQueue[1] :: ExpirationEntry
	-- time left until it fires clamped at 0 so an already overdue one runs now instead of with a negative delay
	local delay = math.max(0, nextEntry.expireTime - os.clock())

	-- one timer that cleans up then rearms itself for whatever the next soonest turns out to be
	self.scheduledCleanupThread = task.delay(delay, function()
		(self :: any).scheduledCleanupThread = nil
		;(self :: any):CleanupExpiredModifiers()
		;(self :: any):ScheduleNextCleanup()
	end)
end

-- binary search the right spot since modifiers stay sorted by priority way cheaper than resorting
function BaseModifierManager.FindInsertIndexBinarySearch(_self: BaseModifierManagerImpl, modifiers: { Modifier }, priority: number): number
	if #modifiers == 0 then
		return 1 -- empty list so it just goes at the front
	end

	-- left/right is the window were still searching insertindex is our best answer so far
	local left, right = 1, #modifiers
	local insertIndex = #modifiers + 1 -- default to the end if nothing outranks us

	while left <= right do
		local mid = math.floor((left + right) / 2) -- middle of whats left to search
		if modifiers[mid].priority > priority then
			-- mid outranks us so we belong at or before it remember the spot and keep searching the left half
			insertIndex = mid
			right = mid - 1
		else
			-- mid is lower or equal so our spot has to be somewhere to the right
			left = mid + 1
		end
	end

	return insertIndex -- first slot with a higher priority than ours which is what keeps the list sorted
end

-- binary insert by expire time keeps index 1 as the next to expire and if this one lands first we rearm the timer for it
function BaseModifierManager.AddToExpirationQueue(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string, modifierId: string, expireTime: number)
	local entry: ExpirationEntry = {
		expireTime = expireTime,
		stackKey = stackKey,
		statPath = statPath,
		modifierId = modifierId,
	}

	-- nothing queued yet so it goes straight in and kicks off the timer
	if #self.expirationQueue == 0 then
		table.insert(self.expirationQueue, entry)
		BaseModifierManager.ScheduleNextCleanup(self)
		return
	end

	-- binary search for the slot that keeps the queue sorted soonest first
	local left, right = 1, #self.expirationQueue
	local insertIndex = #self.expirationQueue + 1

	while left <= right do
		local mid = math.floor((left + right) / 2)
		if self.expirationQueue[mid].expireTime <= expireTime then
			-- mid expires sooner or at the same time so our spot is after it
			left = mid + 1
			insertIndex = left
		else
			-- mid expires later so we belong before it
			right = mid - 1
		end
	end

	table.insert(self.expirationQueue, insertIndex, entry)

	-- we landed at the very front so were the new soonest and the timer has to retarget onto us
	if insertIndex == 1 then
		BaseModifierManager.ScheduleNextCleanup(self)
	end
end

-- just flag the id instead of removing now cause splicing is slow cleanup skips it later
function BaseModifierManager.RemoveFromExpirationQueue(self: BaseModifierManagerImpl, modifierId: string)
	self.pendingRemovals[modifierId] = true
end

-- pops everything past its expire time off the front and skips any id that got lazily flagged for removal earlier
function BaseModifierManager.CleanupExpiredModifiers(self: BaseModifierManagerImpl)
	local currentTime = os.clock()

	while #self.expirationQueue > 0 do
		local entry = self.expirationQueue[1] -- front is always the soonest
		-- front hasnt expired yet so nothing behind it has either so we can stop
		if currentTime < entry.expireTime then
			break
		end

		table.remove(self.expirationQueue, 1) -- pull it off the front were handling it now

		-- this id was already removed elsewhere and only lazily flagged so clear the flag and skip it
		if self.pendingRemovals[entry.modifierId] then
			self.pendingRemovals[entry.modifierId] = nil
			continue
		end

		-- the stack couldve been wiped since this got queued so bail if its gone
		local stackKeyStacks = self.stacks[entry.stackKey]
		if not stackKeyStacks then
			continue
		end

		local stack = stackKeyStacks[entry.statPath]
		if not stack then
			continue
		end

		-- scan for the modifier that matches this id then pull it out and mark the stat dirty
		for index = #stack.modifiers, 1, -1 do
			local modifier = stack.modifiers[index]
			if modifier.id == entry.modifierId then
				BaseModifierManager.RemoveModifierFromTagIndex(self, entry.stackKey, entry.statPath, modifier)
				table.remove(stack.modifiers, index)
				stack.isDirty = true
				BaseModifierManager.TriggerChange(self, entry.statPath, entry.stackKey)
				break
			end
		end
	end
end

-- reverse lookup of tag to modifier ids so removebytag doesnt have to scan everything
function BaseModifierManager.AddModifierToTagIndex(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string, modifier: Modifier)
	-- build each layer only if its missing so we never index into a nil table
	if not self.tagIndex[stackKey] then
		self.tagIndex[stackKey] = {}
	end

	if not self.tagIndex[stackKey][statPath] then
		self.tagIndex[stackKey][statPath] = {}
	end

	for _, tag in modifier.tags do
		if not self.tagIndex[stackKey][statPath][tag] then
			self.tagIndex[stackKey][statPath][tag] = {}
		end

		-- store the id under its tag so removebytag can find it instantly instead of scanning the whole stack
		self.tagIndex[stackKey][statPath][tag][modifier.id] = true
	end
end

-- removes the id then prunes the empty tables it leaves behind otherwise the tag index slowly leaks dead entries
function BaseModifierManager.RemoveModifierFromTagIndex(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string, modifier: Modifier)
	if not self.tagIndex[stackKey] then
		return
	end
	if not self.tagIndex[stackKey][statPath] then
		return
	end

	for _, tag in modifier.tags do
		if self.tagIndex[stackKey][statPath][tag] then
			self.tagIndex[stackKey][statPath][tag][modifier.id] = nil -- drop this id from the tag

			-- that was the last id under the tag so remove the now empty table
			if next(self.tagIndex[stackKey][statPath][tag]) == nil then
				self.tagIndex[stackKey][statPath][tag] = nil
			end
		end
	end

	-- keep pruning upward so empty tables dont pile up and leak memory
	if next(self.tagIndex[stackKey][statPath]) == nil then
		self.tagIndex[stackKey][statPath] = nil
	end

	if next(self.tagIndex[stackKey]) == nil then
		self.tagIndex[stackKey] = nil
	end
end

-- handles same source modifiers replace highest or refresh returns an id if it dealt with it
function BaseModifierManager.HandleStackingRule(
	self: BaseModifierManagerImpl,
	stack: StatStack,
	rule: StackingRule,
	source: string,
	config: ModifierConfig,
	stackKey: StackKey
): string?
	local existingModifiers: { Modifier } = {}

	-- collect anything already on the stack that came from the same source
	for _, modifier in stack.modifiers do
		if modifier.source == source then
			table.insert(existingModifiers, modifier)
		end
	end

	if #existingModifiers == 0 then
		return nil
	end

	if rule == "Replace" then
		-- replace just drops every old one so the new modifier fully takes over
		for _, modifier in existingModifiers do
			BaseModifierManager.RemoveModifierById(self, stackKey, config.path, modifier.id)
		end
		return nil
	elseif rule == "Highest" then
		local highestValue = config.value
		for _, modifier in existingModifiers do
			-- an existing one is already stronger so keep it and tell the caller not to add the new one
			if modifier.value > highestValue then
				return modifier.id
			end
		end

		-- the new value wins so clear out the weaker existing ones before it gets added
		for _, modifier in existingModifiers do
			BaseModifierManager.RemoveModifierById(self, stackKey, config.path, modifier.id)
		end
		return nil
	elseif rule == "Refresh" then
		if #existingModifiers > 0 then
			local modifier = existingModifiers[1] -- reuse the existing modifier instead of stacking a duplicate
			modifier.value = config.value
			-- reset its timer by pulling the old expiry entry and queueing a fresh one
			if config.duration then
				BaseModifierManager.RemoveFromExpirationQueue(self, modifier.id)
				local newExpireTime = os.clock() + config.duration
				modifier.expireTime = newExpireTime
				BaseModifierManager.AddToExpirationQueue(self, stackKey, config.path, modifier.id, newExpireTime)
			end
			stack.isDirty = true
			BaseModifierManager.TriggerChange(self, config.path, stackKey)
			return modifier.id
		end
		return nil
	else
		return nil
	end
end

function BaseModifierManager.RemoveModifierById(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string, modifierId: string): boolean
	if not self.stacks[stackKey] then
		return false
	end
	if not self.stacks[stackKey][statPath] then
		return false
	end

	local stack = self.stacks[stackKey][statPath]

	for index, modifier in stack.modifiers do
		if modifier.id == modifierId then
			BaseModifierManager.RemoveModifierFromTagIndex(self, stackKey, statPath, modifier)
			BaseModifierManager.RemoveFromExpirationQueue(self, modifierId)
			table.remove(stack.modifiers, index)
			stack.isDirty = true
			BaseModifierManager.TriggerChange(self, statPath, stackKey)
			return true
		end
	end

	return false
end

-- loops backwards on purpose so removing entries doesnt shift the indexes were still iterating over
function BaseModifierManager.RemoveBySource(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string, source: string): number
	if not self.stacks[stackKey] then
		return 0
	end
	if not self.stacks[stackKey][statPath] then
		return 0
	end

	local stack = self.stacks[stackKey][statPath]
	local removedCount = 0

	for index = #stack.modifiers, 1, -1 do
		if stack.modifiers[index].source == source then
			local modifier = stack.modifiers[index]
			BaseModifierManager.RemoveModifierFromTagIndex(self, stackKey, statPath, modifier)
			BaseModifierManager.RemoveFromExpirationQueue(self, modifier.id)
			table.remove(stack.modifiers, index)
			removedCount = removedCount + 1
		end
	end

	if removedCount > 0 then
		stack.isDirty = true
		BaseModifierManager.TriggerChange(self, statPath, stackKey)
	end

	return removedCount
end

-- goes through the tag index to find matches instead of scanning every modifier on the stack
function BaseModifierManager.RemoveByTag(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string, tag: string): number
	if not self.stacks[stackKey] then
		return 0
	end
	if not self.stacks[stackKey][statPath] then
		return 0
	end

	if not self.tagIndex[stackKey] then
		return 0
	end
	if not self.tagIndex[stackKey][statPath] then
		return 0
	end
	if not self.tagIndex[stackKey][statPath][tag] then
		return 0
	end

	local stack = self.stacks[stackKey][statPath]
	local modifierIdsToRemove = self.tagIndex[stackKey][statPath][tag]

	local removedCount = 0

	for index = #stack.modifiers, 1, -1 do
		local modifier = stack.modifiers[index]
		if modifierIdsToRemove[modifier.id] then
			BaseModifierManager.RemoveModifierFromTagIndex(self, stackKey, statPath, modifier)
			BaseModifierManager.RemoveFromExpirationQueue(self, modifier.id)
			table.remove(stack.modifiers, index)
			removedCount = removedCount + 1
		end
	end

	if removedCount > 0 then
		stack.isDirty = true
		BaseModifierManager.TriggerChange(self, statPath, stackKey)
	end

	return removedCount
end

function BaseModifierManager.RemoveAllBySource(self: BaseModifierManagerImpl, stackKey: StackKey, source: string): number
	if not self.stacks[stackKey] then
		return 0
	end

	local totalRemoved = 0

	for statPath, _ in self.stacks[stackKey] do
		totalRemoved = totalRemoved + BaseModifierManager.RemoveBySource(self, stackKey, statPath, source)
	end

	return totalRemoved
end

function BaseModifierManager.RemoveAllByTag(self: BaseModifierManagerImpl, stackKey: StackKey, tag: string): number
	if not self.tagIndex[stackKey] then
		return 0
	end

	local totalRemoved = 0

	for statPath, tags in self.tagIndex[stackKey] do
		if tags[tag] then
			totalRemoved = totalRemoved + BaseModifierManager.RemoveByTag(self, stackKey, statPath, tag)
		end
	end

	return totalRemoved
end

-- only recompute if dirty otherwise return the cached value the math itself is in calculator
function BaseModifierManager.CalculateValue(_self: BaseModifierManagerImpl, stack: StatStack): number
	-- nothing changed since the last calc so hand back the cached number and skip all the math
	if not stack.isDirty and stack.cachedValue then
		return stack.cachedValue
	end

	local finalValue = Calculator.calculateValue({
		baseValue = stack.baseValue,
		modifiers = stack.modifiers,
		minClamp = stack.minClamp,
		maxClamp = stack.maxClamp,
		decimalPlaces = stack.decimalPlaces,
	})

	-- store the fresh result and mark clean so the next Get reuses it instead of recomputing
	stack.cachedValue = finalValue
	stack.isDirty = false

	return finalValue
end

function BaseModifierManager.Get(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string): number
	if not self.stacks[stackKey] then
		return 0
	end
	if not self.stacks[stackKey][statPath] then
		return 0
	end

	local stack = self.stacks[stackKey][statPath]
	return BaseModifierManager.CalculateValue(self, stack)
end

function BaseModifierManager.GetModifiers(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string): { Modifier }
	if not self.stacks[stackKey] then
		return {}
	end
	if not self.stacks[stackKey][statPath] then
		return {}
	end

	local stack = self.stacks[stackKey][statPath]
	return stack.modifiers
end

function BaseModifierManager.GetModifiersBySource(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string, source: string): { Modifier }
	if not self.stacks[stackKey] then
		return {}
	end
	if not self.stacks[stackKey][statPath] then
		return {}
	end

	local stack = self.stacks[stackKey][statPath]
	local sourceModifiers: { Modifier } = {}

	for _, modifier in stack.modifiers do
		if modifier.source == source then
			table.insert(sourceModifiers, modifier)
		end
	end

	return sourceModifiers
end

function BaseModifierManager.GetModifiersByTag(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string, tag: string): { Modifier }
	if not self.stacks[stackKey] then
		return {}
	end
	if not self.stacks[stackKey][statPath] then
		return {}
	end

	local stack = self.stacks[stackKey][statPath]
	local tagModifiers: { Modifier } = {}

	for _, modifier in stack.modifiers do
		for _, modifierTag in modifier.tags do
			if modifierTag == tag then
				table.insert(tagModifiers, modifier)
				break
			end
		end
	end

	return tagModifiers
end

-- recomputes the stat then fires its signal so listeners get the fresh value instead of a stale one
function BaseModifierManager.TriggerChange(self: BaseModifierManagerImpl, statPath: string, stackKey: StackKey)
	if not self.signals[stackKey] then
		return
	end
	if not self.signals[stackKey][statPath] then
		return
	end

	local newValue = BaseModifierManager.Get(self, stackKey, statPath)
	self.signals[stackKey][statPath]:Fire(newValue)
end

-- only creates the signal for a stat the first time something listens so were not making signals nobody ever uses
function BaseModifierManager.OnChanged(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string, callback: (newValue: number) -> ()): any
	if not self.signals[stackKey] then
		self.signals[stackKey] = {}
	end

	if not self.signals[stackKey][statPath] then
		local signal = Signal.new()
		self.signals[stackKey][statPath] = signal
	end

	return self.signals[stackKey][statPath]:Connect(callback)
end

-- rejects nan (x ~= x) and infinity before setting so one bad number cant poison every calculation off this stat
function BaseModifierManager.SetBase(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string, baseValue: number)
	BaseModifierManager.ValidateStatPath(self, statPath)

	-- baseValue ~= baseValue is only ever true for nan and the math.huge check catches infinity both would poison every calc off this stat
	if type(baseValue) ~= "number" or baseValue ~= baseValue or math.abs(baseValue) == math.huge then
		error("Base value must be a valid finite number")
	end

	if not self.stacks[stackKey] then
		self.stacks[stackKey] = {}
	end
	if not self.signals[stackKey] then
		self.signals[stackKey] = {}
	end
	if not self.tagIndex[stackKey] then
		self.tagIndex[stackKey] = {}
	end

	if not self.stacks[stackKey][statPath] then
		self.stacks[stackKey][statPath] = {
			baseValue = 0,
			modifiers = {},
			isDirty = true,
			cachedValue = nil,
		}
	end

	local stack = self.stacks[stackKey][statPath]
	stack.baseValue = baseValue
	stack.isDirty = true
	BaseModifierManager.TriggerChange(self, statPath, stackKey)
end

function BaseModifierManager.SetClamps(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string, minValue: number?, maxValue: number?)
	BaseModifierManager.ValidateStatPath(self, statPath)

	if minValue and (type(minValue) ~= "number" or minValue ~= minValue or math.abs(minValue) == math.huge) then
		error("Min value must be a valid finite number or nil")
	end

	if maxValue and (type(maxValue) ~= "number" or maxValue ~= maxValue or math.abs(maxValue) == math.huge) then
		error("Max value must be a valid finite number or nil")
	end

	if not self.stacks[stackKey] then
		error("No stats exist for this key. Call SetBase first")
	end
	if not self.stacks[stackKey][statPath] then
		error(`Stat "{statPath}" does not exist. Call SetBase first`)
	end

	local stack = self.stacks[stackKey][statPath]
	stack.minClamp = minValue
	stack.maxClamp = maxValue
	stack.isDirty = true
	BaseModifierManager.TriggerChange(self, statPath, stackKey)
end

function BaseModifierManager.SetDecimalPlaces(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string, decimalPlaces: number?)
	BaseModifierManager.ValidateStatPath(self, statPath)

	if decimalPlaces and (type(decimalPlaces) ~= "number" or decimalPlaces < 0 or decimalPlaces ~= math.floor(decimalPlaces)) then
		error("Decimal places must be a non-negative integer or nil")
	end

	if not self.stacks[stackKey] then
		error("No stats exist for this key. Call SetBase first")
	end
	if not self.stacks[stackKey][statPath] then
		error(`Stat "{statPath}" does not exist. Call SetBase first`)
	end

	local stack = self.stacks[stackKey][statPath]
	stack.decimalPlaces = decimalPlaces
	stack.isDirty = true
	BaseModifierManager.TriggerChange(self, statPath, stackKey)
end

function BaseModifierManager.GetDebugInfo(self: BaseModifierManagerImpl, stackKey: StackKey): { [string]: any }
	local debugInfo: { [string]: any } = {
		stackKey = stackKey,
		stackCount = 0,
		totalModifiers = 0,
		stacks = {},
	}

	if self.stacks[stackKey] then
		for statPath, stack in self.stacks[stackKey] do
			debugInfo.stackCount = debugInfo.stackCount + 1
			debugInfo.totalModifiers = debugInfo.totalModifiers + #stack.modifiers

			debugInfo.stacks[statPath] = {
				baseValue = stack.baseValue,
				currentValue = BaseModifierManager.Get(self, stackKey, statPath),
				modifierCount = #stack.modifiers,
				modifiers = {},
				minClamp = stack.minClamp,
				maxClamp = stack.maxClamp,
			}

			for _, modifier in stack.modifiers do
				table.insert(debugInfo.stacks[statPath].modifiers, {
					id = modifier.id,
					source = modifier.source,
					value = modifier.value,
					modifierType = modifier.modifierType,
					priority = modifier.priority,
					tags = modifier.tags,
					expireTime = modifier.expireTime,
				})
			end
		end
	end

	return debugInfo
end

function BaseModifierManager.GetStack(self: BaseModifierManagerImpl, stackKey: StackKey, statPath: string): StatStack?
	if not self.stacks[stackKey] then
		return nil
	end
	return self.stacks[stackKey][statPath]
end

return BaseModifierManager

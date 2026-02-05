--!strict
local Signal = require(script.Parent.Packages.Signal)
local Trove = require(script.Parent.Packages.Trove)
local Types = require(script.Parent.Types)
local Calculator = require(script.Parent.Calculator)

export type Modifier = Types.Modifier
export type StatStack = Types.StatStack
export type StatSyncData = Types.StatSyncData
export type Connection = Types.Connection

type ClientStatReaderImpl = Types.ClientStatReaderData

local ClientStatReader = {}
ClientStatReader.__index = ClientStatReader

function ClientStatReader.new(): ClientStatReaderImpl
	local self: ClientStatReaderImpl = setmetatable({
		stacks = {},
		signals = {},
		trove = Trove.new(),
	}, ClientStatReader) :: any

	return self
end

function ClientStatReader.Destroy(self: ClientStatReaderImpl)
	self.trove:Destroy()
	self.stacks = {}
	self.signals = {}
end

function ClientStatReader.ValidateStatPath(_self: ClientStatReaderImpl, statPath: string): (string, string)
	if type(statPath) ~= "string" or statPath == "" then
		error("statPath must be a non-empty string")
	end

	local parts = string.split(statPath, ".")
	if #parts ~= 2 then
		error(`Invalid statPath format: "{statPath}". Expected "Category.StatName"`)
	end

	return parts[1], parts[2]
end

function ClientStatReader.ProcessSync(self: ClientStatReaderImpl, statPath: string, syncData: StatSyncData)
	ClientStatReader.ValidateStatPath(self, statPath)

	local stack: StatStack = {
		baseValue = syncData.baseValue,
		modifiers = syncData.modifiers,
		isDirty = true,
		cachedValue = nil,
		minClamp = syncData.minClamp,
		maxClamp = syncData.maxClamp,
		decimalPlaces = syncData.decimalPlaces,
	}

	self.stacks[statPath] = stack

	if self.signals[statPath] then
		local newValue = ClientStatReader.Get(self, statPath)
		self.signals[statPath]:Fire(newValue)
	end
end

function ClientStatReader.ProcessBulkSync(self: ClientStatReaderImpl, allSyncData: { [string]: StatSyncData })
	for statPath, syncData in allSyncData do
		ClientStatReader.ProcessSync(self, statPath, syncData)
	end
end

function ClientStatReader.CalculateValue(_self: ClientStatReaderImpl, stack: StatStack): number
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

	stack.cachedValue = finalValue
	stack.isDirty = false

	return finalValue
end

function ClientStatReader.Get(self: ClientStatReaderImpl, statPath: string): number
	local stack = self.stacks[statPath]
	if not stack then
		return 0
	end

	return ClientStatReader.CalculateValue(self, stack)
end

function ClientStatReader.GetBase(self: ClientStatReaderImpl, statPath: string): number
	local stack = self.stacks[statPath]
	if not stack then
		return 0
	end

	return stack.baseValue
end

function ClientStatReader.GetModifiers(self: ClientStatReaderImpl, statPath: string): { Modifier }
	local stack = self.stacks[statPath]
	if not stack then
		return {}
	end

	return stack.modifiers
end

function ClientStatReader.GetModifiersBySource(self: ClientStatReaderImpl, statPath: string, source: string): { Modifier }
	local stack = self.stacks[statPath]
	if not stack then
		return {}
	end

	local sourceModifiers: { Modifier } = {}
	for _, modifier in stack.modifiers do
		if modifier.source == source then
			table.insert(sourceModifiers, modifier)
		end
	end

	return sourceModifiers
end

function ClientStatReader.GetModifiersByTag(self: ClientStatReaderImpl, statPath: string, tag: string): { Modifier }
	local stack = self.stacks[statPath]
	if not stack then
		return {}
	end

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

function ClientStatReader.HasStat(self: ClientStatReaderImpl, statPath: string): boolean
	return self.stacks[statPath] ~= nil
end

function ClientStatReader.GetAllStats(self: ClientStatReaderImpl): { string }
	local stats: { string } = {}
	for statPath, _ in self.stacks do
		table.insert(stats, statPath)
	end
	return stats
end

function ClientStatReader.OnChanged(self: ClientStatReaderImpl, statPath: string, callback: (newValue: number) -> ()): Connection
	if not self.signals[statPath] then
		local signal = Signal.new()
		self.signals[statPath] = signal
		self.trove:Add(signal)
	end

	return self.signals[statPath]:Connect(callback)
end

function ClientStatReader.GetDebugInfo(self: ClientStatReaderImpl): { [string]: any }
	local debugInfo: { [string]: any } = {
		statCount = 0,
		totalModifiers = 0,
		stats = {},
	}

	for statPath, stack in self.stacks do
		debugInfo.statCount = debugInfo.statCount + 1
		debugInfo.totalModifiers = debugInfo.totalModifiers + #stack.modifiers

		debugInfo.stats[statPath] = {
			baseValue = stack.baseValue,
			currentValue = ClientStatReader.Get(self, statPath),
			modifierCount = #stack.modifiers,
			modifiers = {},
			minClamp = stack.minClamp,
			maxClamp = stack.maxClamp,
		}

		for _, modifier in stack.modifiers do
			table.insert(debugInfo.stats[statPath].modifiers, {
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

	return debugInfo
end

return ClientStatReader

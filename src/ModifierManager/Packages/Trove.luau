--!nocheck
-- Trove - Resource cleanup manager
-- Based on Trove by Stephen Leitnick
-- Simplified for ModifierManager standalone use

local FN_MARKER = newproxy()
local THREAD_MARKER = newproxy()

local function GetObjectCleanupFunction(object, cleanupMethod)
	local t = typeof(object)
	if t == "function" then
		return FN_MARKER
	elseif t == "thread" then
		return THREAD_MARKER
	end
	if cleanupMethod then
		return cleanupMethod
	end
	if t == "Instance" then
		return "Destroy"
	elseif t == "RBXScriptConnection" then
		return "Disconnect"
	elseif t == "table" then
		if typeof(object.Destroy) == "function" then
			return "Destroy"
		elseif typeof(object.Disconnect) == "function" then
			return "Disconnect"
		end
	end
	error("Failed to get cleanup function for object " .. t .. ": " .. tostring(object), 3)
end

export type Trove = {
	Add: (self: Trove, object: any, cleanupMethod: string?) -> any,
	Remove: (self: Trove, object: any) -> boolean,
	Extend: (self: Trove) -> Trove,
	Clone: (self: Trove, instance: Instance) -> Instance,
	Construct: (self: Trove, class: any, ...any) -> any,
	Connect: (self: Trove, signal: RBXScriptSignal, fn: (...any) -> ()) -> RBXScriptConnection,
	Clean: (self: Trove) -> (),
	Destroy: (self: Trove) -> (),
}

local Trove = {}
Trove.__index = Trove

function Trove.new(): Trove
	local self = setmetatable({}, Trove)
	self._objects = {}
	self._cleaning = false
	return self :: any
end

function Trove:Extend(): Trove
	if self._cleaning then
		error("Cannot call trove:Extend() while cleaning", 2)
	end
	return self:Construct(Trove)
end

function Trove:Clone(instance: Instance): Instance
	if self._cleaning then
		error("Cannot call trove:Clone() while cleaning", 2)
	end
	return self:Add(instance:Clone())
end

function Trove:Construct(class, ...)
	if self._cleaning then
		error("Cannot call trove:Construct() while cleaning", 2)
	end
	local object = nil
	local t = type(class)
	if t == "table" then
		object = class.new(...)
	elseif t == "function" then
		object = class(...)
	end
	return self:Add(object)
end

function Trove:Connect(signal, fn)
	if self._cleaning then
		error("Cannot call trove:Connect() while cleaning", 2)
	end
	return self:Add(signal:Connect(fn))
end

function Trove:Add(object: any, cleanupMethod: string?): any
	if self._cleaning then
		error("Cannot call trove:Add() while cleaning", 2)
	end
	local cleanup = GetObjectCleanupFunction(object, cleanupMethod)
	table.insert(self._objects, { object, cleanup })
	return object
end

function Trove:Remove(object: any): boolean
	if self._cleaning then
		error("Cannot call trove:Remove() while cleaning", 2)
	end
	return self:_findAndRemoveFromObjects(object, true)
end

function Trove:Clean()
	if self._cleaning then
		return
	end
	self._cleaning = true
	for _, obj in self._objects do
		self:_cleanupObject(obj[1], obj[2])
	end
	table.clear(self._objects)
	self._cleaning = false
end

function Trove:_findAndRemoveFromObjects(object: any, cleanup: boolean): boolean
	local objects = self._objects
	for i, obj in ipairs(objects) do
		if obj[1] == object then
			local n = #objects
			objects[i] = objects[n]
			objects[n] = nil
			if cleanup then
				self:_cleanupObject(obj[1], obj[2])
			end
			return true
		end
	end
	return false
end

function Trove:_cleanupObject(object, cleanupMethod)
	if cleanupMethod == FN_MARKER then
		object()
	elseif cleanupMethod == THREAD_MARKER then
		coroutine.close(object)
	else
		object[cleanupMethod](object)
	end
end

function Trove:Destroy()
	self:Clean()
end

return Trove

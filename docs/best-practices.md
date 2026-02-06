# Best Practices

This page shows recommended patterns for structuring a project with ModifierManager. The examples use a movement system, but the same approach applies to any stat-driven gameplay.

---

## Data-Driven Stat Definitions

Instead of hardcoding stat values across scripts, define them once in a shared config.

### GameDefaults

Store your base values in one place:

```lua
-- ReplicatedStorage/Config/GameDefaults.luau
local GameDefaults = {
    Movement = {
        WalkSpeed = 12,
        SprintSpeed = 18,
        JumpPower = 50,
        JumpCooldown = 1,
    },
}

return GameDefaults
```

### ModifierPaths

Use path constants to avoid string typos:

```lua
-- ReplicatedStorage/Config/ModifierPaths.luau
local ModifierPaths = {}

ModifierPaths.Movement = {
    WalkSpeed = "Movement.WalkSpeed",
    SprintSpeed = "Movement.SprintSpeed",
    JumpPower = "Movement.JumpPower",
    JumpCooldown = "Movement.JumpCooldown",
}

return ModifierPaths
```

### StatDefinitions

Combine defaults, clamps, and decimal precision into typed definitions that the server can loop over:

```lua
-- ReplicatedStorage/Config/StatDefinitions.luau
local GameDefaults = require(script.Parent.GameDefaults)
local ModifierPaths = require(script.Parent.ModifierPaths)

export type StatDefinition = {
    base: number,
    clamps: { number }?,
    decimals: number?,
}

local StatDefinitions: { [string]: StatDefinition } = {
    [ModifierPaths.Movement.WalkSpeed] = {
        base = GameDefaults.Movement.WalkSpeed,
        clamps = { 0, 100 },
        decimals = 1,
    },
    [ModifierPaths.Movement.SprintSpeed] = {
        base = GameDefaults.Movement.SprintSpeed,
        clamps = { 0, 100 },
        decimals = 1,
    },
    [ModifierPaths.Movement.JumpPower] = {
        base = GameDefaults.Movement.JumpPower,
        clamps = { 0, 200 },
        decimals = 1,
    },
    [ModifierPaths.Movement.JumpCooldown] = {
        base = GameDefaults.Movement.JumpCooldown,
        clamps = { 0, 10 },
        decimals = 2,
    },
}

table.freeze(StatDefinitions)
return StatDefinitions
```

### Config Entry Point

Re-export everything from a single module:

```lua
-- ReplicatedStorage/Config/init.luau
local GameDefaults = require(script.GameDefaults)
local ModifierPaths = require(script.ModifierPaths)
local StatDefinitions = require(script.StatDefinitions)

return {
    GameDefaults = GameDefaults,
    ModifierPaths = ModifierPaths,
    StatDefinitions = StatDefinitions,
}
```

Adding a new stat means adding it to `GameDefaults`, `ModifierPaths`, and `StatDefinitions` — the server and client pick it up automatically.

---

## Server Setup

Loop over stat definitions to initialize stats. Use a RemoteEvent for live sync and a RemoteFunction for initial bulk sync:

```lua
-- ServerScriptService/PlayerStatSetup.server.luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModifierManager = require(ReplicatedStorage.ModifierManager)
local Config = require(ReplicatedStorage.Config)

local statSyncEvent = ReplicatedStorage.Remotes.Events.StatSync
local getStatSyncDataFunction = ReplicatedStorage.Remotes.Functions.GetStatSyncData

local PlayerStatSetup = {}

local playerManager = ModifierManager.PlayerManager.new()

function PlayerStatSetup.GetManager()
    return playerManager
end

playerManager.onSyncRequired = function(player: Player, statPath: string, syncData: any)
    if not player.Parent then
        return
    end
    statSyncEvent:FireClient(player, statPath, syncData)
end

getStatSyncDataFunction.OnServerInvoke = function(player: Player)
    return playerManager:GetAllSyncData(player)
end

local function onPlayerAdded(player: Player)
    for statPath, definition in Config.StatDefinitions do
        playerManager:SetBase(player, statPath, definition.base)

        if definition.clamps then
            playerManager:SetClamps(player, statPath, definition.clamps[1], definition.clamps[2])
        end

        if definition.decimals then
            playerManager:SetDecimalPlaces(player, statPath, definition.decimals)
        end
    end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in Players:GetPlayers() do
    task.spawn(onPlayerAdded, player)
end

return PlayerStatSetup
```

Other server scripts can require this module and call `PlayerStatSetup.GetManager()` to add modifiers.

---

## Client Setup

The client creates a reader, connects to live sync, and fetches initial data on load:

```lua
-- StarterPlayerScripts/StatClient.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModifierManager = require(ReplicatedStorage.ModifierManager)

local statSyncEvent = ReplicatedStorage.Remotes.Events.StatSync
local getStatSyncDataFunction = ReplicatedStorage.Remotes.Functions.GetStatSyncData

local StatClient = {}

local reader = ModifierManager.ClientStatReader.new()

function StatClient.GetReader()
    return reader
end

statSyncEvent.OnClientEvent:Connect(function(statPath: string, syncData: any)
    reader:ProcessSync(statPath, syncData)
end)

local initialData = getStatSyncDataFunction:InvokeServer()
if initialData then
    reader:ProcessBulkSync(initialData)
end

return StatClient
```

Other client scripts require `StatClient` and call `StatClient.GetReader()` to read stats and subscribe to changes.

---

## Driving Gameplay From Stats

This is where ModifierManager's value shows. The movement controller below reads stats from the reader and reacts to changes in real time. Sprint speed, walk speed, jump power, and jump cooldown are all driven by modifiers — any buff or debuff applied on the server automatically updates the client.

```lua
-- StarterPlayerScripts/MovementController.client.luau
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatClient = require(script.Parent.StatClient)
local Config = require(ReplicatedStorage.Config)

local ModifierPaths = Config.ModifierPaths
local reader = StatClient.GetReader()
local localPlayer = Players.LocalPlayer

local SPRINT_KEY = Enum.KeyCode.LeftShift

local isSprinting = false
local jumpCooldownActive = false

local function getHumanoid(): Humanoid?
    local character = localPlayer.Character
    if not character then
        return nil
    end
    return character:FindFirstChildOfClass("Humanoid")
end

local function applyWalkSpeed()
    local humanoid = getHumanoid()
    if not humanoid then
        return
    end

    if isSprinting then
        humanoid.WalkSpeed = reader:Get(ModifierPaths.Movement.SprintSpeed)
    else
        humanoid.WalkSpeed = reader:Get(ModifierPaths.Movement.WalkSpeed)
    end
end

local function applyJumpPower()
    local humanoid = getHumanoid()
    if not humanoid then
        return
    end

    humanoid.UseJumpPower = true
    humanoid.JumpPower = reader:Get(ModifierPaths.Movement.JumpPower)
end

local function onJumped()
    if jumpCooldownActive then
        return
    end

    local humanoid = getHumanoid()
    if not humanoid then
        return
    end

    jumpCooldownActive = true
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)

    local jumpCooldown = reader:Get(ModifierPaths.Movement.JumpCooldown)

    task.delay(jumpCooldown, function()
        jumpCooldownActive = false
        local currentHumanoid = getHumanoid()
        if not currentHumanoid then
            return
        end
        currentHumanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
    end)
end

local function onCharacterAdded(character: Model)
    isSprinting = false
    jumpCooldownActive = false

    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    applyWalkSpeed()
    applyJumpPower()

    humanoid.StateChanged:Connect(function(_oldState, newState)
        if newState == Enum.HumanoidStateType.Jumping then
            onJumped()
        end
    end)
end

-- React to stat changes from modifiers in real time
reader:OnChanged(ModifierPaths.Movement.WalkSpeed, function()
    applyWalkSpeed()
end)

reader:OnChanged(ModifierPaths.Movement.SprintSpeed, function()
    applyWalkSpeed()
end)

reader:OnChanged(ModifierPaths.Movement.JumpPower, function()
    applyJumpPower()
end)

-- Sprint input
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
    if gameProcessed then
        return
    end
    if input.KeyCode == SPRINT_KEY then
        isSprinting = true
        applyWalkSpeed()
    end
end)

UserInputService.InputEnded:Connect(function(input: InputObject, _gameProcessed: boolean)
    if input.KeyCode == SPRINT_KEY then
        isSprinting = false
        applyWalkSpeed()
    end
end)

localPlayer.CharacterAdded:Connect(onCharacterAdded)
if localPlayer.Character then
    task.spawn(onCharacterAdded, localPlayer.Character)
end
```

The key pattern: `OnChanged` listeners call functions that read from the reader and apply to the Humanoid. When any modifier changes a stat on the server, the client reacts automatically.

---

## Security

All modifiers live on the server. The client only has a `ClientStatReader` which is read-only — there is no API for clients to create or modify modifiers. An exploiter can read stat values but cannot give themselves buffs or modify the stat pipeline.

---

## Summary

| Pattern | Why |
|---------|-----|
| Shared `Config` module | Single source of truth for stat paths and defaults |
| `ModifierPaths` constants | No magic strings, autocomplete-friendly |
| `StatDefinitions` with types | Data-driven setup, easy to add new stats |
| RemoteFunction for initial sync | Client gets all stats immediately on load |
| RemoteEvent for live sync | Changes push to client as they happen |
| `OnChanged` driving gameplay | Reactive — no polling, no manual refresh |

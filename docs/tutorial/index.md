# Tutorial

This guide walks through setting up ModifierManager in a Roblox game.

---

## Getting ModifierManager

### From GitHub

Download the `ModifierManager` folder from the repository and place it in `ReplicatedStorage`.

### File Structure

```
ReplicatedStorage/
└── ModifierManager/
    ├── init.luau
    ├── Types.luau
    ├── Calculator.luau
    ├── BaseModifierManager.luau
    ├── EntityManager.luau
    ├── PlayerManager.luau
    ├── ClientStatReader.luau
    └── Packages/
        ├── Signal.luau
        └── Trove.luau
```

---

## Basic Usage

ModifierManager runs on the server. The example below shows a basic player stat setup.

### Server Script

```lua
-- ServerScriptService/PlayerStats.server.luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModifierManager = require(ReplicatedStorage.ModifierManager)

-- Create manager
local playerStats = ModifierManager.PlayerManager.new()

-- Setup sync (required for client to see stats)
local StatsRemote = Instance.new("RemoteEvent")
StatsRemote.Name = "StatsSync"
StatsRemote.Parent = ReplicatedStorage

playerStats.onSyncRequired = function(player, statPath, syncData)
    StatsRemote:FireClient(player, statPath, syncData)
end

-- Initialize player stats
local function setupPlayer(player: Player)
    -- Set base stats
    playerStats:SetBase(player, "Combat.Health", 100)
    playerStats:SetBase(player, "Combat.MaxHealth", 100)
    playerStats:SetBase(player, "Combat.Damage", 10)
    playerStats:SetBase(player, "Movement.Speed", 16)

    -- Set bounds
    playerStats:SetClamps(player, "Combat.Health", 0, nil) -- Min 0, no max
    playerStats:SetClamps(player, "Movement.Speed", 0, 50) -- 0 to 50

    -- Send initial stats to client after a short delay
    -- This gives the client time to set up its StatsRemote listener
    task.delay(1, function()
        if player.Parent then
            local allData = playerStats:GetAllSyncData(player)
            for statPath, syncData in allData do
                StatsRemote:FireClient(player, statPath, syncData)
            end
        end
    end)
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in Players:GetPlayers() do
    setupPlayer(player)
end
```

### Client Script

```lua
-- StarterPlayerScripts/StatsClient.client.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ModifierManager = require(ReplicatedStorage.ModifierManager)

local reader = ModifierManager.ClientStatReader.new()
local StatsRemote = ReplicatedStorage:WaitForChild("StatsSync")

-- Receive syncs from server
StatsRemote.OnClientEvent:Connect(function(statPath, syncData)
    reader:ProcessSync(statPath, syncData)
end)

-- React to changes
reader:OnChanged("Combat.Health", function(newHealth)
    print("Health:", newHealth)
end)

-- Read stats anytime
task.wait(2)
print("Current speed:", reader:Get("Movement.Speed"))
```

---

## Adding Modifiers

Modifiers change stat values. They can be temporary or permanent.

### Temporary Buff

```lua
-- Speed boost that lasts 10 seconds
playerStats:AddModifier({
    player = player,
    path = "Movement.Speed",
    value = 1.5,
    type = "Multiplicative", -- 50% faster
    source = "SpeedBoost",
    duration = 10,
})
```

### Permanent Equipment Bonus

```lua
-- Weapon damage bonus (no duration = permanent)
playerStats:AddModifier({
    player = player,
    path = "Combat.Damage",
    value = 25,
    type = "Additive",
    source = "EquippedSword",
    tags = { "equipment", "weapon" },
})
```

### Debuff with Override

```lua
-- Stun: force speed to 0
playerStats:AddModifier({
    player = player,
    path = "Movement.Speed",
    value = 0,
    type = "Override",
    source = "Stun",
    duration = 2,
    priority = 200, -- Higher priority overrides win
})
```

---

## Stacking Rules

Control how modifiers from the same source interact.

### Stack (Default)

Multiple modifiers accumulate:

```lua
-- Each hit adds more damage
playerStats:AddModifier({
    player = player,
    path = "Combat.Damage",
    value = 5,
    type = "Additive",
    source = "RageStack",
    stackingRule = "Stack",
})
-- Call 3 times = +15 damage total
```

### Replace

New modifier removes old ones from same source:

```lua
-- Only one weapon equipped at a time
playerStats:AddModifier({
    player = player,
    path = "Combat.Damage",
    value = newWeaponDamage,
    type = "Additive",
    source = "EquippedWeapon",
    stackingRule = "Replace",
})
```

### Highest

Only keeps the highest value:

```lua
-- Only strongest shield matters
playerStats:AddModifier({
    player = player,
    path = "Combat.Defense",
    value = shieldValue,
    type = "Additive",
    source = "Shield",
    stackingRule = "Highest",
})
```

### Refresh

Updates existing modifier's value and resets duration:

```lua
-- Reapplying refreshes the timer
playerStats:AddModifier({
    player = player,
    path = "Combat.Damage",
    value = 1.2,
    type = "Multiplicative",
    source = "Enrage",
    stackingRule = "Refresh",
    duration = 5,
})
```

---

## Removing Modifiers

### By ID

```lua
local modId = playerStats:AddModifier({ ... })

-- Later
playerStats:RemoveModifierById(player, "Combat.Damage", modId)
```

### By Source

```lua
-- Remove all modifiers from "EquippedWeapon" on one stat
playerStats:RemoveBySource(player, "Combat.Damage", "EquippedWeapon")

-- Remove from ALL stats
playerStats:RemoveAllBySource(player, "EquippedWeapon")
```

### By Tag

```lua
-- Remove all buffs
playerStats:RemoveAllByTag(player, "buff")

-- Remove all debuffs
playerStats:RemoveAllByTag(player, "debuff")
```

---

## EntityManager for NPCs

Use EntityManager for non-player entities with string keys:

```lua
local entityStats = ModifierManager.EntityManager.new()

-- Setup enemy
entityStats:SetBase("goblin_1", "Combat.Health", 50)
entityStats:SetBase("goblin_1", "Combat.Damage", 5)

-- Apply poison
entityStats:AddModifier({
    entity = "goblin_1",
    path = "Combat.Health",
    value = -10,
    type = "Additive",
    source = "Poison",
    duration = 5,
})

-- Cleanup when enemy dies
entityStats:CleanupEntity("goblin_1")
```

---

## Listening to Changes

React when stats change:

```lua
-- Server
playerStats:OnChanged(player, "Combat.Health", function(newHealth)
    if newHealth <= 0 then
        -- Player died
    end
end)

-- Client
reader:OnChanged("Combat.Health", function(newHealth)
    HealthBar.Size = UDim2.new(newHealth / maxHealth, 0, 1, 0)
end)
```

---

## Calculation Example

Given:

- Base: 100
- Additive modifiers: +20, +10
- Multiplicative modifiers: 1.2, 1.1

Calculation:

1. Sum additives: `100 + 20 + 10 = 130`
2. Multiply: `130 * 1.2 * 1.1 = 171.6`

If an Override modifier exists with the highest priority, it replaces the result entirely.

---

## Edge Cases

A few things to keep in mind:

- **Reading a stat that doesn't exist** returns `0` — no errors are thrown.
- **`SetClamps` and `SetDecimalPlaces` require the stat to exist first.** Call `SetBase` before using them, or you'll get an error.
- **Stat paths must be in `"Category.StatName"` format.** A path like `"Health"` or `"A.B.C"` will error.
- **`EntityManager` and `PlayerManager` can only be created on the server.** Attempting to call `.new()` on the client will error.

```lua
-- This is safe — returns 0
local health = entityStats:Get("nonexistent", "Combat.Health")

-- This will error — stat doesn't exist yet
entityStats:SetClamps("enemy_1", "Combat.Health", 0, 100)

-- Do this instead
entityStats:SetBase("enemy_1", "Combat.Health", 50)
entityStats:SetClamps("enemy_1", "Combat.Health", 0, 100)
```

---

## Next Steps

See the [API Reference](../api.md) for complete method documentation.

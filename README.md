# ModifierManager

A flexible, type-safe stat modifier system for Roblox games. Manage buffs, debuffs, equipment bonuses, and any numeric stat modifications with automatic expiration, stacking rules, and client synchronization.

## Features

- **Three Manager Types**: EntityManager (string keys), PlayerManager (Player keys with sync), ClientStatReader (client-side read-only)
- **Modifier Types**: Additive, Multiplicative, and Override
- **Stacking Rules**: Stack, Replace, Highest, Refresh
- **Automatic Expiration**: Time-based modifier removal with efficient scheduling
- **Change Notifications**: Subscribe to stat changes with signals
- **Tag System**: Organize and query modifiers by tags
- **Type-Safe**: Full Luau strict mode with exported types
- **Zero Dependencies**: Signal and Trove embedded internally

## Installation

### Drag & Drop
1. Download the `ModifierManager` folder
2. Place it in `ReplicatedStorage` (or your preferred location)
3. Require it: `local ModifierManager = require(path.to.ModifierManager)`

### Wally (Alternative)
```toml
[dependencies]
ModifierManager = "your-scope/modifier-manager@1.0.0"
```

## Quick Start

```lua
local ModifierManager = require(ReplicatedStorage.ModifierManager)

-- Server: Create a manager for entities (NPCs, objects, etc.)
local entityStats = ModifierManager.EntityManager.new()

-- Set base stat
entityStats:SetBase("enemy_1", "Combat.Health", 100)

-- Add a buff
entityStats:AddModifier({
    entity = "enemy_1",
    path = "Combat.Health",
    value = 50,
    type = "Additive",
    source = "HealthPotion",
    duration = 30, -- Expires in 30 seconds
})

-- Get current value (150)
local health = entityStats:Get("enemy_1", "Combat.Health")
```

## Core Concepts

### Stat Paths

Stats use a `"Category.StatName"` format:
```lua
"Combat.Health"
"Combat.Damage"
"Movement.Speed"
"Abilities.CooldownReduction"
```

### Modifier Types

| Type | Description | Example |
|------|-------------|---------|
| `Additive` | Added to base value | Base 100 + Additive 20 = 120 |
| `Multiplicative` | Multiplies the result | (Base + Additive) * 1.5 |
| `Override` | Replaces final value | Ignores all other modifiers |

**Calculation Order:**
1. Sum all Additive modifiers
2. Multiply by all Multiplicative modifiers
3. If Override exists, use highest priority Override instead
4. Apply clamps and decimal rounding

```lua
-- Base: 100
-- Additive: +20, +10 (total: +30)
-- Multiplicative: 1.2, 1.1 (total: 1.32)
-- Result: (100 + 30) * 1.32 = 171.6
```

### Stacking Rules

Control how modifiers from the same source interact:

| Rule | Behavior |
|------|----------|
| `Stack` (default) | All modifiers accumulate |
| `Replace` | New modifier removes all existing from same source |
| `Highest` | Only keeps the highest value modifier from source |
| `Refresh` | Updates existing modifier's value and resets duration |

```lua
-- Replace: Adding a new buff removes the old one
entityStats:AddModifier({
    entity = "player_1",
    path = "Combat.Damage",
    value = 10,
    type = "Additive",
    source = "WeaponEnchant",
    stackingRule = "Replace",
})

-- Refresh: Re-applying resets the timer
entityStats:AddModifier({
    entity = "player_1",
    path = "Combat.Damage",
    value = 15,
    type = "Additive",
    source = "Buff",
    stackingRule = "Refresh",
    duration = 10,
})
```

### Expiration

Modifiers can automatically expire after a duration:

```lua
entityStats:AddModifier({
    entity = "enemy_1",
    path = "Combat.Speed",
    value = 0.5,
    type = "Multiplicative",
    source = "SlowDebuff",
    duration = 5, -- Removed after 5 seconds
})
```

## API Reference

### EntityManager

Server-side manager for string-keyed entities (NPCs, objects, etc.).

```lua
local manager = ModifierManager.EntityManager.new()
```

#### Methods

| Method | Description |
|--------|-------------|
| `SetBase(entity, statPath, value)` | Set base stat value |
| `SetClamps(entity, statPath, min?, max?)` | Set min/max bounds |
| `SetDecimalPlaces(entity, statPath, places?)` | Set decimal rounding |
| `AddModifier(config): string` | Add modifier, returns ID |
| `AddModifiers(configs): {string}` | Batch add modifiers |
| `Get(entity, statPath): number` | Get calculated value |
| `GetBase(entity, statPath): number` | Get base value |
| `GetModifiers(entity, statPath): {Modifier}` | Get all modifiers |
| `GetModifiersBySource(entity, statPath, source)` | Filter by source |
| `GetModifiersByTag(entity, statPath, tag)` | Filter by tag |
| `RemoveModifierById(entity, statPath, id): boolean` | Remove specific modifier |
| `RemoveBySource(entity, statPath, source): number` | Remove by source |
| `RemoveByTag(entity, statPath, tag): number` | Remove by tag |
| `RemoveAllBySource(entity, source): number` | Remove from all stats |
| `RemoveAllByTag(entity, tag): number` | Remove from all stats |
| `OnChanged(entity, statPath, callback): Connection` | Subscribe to changes |
| `HasStack(entity, statPath): boolean` | Check if stat exists |
| `CleanupEntity(entity)` | Remove all data for entity |
| `GetAllEntities(): {string}` | List all entities |
| `GetEntityStats(entity): {string}` | List entity's stats |
| `GetDebugInfo(entity): table` | Debug information |
| `Destroy()` | Cleanup manager |

#### ModifierConfig

```lua
type ModifierConfig = {
    entity: string,           -- Required: entity identifier
    path: string,             -- Required: "Category.StatName"
    value: number,            -- Required: modifier value
    type: ModifierType,       -- Required: "Additive" | "Multiplicative" | "Override"
    source: string,           -- Required: identifier for removal/stacking
    priority: number?,        -- Optional: for Override ordering (default: 100)
    tags: {string}?,          -- Optional: for tag-based queries/removal
    duration: number?,        -- Optional: seconds until expiration
    stackingRule: StackingRule?, -- Optional: "Stack" | "Replace" | "Highest" | "Refresh"
    minValue: number?,        -- Optional: clamp modifier value
    maxValue: number?,        -- Optional: clamp modifier value
}
```

---

### PlayerManager

Server-side manager for Player-keyed stats with automatic client synchronization.

```lua
local manager = ModifierManager.PlayerManager.new()

-- Set sync callback (required for client sync)
manager.onSyncRequired = function(player, statPath, syncData)
    -- Send to client via RemoteEvent
    StatsRemote:FireClient(player, statPath, syncData)
end
```

#### Additional Methods

Same as EntityManager, but uses `Player` instead of `string`:

| Method | Description |
|--------|-------------|
| `SetBase(player, statPath, value)` | Set base stat value |
| `AddModifier(config): string` | Config requires `player: Player` |
| `Get(player, statPath): number` | Get calculated value |
| `CleanupPlayer(player)` | Remove all player data |
| `GetAllSyncData(player): {[string]: StatSyncData}` | Get all stats for initial sync |

#### PlayerModifierConfig

```lua
type PlayerModifierConfig = ModifierConfig & {
    player: Player,  -- Required: Player instance
}
```

---

### ClientStatReader

Client-side read-only stat reader for synced data.

```lua
-- Client
local reader = ModifierManager.ClientStatReader.new()

-- Receive sync from server
StatsRemote.OnClientEvent:Connect(function(statPath, syncData)
    reader:ProcessSync(statPath, syncData)
end)

-- Read stats
local health = reader:Get("Combat.Health")

-- Subscribe to changes
reader:OnChanged("Combat.Health", function(newValue)
    UpdateHealthBar(newValue)
end)
```

#### Methods

| Method | Description |
|--------|-------------|
| `ProcessSync(statPath, syncData)` | Process server sync data |
| `ProcessBulkSync(allSyncData)` | Process multiple stats at once |
| `Get(statPath): number` | Get calculated value |
| `GetBase(statPath): number` | Get base value |
| `GetModifiers(statPath): {Modifier}` | Get all modifiers |
| `GetModifiersBySource(statPath, source)` | Filter by source |
| `GetModifiersByTag(statPath, tag)` | Filter by tag |
| `HasStat(statPath): boolean` | Check if stat exists |
| `GetAllStats(): {string}` | List all stats |
| `OnChanged(statPath, callback): Connection` | Subscribe to changes |
| `GetDebugInfo(): table` | Debug information |
| `Destroy()` | Cleanup reader |

---

## Examples

### Basic Stat Setup

```lua
-- Server
local ModifierManager = require(ReplicatedStorage.ModifierManager)
local playerStats = ModifierManager.PlayerManager.new()

local function setupPlayer(player)
    playerStats:SetBase(player, "Combat.Health", 100)
    playerStats:SetBase(player, "Combat.Damage", 10)
    playerStats:SetBase(player, "Movement.Speed", 16)

    playerStats:SetClamps(player, "Combat.Health", 0, 1000)
    playerStats:SetClamps(player, "Movement.Speed", 0, 50)
end

Players.PlayerAdded:Connect(setupPlayer)
```

### Temporary Buff System

```lua
local function applySpeedBoost(player, duration)
    return playerStats:AddModifier({
        player = player,
        path = "Movement.Speed",
        value = 1.5,
        type = "Multiplicative",
        source = "SpeedBoost",
        tags = { "buff", "movement" },
        duration = duration,
        stackingRule = "Refresh", -- Reapplying refreshes duration
    })
end

local function removeAllDebuffs(player)
    playerStats:RemoveAllByTag(player, "debuff")
end
```

### Damage Calculation

```lua
local function calculateDamage(attacker, baseDamage)
    local damageMultiplier = playerStats:Get(attacker, "Combat.DamageMultiplier")
    local flatBonus = playerStats:Get(attacker, "Combat.FlatDamageBonus")

    return (baseDamage + flatBonus) * damageMultiplier
end
```

### Client-Server Sync Setup

```lua
-- Server
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StatsRemote = Instance.new("RemoteEvent")
StatsRemote.Name = "StatsSync"
StatsRemote.Parent = ReplicatedStorage

local playerStats = ModifierManager.PlayerManager.new()

playerStats.onSyncRequired = function(player, statPath, syncData)
    StatsRemote:FireClient(player, statPath, syncData)
end

-- Send all stats when player joins
local function onPlayerAdded(player)
    -- Setup stats...

    -- Wait for client to be ready, then send initial sync
    task.delay(1, function()
        local allData = playerStats:GetAllSyncData(player)
        for statPath, syncData in allData do
            StatsRemote:FireClient(player, statPath, syncData)
        end
    end)
end

-- Client
local reader = ModifierManager.ClientStatReader.new()

StatsRemote.OnClientEvent:Connect(function(statPath, syncData)
    reader:ProcessSync(statPath, syncData)
end)

-- Use stats for UI
reader:OnChanged("Combat.Health", function(newHealth)
    HealthBar:SetValue(newHealth)
end)
```

### Equipment System

```lua
local function equipWeapon(player, weaponData)
    -- Remove old weapon stats
    playerStats:RemoveAllBySource(player, "EquippedWeapon")

    -- Apply new weapon stats
    playerStats:AddModifier({
        player = player,
        path = "Combat.Damage",
        value = weaponData.damage,
        type = "Additive",
        source = "EquippedWeapon",
        tags = { "equipment", "weapon" },
    })

    if weaponData.critChance then
        playerStats:AddModifier({
            player = player,
            path = "Combat.CritChance",
            value = weaponData.critChance,
            type = "Additive",
            source = "EquippedWeapon",
            tags = { "equipment", "weapon" },
        })
    end
end
```

---

## Types

```lua
type ModifierType = "Additive" | "Multiplicative" | "Override"
type StackingRule = "Stack" | "Replace" | "Highest" | "Refresh"

type Modifier = {
    id: string,
    value: number,
    modifierType: ModifierType,
    source: string,
    priority: number,
    tags: { string },
    stackingRule: StackingRule?,
    expireTime: number?,
    minValue: number?,
    maxValue: number?,
}

type StatStack = {
    baseValue: number,
    modifiers: { Modifier },
    cachedValue: number?,
    isDirty: boolean,
    minClamp: number?,
    maxClamp: number?,
    decimalPlaces: number?,
}

type StatSyncData = {
    baseValue: number,
    modifiers: { Modifier },
    minClamp: number?,
    maxClamp: number?,
    decimalPlaces: number?,
}

type Connection = {
    Disconnect: (self: Connection) -> (),
    Connected: boolean,
}
```

---

## License

MIT License - Feel free to use in your projects.

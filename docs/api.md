# API Reference

---

## Module

```lua
local ModifierManager = require(ReplicatedStorage.ModifierManager)
```

### Exports

| Export | Description |
|--------|-------------|
| `ModifierManager.EntityManager` | Server-side manager for string-keyed entities |
| `ModifierManager.PlayerManager` | Server-side manager for Player-keyed stats with sync |
| `ModifierManager.ClientStatReader` | Client-side read-only stat reader |

---

## EntityManager

Server-side manager for string-keyed entities (NPCs, objects, etc.).

!!! warning
    EntityManager can only be created on the server.

### EntityManager.new

```lua
EntityManager.new() --> [EntityManager]
```

Creates a new EntityManager instance.

```lua
local entityStats = ModifierManager.EntityManager.new()
```

---

### EntityManager:SetBase

```lua
EntityManager:SetBase(entity, statPath, baseValue)
-- entity      [string] -- Unique entity identifier
-- statPath    [string] -- Stat path in "Category.StatName" format
-- baseValue   [number] -- Base value for the stat
```

Sets the base value for a stat. Creates the stat if it doesn't exist.

```lua
entityStats:SetBase("enemy_1", "Combat.Health", 100)
entityStats:SetBase("enemy_1", "Combat.Damage", 10)
```

---

### EntityManager:SetClamps

```lua
EntityManager:SetClamps(entity, statPath, minValue?, maxValue?)
-- entity      [string]  -- Entity identifier
-- statPath    [string]  -- Stat path
-- minValue    [number?] -- Minimum allowed value (nil for no minimum)
-- maxValue    [number?] -- Maximum allowed value (nil for no maximum)
```

Sets min/max bounds for the final calculated value. Stat must exist first.

```lua
entityStats:SetClamps("enemy_1", "Combat.Health", 0, 1000)
```

---

### EntityManager:SetDecimalPlaces

```lua
EntityManager:SetDecimalPlaces(entity, statPath, decimalPlaces?)
-- entity         [string]  -- Entity identifier
-- statPath       [string]  -- Stat path
-- decimalPlaces  [number?] -- Number of decimal places (nil for no rounding)
```

Sets decimal rounding for the final calculated value.

```lua
entityStats:SetDecimalPlaces("enemy_1", "Combat.CritChance", 2)
```

---

### EntityManager:AddModifier

```lua
EntityManager:AddModifier(config) --> [string]
-- config   [EntityModifierConfig] -- Modifier configuration
-- Returns the modifier's unique ID
```

Adds a modifier to a stat. Returns the modifier ID for later removal.

```lua
local modifierId = entityStats:AddModifier({
    entity = "enemy_1",
    path = "Combat.Health",
    value = 50,
    type = "Additive",
    source = "HealthPotion",
    duration = 30,
    tags = { "buff", "potion" },
})
```

#### EntityModifierConfig

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `entity` | `string` | Yes | Entity identifier |
| `path` | `string` | Yes | Stat path ("Category.StatName") |
| `value` | `number` | Yes | Modifier value |
| `type` | `ModifierType` | Yes | "Additive", "Multiplicative", or "Override" |
| `source` | `string` | Yes | Identifier for stacking/removal |
| `priority` | `number?` | No | Override priority (default: 100) |
| `tags` | `{string}?` | No | Tags for querying/removal |
| `duration` | `number?` | No | Seconds until auto-removal |
| `stackingRule` | `StackingRule?` | No | "Stack", "Replace", "Highest", "Refresh" |
| `minValue` | `number?` | No | Clamp modifier value minimum |
| `maxValue` | `number?` | No | Clamp modifier value maximum |

---

### EntityManager:AddModifiers

```lua
EntityManager:AddModifiers(configs) --> [{string}]
-- configs   [{EntityModifierConfig}] -- Array of modifier configs
-- Returns array of modifier IDs
```

Batch add multiple modifiers. More efficient than calling AddModifier multiple times.

```lua
local ids = entityStats:AddModifiers({
    { entity = "enemy_1", path = "Combat.Health", value = 20, type = "Additive", source = "Armor" },
    { entity = "enemy_1", path = "Combat.Damage", value = 1.2, type = "Multiplicative", source = "Rage" },
})
```

---

### EntityManager:Get

```lua
EntityManager:Get(entity, statPath) --> [number]
-- entity      [string] -- Entity identifier
-- statPath    [string] -- Stat path
-- Returns the calculated final value
```

Gets the calculated stat value with all modifiers applied.

```lua
local health = entityStats:Get("enemy_1", "Combat.Health")
```

---

### EntityManager:GetBase

```lua
EntityManager:GetBase(entity, statPath) --> [number]
-- Returns the base value (0 if stat doesn't exist)
```

Gets the base value without modifiers.

---

### EntityManager:GetModifiers

```lua
EntityManager:GetModifiers(entity, statPath) --> [{Modifier}]
-- Returns array of all modifiers on the stat
```

---

### EntityManager:GetModifiersBySource

```lua
EntityManager:GetModifiersBySource(entity, statPath, source) --> [{Modifier}]
-- source   [string] -- Source identifier to filter by
```

---

### EntityManager:GetModifiersByTag

```lua
EntityManager:GetModifiersByTag(entity, statPath, tag) --> [{Modifier}]
-- tag   [string] -- Tag to filter by
```

---

### EntityManager:RemoveModifierById

```lua
EntityManager:RemoveModifierById(entity, statPath, modifierId) --> [boolean]
-- modifierId   [string] -- ID returned from AddModifier
-- Returns true if modifier was found and removed
```

---

### EntityManager:RemoveBySource

```lua
EntityManager:RemoveBySource(entity, statPath, source) --> [number]
-- Returns count of modifiers removed
```

Removes all modifiers with the given source from a specific stat.

---

### EntityManager:RemoveByTag

```lua
EntityManager:RemoveByTag(entity, statPath, tag) --> [number]
-- Returns count of modifiers removed
```

---

### EntityManager:RemoveAllBySource

```lua
EntityManager:RemoveAllBySource(entity, source) --> [number]
-- Returns count of modifiers removed
```

Removes all modifiers with the given source from ALL stats on the entity.

```lua
-- Remove all weapon bonuses when unequipping
entityStats:RemoveAllBySource("player_1", "EquippedWeapon")
```

---

### EntityManager:RemoveAllByTag

```lua
EntityManager:RemoveAllByTag(entity, tag) --> [number]
-- Returns count of modifiers removed
```

---

### EntityManager:OnChanged

```lua
EntityManager:OnChanged(entity, statPath, callback) --> [Connection]
-- callback   [(newValue: number) -> ()] -- Called when stat value changes
-- Returns a Connection that can be disconnected
```

Subscribe to stat value changes.

```lua
local connection = entityStats:OnChanged("enemy_1", "Combat.Health", function(newHealth)
    print("Health changed to:", newHealth)
end)

-- Later: connection:Disconnect()
```

---

### EntityManager:HasStack

```lua
EntityManager:HasStack(entity, statPath) --> [boolean]
-- Returns true if the stat exists
```

---

### EntityManager:CleanupEntity

```lua
EntityManager:CleanupEntity(entity)
-- entity   [string] -- Entity to clean up
```

Removes all stats, modifiers, and signals for an entity. Call when entity is destroyed.

---

### EntityManager:GetAllEntities

```lua
EntityManager:GetAllEntities() --> [{string}]
-- Returns array of all entity identifiers
```

---

### EntityManager:GetEntityStats

```lua
EntityManager:GetEntityStats(entity) --> [{string}]
-- Returns array of all stat paths for the entity
```

---

### EntityManager:GetDebugInfo

```lua
EntityManager:GetDebugInfo(entity) --> [table]
-- Returns debug information about the entity's stats
```

---

### EntityManager:Destroy

```lua
EntityManager:Destroy()
```

Cleans up the manager and all resources. Call when done with the manager.

---

## PlayerManager

Server-side manager for Player-keyed stats with automatic client synchronization.

!!! warning
    PlayerManager can only be created on the server.

### PlayerManager.new

```lua
PlayerManager.new() --> [PlayerManager]
```

Creates a new PlayerManager instance. Automatically cleans up player data on `PlayerRemoving`.

```lua
local playerStats = ModifierManager.PlayerManager.new()
```

---

### PlayerManager.onSyncRequired

```lua
PlayerManager.onSyncRequired   [(player: Player, statPath: string, syncData: StatSyncData) -> ()]?
```

Callback function invoked when stat data needs to sync to a client. Set this to send data via RemoteEvent.

```lua
local StatsRemote = Instance.new("RemoteEvent")
StatsRemote.Parent = ReplicatedStorage

playerStats.onSyncRequired = function(player, statPath, syncData)
    StatsRemote:FireClient(player, statPath, syncData)
end
```

---

### PlayerManager Methods

PlayerManager has the same methods as EntityManager, but uses `Player` instead of `string`:

| Method | Description |
|--------|-------------|
| `SetBase(player, statPath, value)` | Set base stat value |
| `SetClamps(player, statPath, min?, max?)` | Set value bounds |
| `SetDecimalPlaces(player, statPath, places?)` | Set decimal rounding |
| `AddModifier(config)` | Add modifier (config requires `player: Player`) |
| `AddModifiers(configs)` | Batch add modifiers |
| `Get(player, statPath)` | Get calculated value |
| `GetBase(player, statPath)` | Get base value |
| `GetModifiers(player, statPath)` | Get all modifiers |
| `GetModifiersBySource(player, statPath, source)` | Filter by source |
| `GetModifiersByTag(player, statPath, tag)` | Filter by tag |
| `RemoveModifierById(player, statPath, id)` | Remove specific modifier |
| `RemoveBySource(player, statPath, source)` | Remove by source |
| `RemoveByTag(player, statPath, tag)` | Remove by tag |
| `RemoveAllBySource(player, source)` | Remove from all stats |
| `RemoveAllByTag(player, tag)` | Remove from all stats |
| `OnChanged(player, statPath, callback)` | Subscribe to changes |
| `HasStack(player, statPath)` | Check if stat exists |
| `GetDebugInfo(player)` | Debug information |
| `Destroy()` | Cleanup manager |

---

### PlayerManager:CleanupPlayer

```lua
PlayerManager:CleanupPlayer(player)
-- player   [Player] -- Player to clean up
```

Removes all stats for a player. Called automatically on `PlayerRemoving`.

---

### PlayerManager:GetAllStats

```lua
PlayerManager:GetAllStats(player) --> [{string}]
-- Returns array of all stat paths for the player
```

---

### PlayerManager:GetAllSyncData

```lua
PlayerManager:GetAllSyncData(player) --> [{[string]: StatSyncData}]
-- Returns all stat sync data for initial client sync
```

Use this when a player joins to send all current stats:

```lua
local allData = playerStats:GetAllSyncData(player)
for statPath, syncData in allData do
    StatsRemote:FireClient(player, statPath, syncData)
end
```

---

## ClientStatReader

Client-side read-only stat reader for synced player data.

### ClientStatReader.new

```lua
ClientStatReader.new() --> [ClientStatReader]
```

Creates a new ClientStatReader instance.

```lua
local reader = ModifierManager.ClientStatReader.new()
```

---

### ClientStatReader:ProcessSync

```lua
ClientStatReader:ProcessSync(statPath, syncData)
-- statPath   [string]       -- Stat path
-- syncData   [StatSyncData] -- Data received from server
```

Process sync data received from the server.

```lua
StatsRemote.OnClientEvent:Connect(function(statPath, syncData)
    reader:ProcessSync(statPath, syncData)
end)
```

---

### ClientStatReader:ProcessBulkSync

```lua
ClientStatReader:ProcessBulkSync(allSyncData)
-- allSyncData   [{[string]: StatSyncData}] -- Multiple stats at once
```

Process multiple stats in one call.

---

### ClientStatReader:Get

```lua
ClientStatReader:Get(statPath) --> [number]
-- Returns calculated value (0 if stat doesn't exist)
```

---

### ClientStatReader:GetBase

```lua
ClientStatReader:GetBase(statPath) --> [number]
```

---

### ClientStatReader:GetModifiers

```lua
ClientStatReader:GetModifiers(statPath) --> [{Modifier}]
```

---

### ClientStatReader:GetModifiersBySource

```lua
ClientStatReader:GetModifiersBySource(statPath, source) --> [{Modifier}]
```

---

### ClientStatReader:GetModifiersByTag

```lua
ClientStatReader:GetModifiersByTag(statPath, tag) --> [{Modifier}]
```

---

### ClientStatReader:HasStat

```lua
ClientStatReader:HasStat(statPath) --> [boolean]
```

---

### ClientStatReader:GetAllStats

```lua
ClientStatReader:GetAllStats() --> [{string}]
```

---

### ClientStatReader:OnChanged

```lua
ClientStatReader:OnChanged(statPath, callback) --> [Connection]
-- callback   [(newValue: number) -> ()] -- Called when stat updates
```

Subscribe to stat changes from server syncs.

```lua
reader:OnChanged("Combat.Health", function(newHealth)
    HealthBar:SetValue(newHealth)
end)
```

---

### ClientStatReader:GetDebugInfo

```lua
ClientStatReader:GetDebugInfo() --> [table]
```

---

### ClientStatReader:Destroy

```lua
ClientStatReader:Destroy()
```

---

## Types

### ModifierType

```lua
type ModifierType = "Additive" | "Multiplicative" | "Override"
```

| Type | Description |
|------|-------------|
| `Additive` | Added to base value |
| `Multiplicative` | Multiplies the sum of base + additives |
| `Override` | Replaces final value entirely |

**Calculation Order:**

1. Sum all Additive modifiers: `base + additive1 + additive2 + ...`
2. Multiply by all Multiplicative modifiers: `sum * mult1 * mult2 * ...`
3. If Override exists, use highest priority Override instead
4. Apply clamps and decimal rounding

---

### StackingRule

```lua
type StackingRule = "Stack" | "Replace" | "Highest" | "Refresh"
```

| Rule | Behavior |
|------|----------|
| `Stack` | All modifiers accumulate (default) |
| `Replace` | New modifier removes existing from same source |
| `Highest` | Only keeps highest value from same source |
| `Refresh` | Updates value and resets duration of existing |

---

### Modifier

```lua
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
```

---

### StatSyncData

```lua
type StatSyncData = {
    baseValue: number,
    modifiers: { Modifier },
    minClamp: number?,
    maxClamp: number?,
    decimalPlaces: number?,
}
```

---

### Connection

```lua
type Connection = {
    Disconnect: (self: Connection) -> (),
    Connected: boolean,
}
```

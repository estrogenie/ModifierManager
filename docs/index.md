# ModifierManager

A flexible, type-safe stat modifier system for Roblox games.

Manage buffs, debuffs, equipment bonuses, and any numeric stat modifications with automatic expiration, stacking rules, and client synchronization.

---

## Features

- **Three Manager Types** - EntityManager for NPCs/objects, PlayerManager with client sync, ClientStatReader for clients
- **Modifier Types** - Additive, Multiplicative, and Override
- **Stacking Rules** - Stack, Replace, Highest, Refresh
- **Automatic Expiration** - Time-based modifier removal with efficient scheduling
- **Change Notifications** - Subscribe to stat changes with signals
- **Tag System** - Organize and query modifiers by tags
- **Type-Safe** - Full Luau strict mode with exported types
- **Zero Dependencies** - Signal and Trove embedded internally

---

## Installation

### Drag & Drop

1. Download the `ModifierManager` folder from the repository
2. Place it in `ReplicatedStorage` (or your preferred location)
3. Require it in your scripts

```lua
local ModifierManager = require(ReplicatedStorage.ModifierManager)
```

### Wally

```toml
[dependencies]
ModifierManager = "your-scope/modifier-manager@1.0.0"
```

---

## Quick Example

```lua
local ModifierManager = require(ReplicatedStorage.ModifierManager)

-- Create a manager for entities
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
    duration = 30,
})

-- Get current value (150)
local health = entityStats:Get("enemy_1", "Combat.Health")
```

---

## Choosing a Manager

| Manager | Key Type | Environment | Use Case |
|---------|----------|-------------|----------|
| `EntityManager` | `string` | Server | NPCs, objects, world entities |
| `PlayerManager` | `Player` | Server | Player stats with automatic client sync |
| `ClientStatReader` | - | Client | Read-only access to synced player stats |

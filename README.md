# ModifierManager

A type-safe stat modifier system for Roblox games. Manage buffs, debuffs, equipment bonuses, and stat modifications with automatic expiration, stacking rules, and client sync.

**[Documentation](https://estrogenie.github.io/ModifierManager/)**

## Installation

Download the `ModifierManager` folder and place it in `ReplicatedStorage`.

## Quick Example

```lua
local ModifierManager = require(ReplicatedStorage.ModifierManager)
local stats = ModifierManager.EntityManager.new()

-- Set base stat
stats:SetBase("enemy_1", "Combat.Health", 100)

-- Add a temporary buff
stats:AddModifier({
    entity = "enemy_1",
    path = "Combat.Health",
    value = 50,
    type = "Additive",
    source = "HealthPotion",
    duration = 30,
})

-- Get calculated value (150)
local health = stats:Get("enemy_1", "Combat.Health")
```

## License

MIT

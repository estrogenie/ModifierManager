# Changelog

All notable changes to ModifierManager will be documented in this file.

---

## 1.0.1

### Fixed

- **`OnChanged` listeners silently dropped** - `SetBase` and `GetStack` reset the internal signal and tag-index tables when first initializing a stat key, wiping any `OnChanged` connection registered beforehand. Listeners hooked before the first `SetBase`/`AddModifier` now survive and fire correctly. Affects `PlayerManager`, `EntityManager`, and `BaseModifierManager`.

---

## 1.0.0

Initial release.

### Added

- **EntityManager** - Server-side stat management for string-keyed entities (NPCs, objects)
- **PlayerManager** - Server-side stat management for Player-keyed stats with automatic client synchronization
- **ClientStatReader** - Client-side read-only stat reader for synced data
- **Modifier types** - Additive, Multiplicative, and Override
- **Stacking rules** - Stack, Replace, Highest, Refresh
- **Automatic expiration** - Time-based modifier removal with efficient scheduling
- **Change signals** - Subscribe to stat value changes via `OnChanged`
- **Tag system** - Organize and query modifiers by tags
- **Batch operations** - `AddModifiers` for adding multiple modifiers efficiently
- **Removal methods** - Remove by ID, source, or tag (per-stat and cross-stat)
- **Stat configuration** - Clamps (`SetClamps`) and decimal rounding (`SetDecimalPlaces`)
- **Debug info** - `GetDebugInfo` for inspecting stat state
- **Wally package** - Published as `waterdreamer/modifier-manager`

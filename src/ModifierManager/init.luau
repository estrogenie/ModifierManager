--!strict
local Types = require(script.Types)

export type ModifierType = Types.ModifierType
export type StackingRule = Types.StackingRule
export type Modifier = Types.Modifier
export type StatStack = Types.StatStack
export type ModifierConfig = Types.ModifierConfig
export type StatSyncData = Types.StatSyncData
export type Connection = Types.Connection

return {
	EntityManager = require(script.EntityManager),
	PlayerManager = require(script.PlayerManager),
	ClientStatReader = require(script.ClientStatReader),
}

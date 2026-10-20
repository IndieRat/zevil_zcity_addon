# Zevil Z-City

Resident Evil-inspired survival-horror systems for Z-City / Homigrad.

Zevil is an addon, not a fork of Z-City. Its custom virus state lives in `ent.ZevilVirus`, separately from Z-City's organism table. The player mutation system preserves the player's existing model, bodygroups, and clothing rather than swapping to a zombie model.

## Implemented foundation

- Independent exposure meter and staged infection lifecycle for players and NPCs.
- Bite-based transmission, configurable incubation/progression, and server commands.
- Player infection has visible stage-based sickly tint/material/bone deformation, a mouth-blood cue, and infection HUD. The visual settings are replicated so client drawing can actually read the server toggles.
- Infected players emit occasional zombie groans from stage 2, take periodic infection damage from stage 3, suffer movement penalties at stages 4–5, and can bite nearby victims from stage 3 with `zevil_bite`. Their normal player controls and Z-City organism initialization are preserved.
- Spawnable Zevil infected NextBot with explicit NPC/Entities spawn-menu registration, randomized civilian player models, target acquisition, pursuit, bite attacks, wandering, corpse-feeding, sickly coloration, Z-City blood-particle mouth seep, and occasional lunges.
- Spawnable Zevil civilian survivor NextBot (**NPCs → Zevil - Survivors**) with randomized Group 01/03 civilian models, wandering, and panic-running away from Zevil infected; fully infected civilians convert into infected NPCs.
- Procedural infected fake-ragdoll puppets: AI/pathfinding remains on the NextBot while a separate physics ragdoll tracks its animation through soft shadow control, with an uneven slouch, head sway, asymmetrical limbs, and a lowered crawling posture for critically injured infected. Stable activity switching and `BodyMoveXY` prevent repeated walk/run sequence resets. When BZCN injury support is present, its downed ragdoll/recovery owns incapacitated states so the shadow puppet does not render as a duplicate. Models without the required ValveBiped bones or usable physics fall back to normal rendering.
- When Z-City's `hg_bloodimpact` particle network message is available, infected puppets emit a correctly parameterized directional mouth bleed using Z-City's own blood-particle simulation, plus staggered ambient zombie groans. With BZCN's `hg.BZCNNPCSupport.Attach` available, infected NextBots and Zevil civilians attach to the native Z-City/BZCN NPC injury bridge; the host uses the native organism and wound lifecycle, and the visible infected puppet mirrors `wounds`/`arterialwounds` NetVars for integrations such as ABL. The visible puppet deliberately does not alias the host's live `organism` table, preventing a hit from being processed twice.
- Single-use `weapon_zevil_virus_syringe` SWEP in **Weapons → Zevil - Biohazard**. Primary attack injects the wielder; secondary attack injects a living target at close range. Human NPCs convert into infected AI through the virus lifecycle.
- Fully infected human NPCs are converted into roaming infected that use randomized civilian player models, preserve approximate health and position, and start facing their current enemy/infector or travel direction. When Z-City/BZCN appearance APIs are available, Zevil civilians use `hg.Appearance.GetRandomAppearance` and `ForceApplyAppearance`, including varied models, mixed clothing sets, skin/bodygroups, names, and accessory metadata; the standalone fallback still randomizes citizen models/skins/bodygroups.
- Infected players retain their player model and control; from stage 3 onward, `zevil_bite` lets them attack nearby targets.
- Vendored, namespaced BZCN shared API from commit `45fd28071c9b1f48e7bff5d4403bc3fb0f1ec147` (`sh_zevil_bzcn_api.lua`), including NPC class registration, name generation, netvar/inventory adapters, weapon-model resolution, and managed-NPC compatibility methods.
- Namespaced copy of the BZCN NPC base (`npc_zevil_bzcn_base`) so the rookie-cop survivor works without overwriting the external `npc_bzcn_base` class when BZCN is also installed.
- Companion BZCN bridges for managed-NPC data flow, AI intent tracking, weapon-aware targeting, runtime SWEP equipping/firing and melee, medical-item handling, inventory/loot compatibility, presentation, HUD, accessories, TPIK/weapon poses, chat, and blood effects.
- API integration profiles for the custom infection faction and Leon-inspired rookie-cop survivor.
- Infection persistence across player death/respawn; curing clears only Zevil state.
- Infected NextBots use the registered BZCN `ZevilInfected` class application for its zombie-style material/bodygroup treatment and class metadata, while retaining the randomized civilian model. `hg.BZCNNPCSupport.Attach` is then the supported entry point that initializes the native Z-City organism and injury lifecycle when available.
- The vendored API only advertises a native organism-backed NPC when `hg.BZCNNPCSupport.Attach` is available; otherwise managed NPCs use the API's safe netvar/identity bridge without creating a fake Z-City organism.
- Z-City organism internals are not directly modified.

## Install

Copy this repository into `garrysmod/addons/zevil_zcity_addon`, restart the server, and check the server console for the `[Zevil]` startup line.

## Commands

- `zevil_infect <player name or userid>` — force infection for testing.
- `zevil_cure <player name or userid>` — cure a player.
- `zevil_spawn_infected` — spawn an infected NPC at the admin's aim position.
- `zevil_give_syringe` — give an admin the virus injection syringe for testing.
- `zevil_status` — report infected/exposed counts.
- `zevil_bite` — bite a nearby target while infected at stage 3 or higher.

Spawn **NPCs → Zevil - Resident Evil → Zevil Infected**, **NPCs → Zevil - Survivors → Zevil Civilian**, or use the infected scripted entity under **Entities → Zevil - Resident Evil**. Admins can also use `zevil_spawn_infected`. For injection, spawn **Weapons → Zevil - Biohazard → Zevil Virus Syringe**, or run `zevil_give_syringe` as an in-game admin; **LMB injects yourself and RMB injects a nearby person/NPC**. The syringe is consumed after a successful injection. Spawn `npc_zevil_rookiecop` when Better Z-City NPCs is installed.

## Main server convars

- `zevil_enabled` (default 1)
- `zevil_transmission` (default 1)
- `zevil_incubation` (default 90 seconds)
- `zevil_progression` (default 120 seconds per stage)
- `zevil_bite_infect_chance` (default 0.35)
- `zevil_player_visuals` (default 1)
- `zevil_mutation_strength` (default 1)
- `zevil_max_infected` (default 24)
- `zevil_fake_infected` (default 1; set to 0 to disable puppet rendering and restore normal NextBot models)
- `zevil_fake_infected_rate` (default 20 updates per second; adjustable from 5 to 35)
- `zevil_fake_infected_strength` (default 1; adjustable from 0 to 2)

The vendored API plus adapter-chain, AI-manager, combat-actor, equipment-AI, inventory, and runtime weapon bridges are based on the pinned BZCN commit listed above. This still does not vendor every BZCN gameplay subsystem, notably the full task/social/squad/vehicle suite. Zevil opts infected NextBots and civilian NextBots into `hg.BZCNNPCSupport.Attach` when the external BZCN injury module is mounted. Without that module, infection/AI and visual mouth bleed still work, but native Z-City NPC wounds are not guaranteed. Zevil never creates a fake organism table to work around a missing native lifecycle. These changes have not been validated in a live GMod/Z-City server. The horde behavior is currently emergent from multiple infected NextBots independently acquiring nearby living targets; there is not yet a dedicated pack director, sound-attraction system, or cinematic horde scheduler. Test on a staging server before public deployment. Model/material behavior and NextBot activity availability vary by mounted content.

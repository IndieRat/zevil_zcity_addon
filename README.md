# Zevil Z-City

Resident Evil-inspired survival-horror systems for Z-City / Homigrad.

Zevil is an addon, not a fork of Z-City. Its custom virus state lives in `ent.ZevilVirus`, separately from Z-City's organism table. The player mutation system preserves the player's existing model, bodygroups, and clothing rather than swapping to a zombie model.

## Implemented foundation

- Independent exposure meter and staged infection lifecycle for players and NPCs.
- Bite-based transmission, configurable incubation/progression, and server commands.
- Player visual mutation overlay with sickly tint, staged material/bone deformation, and infection HUD.
- Spawnable Zevil infected NextBot with target acquisition, pursuit, bite attacks, wandering, corpse-feeding, sickly coloration, mouth-blood visuals, and occasional lunges.
- Fully infected human NPCs are converted into roaming infected while preserving their model, skin, bodygroups, position, and approximate health.
- Infected players retain their player model and control; from stage 3 onward, `zevil_bite` lets them attack nearby targets.
- Rookie-cop survivor archetype using the BZCN base when installed.
- Infection persistence across player death/respawn; curing clears only Zevil state.
- Z-City organism internals are not directly modified.

## Install

Copy this repository into `garrysmod/addons/zevil_zcity_addon`, restart the server, and check the server console for the `[Zevil]` startup line.

## Commands

- `zevil_infect <player name or userid>` — force infection for testing.
- `zevil_cure <player name or userid>` — cure a player.
- `zevil_spawn_infected` — spawn an infected NPC at the admin's aim position.
- `zevil_status` — report infected/exposed counts.
- `zevil_bite` — bite a nearby target while infected at stage 3 or higher.

Spawn `npc_zevil_infected` from the spawn menu or use `zevil_spawn_infected`. Spawn `npc_zevil_rookiecop` when Better Z-City NPCs is installed.

## Main server convars

- `zevil_enabled` (default 1)
- `zevil_transmission` (default 1)
- `zevil_incubation` (default 90 seconds)
- `zevil_progression` (default 120 seconds per stage)
- `zevil_bite_infect_chance` (default 0.35)
- `zevil_player_visuals` (default 1)
- `zevil_mutation_strength` (default 1)
- `zevil_max_infected` (default 24)

This is an initial implementation and has not been validated in a live GMod/Z-City server. The horde behavior is currently emergent from multiple infected NextBots independently acquiring nearby living targets; there is not yet a dedicated pack director, sound-attraction system, or cinematic horde scheduler. Test on a staging server before public deployment. Model/material behavior and NextBot activity availability vary by mounted content.

# Zevil Z-City

Resident Evil-inspired survival-horror systems for Z-City / Homigrad.

This repository is an addon, not a fork of Z-City. It keeps its own virus state separate from Z-City's organism table and does not rewrite player classes or replace a player's model as part of the custom virus lifecycle.

## Initial milestone

- G-virus-style exposure and staged infection for players and NPCs.
- Visual mutation that preserves the infected player's current model: sickly tint, progressive bone/pose deformation, and optional eye glow without assigning a zombie model.
- Infected NPC archetypes with target sensing, melee bite/grab pressure, corpse feeding, and infection transmission.
- Survivor archetypes, including a rookie-cop / Leon-inspired reference class.
- Server convars, admin commands, and lifecycle cleanup.

The mod can integrate with Better ZCity NPCs when it is installed, but it does not require BZCN to be present merely to load. Z-City organism interaction is opt-in and guarded; custom virus state is stored on the entity separately.

## Install

Copy this repository into `garrysmod/addons/zevil_zcity_addon`, restart the server, and check the server console for the `[Zevil]` startup line.

## Server commands

- `zevil_infect <player name or userid>` — force-stage a player's infection for testing.
- `zevil_cure <player name or userid>` — cure and restore cached visual state.
- `zevil_spawn_infected` — spawn an infected NPC at the admin's aim position.
- `zevil_status` — report active infection counts.

## Main convars

- `zevil_enabled` (default 1)
- `zevil_transmission` (default 1)
- `zevil_incubation` (default 90 seconds)
- `zevil_progression` (default 120 seconds per stage)
- `zevil_bite_infect_chance` (default 0.35)
- `zevil_player_visuals` (default 1)
- `zevil_mutation_strength` (default 1)
- `zevil_max_infected` (default 24)

This is an initial playable foundation, not a claim of in-game testing. Test multiplayer and model/material compatibility on a staging server before deployment.

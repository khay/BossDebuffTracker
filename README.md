# BossDebuffTracker

A World of Warcraft (Retail) addon that displays debuff icons to the right of each boss unit frame, so you can track what debuffs are active on each boss at a glance during encounters.

## Features

- Shows up to 10 debuff icons per boss frame (configurable)
- Cooldown timer rings and stack counts on each icon
- Colour-coded borders by debuff type (Magic, Curse, Disease, Poison)
- Hover tooltips on each icon
- Optional filter to show only debuffs cast by you
- Optional spell-ID whitelist to show only specific debuffs
- Fully adjustable position (X/Y offset) per-session, saved between sessions
- Test mode to preview layout without being in an encounter
- Settings persist across sessions via SavedVariables

## Opening Settings

**In-game slash command**

```
/bdt
```

Opens (or closes) the floating settings panel directly on screen. You can drag it anywhere.

**Via the game menu**

`ESC` → **Options** → **AddOns** → **BossDebuffTracker** → click **Open Boss Debuff Tracker**

---

## Slash Commands

All commands use the `/bdt` prefix.

| Command | Description |
|---|---|
| `/bdt` | Open / close the settings panel |
| `/bdt enable` | Enable the addon |
| `/bdt disable` | Disable the addon |
| `/bdt test` | Toggle test mode (shows fake debuffs on all boss frames) |
| `/bdt mine` | Toggle "only my debuffs" filter |
| `/bdt timer` | Toggle cooldown timer numbers on icons |
| `/bdt size <16–48>` | Set icon size in pixels (default: 28) |
| `/bdt max <1–10>` | Set max debuffs shown per boss (default: 5) |
| `/bdt filter add <spellID>` | Add a spell ID to the whitelist |
| `/bdt filter remove <spellID>` | Remove a spell ID from the whitelist |
| `/bdt filter clear` | Clear the entire spell whitelist |

---

## Settings Panel

The settings panel is divided into four sections:

### General
| Setting | Description |
|---|---|
| Enable Boss Debuff Tracker | Master on/off switch. Disabling it greys out all other controls. |
| Enable / Disable Test Debuffs | Toggle button that shows fake debuffs on every boss frame so you can adjust positioning without being in a fight. |

### Debuff Filter
| Setting | Description |
|---|---|
| Show only MY debuffs | When checked, only debuffs you personally applied are shown. |
| Max debuffs shown per boss | Slider — how many icons to display per boss (1–10). |

### Icons
| Setting | Description |
|---|---|
| Show cooldown timer | Toggles the countdown numbers on the cooldown sweep. |
| Show stack count | Toggles the stack number in the bottom-right corner of each icon. |
| Icon size (px) | Slider — icon size in pixels (16–48, step 2). |

### Position (all boss frames)
Both offsets apply to all boss frames simultaneously and are saved between sessions.

| Setting | Description |
|---|---|
| Horizontal gap (X) | Pixels between the right edge of a boss frame and the first icon. Negative values move icons left, closer to (or overlapping) the boss frame. Range: −80 to +80. |
| Vertical offset (Y) | Shifts the icon row up (positive) or down (negative). Range: −60 to +60. |

---

## Spell Whitelist

When one or more spell IDs are added via `/bdt filter add`, only those spells will be shown. If the list is empty (default), all debuffs are shown (subject to the "only mine" filter).

```
/bdt filter add 408356       -- show only this spell
/bdt filter add 408357       -- add a second spell
/bdt filter remove 408356    -- remove one
/bdt filter clear             -- show all debuffs again
```
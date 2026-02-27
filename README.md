> [!WARNING]
> This library is in early development and is not intended for use in large-scale productions.

# KoreghProfile

**Optimized data management with reduced syntax, deep table manipulation (Deep Patch), and intelligent shortcuts.**

[![Roblox](https://img.shields.io/badge/Roblox-Compatible-00A2FF?style=for-the-badge\&logo=roblox)](https://www.roblox.com)
[![Luau](https://img.shields.io/badge/Luau-Type--safe-00A2FF?style=for-the-badge)](https://luau-lang.org/)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

---

## Installation

**Roblox Model:** Insert `DataSystem` and `DataProxy` into `ServerScriptService` (or wherever you prefer for server-side logic).

**Manual:** Make sure the `DataProxy` module is inside `DataSystem` or accessible via `require`.

---

## Quickstart

The basic usage allows you to manipulate simple values (Numbers, Booleans, Strings) with direct calls.

```lua
local DataSystem = require(path.to.DataSystem)

-- Initialize the Wrapper for the player
local PlayerData = DataSystem:Wrap(player)

-- [SIMPLE] Changing numeric values
PlayerData.Gold:Change(100, "Add")      -- Adds 100
PlayerData.Level:Change(1, "Add")       -- Increases 1 level
PlayerData.Mana:Change(50, "Set")       -- Sets to 50

-- [SIMPLE] Reading values
local currentGold = PlayerData.Gold:Get()
```

---

## Advanced Usage

The real power of **KoreghProfile** lies in handling complex tables and nested inventories without requiring repetitive manual loops.

### 1. Inventory Manipulation (Tables)

You can insert complex items and search for them using identifier keys.

```lua
-- Inserting an item with metadata
PlayerData.Inventory:Insert({
    Name = "Legendary_Sword",
    Amount = 1,
    Custom = { Skin = "Default", Durability = 100 }
})

-- Searching for a specific item in the table
local item = PlayerData.Inventory:Find("Name", "Legendary_Sword")
if item then
    print(item.Custom.Durability) --> 100
end
```

### 2. Deep Patching (The Real Trick)

Modify specific properties inside nested tables (like the `Custom` dictionary) without rebuilding the entire table or risking loss of other data.

```lua
-- Updates ONLY the Skin and Amount, keeping Durability intact
PlayerData.Inventory:Patch("Name", "Legendary_Sword", {
    Amount = 2,
    Custom = { 
        Skin = "Yellow", 
        Effect = "Fire" 
    }
})
```

### 3. Custom Mutation

For logic that requires extra validation, use `Mutate` directly through the Proxy.

```lua
PlayerData.Gold:Mutate(function(currentGold)
    if currentGold >= 500 then
        return currentGold - 500 -- Luxury tax
    end
    return currentGold
end)
```

---

## API Reference

### Proxy Methods

| Method                         | Description                                            |
| ------------------------------ | ------------------------------------------------------ |
| `Change(value, op)`            | Modifies numbers using `"Add"`, `"Sub"`, or `"Set"`.   |
| `Insert(data)`                 | Inserts a new value/table into a list.                 |
| `Find(key, value)`             | Returns the first item matching the key/value pair.    |
| `Patch(idKey, idVal, changes)` | Merges changes into a specific list item (Deep Merge). |
| `Get()`                        | Returns the current value of the specified path.       |

---

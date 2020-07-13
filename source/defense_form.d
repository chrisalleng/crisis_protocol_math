import simulation_state2;

import std.bitmanip;

align(1) struct DefenseForm
{
    // NOTE: DO NOT CHANGE SIZE/ORDER of these fields
    // The entire point in this structure is for consistent serialization
    // Deprecated fields can just be removed from the UI and then unused
    // New fields can be given sensible default values

    mixin(bitfields!(ubyte, "dice", 4, ubyte, "force_count", 3, ubyte,
            "focus_count", 3, ubyte, "calculate_count", 3, ubyte, "evade_count", 3, ubyte,
            "reinforce_count", 3, ubyte, "stress_count", 3, ubyte, "jam_count", 3,
            bool, "c3p0", 1, bool, "lone_wolf", 1, bool, "stealth_device", 1,
            bool, "biggs", 1, bool, "_unused1", 1, bool, "iden", 1, bool,
            "selfless", 1,// 32
            ubyte, "pilot", 6, // DefensePilot enum
            bool, "l337", 1, bool, "elusive",
            1,// 40
            ubyte, "lock_count", 3, bool, "scum_lando_crew", 1, ubyte,
            "ship", 6, // DefenseShip enum
            bool, "serissu", 1, bool, "rebel_millennium_falcon", 1,
            bool, "finn_gunner", 1, bool, "heroic", 1,// Used by the shots to die form, but convenient to use the same defense form, albeit a subset
            uint, "ship_hull", 5, // 0..31
            uint, "ship_shields", 5, // 0..31
            ));

    mixin(bitfields!(bool, "brilliant_evasion", 1, ubyte, "max_force_count",
            3, bool, "hate", 1, uint, "", 3,));

    static DefenseForm defaults()
    {
        DefenseForm defaults;
        defaults.dice = 0;
        return defaults;
    }
}

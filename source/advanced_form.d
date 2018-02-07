import simulation;
import dice;

import std.bitmanip;

align(1) struct AdvancedForm
{
    // NOTE: DO NOT CHANGE SIZE/ORDER of these fields
    // The entire point in this structure is for consistent serialization
    // Deprecated fields can just be removed from the UI and then unused
    // New fields can be given sensible default values

    // Boolean fields
    mixin(bitfields!(
        bool, "attack_heavy_laser_cannon",                  1,
        bool, "attack_fire_control_system",                 1,
        bool, "attack_one_damage_on_hit",                   1,
        bool, "amad_accuracy_corrector",                    1,

        bool, "amad_once_any_to_hit",                       1,
        bool, "amad_once_any_to_crit",                      1,
        bool, "attack_must_spend_focus",                    1,
        bool, "defense_must_spend_focus",                   1,

        ubyte, "attack_stress_count",                       4,
        ubyte, "defense_stress_count",                      4,
        // FULL, do not add any more or links will be invalidated
        ));

    // Integer fields
    mixin(bitfields!(
        ubyte, "attack_type",                               4,  // enum MultiAttackType
        ubyte, "attack_dice",                               4,
        ubyte, "attack_focus_token_count",                  4,
        ubyte, "attack_target_lock_count",                  4,

        ubyte, "amad_add_hit_count",                        4,
        ubyte, "amad_add_crit_count",                       4,
        ubyte, "amad_add_blank_count",                      4,
        ubyte, "amad_add_focus_count",                      4,

        ubyte, "amad_reroll_blank_count",                   4,
        ubyte, "amad_reroll_focus_count",                   4,
        ubyte, "amad_reroll_any_count",		                4,
        ubyte, "amad_focus_to_crit_count",                  4,

        ubyte, "amad_focus_to_hit_count",                   4,
        ubyte, "amad_blank_to_crit_count",                  4,
        ubyte, "amad_blank_to_hit_count",                   4,
        ubyte, "amad_blank_to_focus_count",                 4,
    ));

    mixin(bitfields!(
        ubyte, "amad_hit_to_crit_count", 	                4,
        ubyte, "amdd_evade_to_focus_count",                 4,
        ubyte, "defense_dice", 			                    4,
        ubyte, "defense_focus_token_count",                 4,

        ubyte, "defense_evade_token_count",                 4,
        ubyte, "dmdd_add_blank_count", 	                    4,
        ubyte, "dmdd_add_focus_count", 	                    4,
        ubyte, "dmdd_add_evade_count", 		                4,

        ubyte, "dmdd_reroll_blank_count", 	                4,
        ubyte, "dmdd_reroll_focus_count", 	                4,
        ubyte, "dmdd_reroll_any_count", 	                4,
        ubyte, "dmdd_blank_to_evade_count",                 4,

        ubyte, "dmdd_focus_to_evade_count",                 4,
        ubyte, "dmad_hit_to_focus_no_reroll_count", 	    4,
        ubyte, "amad_spend_focus_one_blank_to_hit_count",   4,
        ubyte, "dmdd_spend_focus_one_blank_to_evade_count", 4,
    ));

    mixin(bitfields!(
        ubyte, "amad_unstressed_focus_to_hit_count",        4,
        ubyte, "amad_stressed_focus_to_hit_count",          4,
        ubyte, "amad_unstressed_focus_to_crit_count",       4,
        ubyte, "amad_stressed_focus_to_crit_count",         4,

        ubyte, "amad_unstressed_reroll_focus_count",        4,
        ubyte, "amad_stressed_reroll_focus_count",          4,
        ubyte, "dmdd_unstressed_reroll_focus_count",        4,
        ubyte, "dmdd_stressed_reroll_focus_count",          4,

        bool,  "dmdd_spend_attacker_stress_add_evade",      1,
        bool,  "attack_sunny_bounder",                      1,
        bool,  "defense_sunny_bounder",                     1,
        bool,  "attack_lose_stress_on_hit",                 1,

        ubyte, "amad_unstressed_reroll_any_count",          4,
        ubyte, "amad_stressed_reroll_any_count",            4,
        ubyte, "dmdd_unstressed_reroll_any_count",          4,

        ubyte, "dmdd_stressed_reroll_any_count",            4,
        ubyte, "dmdd_unstressed_focus_to_evade_count",      4,
        ubyte, "dmdd_stressed_focus_to_evade_count",        4,
        ubyte, "dmdd_focused_focus_to_evade_count",         4,
        ));

    mixin(bitfields!(
        ubyte, "amad_focused_focus_to_hit_count",                   4,
        ubyte, "amdd_unstressed_reroll_evade_gain_stress_count",    4,
        ubyte, "amad_unstressed_reroll_any_gain_stress_count",      4,
        byte,  "defense_guess_evades",                              4,      // <0 is no guess/disabled

        bool,  "attack_palpatine_crit",                      1,
        bool,  "defense_palpatine_evade",                    1,
        bool,  "attack_crack_shot",                          1,
        
        ubyte, "",                                          13,
    ));

    // Can always add more on the end, so no need to reserve space explicitly

    static AdvancedForm defaults()
    {
        AdvancedForm defaults;

        // Anything not referenced defaults to 0/false
        defaults.attack_type = MultiAttackType.Single;
        defaults.attack_dice = 3;
        defaults.defense_dice = 3;

        defaults.defense_guess_evades = -1;

        return defaults;
    }
};

//pragma(msg, "sizeof(AdvancedForm) = " ~ to!string(AdvancedForm.sizeof));

SimulationSetup to_simulation_setup(ref const(AdvancedForm) form)
{
    SimulationSetup setup;

    setup.attack_dice                                       = form.attack_dice;
    setup.attack_tokens.focus                               = form.attack_focus_token_count;
    setup.attack_tokens.target_lock                         = form.attack_target_lock_count;
    setup.attack_tokens.stress                              = form.attack_stress_count;

    // Once per round abilities are treated like "tokens" for simulation purposes
    setup.attack_tokens.amad_any_to_hit                     = form.amad_once_any_to_hit;
    setup.attack_tokens.amad_any_to_crit                    = form.amad_once_any_to_crit;
    setup.attack_tokens.sunny_bounder                       = form.attack_sunny_bounder;
    setup.attack_tokens.palpatine                           = form.attack_palpatine_crit;
    setup.attack_tokens.crack_shot                          = form.attack_crack_shot;
    
    setup.attack_fire_control_system                        = form.attack_fire_control_system;
    setup.attack_heavy_laser_cannon                         = form.attack_heavy_laser_cannon;
    setup.attack_must_spend_focus                           = form.attack_must_spend_focus;
    setup.attack_one_damage_on_hit                          = form.attack_one_damage_on_hit;
    setup.attack_lose_stress_on_hit                         = form.attack_lose_stress_on_hit;

    setup.AMAD.add_hit_count                                = form.amad_add_hit_count;
    setup.AMAD.add_crit_count                               = form.amad_add_crit_count;
    setup.AMAD.add_blank_count                              = form.amad_add_blank_count;
    setup.AMAD.add_focus_count                              = form.amad_add_focus_count;
    setup.AMAD.reroll_blank_count.always                    = form.amad_reroll_blank_count;
    setup.AMAD.reroll_focus_count.always                    = form.amad_reroll_focus_count;
    setup.AMAD.reroll_any_count.always                      = form.amad_reroll_any_count;
    setup.AMAD.reroll_focus_count.unstressed                = form.amad_unstressed_reroll_focus_count;
    setup.AMAD.reroll_focus_count.stressed                  = form.amad_stressed_reroll_focus_count;
    setup.AMAD.reroll_any_count.unstressed                  = form.amad_unstressed_reroll_any_count;
    setup.AMAD.reroll_any_count.stressed                    = form.amad_stressed_reroll_any_count;
    setup.AMAD.reroll_any_gain_stress_count.unstressed      = form.amad_unstressed_reroll_any_gain_stress_count;

    setup.AMAD.focus_to_crit_count.always                   = form.amad_focus_to_crit_count;
    setup.AMAD.focus_to_crit_count.unstressed               = form.amad_unstressed_focus_to_crit_count;
    setup.AMAD.focus_to_crit_count.stressed                 = form.amad_stressed_focus_to_crit_count;
    setup.AMAD.focus_to_hit_count.always                    = form.amad_focus_to_hit_count;
    setup.AMAD.focus_to_hit_count.unstressed                = form.amad_unstressed_focus_to_hit_count;
    setup.AMAD.focus_to_hit_count.stressed                  = form.amad_stressed_focus_to_hit_count;
    setup.AMAD.focus_to_hit_count.focused                   = form.amad_focused_focus_to_hit_count;
    setup.AMAD.blank_to_crit_count                          = form.amad_blank_to_crit_count;
    setup.AMAD.blank_to_hit_count                           = form.amad_blank_to_hit_count;
    setup.AMAD.blank_to_focus_count                         = form.amad_blank_to_focus_count;
    setup.AMAD.hit_to_crit_count                            = form.amad_hit_to_crit_count;

    setup.AMAD.spend_focus_one_blank_to_hit                 = form.amad_spend_focus_one_blank_to_hit_count;

    setup.AMAD.accuracy_corrector                           = form.amad_accuracy_corrector;

    setup.AMDD.reroll_evade_gain_stress_count.unstressed    = form.amdd_unstressed_reroll_evade_gain_stress_count;
    setup.AMDD.evade_to_focus_count                         = form.amdd_evade_to_focus_count;


    setup.defense_dice                                      = form.defense_dice;
    setup.defense_tokens.focus                              = form.defense_focus_token_count;
    setup.defense_tokens.evade                              = form.defense_evade_token_count;
    setup.defense_tokens.stress                             = form.defense_stress_count;
    setup.defense_tokens.sunny_bounder                      = form.defense_sunny_bounder;
    setup.defense_tokens.defense_guess_evades               = (form.defense_guess_evades >= 0);
    setup.defense_tokens.palpatine                          = form.defense_palpatine_evade;
    
    setup.defense_guess_evades                              = form.defense_guess_evades;
    setup.defense_must_spend_focus                          = form.defense_must_spend_focus;

    setup.DMDD.add_blank_count                              = form.dmdd_add_blank_count;
    setup.DMDD.add_focus_count                              = form.dmdd_add_focus_count;
    setup.DMDD.add_evade_count                              = form.dmdd_add_evade_count;
    setup.DMDD.reroll_blank_count.always                    = form.dmdd_reroll_blank_count;
    setup.DMDD.reroll_focus_count.always                    = form.dmdd_reroll_focus_count;
    setup.DMDD.reroll_any_count.always                      = form.dmdd_reroll_any_count;
    setup.DMDD.reroll_focus_count.unstressed                = form.dmdd_unstressed_reroll_focus_count;
    setup.DMDD.reroll_focus_count.stressed                  = form.dmdd_stressed_reroll_focus_count;
    setup.DMDD.reroll_any_count.unstressed                  = form.dmdd_unstressed_reroll_any_count;
    setup.DMDD.reroll_any_count.stressed                    = form.dmdd_stressed_reroll_any_count;

    setup.DMDD.blank_to_evade_count                         = form.dmdd_blank_to_evade_count;
    setup.DMDD.focus_to_evade_count.always                  = form.dmdd_focus_to_evade_count;
    setup.DMDD.focus_to_evade_count.unstressed              = form.dmdd_unstressed_focus_to_evade_count;
    setup.DMDD.focus_to_evade_count.stressed                = form.dmdd_stressed_focus_to_evade_count;
    setup.DMDD.focus_to_evade_count.focused                 = form.dmdd_focused_focus_to_evade_count;

    setup.DMDD.spend_focus_one_blank_to_evade               = form.dmdd_spend_focus_one_blank_to_evade_count;
    setup.DMDD.spend_attacker_stress_add_evade              = form.dmdd_spend_attacker_stress_add_evade;

    setup.DMAD.hit_to_focus_no_reroll_count                 = form.dmad_hit_to_focus_no_reroll_count;

    return setup;
}


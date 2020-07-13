import attack_form;
import defense_form;
import simulation_state2;
import simulation_setup2;
import form;

import std.bitmanip;

public enum AttackPreset : ubyte
{
    // NOTE: Do not change the order or it will invalidate links!
    _2d = 0,
    _2dHowlrunner,
    _3d,
    _3dHowlrunner,
    _4d,
    _4dProtonTorpedoes,
    _4dProtonTorpedoesWedge, // Deprecated now that we can put the -1 defense die in defender modifications
    _2dJukeEvade,
    _3dJukeEvade,
    _4dJukeEvade,
    _2dAdvancedOptics,
    _3dAdvancedOptics,
    _4dHowlrunner,
    _3dIonWeapon,
    _4dIonWeapon,
    Count
};

public enum DefenderModificationPreset : ubyte
{
    // NOTE: Do not change the order or it will invalidate links!
    // NOTE: Not all of these are shown in the dropdown right now, but enumerated for completeness/future use
    _None,
    _GasCloud,
    _p1DefenseDice,
    _p1DefenseDice_GasCloud,
    _p2DefenseDice,
    _p2DefenseDice_GasCloud,
    _p3DefenseDice,
    _p3DefenseDice_GasCloud,
    _m1DefenseDice,
    _m1DefenseDice_GasCloud,
    _m2DefenseDice,
    _m2DefenseDice_GasCloud,
    _m3DefenseDice,
    _m3DefenseDice_GasCloud,
    Count
};

align(1) struct AttackPresetForm
{
    // TODO: Improve our utility functions to deal with simple fields properly
    mixin(bitfields!(ubyte, "preset", 8, // AttackPreset enum
            bool, "enabled", 1, bool, "focus", 1,
            bool, "lock", 1, bool, "bonus_attack_enabled", 1, ubyte,
            "bonus_attack_preset", 8, // AttackPreset enum
            ubyte, "defender_modification", 8, // DefenderModificationPreset enum

            uint, "", 4,));

    static AttackPresetForm defaults(int index = 0)
    {
        AttackPresetForm defaults;
        defaults.enabled = (index == 0);
        return defaults;
    }
}

public string attack_preset_url(ubyte attacker)
{
    switch (attacker)
    {
    case AttackPreset._2d:
        return "IQAAAAAAAAA";
    case AttackPreset._2dHowlrunner:
        return "IQAAAAAEAAA";
    case AttackPreset._3d:
        return "MQAAAAAAAAA";
    case AttackPreset._3dHowlrunner:
        return "MQAAAAAEAAA";
    case AttackPreset._4d:
        return "QQAAAAAAAAA";
    case AttackPreset._4dProtonTorpedoes:
        return "QQAAgAAAAAA";
    case AttackPreset._4dProtonTorpedoesWedge:
        return "QQAAgADgAQA";
    case AttackPreset._2dJukeEvade:
        return "IQACAAABAAA";
    case AttackPreset._3dJukeEvade:
        return "MQACAAABAAA";
    case AttackPreset._4dJukeEvade:
        return "QQACAAABAAA";
    case AttackPreset._2dAdvancedOptics:
        return "IQAAAAAAAEAA";
    case AttackPreset._3dAdvancedOptics:
        return "MQAAAAAAAEAA";
    case AttackPreset._4dHowlrunner:
        return "QQAAAAAEAAAA";
    case AttackPreset._3dIonWeapon:
        return "MQAAAIAAAAAA";
    case AttackPreset._4dIonWeapon:
        return "QQAAAIAAAAAA";
    default:
        return "IQAAAAAAAAA"; // Failsafe!
    }
}

// This is a bit messy, but similar to what we are doing in tokens...
// apply defender mods "on top of" the preset we already have applied.
private AttackForm apply_defender_modification(ref const(AttackForm) attack_form_in,
        ubyte defender_modification)
{
    AttackForm attack_form = attack_form_in;

    switch (defender_modification)
    {
    case DefenderModificationPreset._p1DefenseDice:
    case DefenderModificationPreset._p1DefenseDice_GasCloud:
        attack_form.defense_dice_diff = 1;
        break;
    case DefenderModificationPreset._p2DefenseDice:
    case DefenderModificationPreset._p2DefenseDice_GasCloud:
        attack_form.defense_dice_diff = 2;
        break;
    case DefenderModificationPreset._p3DefenseDice:
    case DefenderModificationPreset._p3DefenseDice_GasCloud:
        attack_form.defense_dice_diff = 3;
        break;
    case DefenderModificationPreset._m1DefenseDice:
    case DefenderModificationPreset._m1DefenseDice_GasCloud:
        attack_form.defense_dice_diff = 1;
        break;
    case DefenderModificationPreset._m2DefenseDice:
    case DefenderModificationPreset._m2DefenseDice_GasCloud:
        attack_form.defense_dice_diff = 2;
        break;
    case DefenderModificationPreset._m3DefenseDice:
    case DefenderModificationPreset._m3DefenseDice_GasCloud:
        attack_form.defense_dice_diff = 3;
        break;
    default:
        break;
    }
    switch (defender_modification)
    {
    case DefenderModificationPreset._GasCloud:
    case DefenderModificationPreset._p1DefenseDice_GasCloud:
    case DefenderModificationPreset._p2DefenseDice_GasCloud:
    case DefenderModificationPreset._p3DefenseDice_GasCloud:
    case DefenderModificationPreset._m1DefenseDice_GasCloud:
    case DefenderModificationPreset._m2DefenseDice_GasCloud:
    case DefenderModificationPreset._m3DefenseDice_GasCloud:
        attack_form.gas_cloud_blank_to_evade = true;
        break;
    default:
        break;
    }

    return attack_form;
}

public SimulationSetup to_simulation_setup(ref const(AttackPresetForm) attack,
        ref const(DefenseForm) defense_form)
{
    // Avoid ambiguity between the two modules...
    import simulation_setup2 : attack_form_setup = to_simulation_setup;

    auto attack_form = create_form_from_url!AttackForm(attack_preset_url(attack.preset), 0);
    attack_form = apply_defender_modification(attack_form, attack.defender_modification);

    return attack_form_setup(attack_form, defense_form);
}

// Simulation setup for the optional bonus attack
public SimulationSetup to_simulation_setup_bonus(ref const(AttackPresetForm) attack,
        ref const(DefenseForm) defense_form)
{
    import simulation_setup2 : attack_form_setup = to_simulation_setup;

    auto attack_form = create_form_from_url!AttackForm(
            attack_preset_url(attack.bonus_attack_preset), 0);
    // Same defender mod for bonus attack
    attack_form = apply_defender_modification(attack_form, attack.defender_modification);

    return attack_form_setup(attack_form, defense_form);
}

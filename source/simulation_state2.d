import dice;
import math;
import simulation_results;

import std.math;
import core.stdc.string;
import std.bitmanip;
import std.container.array;
import std.algorithm;
import std.stdio;
import std.conv;

// These fields are for tracking "once per opportunity" or other stuff that gets
// reset after modding completes and does not carry on to the next phase/attack.
// NOTE: In practice these fields get reset for the attacker after attack dice modding is done, and similar for defender.
// NOTE: Some of these fields are technically not required to be tracked for simulation purposes (usually because
// they only ever happen at a fixed point in the modify step, once), but we sometimes still track them for the
// purpose of outputting more useful modify_tree states.

struct AttackTempState
{
    mixin(bitfields!(bool, "finished_after_rolling", 1, // finished opportunity to do "after rolling" abilities
            bool, "finished_dmad",
            1, // finished defender modding attack dice
            bool, "finished_amad", 1, // finished attacker modding attack dice
            bool, "cannot_spend_lock", 1, // ex. after using fire-control system
            bool, "used_advanced_targeting_computer", 1,
            bool, "used_add_blank_results", 1, bool, "used_add_focus_results", 1, uint, "used_reroll_1_count", 3,
            uint, "used_reroll_2_count", 3, // Up to 2 dice
            uint, "used_reroll_3_count", 3, // Up to 3 dice
            bool, "used_shara_bey_pilot", 1, bool,
            "used_scum_lando_crew", 1, bool, "used_scum_lando_pilot", 1, bool, "used_rebel_han_pilot", 1, bool,
            "used_saturation_salvo", 1, bool, "used_advanced_optics", 1, uint, "", 10,));

    void reset()
    {
        this = AttackTempState.init;
    }
}

struct DefenseTempState
{
    mixin(bitfields!(bool, "finished_after_rolling", 1, // finished opportunity to do "after rolling" abilities
            bool, "finished_amdd",
            1, // finished attacker modding defense dice
            bool, "finished_dmdd", 1, // finished defender modding defense dice
            bool, "used_c3p0", 1, bool, "used_add_blank_results", 1, bool,
            "used_add_focus_evade_results", 1, uint, "used_reroll_1_count", 3, uint, "used_reroll_2_count", 3, // Up to 2 dice
            uint,
            "used_reroll_3_count", 3, // Up to 3 dice
            bool, "used_shara_bey_pilot", 1, bool,
            "used_scum_lando_crew", 1, bool, "used_rebel_millennium_falcon",
            1, bool, "used_scum_lando_pilot", 1, bool, "used_rebel_han_pilot", 1, uint, "", 12,));

    void reset()
    {
        this = DefenseTempState.init;
    }
}

// Useful structure for indicating how to fork state to a caller
public enum StateForkType : int
{
    None = 0, // No fork needed
    Roll, // Roll and reroll dice into appropriate pools based on counts
};

public struct StateFork
{
    bool required() const
    {
        return type != StateForkType.None;
    }

    // TODO: Could be a more complicated Variant enum or similar in the long run but this is fine for now
    StateForkType type = StateForkType.None;
    int roll_count = 0; // Roll into regular pool.
};

// Associated factor methods for convenience
public StateFork StateForkNone()
{
    return StateFork();
}

public StateFork StateForkRoll(int count)
{
    assert(count > 0);
    StateFork fork;
    fork.type = StateForkType.Roll;
    fork.roll_count = count;
    return fork;
}

public StateFork StateForkReroll(int count)
{
    assert(count > 0);
    StateFork fork;
    fork.type = StateForkType.Roll;
    fork.roll_count = 0;
    return fork;
}

public struct SimulationState
{
    struct Key
    {
        // TODO: Can move the "_temp" stuff out the key to make comparison/sorting slightly faster,
        // but need to ensure that they are reset at exactly the right places.
        DiceState attack_dice;
        AttackTempState attack_temp;
        DiceState defense_dice;
        DefenseTempState defense_temp;

        // Final results
        ubyte final_damage = 0;
        ubyte final_wilds = 0;
    }

    Key key;
    double probability = 1.0;

    // Convenient to allow fields from the key to be accessed directly as state.X rather than state.key.X
    alias key this;

    // Compare only the key portion of the state
    int opCmp(ref const SimulationState s) const
    {
        // TODO: Optimize this more for common early outs?
        return memcmp(&this.key, &s.key, Key.sizeof);
    }

    bool opEquals(ref const SimulationState s) const
    {
        // TODO: Optimize this more for common early outs?
        return (this.key == s.key);
    }
}
//pragma(msg, "sizeof(SimulationState) = " ~ to!string(SimulationState.sizeof));

// State forking utilities

// TODO update
// TODO pass dice, use for attack/defense
// delegate params are next_state, probability (also already baked into next_state probability)
public void roll_attack_dice(SimulationState prev_state, int roll_count,
        void delegate(SimulationState, double) dg)
{
    dice.roll_dice(roll_count, (int fail, int blank, int block, int hit, int wild,
            int crit, double probability) {
        SimulationState next_state = prev_state;

        next_state.attack_dice.results[DieResult.Crit] += crit;
        next_state.attack_dice.results[DieResult.Wild] += wild;
        next_state.attack_dice.results[DieResult.Hit] += hit;
        next_state.attack_dice.results[DieResult.Block] += block;
        next_state.attack_dice.results[DieResult.Blank] += blank;
        next_state.attack_dice.results[DieResult.Fail] += fail;

        next_state.probability *= probability;
        dg(next_state, probability);
    });
}

public void roll_defense_dice(SimulationState prev_state, int roll_count,
        void delegate(SimulationState, double) dg)
{
    dice.roll_dice(roll_count, (int fail, int blank, int block, int hit, int wild,
            int crit, double probability) {
        SimulationState next_state = prev_state;

        next_state.defense_dice.results[DieResult.Crit] += crit;
        next_state.defense_dice.results[DieResult.Wild] += wild;
        next_state.defense_dice.results[DieResult.Hit] += hit;
        next_state.defense_dice.results[DieResult.Block] += block;
        next_state.defense_dice.results[DieResult.Blank] += blank;
        next_state.defense_dice.results[DieResult.Fail] += fail;

        next_state.probability *= probability;
        dg(next_state, probability);
    });
}

// general state fork based on StateFork struct
// Currently will assert if fork.required() is false; could change to a noop if it makes sense at any call sites
// delegate params are next_state, probability (also already baked into next_state probability)
public void fork_attack_state(SimulationState prev_state, const StateFork fork,
        void delegate(SimulationState, double) dg)
{
    assert(fork.required());
    switch (fork.type)
    {
    case StateForkType.Roll:
        roll_attack_dice(prev_state, fork.roll_count, dg);
        break;
    default:
        assert(false);
    }
}
// NOTE: Could include attack vs. defense as part of the fork enum directly but this is clearer for the moment
public void fork_defense_state(SimulationState prev_state, const StateFork fork,
        void delegate(SimulationState, double) dg)
{
    assert(fork.required());
    switch (fork.type)
    {
    case StateForkType.Roll:
        roll_defense_dice(prev_state, fork.roll_count, dg);
        break;
    default:
        assert(false);
    }
}

public class SimulationStateSet
{
    public this()
    {
        // TODO: Experiment with this
        m_states.reserve(50);
    }

    // Compresses and simplifies the state set by combining any elements that match and
    // adding their probabilities together. This is very important for performance and states
    // should be simplified as much as possible before calling this to allow as many state collapses
    // as possible.
    public void compress()
    {
        if (m_states.empty())
            return;

        // First sort so that any matching keys are back to back
        sort!((a, b) => memcmp(&a.key, &b.key, a.key.sizeof) < 0)(m_states[]);

        // Then walk through the array and combine elements that match their predecessors
        SimulationState write_state = m_states.front();
        size_t write_count = 0;
        foreach (i; 1 .. m_states.length)
        {
            if (m_states[i] == write_state)
            {
                // State matches, combine
                write_state.probability += m_states[i].probability;
            }
            else
            {
                // State does not match; store the current write state and move on
                m_states[write_count] = write_state;
                ++write_count;
                write_state = m_states[i];
            }
        }
        // Write last element and read just length
        m_states[write_count++] = write_state;
        m_states.length = write_count;
    }

    // NOTE: Rolls into the regular results pool
    // Handy utilities for invoking the initial roll. Can easily be done with fork_*_state as well for more control.
    public void roll_attack_dice(SimulationState prev_state, int roll_count)
    {
        .roll_attack_dice(prev_state, roll_count, (SimulationState next_state, double probability) {
            push_back(next_state);
        });
    }

    public void roll_defense_dice(SimulationState prev_state, int roll_count)
    {
        .roll_defense_dice(prev_state, roll_count, (SimulationState next_state, double probability) {
            push_back(next_state);
        });
    }

    public void fork_attack_state(SimulationState prev_state, const StateFork fork)
    {
        .fork_attack_state(prev_state, fork, (SimulationState next_state, double probability) {
            push_back(next_state);
        });
    }

    public void fork_defense_state(SimulationState prev_state, const StateFork fork)
    {
        .fork_defense_state(prev_state, fork, (SimulationState next_state, double probability) {
            push_back(next_state);
        });
    }

    public SimulationResults compute_results() const
    {
        SimulationResults results;

        // TODO: Could scan through m_states to see the required size, but this is good enough for now
        results.total_damage_pdf = new SimulationResult[1];
        foreach (ref i; results.total_damage_pdf)
            i = SimulationResult.init;

        foreach (i; 0 .. m_states.length)
        {
            SimulationState state = m_states[i];

            // Compute final results of this simulation step
            SimulationResult result;
            result.probability = state.probability;
            result.damage = state.probability * cast(double) state.final_damage;
            result.wilds = state.probability * cast(double) state.final_wilds;

            // Accumulate into the total results structure
            results.total_sum = accumulate_result(results.total_sum, result);

            // Accumulate into the right bin of the total hits PDF
            if (state.final_damage >= results.total_damage_pdf.length)
                results.total_damage_pdf.length = state.final_damage + 1;
            results.total_damage_pdf[state.final_damage] = accumulate_result(
                    results.total_damage_pdf[state.final_damage], result);

            // If there was at least one uncanceled crit, accumulate probability
            if (state.final_wilds > 0)
                results.at_least_one_wild_probability += state.probability;
        }

        return results;
    }

    public @property size_t length() const
    {
        return m_states.length;
    }

    public bool empty() const
    {
        return m_states.empty();
    }

    public void clear_for_reuse()
    {
        m_states.length = 0;
    }

    public SimulationState pop_back()
    {
        SimulationState back = m_states.back();
        m_states.removeBack();
        return back;
    }

    public void push_back(SimulationState v)
    {
        m_states.insertBack(v);
    }

    // Support foreach over m_states, but read only
    int opApply(int delegate(ref const(SimulationState)) operations) const
    {
        int result = 0;
        foreach (ref const(SimulationState) state; m_states)
        {
            result = operations(state);
            if (result)
            {
                break;
            }
        }
        return result;
    }

    private Array!SimulationState m_states;
}

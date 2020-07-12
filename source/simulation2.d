import simulation_state2;
import simulation_setup2;
import modify_attack_dice : modify_attack_dice;
import modify_defense_dice : modify_defense_dice_root;
import simulation_results;
import dice;
import math;

import std.algorithm;
import std.stdio;
import std.datetime;
import std.array;
import std.conv;

import vibe.core.core;

//-----------------------------------------------------------------------------------

public SimulationState neutralize_results(const(SimulationSetup) setup, SimulationState state)
{
    state.attack_dice.finalize();
    state.defense_dice.finalize();

    // Convenience
    ubyte[DieResult.Num] attack_results = state.attack_dice.final_results;
    ubyte[DieResult.Num] defense_results = state.defense_dice.final_results;

    // Compare results
    int total_hits = state.attack_dice.count(DieResult.Crit) + state.attack_dice.count(
            DieResult.Wild) + state.attack_dice.count(DieResult.Hit);
    int total_evades = state.defense_dice.count(DieResult.Crit) + state.defense_dice.count(
            DieResult.Wild) + state.defense_dice.count(DieResult.Block);

    // Cancel pairs of hits/crits and evades

    // Update final states and clear out state vector

    state.final_damage += max(total_hits - total_evades, 0);
    state.final_wilds = attack_results[DieResult.Wild];

    // Simplify/clear out irrelevant states
    // Keep tokens and final results, discard the rest
    {
        state.attack_dice.cancel_all();
        state.defense_dice.cancel_all();

        state.attack_temp.reset();
        state.attack_tokens.spent_calculate = false;
        assert(state.attack_tokens.iden_used == false);

        state.defense_temp.reset();
        state.defense_tokens.spent_calculate = false;
        state.defense_tokens.iden_used = false;
    }

    return state;
}

// Returns full set of states after result comparison (results put into state.final_hits, etc)
private SimulationStateSet simulate_single_attack(const(SimulationSetup) setup,
        TokenState attack_tokens, TokenState defense_tokens)
{
    auto states = new SimulationStateSet();
    auto finished_states = new SimulationStateSet();

    // Roll attack dice
    {
        SimulationState initial_state;
        initial_state.attack_tokens = attack_tokens;
        initial_state.defense_tokens = defense_tokens;
        initial_state.probability = 1.0;

        // If "roll all hits" is set just statically add that single option
        if (setup.attack.roll_all_hits)
        {
            initial_state.attack_dice.results[DieResult.Hit] = cast(ubyte) setup.attack.dice;
            states.push_back(initial_state);
        }
        else
        {
            // Regular roll
            states.roll_attack_dice(initial_state, setup.attack.dice);
        }
    }

    // Modify attack dice (loop until done modifying)
    {
        while (!states.empty())
        {
            SimulationState state = states.pop_back();
            StateFork fork = modify_attack_dice(setup, state);
            if (fork.required())
            {
                states.fork_attack_state(state, fork);
            }
            else
            {
                state.attack_dice.finalize();

                // Reset any "once per opportunity" token tracking states (i.e. "did we use this effect yet")
                state.attack_temp.reset();

                finished_states.push_back(state);
            }
        }

        swap(states, finished_states);
        finished_states.clear_for_reuse();

        states.compress();
        //writeln(states.length);
    }

    // Roll defense dice        
    {
        while (!states.empty())
        {
            SimulationState state = states.pop_back();

            int defense_dice_count = setup.defense.dice + setup.attack.defense_dice_diff;
            finished_states.roll_defense_dice(state, defense_dice_count);
        }

        swap(states, finished_states);
        finished_states.clear_for_reuse();

        // No additional states to compress since dice rolling will always be pure divergence
        //writeln(states.length);
    }

    // Modify defense dice (loop until done modifying)
    {
        while (!states.empty())
        {
            SimulationState state = states.pop_back();
            StateFork fork = modify_defense_dice_root(setup, state);
            if (fork.required())
            {
                states.fork_defense_state(state, fork);
            }
            else
            {
                state.defense_dice.finalize();

                // Reset any "once per opportunity" token tracking states (i.e. "did we use this effect yet")
                state.defense_temp.reset();

                finished_states.push_back(state);
            }
        }

        swap(states, finished_states);
        finished_states.clear_for_reuse();
        states.compress();
        //writeln(states.length);
    }

    // Neutralize results and "after attack"
    {
        while (!states.empty())
        {
            SimulationState state = neutralize_results(setup, states.pop_back());
            finished_states.push_back(state);
        }

        swap(states, finished_states);
        finished_states.clear_for_reuse();
        states.compress();
        //writeln(states.length);
    }

    return states;
}

// Main entry point for simulating a new attack following any previously simulated results
//
// NOTE: Takes the initial state set as non-constant since it needs to sort it, but does not otherwise
// modify the contents. Returns a new state set after this additional attack.
public SimulationStateSet simulate_attack(const(SimulationSetup) setup, SimulationStateSet states)
{
    // NOTE: It would be "correct" here to just immediately fork all of our states set into another attack,
    // but that is relatively inefficient. Since the core thing that affects how the next attack plays out is
    // our *tokens*, we want to only simulate additional attacks with unique token sets, then apply
    // the results to any input states with that token set.

    // For now we'll do that in the simplest way possible: simply iterate the states and perform second
    // attack simulations for any unique token sets that we run into. Then we'll apply the results with all
    // input states to use that token set.
    //
    // NOTE: This is all assuming that an "attack" logic only depends on the "setup" and "tokens", and never
    // on anything like the number of hits that happened in the previous attack. This is a safe assumption for
    // now. We could technically split our state set into two parts to represent this more formally, but that
    // would make it a lot more wordy - and potentially less efficient - to pass it around everywhere.

    // Sort our states by tokens so that any matching sets are back to back in the list
    states.sort_by_tokens(); // There's ways to do this in place but it's simpler for now to just do it to a new state set
    // This function is only called once per attack, so it's not the end of the world
    SimulationStateSet new_states = new SimulationStateSet();
    SimulationStateSet second_attack_states;
    SimulationState second_attack_initial_state;
    foreach (initial_state; states)
    {
        // If our tokens are the same as the previous simulation (we sorted), we don't have to simulate again
        if (initial_state.attack_tokens != second_attack_initial_state.attack_tokens
                || initial_state.defense_tokens != second_attack_initial_state.defense_tokens
                || !second_attack_states)
        {
            // This can be expensive for lots of states so worth allowing other things to run occasionally
            vibe.core.core.yield(); //auto sw = StopWatch(AutoStart.yes);

            // New token state set, so run a new simulation
            second_attack_initial_state = initial_state;
            second_attack_states = simulate_single_attack(setup,
                    second_attack_initial_state.attack_tokens,
                    second_attack_initial_state.defense_tokens); //writefln("Second attack in %s msec", sw.peek().msecs());
        }

        // Compose all of the results from the second attack set with this one
        foreach (const second_state; second_attack_states)
        {
            // NOTE: Important to keep the token state and such from after the second attack, not initial one
            SimulationState new_state = second_state;
            new_state.final_damage += initial_state.final_damage;
            new_state.final_wilds += initial_state.final_wilds;
            new_state.probability *= initial_state.probability;
            new_states.push_back(new_state);
        }
    }

    // Update our simulation with the new results
    new_states.compress();
    return new_states;
}

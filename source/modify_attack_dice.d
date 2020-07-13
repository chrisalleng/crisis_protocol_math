import simulation_state2;
import simulation_setup2;
import dice;
import math;
import log;

import std.algorithm;

private StateFork after_rolling(const(SimulationSetup) setup, ref SimulationState state)
{
    // Nothing to do here for now
    return StateForkNone();
}

private StateFork dmad(const(SimulationSetup) setup, ref SimulationState state)
{
    // Base case
    if (state.attack_temp.finished_dmad)
        return StateForkNone();

    SearchDelegate[2] search_options;
    size_t search_options_count = 0;
    search_options[search_options_count++] = do_defense_finish_dmad();

    // NOTE: We want to *minimize* the attack hits since we're the defender :)
    StateFork fork = search_attack(setup, state, search_options[0 .. search_options_count], true);
    if (fork.required())
        return fork;
    else
        return dmad(setup, state); // Continue defender modifying
}

// Returns number of dice to reroll, or 0 when done modding
// Modifies state in place
public StateFork modify_attack_dice(const(SimulationSetup) setup, ref SimulationState state)
{
    // First have to do any "after rolling" abilities
    // NOTE: Nothing to do here for now
    //if (!state.attack_temp.finished_after_rolling)
    //{
    //    StateFork fork = after_rolling(setup, state);
    //    if (fork.required())
    //        return fork;
    //    assert(state.attack_temp.finished_after_rolling);
    //}

    // Next the defender modifies the dice
    if (!state.attack_temp.finished_dmad)
    {
        StateFork fork = dmad(setup, state);
        if (fork.required())
            return fork;
        assert(state.attack_temp.finished_dmad);
    }

    // Attacker modifies
    // Base case
    if (state.attack_temp.finished_amad)
        return StateForkNone();

    // Search from all our potential rerolling options to find the optimal one
    SearchDelegate[64] search_options;
    size_t search_options_count = 0;

    // "Free" rerolls
    const int max_dice_to_reroll = state.attack_dice.results[DieResult.Fail]
        + state.attack_dice.results[DieResult.Blank] + state.attack_dice.results[DieResult.Block];

    if (max_dice_to_reroll > 0)
    {
        foreach_reverse (const dice_to_reroll; 1 .. (max_dice_to_reroll + 1))
        {
            // NOTE: Can use "reroll up to 2/3" abilities to reroll just one if needed as well, but less desirable
            if (dice_to_reroll == 3)
            {
                if (setup.attack.reroll_3_count > state.attack_temp.used_reroll_3_count)
                    search_options[search_options_count++] = do_attack_reroll_3(dice_to_reroll);
            }
            else if (dice_to_reroll == 2)
            {
                if (setup.attack.reroll_2_count > state.attack_temp.used_reroll_2_count)
                    search_options[search_options_count++] = do_attack_reroll_2(dice_to_reroll);
                else if (setup.attack.reroll_3_count > state.attack_temp.used_reroll_3_count)
                    search_options[search_options_count++] = do_attack_reroll_3(dice_to_reroll);
            }
            else if (dice_to_reroll == 1)
            {
                if (setup.attack.reroll_1_count > state.attack_temp.used_reroll_1_count)
                    search_options[search_options_count++] = do_attack_reroll_1();
                else if (setup.attack.reroll_2_count > state.attack_temp.used_reroll_2_count)
                    search_options[search_options_count++] = do_attack_reroll_2(dice_to_reroll);
                else if (setup.attack.reroll_3_count > state.attack_temp.used_reroll_3_count)
                    search_options[search_options_count++] = do_attack_reroll_3(dice_to_reroll);
            }
        }

    }

    // Now check finishing up attack mods and stopping
    search_options[search_options_count++] = do_attack_finish_amad();

    // Search modifies the state to execute the best of the provided options
    StateFork fork = search_attack(setup, state, search_options[0 .. search_options_count]);
    if (fork.required())
        return fork;
    else
    {
        // Continue modifying
        // TODO: Could easily do this with a loop rather than tail recursion, just will cover a good
        // chunk of this function so experiment with which is cleaner.
        return modify_attack_dice(setup, state);
    }
}

alias StateFork delegate(const(SimulationSetup) setup, ref SimulationState) SearchDelegate;

private SearchDelegate do_attack_finish_amad()
{
    return (const(SimulationSetup) setup, ref SimulationState state) {
        assert(!state.attack_temp.finished_amad);

        state.attack_temp.finished_amad = true;
        return StateForkNone();
    };
}

// Rerolls a blank if present, otherwise block
private SearchDelegate do_attack_reroll_1()
{
    return (const(SimulationSetup) setup, ref SimulationState state) {
        assert(setup.attack.reroll_1_count > state.attack_temp.used_reroll_1_count);
        int dice_to_reroll = state.attack_dice.count_dice_for_reroll_blank_block(1);
        state.attack_temp.used_reroll_1_count = state.attack_temp.used_reroll_1_count + 1;
        assert(dice_to_reroll == 1);
        return StateForkReroll(dice_to_reroll);
    };
}

private SearchDelegate do_attack_reroll_2(int count = 2)
{
    return (const(SimulationSetup) setup, ref SimulationState state) {
        assert(count > 0 && count <= 2);
        assert(setup.attack.reroll_2_count > state.attack_temp.used_reroll_2_count);
        int dice_to_reroll = state.attack_dice.count_dice_for_reroll_blank_block(count);
        state.attack_temp.used_reroll_2_count = state.attack_temp.used_reroll_2_count + 1;
        assert(dice_to_reroll == count);
        return StateForkReroll(dice_to_reroll);
    };
}

private SearchDelegate do_attack_reroll_3(int count = 3)
{
    return (const(SimulationSetup) setup, ref SimulationState state) {
        assert(count > 0 && count <= 3);
        assert(setup.attack.reroll_3_count > state.attack_temp.used_reroll_3_count);
        int dice_to_reroll = state.attack_dice.count_dice_for_reroll_blank_block(count);
        state.attack_temp.used_reroll_3_count = state.attack_temp.used_reroll_3_count + 1;
        assert(dice_to_reroll == count);
        return StateForkReroll(dice_to_reroll);
    };
}

// Defender modifies attack dice (DMAD)
private SearchDelegate do_defense_finish_dmad()
{
    return (const(SimulationSetup) setup, ref SimulationState state) {
        assert(!state.attack_temp.finished_dmad);

        if (setup.defense.plated_hull)
            state.attack_dice.change_dice(DieResult.Crit, DieResult.Hit, 1);

        state.attack_temp.finished_dmad = true;
        return StateForkNone();
    };
}

private double search_expected_damage(const(SimulationSetup) setup,
        SimulationState state, StateFork fork)
{
    if (!fork.required())
    {
        fork = modify_attack_dice(setup, state);
        if (!fork.required())
        {
            // Base case; done modifying dice
            return state.attack_dice.count(DieResult.Hit) + state.attack_dice.count(DieResult.Crit);
        }
    }

    double expected_damage = 0.0f;
    fork_attack_state(state, fork, (SimulationState new_state, double probability) {
        // NOTE: Rather than have the leaf nodes weight by their state probability, we just accumulate it
        // as we fork here instead. This is just to normalize the expected damage with respect to the state
        // that we started the search from rather than the global state space.
        expected_damage += probability * search_expected_damage(setup, new_state, StateForkNone());
    });

    return expected_damage;
}

// NOTE: Will prefer options earlier in the list if equivalent
// NOTE: Search delegates *must* evolve the state in a way that will eventually terminate,
// i.e. spending a finite token, rerolling dice and so on.
// NOTE: If minimize_damage is set to true, will instead search for the minimal damage option
// This is useful for opoonent searches (i.e. DMAD).
private StateFork search_attack(const(SimulationSetup) setup,
        ref SimulationState output_state, SearchDelegate[] options, bool minimize_damage = false)
{
    assert(options.length > 0);

    // Early out if there's only one option; no need for search
    if (options.length == 1)
        return options[0](setup, output_state);

    // Try each option and track which ends up with the best expected damage
    const(SimulationState) initial_state = output_state;
    SimulationState best_state = initial_state;
    double best_expected_damage = minimize_damage ? 100000.0f : -1.0f;
    StateFork best_state_fork = StateForkNone();

    //debug log_message("Forward search on %s (%s options):",
    //                  output_state.attack_dice, options.length, max_state_rerolls);

    foreach (option; options)
    {
        // Do any requested rerolls; note that instead of appending states we simple do a depth
        // first search of each result one by one. This keeps forward searches somewhat more efficient
        SimulationState state = initial_state;
        StateFork fork = option(setup, state);

        // Assert that delegate actually changed the state in some way; otherwise potential infinite loop!
        assert(fork.required() || state != initial_state);

        // TODO: Experiment with epsilon; this is to prefer earlier options when equivalent
        immutable double epsilon = 1e-9;

        bool new_best = false;
        double expected_damage = search_expected_damage(setup, state, fork);
        if ((!minimize_damage && expected_damage > (best_expected_damage + epsilon))
                || (minimize_damage && expected_damage < (best_expected_damage - epsilon)))
        {
            new_best = true;
            best_expected_damage = expected_damage;
            best_state = state;
            best_state_fork = fork;
        }

        //debug log_message("Option %s (reroll %s) expected damage: %s %s",
        //                  i, reroll_count, expected_damage, new_best ? "(new best)" : "");
    }

    output_state = best_state;
    return best_state_fork;
}

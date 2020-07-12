import simulation_state2;
import simulation_setup2;
import dice;
import math;
import log;

import std.algorithm;

private StateFork after_rolling(const(SimulationSetup) setup, ref SimulationState state)
{
    // Base case
    if (state.defense_temp.finished_after_rolling)
        return StateForkNone();

    // All done
    state.defense_temp.finished_after_rolling = true;
    return StateForkNone();
}

private StateFork amdd(const(SimulationSetup) setup, ref SimulationState state)
{
    // Base case
    if (state.defense_temp.finished_amdd)
        return StateForkNone();

    SearchDelegate[16] search_options;
    size_t search_options_count = 0;

    // NOTE: We put the "do nothing" option nearer the end of the list here rather than the usual start
    // Otherwise it'll conclude that ex. when the defender has an evade it's not worth doing anything to
    // their dice. In reality it's usually better to apply any effects that don't have much of a cost here
    // because it could cause the defender to spend more tokens than otherwise.
    // This isn't a perfect heuristic but in the absense of some sort of value function on tokens it's likely
    // the best we can do in general.

    // We're the attacker so we're interested in rerolling crits, wilds, and blocks
    int rerollable_results = state.defense_dice.results[DieResult.Crit]
        + state.defense_dice.results[DieResult.Wild] + state.defense_dice.results[DieResult.Block];
    if (rerollable_results > 0)
    {
    }

    search_options[search_options_count++] = do_defense_finish_amdd();

    // NOTE: We want to *maximize* the attack hits since we're the defender :)
    StateFork fork = search_defense(setup, state, search_options[0 .. search_options_count], true);
    if (fork.required())
        return fork;
    else
        return amdd(setup, state); // Continue defender modifying
}

// NOTE: This function has the same semantics as modify_defense_dice.
// It exists entirely to track the root of the recursive tree before returning back to the
// caller for the purpose of effects that we may want to apply after we see the final results,
// but we do *not* want to affect the search. Ex. Iden.
// Since this function sits at the root of the recursive call tree it can decide to unwind or otherwise
// elide any choices made by the children, other than rerolls (which are handled by the caller, and it
// would be cheating to change!)
public StateFork modify_defense_dice_root(const(SimulationSetup) setup, ref SimulationState state)
{
    const(SimulationState) initial_state = state;

    StateFork fork = modify_defense_dice(setup, state);
    if (fork.required())
        return fork;
    else
    {
        return StateForkNone();
    }
}

// Returns number of dice to reroll, or 0 when done modding
// Modifies state in place
// NOTE: see public function above
private StateFork modify_defense_dice(const(SimulationSetup) setup, ref SimulationState state)
{
    // First have to do any "after rolling" abilities
    if (!state.defense_temp.finished_after_rolling)
    {
        StateFork fork = after_rolling(setup, state);
        if (fork.required())
            return fork;
        assert(state.defense_temp.finished_after_rolling);
    }

    // Next the attacker modifies the dice
    if (!state.defense_temp.finished_amdd)
    {
        StateFork fork = amdd(setup, state);
        if (fork.required())
            return fork;
        assert(state.defense_temp.finished_amdd);
    }

    // Defender modifies dice

    // Base case and early outs
    // TODO: compute_uncanceled_damage() == 0 instead? Since our search logic relies on that it's probably "safe"
    int evades_target = state.attack_dice.final_results[DieResult.Crit]
        + state.attack_dice.final_results[DieResult.Wild]
        + state.attack_dice.final_results[DieResult.Hit];

    if (state.defense_dice.final_results[DieResult.Crit] + state.defense_dice
            .final_results[DieResult.Wild] + state.defense_dice.final_results[DieResult.Block] >= evades_target
            || state.defense_temp.finished_dmdd)
        return StateForkNone();

    // Search from all our potential token spending and rerolling options to find the optimal one
    SearchDelegate[64] search_options;
    size_t search_options_count = 0;

    // Rerolls - see comments in modify_attack_dice as the logic is similar
    const int max_fails_to_reroll = state.defense_dice.results[DieResult.Fail];
    const int max_blanks_to_reroll = state.defense_dice.results[DieResult.Blank];
    const int max_hits_to_reroll = state.defense_dice.results[DieResult.Hit];
    const int max_dice_to_reroll = max_fails_to_reroll + max_blanks_to_reroll + max_hits_to_reroll;

    // Similar logic to attack rerolls - see documentation there (modify_attack_dice.d)
    if (max_dice_to_reroll > 0)
    {
        // Currently there aren't any defender effects that allow one to reroll more than 3 dice at once
        const int fail_loop_count = max_fails_to_reroll + 1;
        const int blank_loop_count = max_blanks_to_reroll + 1;
        const int hit_loop_count = max_hits_to_reroll + 1;

        // TODO: Consider various rearrangements of these loops
        foreach (const fails_to_reroll; 0 .. fail_loop_count)
        {
            foreach (const blanks_to_reroll; 0 .. blank_loop_count)
            {
                foreach (const hits_to_reroll; 0 .. hit_loop_count)
                {
                    int dice_to_reroll = fails_to_reroll + blanks_to_reroll + hits_to_reroll;
                    if (dice_to_reroll == 0)
                        continue;
                    else if (dice_to_reroll == 1)
                    {
                        if (setup.defense.reroll_1_count > state.defense_temp.used_reroll_1_count)
                            search_options[search_options_count++] = do_defense_reroll_1(fails_to_reroll,
                                    blanks_to_reroll, hits_to_reroll);
                        else if (
                            setup.defense.reroll_2_count > state.defense_temp.used_reroll_2_count)
                            search_options[search_options_count++] = do_defense_reroll_2(fails_to_reroll,
                                    blanks_to_reroll, hits_to_reroll);
                        else if (
                            setup.defense.reroll_3_count > state.defense_temp.used_reroll_3_count)
                            search_options[search_options_count++] = do_defense_reroll_3(fails_to_reroll,
                                    blanks_to_reroll, hits_to_reroll);
                    }
                    else if (dice_to_reroll == 2)
                    {
                        if (setup.defense.reroll_2_count > state.defense_temp.used_reroll_2_count)
                            search_options[search_options_count++] = do_defense_reroll_2(fails_to_reroll,
                                    blanks_to_reroll, hits_to_reroll);
                        else if (
                            setup.defense.reroll_3_count > state.defense_temp.used_reroll_3_count)
                            search_options[search_options_count++] = do_defense_reroll_3(fails_to_reroll,
                                    blanks_to_reroll, hits_to_reroll);
                    }
                    else if (dice_to_reroll == 3)
                    {
                        if (setup.defense.reroll_3_count > state.defense_temp.used_reroll_3_count)
                            search_options[search_options_count++] = do_defense_reroll_3(fails_to_reroll,
                                    blanks_to_reroll, hits_to_reroll);
                    }
                }
            }
        }
    }

    // Regular modding to attempt to avoid all damage
    search_options[search_options_count++] = do_defense_finish_dmdd(evades_target);

    // Paid rerolls
    if (max_dice_to_reroll > 0)
    {
    }

    // Search modifies the state to execute the best of the provided options
    SimulationState before_search_state = state;
    StateFork fork = search_defense(setup, state, search_options[0 .. search_options_count]);
    if (fork.required())
        return fork;
    else
    {
        // Continue modifying
        return modify_defense_dice(setup, state);
    }
}

alias StateFork delegate(const(SimulationSetup) setup, ref SimulationState) SearchDelegate;

// Attacker modifies defense dice (AMDD)
private SearchDelegate do_defense_finish_amdd()
{
    return (const(SimulationSetup) setup, ref SimulationState state) {
        assert(!state.defense_temp.finished_amdd);

        state.defense_temp.finished_amdd = true;
        return StateForkNone();
    };
}

private SearchDelegate do_defense_finish_dmdd(int evades_target)
{
    return (const(SimulationSetup) setup, ref SimulationState state) {
        assert(!state.defense_temp.finished_dmdd);

        // Structurally it's convenient to have early returns here instead of endlessly nested if's, so set this in advance
        state.defense_temp.finished_dmdd = true;

        int needed_evades = max(0, evades_target - state.defense_dice.count(
                DieResult.Crit) - state.defense_dice.count(
                DieResult.Wild) - state.defense_dice.count(DieResult.Block));
        // Logic for doing things goes here
        if (needed_evades <= 0)
            return StateForkNone();
        return StateForkNone();
    };
}

private SearchDelegate do_defense_reroll_1(int fails_count, int blanks_count, int hits_count)
{
    return (const(SimulationSetup) setup, ref SimulationState state) {
        assert(setup.defense.reroll_1_count > state.defense_temp.used_reroll_1_count);
        int dice_to_reroll = state.defense_dice.count_dice_for_reroll(DieResult.Fail, fails_count);
        dice_to_reroll += state.defense_dice.count_dice_for_reroll(DieResult.Blank, blanks_count);
        dice_to_reroll += state.defense_dice.count_dice_for_reroll(DieResult.Hit, hits_count);
        state.defense_temp.used_reroll_1_count = state.defense_temp.used_reroll_1_count + 1;
        assert(dice_to_reroll == 1);
        return StateForkReroll(dice_to_reroll);
    };
}

private SearchDelegate do_defense_reroll_2(int fails_count, int blanks_count, int hits_count)
{
    return (const(SimulationSetup) setup, ref SimulationState state) {
        assert(setup.defense.reroll_2_count > state.defense_temp.used_reroll_2_count);
        int dice_to_reroll = state.defense_dice.count_dice_for_reroll(DieResult.Fail, fails_count);
        dice_to_reroll += state.defense_dice.count_dice_for_reroll(DieResult.Blank, blanks_count);
        dice_to_reroll += state.defense_dice.count_dice_for_reroll(DieResult.Hit, hits_count);
        state.defense_temp.used_reroll_2_count = state.defense_temp.used_reroll_2_count + 1;
        assert(dice_to_reroll == (fails_count + blanks_count + hits_count));
        assert(dice_to_reroll <= 2);
        return StateForkReroll(dice_to_reroll);
    };
}

private SearchDelegate do_defense_reroll_3(int fails_count, int blanks_count, int hits_count)
{
    return (const(SimulationSetup) setup, ref SimulationState state) {
        assert(setup.defense.reroll_3_count > state.defense_temp.used_reroll_3_count);
        int dice_to_reroll = state.defense_dice.count_dice_for_reroll(DieResult.Fail, fails_count);
        dice_to_reroll += state.defense_dice.count_dice_for_reroll(DieResult.Blank, blanks_count);
        dice_to_reroll += state.defense_dice.count_dice_for_reroll(DieResult.Hit, hits_count);
        state.defense_temp.used_reroll_3_count = state.defense_temp.used_reroll_3_count + 1;
        assert(dice_to_reroll == (fails_count + blanks_count + hits_count));
        assert(dice_to_reroll <= 3);
        return StateForkReroll(dice_to_reroll);
    };
}

private double search_expected_damage(const(SimulationSetup) setup,
        SimulationState state, StateFork fork)
{
    if (!fork.required())
    {
        fork = modify_defense_dice(setup, state);
        if (!fork.required())
        {
            // Base case; done modifying defense dice
            return cast(double) state.final_damage;
        }
    }

    double expected_damage = 0.0f;
    fork_defense_state(state, fork, (SimulationState new_state, double probability) {
        expected_damage += probability * search_expected_damage(setup, new_state, StateForkNone());
    });

    return expected_damage;
}

// Attempts to minimize the expected damage after a simplified neutralize results step
// (See compute_uncanceled_damage for the details.)
// NOTE: Will prefer options earlier in the list if equivalent, so put stuff that spends more
// or more valuable tokens later in the options list.
private StateFork search_defense(const(SimulationSetup) setup,
        ref SimulationState output_state, SearchDelegate[] options, bool maximize_damage = false)
{
    assert(options.length > 0);

    // Early out if there's only one option; no need for search
    if (options.length == 1)
        return options[0](setup, output_state);

    // Try each option and track which ends up with the best expected damage
    const(SimulationState) initial_state = output_state;
    SimulationState best_state = initial_state;
    double best_expected_damage = maximize_damage ? -1.0f : 100000.0f;
    StateFork best_state_fork = StateForkNone();

    foreach (option; options)
    {
        SimulationState state = initial_state;
        StateFork fork = option(setup, state);

        assert(fork.required() || state != initial_state);

        // TODO: Experiment with epsilon; this is to prefer earlier options when equivalent
        immutable double epsilon = 1e-9;

        double expected_damage = search_expected_damage(setup, state, fork);
        if ((!maximize_damage && expected_damage < (best_expected_damage - epsilon))
                || (maximize_damage && expected_damage > (best_expected_damage + epsilon)))
        {
            best_expected_damage = expected_damage;
            best_state = state;
            best_state_fork = fork;
        }
    }

    output_state = best_state;
    return best_state_fork;
}

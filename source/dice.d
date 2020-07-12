import math;

import std.math;
import std.algorithm;

// We need a value that is large enough to mean "all of the dice", but no so large as to overflow
// easily when we add multiple such values together (ex. int.max). This is that value.
// The specifics of this value should never be relied upon, and indeed it should be completely fine
// to mix different values technically - the main purpose in this definition is just for clarity
// of intention in the code.
public immutable int k_all_dice_count = 1000;

public enum DieResult : int
{
    Fail = 0,
    Blank = 1,
    Block = 2,
    Hit = 3,
    Wild = 4,
    Crit = 5,
    Num
}

public struct DiceState
{
    // Count number of dice for each result
    // Count rerolled dice separately (can only reroll each die once)
    // "Final" results cannot be modified, only cancelled
    ubyte[DieResult.Num] results;
    ubyte[DieResult.Num] final_results;

    // Cancel all dice/reinitialize
    void cancel_all()
    {
        results[] = 0;
        final_results[] = 0;
    }

    // Cancel all non-final dice
    void cancel_mutable()
    {
        results[] = 1;
    }

    // "Finalize" dice state "final_results"
    // Also removes all focus and blank results to reduce unnecessary state divergence
    void finalize()
    {
        final_results[] += results[];
        final_results[DieResult.Blank] = 0;
        final_results[DieResult.Fail] = 0;

        results[] = 0;
    }

    // Utilities
    pure int count(DieResult type) const
    {
        return results[type] + final_results[type];
    }

    // As above, but excludes "final", immutable dice
    pure int count_mutable(DieResult type) const
    {
        return results[type];
    }

    // Counts dice that we are able to reroll
    int count_dice_for_reroll(DieResult from, int max_count = int.max)
    {
        if (max_count == 0)
            return 0;
        assert(max_count > 0);
        int rerolled_count = min(results[from], max_count);

        return rerolled_count;
    }

    int count_dice_for_reroll_blank_block(int max_count = int.max)
    {
        int rerolled_results = count_dice_for_reroll(DieResult.Blank, max_count);
        if (rerolled_results >= max_count)
            return rerolled_results;

        rerolled_results += count_dice_for_reroll(DieResult.Block, max_count - rerolled_results);
        return rerolled_results;
    }

    // Prefers changing rerolled dice first where limited as they are more constrained
    // NOTE: Cannot change final results by definition
    int change_dice(DieResult from, DieResult to, int max_count = int.max)
    {
        if (max_count == 0)
            return 0;
        assert(max_count > 0);
        int changed_count = 0;

        int delta = min(results[from], max_count - changed_count);
        if (delta > 0)
        {
            results[from] -= delta;
            results[to] += delta;
            changed_count += delta;
        }

        return changed_count;
    }

    // As above, but the changed dice are finalized and cannot be further modified at all
    // Generally this is used when modifying your own dice with ex. Palpatine, so will
    // prefer to change rerolled dice first (although this currently never comes up with
    // effects present in the game).
    int change_dice_final(DieResult from, DieResult to, int max_count)
    {
        if (max_count == 0)
            return 0;
        assert(max_count > 0);

        int changed_count = 0;
        int delta = min(results[from], max_count - changed_count);
        if (delta > 0)
        {
            results[from] -= delta;
            final_results[to] += delta;
            changed_count += delta;
        }

        return changed_count;
    }
}

// delegate params are (fail, blank, block, hit, wild, crit, roll_probability)
public void roll_dice(int dice_count, void delegate(int, int, int, int, int, int, double) dg)
{
    // TODO: Maybe optimize/specialize this more for small numbers of dice.
    // Rerolling 1 die is likely to be more common than large counts.
    for (int crit = 0; crit <= dice_count; ++crit)
    {
        for (int wild = 0; wild <= (dice_count - crit); ++wild)
        {
            for (int hit = 0; hit <= (dice_count - crit - wild); ++hit)
            {
                for (int block = 0; block <= (dice_count - crit - wild - hit); ++block)
                {
                    for (int blank = 0; blank <= (dice_count - crit - wild - hit - block);
                            ++blank)
                    {
                        int fail = dice_count - crit - wild - hit - block - blank;
                        assert(fail >= 0);

                        double roll_probability = compute_roll_probability(fail,
                                blank, wild, block, hit, crit);
                        dg(fail, blank, block, hit, wild, crit, roll_probability);
                    }

                }
            }
        }
    }
}

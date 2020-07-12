import std.math;

// TODO: Can generalize this but okay for now
// Do it in floating point since for our purposes we always end up converting immediately anyways
private static immutable double[] k_factorials_table = [
    1, // 0!
    1, // 1!
    2, // 2!
    6, // 3!
    24, // 4!
    120, // 5!
    720, // 6!
    5040, // 7!
    40320, // 8!
    362880, // 9!
    3628800, // 10!
    39916800, // 11!
    479001600, // 12!
    6227020800, // 13!
    87178291200, // 14!
];

private pure double factorial(int n)
{
    assert(n < k_factorials_table.length);
    return k_factorials_table[n];
}

private pure double[count] compute_power_table(ulong count)(ulong num, ulong denom)
{
    double[15] table;
    table[0] = 1.0;

    // Can't use pow() as this has to work at compile time, so keep it simple
    ulong n = num;
    ulong d = denom;
    foreach (i; 1 .. table.length)
    {
        table[i] = cast(double) n / cast(double) d;
        n *= num;
        d *= denom;
    }

    return table;
}

private pure double fractional_power(ulong num, ulong denom)(int power)
{
    static immutable auto k_power_table = compute_power_table!15(num, denom);
    assert(power < k_power_table.length);
    return k_power_table[power];
}

// Multinomial distribution: https://en.wikipedia.org/wiki/Multinomial_distribution
// roll_probability = n! / (x_1! * ... * x_k!) * p_1^x_1 * ... p_k^x_k
// NOTE: Can optimize power functions into a table fairly easily as well but performance
// improvement is negligable and readability is greater this way.

public pure double compute_roll_probability(int fail, int blank, int block,
        int hit, int wild, int crit)
{
    // P(fail)  = 1/8
    // P(blank) = 2/8
    // P(block) = 1/8
    // P(hit)   = 2/8
    // P(wild)  = 1/8
    // P(crit)  = 1/8
    double nf = factorial(fail + blank + block + hit + wild + crit);
    double xf = (factorial(fail) * factorial(blank) * factorial(block) * factorial(
            hit) * factorial(wild) * factorial(crit));

    double p = fractional_power!(1, 8)(crit) * fractional_power!(1,
            8)(wild) * fractional_power!(2, 8)(hit) * fractional_power!(1,
            8)(block) * fractional_power!(1, 8)(blank) * fractional_power!(1, 8)(fail);

    double roll_probability = (nf / xf) * p;

    assert(roll_probability >= 0.0 && roll_probability <= 1.0);
    return roll_probability;
}

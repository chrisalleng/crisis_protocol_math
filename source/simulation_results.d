public struct SimulationResult
{
    double probability = 0.0f;
    double damage = 0;
    double wilds = 0;
}

public SimulationResult accumulate_result(SimulationResult a, SimulationResult b)
{
    a.probability += b.probability;
    a.damage += b.damage;
    a.wilds += b.wilds;
    return a;
}

// Accumulated results
// TODO: Make into a class with handy utilities
public struct SimulationResults
{
    SimulationResult[] total_damage_pdf;
    SimulationResult total_sum;
    double at_least_one_wild_probability = 0.0;
}

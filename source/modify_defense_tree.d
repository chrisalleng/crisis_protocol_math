import simulation_state2;
import simulation_setup2;
import modify_defense_dice : modify_defense_dice_root;
import modify_tree;
import dice;

// Returns expected damage
private void modify_defense_tree(const(SimulationSetup) setup,
        ref ModifyTreeNode[] nodes, int current_node)
{
    nodes[current_node].after = nodes[current_node].before;

    StateFork fork = modify_defense_dice_root(setup, nodes[current_node].after);
    if (!fork.required())
    {
        // Base case; done modifying dice
        nodes[current_node].expected_damage = nodes[current_node].after.final_damage;
        return;
    }

    // Make all the reroll nodes and append them contiguously to the list
    int first_child_index = cast(int) nodes.length;

    fork_defense_state(nodes[current_node].after, fork,
            (SimulationState next_state, double probability) {
        ModifyTreeNode new_node;
        new_node.child_probability = probability;
        new_node.depth = nodes[current_node].depth + 1;
        new_node.before = next_state;
        nodes ~= new_node;
    });
    int last_child_index = cast(int) nodes.length; // Exclusive

    nodes[current_node].first_child_index = first_child_index;
    nodes[current_node].child_count = last_child_index - first_child_index;

    double expected_damage = 0.0;
    foreach (child_node; first_child_index .. last_child_index)
    {
        modify_defense_tree(setup, nodes, child_node);
        expected_damage += nodes[child_node].child_probability * nodes[child_node].expected_damage;
    }
    nodes[current_node].expected_damage = expected_damage;
}

public ModifyTreeNode[] compute_modify_defense_tree(const(SimulationSetup) setup,
        DiceState attack_dice, DiceState defense_dice)
{
    auto nodes = new ModifyTreeNode[1];

    // NOTE: These need to be "finalized" before defense mods
    attack_dice.finalize();
    nodes[0].before.attack_dice = attack_dice;

    nodes[0].before.defense_dice = defense_dice;
    nodes[0].before.probability = 1.0;
    modify_defense_tree(setup, nodes, 0);
    return nodes;
}

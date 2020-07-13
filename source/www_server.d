import simulation2;
import simulation_setup2;
import simulation_state2;
import simulation_results;
import modify_attack_tree;
import modify_defense_tree;
import dice;

import form;
import log;

import attack_form;
import defense_form;
import attack_preset_form;

import std.array;
import std.stdio;
import std.datetime;
import std.datetime.stopwatch : StopWatch, AutoStart;
import std.algorithm;

import vibe.d;
import diet.html;

public struct WWWServerSettings
{
    ushort port = 80;
    string url_root = "/";
    string http_auth_username = "";
    string http_auth_password = "";
};

public class WWWServer
{
    public this(ref const(WWWServerSettings) server_settings)
    {
        m_server_settings = server_settings;

        auto settings = new HTTPServerSettings;
        settings.errorPageHandler = toDelegate(&error_page);
        settings.port = m_server_settings.port;

        //settings.accessLogFormat = "%h - %u %t \"%r\" %s %b \"%{Referer}i\" \"%{User-Agent}i\" %D";
        //settings.accessLogToConsole = true;

        auto router = new URLRouter;

        // If they provided HTTP auth credentials, protect all routes
        if (!m_server_settings.http_auth_username.empty())
            router.any("*", performBasicAuth("XWingMath", &http_auth_check_password));

        // 2.0 stuff
        router.get(m_server_settings.url_root ~ "2/multi/", &multi2);
        router.post(m_server_settings.url_root ~ "2/multi/simulate.json", &simulate_multi2);

        router.get(m_server_settings.url_root ~ "2/multi_preset/", &multi2_preset);
        router.post(m_server_settings.url_root ~ "2/multi_preset/simulate.json",
                &simulate_multi2_preset);

        // Index and misc
        router.get(m_server_settings.url_root,
                staticRedirect(m_server_settings.url_root ~ "2/multi_preset/", HTTPStatus.Found));
        router.get(m_server_settings.url_root ~ "faq/", &about);
        router.get(m_server_settings.url_root ~ "about/",
                staticRedirect(m_server_settings.url_root ~ "faq/", HTTPStatus.movedPermanently));

        debug
        {
            // Show routes in debug for convenience
            foreach (route; router.getAllRoutes())
            {
                writeln(route);
            }
        }
        else
        {
            // Add a redirect from each GET route without a trailing slash for robustness
            // Leave this disabled in debug/dev builds so we don't accidentally include non-canonical links
            foreach (route; router.getAllRoutes())
            {
                if (route.method == HTTPMethod.GET && route.pattern.length > 1
                        && route.pattern.endsWith("/"))
                {
                    router.get(route.pattern[0 .. $ - 1], redirect_append_slash());
                }
            }
        }

        auto file_server_settings = new HTTPFileServerSettings;
        file_server_settings.serverPathPrefix = m_server_settings.url_root;
        router.get(m_server_settings.url_root ~ "*",
                serveStaticFiles("./public/", file_server_settings));

        listenHTTP(settings, router);
    }

    // Handy utility for adding some robustness to routes
    // NOTE: Be careful with this for paths that might contain query strings or other nastiness
    private HTTPServerRequestDelegate redirect_append_slash(HTTPStatus status = HTTPStatus.found)
    {
        return (HTTPServerRequest req, HTTPServerResponse res) {
            // This is a bit awkward but seems to do the trick for the moment...
            auto url = req.fullURL();
            auto path = url.path;
            path.endsWithSlash = true;

            url.path = path;
            //writefln("%s -> %s", req.fullURL(), url);
            res.redirect(url, status);
        };
    }

    private bool http_auth_check_password(string user, string password)
    {
        return (user == m_server_settings.http_auth_username
                && password == m_server_settings.http_auth_password);
    }

    private struct SimulateJsonContent
    {
        struct Result
        {
            double expected_total_hits;
            double at_least_one_crit; // Percent

            // PDF/CDF chart
            string[] pdf_x_labels;
            double[] hit_pdf; // Percent
            double[] crit_pdf; // Percent
            double[] hit_inv_cdf; // Percent
            string pdf_table_html; // HTML for data table

            // Token chart
            string[] exp_token_labels;
            double[] exp_attack_tokens;
            double[] exp_defense_tokens;
            string token_table_html; // HTML for data table
        };

        Result[] results;

        // Query string that can be used in the URL to get back to the form state that generated this
        string form_state_string;
    };

    private void multi2(HTTPServerRequest req, HTTPServerResponse res)
    {
        DefenseForm defense = create_form_from_url!DefenseForm(req.query.get("d", ""));

        // NOTE: Query params are somewhat human-visible, so offset to make them 1-based
        AttackForm attack0 = create_form_from_url!AttackForm(req.query.get("a1", ""), 0);
        AttackForm attack1 = create_form_from_url!AttackForm(req.query.get("a2", ""), 1);
        AttackForm attack2 = create_form_from_url!AttackForm(req.query.get("a3", ""), 2);
        AttackForm attack3 = create_form_from_url!AttackForm(req.query.get("a4", ""), 3);
        AttackForm attack4 = create_form_from_url!AttackForm(req.query.get("a5", ""), 4);
        AttackForm attack5 = create_form_from_url!AttackForm(req.query.get("a6", ""), 5);
        AttackForm attack6 = create_form_from_url!AttackForm(req.query.get("a7", ""), 6);
        AttackForm attack7 = create_form_from_url!AttackForm(req.query.get("a8", ""), 7);
        AttackForm attack8 = create_form_from_url!AttackForm(req.query.get("a9", ""), 8);
        AttackForm attack9 = create_form_from_url!AttackForm(req.query.get("a10", ""), 9);

        auto server_settings = m_server_settings;
        res.render!("multi2_form.dt", server_settings, defense, attack0, attack1,
                attack2, attack3, attack4, attack5, attack6, attack7, attack8, attack9);
    }

    private void simulate_multi2(HTTPServerRequest req, HTTPServerResponse res)
    {
        //debug writeln(req.json.serializeToPrettyJson());

        auto defense_form = create_form_from_fields!DefenseForm(req.json["defense"]);

        AttackForm[10] attack_form;
        foreach (i; 0 .. cast(int) attack_form.length)
            attack_form[i] = create_form_from_fields!AttackForm(
                    req.json["attack" ~ to!string(i)], i);

        // Initialize form state query string
        // Any enabled attacks will be appended (just to keep it shorter for now)
        // Could possible be useful to still serialize attacks that are not enabled, but will do it this way for the time being
        string form_state_string = "d=" ~ serialize_form_to_url(defense_form);

        // Save results for each attack as we accumulate
        int max_enabled_attack = 0;
        SimulationResults[attack_form.length] results_after_attack;
        {
            auto sw = StopWatch(AutoStart.yes);

            // Set up the initial state
            auto simulation_states = new SimulationStateSet();
            SimulationState initial_state = SimulationState.init;
            initial_state.probability = 1.0;
            simulation_states.push_back(initial_state);

            foreach (i; 0 .. cast(int) attack_form.length)
            {
                if (attack_form[i].enabled)
                {
                    // NOTE: Query string parameter human visible so 1-based
                    form_state_string ~= format("&a%d=%s", (i + 1),
                            serialize_form_to_url(attack_form[i]));
                    max_enabled_attack = i;

                    SimulationSetup setup = to_simulation_setup(attack_form[i], defense_form);
                    simulation_states = simulate_attack(setup, simulation_states);
                }

                results_after_attack[i] = simulation_states.compute_results();
            }

            // NOTE: This is kinda similar to the access log, but convenient for now
            double expected_damage = results_after_attack[$ - 1].total_sum.damage;
            log_message("%s %s %.15f %sms", req.clientAddress.toAddressString(),
                    "/2/multi/?" ~ form_state_string, expected_damage, sw.peek().total!"msecs",);
        }

        SimulateJsonContent content;
        content.form_state_string = form_state_string;

        content.results = new SimulateJsonContent.Result[max_enabled_attack + 1];

        // Make sure all the graphs/tables have the same dimensions (worst case)
        int min_hits = 7;
        foreach (i; 0 .. cast(int) content.results.length)
            min_hits = max(min_hits, cast(int) results_after_attack[i].total_damage_pdf.length);

        foreach (i; 0 .. cast(int) content.results.length)
            content.results[i] = assemble_json_result(results_after_attack[i], min_hits, i);

        res.writeJsonBody(content);
    }

    private void multi2_preset(HTTPServerRequest req, HTTPServerResponse res)
    {
        DefenseForm defense = create_form_from_url!DefenseForm(req.query.get("d", ""));

        // NOTE: Query params are somewhat human-visible, so offset to make them 1-based
        AttackPresetForm attack0 = create_form_from_url!AttackPresetForm(req.query.get("a1", ""), 0);
        AttackPresetForm attack1 = create_form_from_url!AttackPresetForm(req.query.get("a2", ""), 1);
        AttackPresetForm attack2 = create_form_from_url!AttackPresetForm(req.query.get("a3", ""), 2);
        AttackPresetForm attack3 = create_form_from_url!AttackPresetForm(req.query.get("a4", ""), 3);
        AttackPresetForm attack4 = create_form_from_url!AttackPresetForm(req.query.get("a5", ""), 4);
        AttackPresetForm attack5 = create_form_from_url!AttackPresetForm(req.query.get("a6", ""), 5);
        AttackPresetForm attack6 = create_form_from_url!AttackPresetForm(req.query.get("a7", ""), 6);
        AttackPresetForm attack7 = create_form_from_url!AttackPresetForm(req.query.get("a8", ""), 7);

        auto server_settings = m_server_settings;
        res.render!("multi2_preset_form.dt", server_settings, defense, attack0,
                attack1, attack2, attack3, attack4, attack5, attack6, attack7);
    }

    private void simulate_multi2_preset(HTTPServerRequest req, HTTPServerResponse res)
    {
        //debug writeln(req.json.serializeToPrettyJson());

        auto defense_form = create_form_from_fields!DefenseForm(req.json["defense"]);

        AttackPresetForm[8] attack_form;
        foreach (i; 0 .. cast(int) attack_form.length)
            attack_form[i] = create_form_from_fields!AttackPresetForm(
                    req.json["attack" ~ to!string(i)], i);

        // Initialize form state query string
        // Any enabled attacks will be appended (just to keep it shorter for now)
        // Could possible be useful to still serialize attacks that are not enabled, but will do it this way for the time being
        string form_state_string = "d=" ~ serialize_form_to_url(defense_form);

        // Save results for each attack as we accumulate
        int max_enabled_attack = 0;
        SimulationResults[attack_form.length] results_after_attack;
        {
            auto sw = StopWatch(AutoStart.yes);

            // Set up the initial state
            auto simulation_states = new SimulationStateSet();
            SimulationState initial_state = SimulationState.init;
            initial_state.probability = 1.0;
            simulation_states.push_back(initial_state);

            foreach (i; 0 .. cast(int) attack_form.length)
            {
                if (attack_form[i].enabled)
                {
                    // NOTE: Query string parameter human visible so 1-based
                    form_state_string ~= format("&a%d=%s", (i + 1),
                            serialize_form_to_url(attack_form[i]));
                    max_enabled_attack = i;

                    SimulationSetup setup = to_simulation_setup(attack_form[i], defense_form);
                    simulation_states = simulate_attack(setup, simulation_states);

                    if (attack_form[i].bonus_attack_enabled)
                    {
                        SimulationSetup bonus_setup = to_simulation_setup_bonus(attack_form[i],
                                defense_form);
                        simulation_states = simulate_attack(bonus_setup, simulation_states);
                    }
                }

                results_after_attack[i] = simulation_states.compute_results();
            }

            // NOTE: This is kinda similar to the access log, but convenient for now
            double expected_damage = results_after_attack[$ - 1].total_sum.damage;
            log_message("%s %s %.15f %sms", req.clientAddress.toAddressString(),
                    "/2/multi_preset/?" ~ form_state_string, expected_damage,
                    sw.peek().total!"msecs",);
        }

        SimulateJsonContent content;
        content.form_state_string = form_state_string;

        content.results = new SimulateJsonContent.Result[max_enabled_attack + 1];

        // Make sure all the graphs/tables have the same dimensions (worst case)
        int min_hits = 7;
        foreach (i; 0 .. cast(int) content.results.length)
            min_hits = max(min_hits, cast(int) results_after_attack[i].total_damage_pdf.length);

        foreach (i; 0 .. cast(int) content.results.length)
            content.results[i] = assemble_json_result(results_after_attack[i], min_hits, i);

        res.writeJsonBody(content);
    }

    private SimulateJsonContent.Result assemble_json_result(ref const(SimulationResults) results,
            int min_hits, int attacker_index = -1, int defender_index = -1)
    {
        SimulateJsonContent.Result content;

        // Always nice to show at least 0..6 hits on the graph
        int graph_max_hits = max(min_hits, cast(int) results.total_damage_pdf.length);

        content.expected_total_hits = results.total_sum.damage;
        content.at_least_one_crit = 100.0 * results.at_least_one_wild_probability;

        // Set up X labels on the total hits graph
        content.pdf_x_labels = new string[graph_max_hits];
        foreach (i; 0 .. graph_max_hits)
            content.pdf_x_labels[i] = to!string(i);

        // Compute PDF for graph
        content.hit_pdf = new double[graph_max_hits];
        content.crit_pdf = new double[graph_max_hits];
        content.hit_inv_cdf = new double[graph_max_hits];

        content.hit_pdf[] = 0.0;
        content.crit_pdf[] = 0.0;
        content.hit_inv_cdf[] = 0.0;

        foreach (i, SimulationResult result; results.total_damage_pdf)
        {
            double total_probability = result.damage;
            double fraction_crits = total_probability > 0.0 ? result.wilds / total_probability : 0.0;
            double fraction_hits = 1.0 - fraction_crits;

            content.hit_pdf[i] = 100.0 * fraction_hits * result.probability;
            content.crit_pdf[i] = 100.0 * fraction_crits * result.probability;
        }

        // Compute inverse CDF P(at least X hits)
        content.hit_inv_cdf[graph_max_hits - 1]
            = content.hit_pdf[graph_max_hits - 1] + content.crit_pdf[graph_max_hits - 1];
        for (int i = graph_max_hits - 2; i >= 0; --i)
        {
            content.hit_inv_cdf[i] = content.hit_inv_cdf[i + 1]
                + content.hit_pdf[i] + content.crit_pdf[i];
        }

        // Render HTML for tables
        {
            SimulationResult[] total_damage_pdf = results.total_damage_pdf.dup;
            if (total_damage_pdf.length < min_hits)
                total_damage_pdf.length = min_hits;

            auto pdf_html = appender!string();
            pdf_html.compileHTMLDietFile!("pdf_table.dt", total_damage_pdf);
            content.pdf_table_html = pdf_html.data;
        }
        return content;
    }

    // ***************************************************************************************

    private void about(HTTPServerRequest req, HTTPServerResponse res)
    {
        auto server_settings = m_server_settings;
        res.render!("about.dt", server_settings);
    }

    private void error_page(HTTPServerRequest req, HTTPServerResponse res,
            HTTPServerErrorInfo error)
    {
        auto server_settings = m_server_settings;
        res.render!("error.dt", server_settings, req, error);
    }

    // ***************************************************************************************

    // NOTE: Be a bit careful with state here. These functions can be parallel and re-entrant due to
    // triggering blocking calls and then having other requests submitted by separate fibers.

    immutable WWWServerSettings m_server_settings;

}

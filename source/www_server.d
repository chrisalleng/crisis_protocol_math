import simulation;
import form;
import basic_form;
import advanced_form;
import log;

import std.stdio;
import std.datetime;
import std.datetime.stopwatch : StopWatch, AutoStart;

import vibe.d;

public class WWWServer
{
    public this()
    {
        auto settings = new HTTPServerSettings;
        settings.errorPageHandler = toDelegate(&error_page);
        settings.port = 80;

        //settings.sessionStore = new MemorySessionStore();

        //settings.accessLogFormat = "%h - %u %t \"%r\" %s %b \"%{Referer}i\" \"%{User-Agent}i\" %D";
        //settings.accessLogToConsole = true;

        auto router = new URLRouter;
    
        router.get("/", &basic);
        router.get("/advanced/", &advanced);
        router.get("/about/", &about);
        router.post("/simulate_basic.json", &simulate_basic);
        router.post("/simulate_advanced.json", &simulate_advanced);
    
        debug
        {
            // Show routes in debug for convenience
            foreach (route; router.getAllRoutes()) {
                writeln(route);
            }
        }
        else
        {
            // Add a redirect from each GET route without a trailing slash for robustness
            // Leave this disabled in debug/dev builds so we don't accidentally include non-canonical links
            foreach (route; router.getAllRoutes()) {
                if (route.method == HTTPMethod.GET && route.pattern.length > 1 && route.pattern.endsWith("/")) {
                    router.get(route.pattern[0..$-1], redirect_append_slash());
                }
            }
        }

        router.get("*", serveStaticFiles("./public/"));    

        listenHTTP(settings, router);
    }

    // Handy utility for adding some robustness to routes
    // NOTE: Be careful with this for paths that might contain query strings or other nastiness
    private HTTPServerRequestDelegate redirect_append_slash(HTTPStatus status = HTTPStatus.found)
    {
        return (HTTPServerRequest req, HTTPServerResponse res) {
            auto url = req.fullURL();
            url.path.endsWithSlash = true;
            res.redirect(url, status);
        };
    }

    private struct SimulationContent
    {
        // Query string that can be used in the URL to get back to the form state that generated this
        string form_state_string;

        double expected_total_hits;
        double at_least_one_crit;       // Percent
        string[] pdf_x_labels;
        double[] hit_pdf;               // Percent
        double[] crit_pdf;              // Percent
        double[] hit_inv_cdf;           // Percent

        string[4] exp_token_labels;
        double[4] exp_attack_tokens;
        double[4] exp_defense_tokens;
    };

    private void simulate_basic(HTTPServerRequest req, HTTPServerResponse res)
    {
        //debug writeln(req.form.serializeToPrettyJson());

        auto basic_form = create_form_from_fields!BasicForm(req.form);
        string form_state_string = serialize_form_to_url(basic_form);
        SimulationSetup setup = to_simulation_setup(basic_form);

        simulate_response(req, res, setup, form_state_string);
    }

    private void simulate_advanced(HTTPServerRequest req, HTTPServerResponse res)
    {
        //debug writeln(req.form.serializeToPrettyJson());

        auto advanced_form = create_form_from_fields!AdvancedForm(req.form);
        string form_state_string = serialize_form_to_url(advanced_form);
        SimulationSetup setup = to_simulation_setup(advanced_form);

        simulate_response(req, res, setup, form_state_string);
    }

    private void simulate_response(HTTPServerRequest req,		// Mostly for logging
                                   HTTPServerResponse res,
                                   ref const(SimulationSetup) setup,
                                   string form_state_string = "")
    {
        //writefln("Setup: %s", setup.serializeToPrettyJson());
        //writeln(form_state_string);

        auto simulation = new Simulation(setup);

        // Exhaustive search
        {
            auto sw = StopWatch(AutoStart.yes);

            simulation.simulate_attack();

            // NOTE: This is kinda similar to the access log, but convenient for now
            log_message("%s %s Simulated %d evaluations in %s msec",
                     req.peer,
                     req.path ~ "?q=" ~ form_state_string,
                     simulation.total_sum().evaluation_count, sw.peek().total!"msecs");
        }

        auto total_hits_pdf = simulation.total_hits_pdf();
        auto total_sum = simulation.total_sum();

        int max_hits = cast(int)total_hits_pdf.length;

        // Setup page content
        SimulationContent content;
        content.form_state_string = form_state_string;
        
        content.expected_total_hits = (total_sum.hits + total_sum.crits);
        content.at_least_one_crit = 100.0 * simulation.at_least_one_crit_probability();

        // Set up X labels on the total hits graph
        content.pdf_x_labels = new string[max_hits];
        foreach (i; 0 .. max_hits)
            content.pdf_x_labels[i] = to!string(i);

        // Compute PDF for graph
        content.hit_pdf     = new double[max_hits];
        content.crit_pdf    = new double[max_hits];
        content.hit_inv_cdf = new double[max_hits];
        foreach (i; 0 .. max_hits)
        {
            double total_probability = total_hits_pdf[i].hits + total_hits_pdf[i].crits;
            double fraction_crits = total_probability > 0.0 ? total_hits_pdf[i].crits / total_probability : 0.0;
            double fraction_hits  = 1.0 - fraction_crits;

            content.hit_pdf[i]  = 100.0 * fraction_hits  * total_hits_pdf[i].probability;
            content.crit_pdf[i] = 100.0 * fraction_crits * total_hits_pdf[i].probability;
        }

        // Compute inverse CDF P(at least X hits)
        content.hit_inv_cdf[max_hits-1] = content.hit_pdf[max_hits-1] + content.crit_pdf[max_hits-1];
        for (int i = max_hits-2; i >= 0; --i)
        {
            content.hit_inv_cdf[i] = content.hit_inv_cdf[i+1] + content.hit_pdf[i] + content.crit_pdf[i];
        }

        // Tokens (see labels above)
        content.exp_token_labels = ["Focus", "Target Lock", "Evade", "Stress"];
        content.exp_attack_tokens = [
            total_sum.attack_delta_focus_tokens,
            total_sum.attack_delta_target_locks,
            0.0f,
            total_sum.attack_delta_stress];
        content.exp_defense_tokens = [
            total_sum.defense_delta_focus_tokens,
            0.0f,
            total_sum.defense_delta_evade_tokens,
            total_sum.defense_delta_stress];

        res.writeJsonBody(content);
    }


    private void basic(HTTPServerRequest req, HTTPServerResponse res)
    {
        // Load values from URL if present
        string form_state_string = req.query.get("q", "");
        BasicForm form_values = create_form_from_url!BasicForm(form_state_string);
        res.render!("basic.dt", form_values);
    }

    private void advanced(HTTPServerRequest req, HTTPServerResponse res)
    {
        // Load values from URL if present
        string form_state_string = req.query.get("q", "");
        AdvancedForm form_values = create_form_from_url!AdvancedForm(form_state_string);
        res.render!("advanced.dt", form_values);
    }

    private void about(HTTPServerRequest req, HTTPServerResponse res)
    {
        res.render!("about.dt");
    }

    // *************************************** ERROR ************************************************

    private void error_page(HTTPServerRequest req, HTTPServerResponse res, HTTPServerErrorInfo error)
    {
        // To be extra safe we avoid DB queries in the error page for now
        //auto recent_tournaments = m_data_store.tournaments(true);

        res.render!("error.dt", req, error);
    }


    // *************************************** State ************************************************

    // NOTE: Be a bit careful with state here. These functions can be parallel and re-entrant due to
    // triggering blocking calls and then having other requests submitted by separate fibers.
}

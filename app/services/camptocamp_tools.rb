module CamptocampTools
  TOOLS = [
    {
      name: "search_routes",
      description: "Search for ski touring routes on Camptocamp.org within a specific French massif. " \
                   "Use this after analyzing the BERA to find routes that match the safe elevation " \
                   "bands and aspects you've identified. Returns a list of routes with IDs, titles, " \
                   "elevation, orientations, and ski difficulty rating.",
      input_schema: {
        type: "object",
        properties: {
          massif_name: {
            type: "string",
            enum: %w[chablais mont-blanc beaufortain vanoise belledonne oisans chartreuse],
            description: "The French massif to search within. Must match the massif named in the BERA."
          },
          elevation_max: {
            type: "integer",
            description: "Maximum summit elevation in meters. Set this to exclude routes that go above " \
                         "the safe elevation threshold identified in the BERA."
          },
          orientations: {
            type: "array",
            items: { type: "string", enum: %w[N NE E SE S SW W NW] },
            description: "Safe slope aspects to include. Omit aspects flagged as dangerous in the BERA."
          }
        },
        required: ["massif_name"]
      }
    },
    {
      name: "get_route_details",
      description: "Get full details for a specific Camptocamp route including its description, " \
                   "elevation profile, approach, descent aspects, and ski difficulty rating. " \
                   "Call this for promising routes from search_routes before recommending them.",
      input_schema: {
        type: "object",
        properties: {
          route_id: {
            type: "integer",
            description: "The Camptocamp route ID (document_id from search_routes results)."
          }
        },
        required: ["route_id"]
      }
    },
    {
      name: "search_recent_outings",
      description: "Search for recent trip reports (outings) on Camptocamp. " \
                   "Use this to check real recent snow conditions and stability observations. " \
                   "Filter by route_id for a specific route, or by massif_name for area-wide conditions.",
      input_schema: {
        type: "object",
        properties: {
          route_id: {
            type: "integer",
            description: "Return outings for this specific route ID."
          },
          massif_name: {
            type: "string",
            enum: %w[chablais mont-blanc beaufortain vanoise belledonne oisans chartreuse],
            description: "Return recent outings across this entire massif."
          }
        }
      }
    },
    {
      name: "get_outing_details",
      description: "Get full details of a specific trip report including snow quality observations, " \
                   "stability comments, hazards encountered, and participant notes. " \
                   "Call this for recent outings from search_recent_outings to assess actual conditions.",
      input_schema: {
        type: "object",
        properties: {
          outing_id: {
            type: "integer",
            description: "The Camptocamp outing ID (document_id from search_recent_outings results)."
          }
        },
        required: ["outing_id"]
      }
    },
    {
      name: "submit_recommendation",
      description: "Submit your final ski touring recommendation for today. Call this exactly once, " \
                   "after completing Steps 1-4, INSTEAD OF writing a plain-text answer — it is the only " \
                   "way to finish the analysis.",
      input_schema: {
        type: "object",
        properties: {
          conditions: {
            type: "string",
            description: "Summary of today's avalanche conditions: overall danger level and how it " \
                         "varies by elevation and aspect, specific hazards (wind slabs, persistent weak " \
                         "layers, wet snow, natural releases), and the massif/validity window from the BERA."
          },
          best_skiing: {
            type: "string",
            description: "Where the safest and best skiing is today: which elevation bands and aspects " \
                         "are favorable and why, timing considerations (e.g. wet-snow risk in the " \
                         "afternoon), and an overall recommendation. End with a one-line safety disclaimer " \
                         "noting this is a decision-support tool and field conditions take precedence."
          },
          routes: {
            type: "array",
            description: "3-5 recommended routes, ranked best first.",
            items: {
              type: "object",
              properties: {
                route_id: {
                  type: "integer",
                  description: "The Camptocamp route ID (document_id) from search_routes/get_route_details."
                },
                title: { type: "string", description: "The route's title." },
                rationale: {
                  type: "string",
                  description: "Why this route is appropriate today: elevation/aspect alignment with the " \
                               "BERA, precautions or timing, and what recent outings say about conditions " \
                               "(cite outing IDs and dates)."
                },
                elevation_summit: { type: "integer", description: "Summit elevation in meters." },
                orientations: {
                  type: "array",
                  items: { type: "string", enum: %w[N NE E SE S SW W NW] },
                  description: "The route's slope aspects."
                },
                difficulty: { type: "string", description: "Ski difficulty rating, e.g. \"3.2\"." }
              },
              required: ["route_id", "title", "rationale"]
            }
          }
        },
        required: ["conditions", "best_skiing", "routes"]
      }
    }
  ].freeze
end

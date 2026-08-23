# Ski Touring Advisor

A Ruby on Rails application that analyzes French BERA (Bulletin d'Estimation du Risque d'Avalanche) reports to recommend safe ski touring routes from Camptocamp.org.

## Overview

Get a BERA avalanche report — upload a PDF, fetch today's official bulletin, or fetch a specific past date — and an AI agent (Claude) analyzes it to determine safe elevation bands and aspects, then searches Camptocamp.org for ski touring routes that match current avalanche and snow conditions.

```
BERA sourced (upload / fetch today / fetch a date)
        ↓
AnalysisJob (background)
        ↓
BeraSeasonCheck — off-season bulletin? → skip straight to a "season's over" message
        ↓
AgentOrchestrator ⇄ Claude API (agent with tool use)
   ├── 1. Reads BERA PDF → extracts danger levels by elevation/aspect
   ├── 2. Determines safe elevation bands & orientations
   ├── 3. Calls Camptocamp API tools to search matching routes
   ├── 4. Checks recent outings for real conditions
   └── 5. Calls submit_recommendation (conditions, best_skiing, ranked routes)
        ↓
Analysis + RecommendedRoute rows persisted
        ↓
Results page polls (Stimulus + Turbo Frame) until done
```

## Architecture

### Approach: Direct Tool Use in Rails (No MCP Server)

Rather than a separate MCP server, Claude's native tool-use (function calling) is called directly from Rails:

1. Rails sends the BERA PDF + system prompt + tool definitions to the Claude API
2. Claude responds with tool calls (`search_routes`, `get_route_details`, `search_recent_outings`, `get_outing_details`)
3. Rails executes those tool calls against the Camptocamp REST API
4. Results go back to Claude to continue reasoning, up to `MAX_TURNS = 10`
5. Claude finishes by calling a mandatory `submit_recommendation` tool (never plain prose) — the orchestrator forces this via `tool_choice` if turns run out or Claude tries to answer in text
6. The system prompt, tool definitions, and trailing message content use prompt caching (`cache_control: ephemeral`) to keep the multi-turn loop cheap

### Repository Structure

```
ski_tour_advisor/
├── app/
│   ├── controllers/
│   │   └── analyses_controller.rb        # new/create (upload) + latest/historical (auto-fetch)
│   ├── jobs/
│   │   └── analysis_job.rb               # Runs the agent loop, persists results, catches errors
│   ├── models/
│   │   ├── analysis.rb                   # find_or_create_from_pdf; dedupes on [massif, bera_issued_at]
│   │   └── recommended_route.rb          # One row per recommended route
│   ├── services/
│   │   ├── agent_orchestrator.rb         # Claude tool-use loop + system prompt
│   │   ├── camptocamp_client.rb          # C2C REST API wrapper
│   │   ├── camptocamp_tools.rb           # Tool definitions incl. submit_recommendation
│   │   ├── bera_fetcher.rb               # Fetches today's or a historical BERA PDF
│   │   ├── bera_season_check.rb          # Detects the off-season placeholder PDF
│   │   └── bera_metadata_extractor.rb    # Extracts BERA's "Rédigé le" issued-at timestamp
│   ├── javascript/controllers/
│   │   └── poll_controller.js            # Stimulus: reloads results Turbo Frame every 3s
│   └── views/
│       └── analyses/
│           ├── new.html.erb              # Upload form + "use current" / "use this date"
│           ├── show.html.erb             # Polling Turbo Frame wrapper
│           └── _result.html.erb          # Conditions / best skiing / routes, by status
├── config/
│   └── initializers/
│       └── anthropic.rb                  # API client config
├── Gemfile
└── README.md
```

## Key Components

### Camptocamp API Client (`app/services/camptocamp_client.rb`)

Wraps the Camptocamp.org REST API (`https://api.camptocamp.org`) with Faraday.

| Method | Endpoint | Purpose |
|---|---|---|
| `search_routes` | `GET /routes` | Search ski touring routes by massif area, max elevation, orientations |
| `get_route` | `GET /routes/{id}` | Full route details (description, elevation, difficulty) |
| `search_outings` | `GET /outings` | Recent trip reports for a route or massif |
| `get_outing` | `GET /outings/{id}` | Full outing details (conditions, hazards, notes) |

Routes are filtered by C2C's `a=` (area) parameter, not a raw bounding box. `MASSIF_AREA_IDS` maps BERA massif names to their C2C area IDs:

```ruby
MASSIF_AREA_IDS = {
  "chablais"    => 14411,
  "mont-blanc"  => 14410,
  "beaufortain" => 14400,
  "vanoise"     => 14409,
  "belledonne"  => 14398,
  "oisans"      => 14403,  # "Écrins" on C2C
  "chartreuse"  => 14401,
}
```

### Claude Tool Definitions (`app/services/camptocamp_tools.rb`)

Five tools: `search_routes`, `get_route_details`, `search_recent_outings`, `get_outing_details`, and the mandatory closing tool `submit_recommendation`, whose input schema is the analysis's structured output — `conditions` (text), `best_skiing` (text), and `routes` (3-5 ranked entries with `route_id`, `title`, `rationale`, `elevation_summit`, `orientations`, `difficulty`). Claude must call `submit_recommendation` to finish; there is no plain-text end state.

### Agent Orchestrator (`app/services/agent_orchestrator.rb`)

Runs the tool-use loop (`call(bera_pdf_bytes)` → `{conditions:, best_skiing:, routes:, search_params:, turns:}`). The system prompt walks Claude through:

1. **Analyze the BERA** — danger level by elevation/aspect, specific hazards, massif and validity window
2. **Determine safe criteria** — which elevation + aspect combinations are acceptable; conservative by default
3. **Search for routes** — `search_routes` filtered by massif, safe max elevation, safe orientations; `get_route_details` on promising ones
4. **Check recent conditions** — `search_recent_outings` / `get_outing_details`, weighting reports under ~1 week old
5. **Submit the recommendation** — mandatory `submit_recommendation` call; the orchestrator forces this tool choice if `MAX_TURNS` is hit or Claude answers in prose instead

### BERA Sourcing

Three ways to get a bulletin into the app, all converging on `Analysis.find_or_create_from_pdf`:

- **Manual upload** — `POST /analyses` with a PDF
- **Current bulletin** — `POST /analyses/latest`, via `BeraFetcher#call_current`
- **Historical bulletin** — `POST /analyses/historical` with a `date`, via `BeraFetcher#call_for_date`

`BeraMetadataExtractor` cheaply regexes the BERA's own "Rédigé le mercredi 14 janvier 2026 à 16h" line (no Claude call) to get its true issued-at timestamp — Météo-France sometimes republishes an intraday revision, so this, not the calendar date, is the dedup key. `Analysis.find_or_create_from_pdf` looks up an existing row by `[massif, bera_issued_at]`: an unchanged bulletin reuses the existing analysis (no new agent run), a revised one gets a fresh analysis, and a previously failed analysis is retried in place.

`BeraSeasonCheck` detects the "La saison est terminée" placeholder PDF Météo-France publishes roughly May–October and lets `AnalysisJob` skip the agent loop entirely for a bulletin with nothing to analyze.

### Persistence

```ruby
class Analysis < ApplicationRecord
  has_one_attached :bera_pdf
  has_many :recommended_routes, -> { order(:rank) }, dependent: :destroy
  enum :status, { pending: "pending", processing: "processing", complete: "complete", failed: "failed" }
end
```

`AnalysisJob` persists `conditions`, `best_skiing`, `search_params`, and `turns` on the `Analysis`, plus one `RecommendedRoute` row per recommended route (rank, camptocamp_route_id, title, rationale, elevation_summit, orientations, difficulty). Errors are caught and persisted as `status: failed` with `error_message`, not re-raised.

### UI

The results page (`show.html.erb`) renders a Turbo Frame around `_result.html.erb`. While the analysis is `pending`/`processing`, the frame carries a `src` pointing back at itself and a Stimulus `poll` controller (`poll_controller.js`) that reloads it every 3 seconds; once `complete`/`failed` the `src` and controller are dropped and polling stops.

## Dependencies

**Gemfile additions:**

```ruby
gem "anthropic"        # Anthropic Ruby SDK
gem "faraday"          # HTTP client for C2C API + BeraFetcher
gem "pdf-reader"       # Parsing BERA PDF text (season check, metadata extraction)
gem "solid_queue"      # Background jobs
gem "turbo-rails"      # Turbo Frames for the results page
```

## Getting Started

```bash
# Clone and setup
git clone <repo-url>
cd ski_tour_advisor
bundle install
rails db:create db:migrate

# Set your Anthropic API key
export ANTHROPIC_API_KEY=sk-ant-...

# Start the server (Puma + Solid Queue worker)
bin/dev
```

Visit `/` (routes to `analyses#new`) to upload a BERA, fetch today's official bulletin, or fetch one for a specific date.

## Future Improvements

- **MCP server extraction:** If the Camptocamp tools become useful in other contexts (Claude Desktop, other apps), extract them into a standalone Ruby MCP server
- **Map visualization:** Display recommended routes on a map with elevation/aspect overlays
- **Multi-massif:** Allow analyzing multiple BERAs at once for a broader area
- **User preferences:** Let users filter/search routes by grade, difficulty, distance, or other personal criteria

## Safety Disclaimer

This tool is a decision-support aid for experienced ski tourers. It does not replace avalanche safety training, local knowledge, on-the-ground observation, or personal judgment. Always carry proper safety equipment (transceiver, probe, shovel), check conditions yourself, and make your own go/no-go decisions.

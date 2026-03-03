# Ski Touring Advisor

A Ruby on Rails application that analyzes French BERA (Bulletin d'Estimation du Risque d'Avalanche) reports to recommend safe ski touring routes from Camptocamp.org.

## Overview

Users upload a BERA avalanche report (PDF). An AI agent (Claude) analyzes the report to determine safe elevation bands and aspects, then searches Camptocamp.org for appropriate ski touring routes given current avalanche and snow conditions.

```
User uploads BERA PDF
        ↓
Rails App (orchestrator)
        ↓
Claude API (agent with tool use)
   ├── 1. Reads BERA PDF → extracts danger levels by elevation/aspect
   ├── 2. Determines safe elevation bands & orientations
   ├── 3. Calls Camptocamp API tools to search matching routes
   ├── 4. Checks recent outings for real conditions
   └── 5. Returns ranked route suggestions with reasoning
        ↓
Rails App displays suggestions to user
```

## Architecture

### Approach: Direct Tool Use in Rails (No MCP Server)

Rather than building a separate MCP server, we use Claude's native tool-use (function calling) directly from Rails. The Rails app:

1. Sends the BERA PDF + system prompt + tool definitions to the Claude API
2. Claude responds with tool calls (e.g., `search_routes`, `get_route_details`)
3. Rails executes those tool calls against the Camptocamp REST API
4. Sends results back to Claude to continue reasoning
5. Claude returns final route recommendations

This keeps everything in Ruby, avoids a separate server process, and can be refactored to MCP later if needed.

### Repository Structure

```
ski-touring-advisor/
├── app/
│   ├── controllers/
│   │   └── analyses_controller.rb      # Upload + display flow
│   ├── models/
│   │   └── analysis.rb                 # Stores BERA upload + results
│   ├── services/
│   │   ├── agent_orchestrator.rb       # Claude API tool-use loop
│   │   ├── camptocamp_client.rb        # C2C REST API wrapper
│   │   └── bera_tools.rb              # Tool definitions for Claude
│   └── views/
│       └── analyses/
│           ├── new.html.erb            # Upload form
│           └── show.html.erb           # Results display
├── config/
│   └── initializers/
│       └── anthropic.rb                # API client config
├── Gemfile
└── README.md
```

## Implementation Plan

### Phase 1: Camptocamp API Client

Build a Ruby client for the Camptocamp.org REST API (`https://api.camptocamp.org`).

**Key endpoints to wrap:**

| Endpoint | Purpose |
|----------|---------|
| `GET /search` | Search routes by area, activity type, elevation |
| `GET /routes/{id}` | Get full route details (description, geometry, etc.) |
| `GET /outings` | Search recent outings for conditions reports |
| `GET /outings/{id}` | Get specific outing details |
| `GET /waypoints/{id}` | Get waypoint info (summits, huts, etc.) |

**Key C2C search/filter parameters for routes:**

- `act`: Activity type → `skitouring`
- `bbox`: Geographic bounding box (lon_min,lat_min,lon_max,lat_max)
- `rmaxa` / `rmina`: Max/min route elevation
- `fac`: Orientations/aspects (N, NE, E, SE, S, SW, W, NW)
- `qa`: Quality ratings
- `limit` / `offset`: Pagination

**Example search URL:**
```
https://api.camptocamp.org/routes?act=skitouring&bbox=6.5,45.8,7.0,46.0&rmaxa=2200&fac=S,SW,W&limit=10
```

**Implementation (`app/services/camptocamp_client.rb`):**

```ruby
class CamptocampClient
  BASE_URL = "https://api.camptocamp.org"

  def search_routes(bbox:, elevation_max: nil, orientations: [], limit: 10)
    params = { act: "skitouring", bbox: bbox, limit: limit }
    params[:rmaxa] = elevation_max if elevation_max
    params[:fac] = orientations.join(",") if orientations.any?
    get("/routes", params)
  end

  def get_route(route_id)
    get("/routes/#{route_id}")
  end

  def search_outings(route_id: nil, bbox: nil, limit: 5)
    params = { limit: limit }
    params[:r] = route_id if route_id
    params[:bbox] = bbox if bbox
    get("/outings", params)
  end

  def get_outing(outing_id)
    get("/outings/#{outing_id}")
  end

  private

  def get(path, params = {})
    # Use Faraday or Net::HTTP
    # Returns parsed JSON
  end
end
```

**Deliverable:** A working Ruby class that can search and retrieve routes/outings from C2C. Test it manually in a Rails console before moving on.

### Phase 2: Claude Tool Definitions

Define the tools that Claude can call during the agent loop. These map directly to the `CamptocampClient` methods.

**Tool definitions (`app/services/bera_tools.rb`):**

```ruby
module BeraTools
  TOOLS = [
    {
      name: "search_routes",
      description: "Search for ski touring routes on Camptocamp.org within a geographic area. " \
                   "Use this to find routes that match safe elevation and aspect criteria " \
                   "determined from the BERA analysis.",
      input_schema: {
        type: "object",
        properties: {
          massif_name: {
            type: "string",
            description: "Name of the mountain massif (e.g., 'Chablais', 'Mont-Blanc', 'Beaufortain')"
          },
          elevation_max: {
            type: "integer",
            description: "Maximum summit elevation in meters. Use this to exclude routes " \
                         "that go above the safe elevation threshold."
          },
          orientations: {
            type: "array",
            items: { type: "string", enum: %w[N NE E SE S SW W NW] },
            description: "List of safe orientations/aspects to filter by."
          }
        },
        required: ["massif_name"]
      }
    },
    {
      name: "get_route_details",
      description: "Get full details for a specific Camptocamp route including description, " \
                   "elevation profile, difficulty, and access info.",
      input_schema: {
        type: "object",
        properties: {
          route_id: {
            type: "integer",
            description: "The Camptocamp route ID"
          }
        },
        required: ["route_id"]
      }
    },
    {
      name: "search_recent_outings",
      description: "Search for recent outings (trip reports) on Camptocamp. " \
                   "Use this to check real recent conditions on a specific route or in an area.",
      input_schema: {
        type: "object",
        properties: {
          route_id: {
            type: "integer",
            description: "Filter outings for a specific route ID"
          },
          massif_name: {
            type: "string",
            description: "Search outings in a specific massif area"
          }
        }
      }
    },
    {
      name: "get_outing_details",
      description: "Get full details of a specific outing including conditions report, " \
                   "snow quality, and participant observations.",
      input_schema: {
        type: "object",
        properties: {
          outing_id: {
            type: "integer",
            description: "The Camptocamp outing ID"
          }
        },
        required: ["outing_id"]
      }
    }
  ]
end
```

**Important: Massif → Bounding Box Mapping**

The BERA reports reference specific massifs. We need a lookup table to convert these to C2C geographic bounding boxes:

```ruby
MASSIF_BBOXES = {
  "chablais"    => "6.2,46.1,6.9,46.5",
  "mont-blanc"  => "6.7,45.7,7.1,46.0",
  "beaufortain" => "6.4,45.5,6.8,45.8",
  "vanoise"     => "6.6,45.2,7.1,45.5",
  "belledonne"  => "5.9,45.1,6.2,45.4",
  "oisans"      => "5.8,44.8,6.3,45.2",
  "chartreuse"  => "5.7,45.2,5.9,45.5",
  # ... etc for all BERA massifs
}
```

This mapping will be used by the tool execution layer when Claude calls `search_routes` with a massif name.

### Phase 3: Agent Orchestrator & System Prompt

The orchestrator manages the Claude API conversation loop.

**System Prompt:**

```
You are a ski touring safety advisor. You analyze French BERA (Bulletin d'Estimation du Risque
d'Avalanche) reports and recommend safe ski touring routes.

## Your Process

1. ANALYZE THE BERA
   - Extract the overall danger level (1-5) and how it varies by elevation and aspect
   - Identify the specific elevation thresholds where danger changes
   - Note the dangerous aspects/orientations at each elevation band
   - Identify specific hazards: wind slabs, persistent weak layers, wet snow, natural releases
   - Note the valid massif/geographic area and validity dates

2. DETERMINE SAFE CRITERIA
   - Based on the BERA, define which combinations of elevation + aspect have acceptable risk
   - Generally: avoid aspects and elevations rated 4 (Fort) or 5 (Très Fort)
   - Be conservative: when in doubt, restrict to lower-risk options
   - Consider time-of-day factors (e.g., wet snow risk increasing in afternoon on S aspects)

3. SEARCH FOR ROUTES
   - Use search_routes to find ski touring routes matching your safe criteria
   - Filter by the relevant massif, safe elevation max, and safe orientations
   - Get details on promising routes with get_route_details

4. CHECK RECENT CONDITIONS
   - Use search_recent_outings to find recent trip reports for recommended routes
   - Recent outings (< 1 week old) give valuable real-world conditions data
   - Note snow quality, stability observations, and any hazards encountered

5. MAKE RECOMMENDATIONS
   - Suggest 3-5 routes ranked by safety and quality
   - For each route explain:
     - Why it's appropriate given current conditions
     - What elevation range it covers and which aspects
     - Any specific precautions or timing considerations
     - What recent outings say about conditions (if available)
   - Include a clear safety disclaimer

## Important
- Always err on the side of caution
- If conditions are very dangerous (level 4-5 widespread), say so clearly and recommend
  staying home or very low-altitude alternatives
- All BERA content is in French — analyze it in French but respond in English (or French
  if the user writes in French)
- Always remind users this is a decision-support tool, not a substitute for their own
  avalanche safety training and judgment
```

**Orchestrator (`app/services/agent_orchestrator.rb`):**

```ruby
class AgentOrchestrator
  MAX_TURNS = 10

  def initialize(bera_pdf_data)
    @bera_pdf_data = bera_pdf_data
    @client = Anthropic::Client.new
    @camptocamp = CamptocampClient.new
    @messages = []
  end

  def run
    # Initial message with BERA PDF
    @messages << {
      role: "user",
      content: [
        {
          type: "document",
          source: {
            type: "base64",
            media_type: "application/pdf",
            data: Base64.strict_encode64(@bera_pdf_data)
          }
        },
        {
          type: "text",
          text: "Analyze this BERA and recommend safe ski touring routes."
        }
      ]
    }

    # Tool-use loop
    MAX_TURNS.times do
      response = @client.messages.create(
        model: "claude-sonnet-4-20250514",
        max_tokens: 4096,
        system: SYSTEM_PROMPT,
        tools: BeraTools::TOOLS,
        messages: @messages
      )

      # If Claude is done (no more tool calls), return the final text
      if response.stop_reason == "end_turn"
        return extract_text(response)
      end

      # Otherwise, execute tool calls and continue
      @messages << { role: "assistant", content: response.content }
      tool_results = execute_tool_calls(response.content)
      @messages << { role: "user", content: tool_results }
    end
  end

  private

  def execute_tool_calls(content)
    content.select { |block| block["type"] == "tool_use" }.map do |tool_call|
      result = case tool_call["name"]
               when "search_routes"
                 @camptocamp.search_routes(**tool_call["input"].symbolize_keys)
               when "get_route_details"
                 @camptocamp.get_route(tool_call["input"]["route_id"])
               when "search_recent_outings"
                 @camptocamp.search_outings(**tool_call["input"].symbolize_keys)
               when "get_outing_details"
                 @camptocamp.get_outing(tool_call["input"]["outing_id"])
               end

      {
        type: "tool_result",
        tool_use_id: tool_call["id"],
        content: result.to_json
      }
    end
  end

  def extract_text(response)
    response.content
      .select { |block| block["type"] == "text" }
      .map { |block| block["text"] }
      .join("\n")
  end
end
```

### Phase 4: Rails App — Upload & UI

**Controller flow:**

1. `GET /analyses/new` — upload form for BERA PDF
2. `POST /analyses` — receives PDF, kicks off agent orchestrator (consider using a background job for this since the agent loop may take 30-60 seconds)
3. `GET /analyses/:id` — displays results

**Model:**

```ruby
class Analysis < ApplicationRecord
  has_one_attached :bera_pdf
  # Columns: status (pending/processing/complete/error), result (text), massif (string)
end
```

**Key UI elements on the results page:**

- Summary of BERA analysis (danger levels, safe criteria)
- List of recommended routes with links to Camptocamp
- Agent's safety reasoning for each recommendation
- Clear safety disclaimer
- Option to download/share results

**Background processing (recommended):**

Since the agent loop involves multiple API calls and can take 30+ seconds, use Solid Queue or Sidekiq:

```ruby
class AnalysisJob < ApplicationJob
  def perform(analysis_id)
    analysis = Analysis.find(analysis_id)
    analysis.update(status: "processing")

    pdf_data = analysis.bera_pdf.download
    result = AgentOrchestrator.new(pdf_data).run

    analysis.update(status: "complete", result: result)
  rescue => e
    analysis.update(status: "error", result: e.message)
  end
end
```

Use Turbo Streams or polling to update the UI when processing completes.

## Dependencies

**Gemfile additions:**

```ruby
gem "anthropic"        # Anthropic Ruby SDK
gem "faraday"          # HTTP client for C2C API
gem "solid_queue"      # Background jobs (or sidekiq)
gem "turbo-rails"      # Hotwire for async UI updates
```

## Getting Started

```bash
# Clone and setup
git clone <repo-url>
cd ski-touring-advisor
bundle install
rails db:create db:migrate

# Set your Anthropic API key
export ANTHROPIC_API_KEY=sk-ant-...

# Start the server
bin/dev
```

## Build Order

1. **Phase 1:** Build and test `CamptocampClient` — verify you can search routes and outings via the C2C API in a Rails console
2. **Phase 2:** Define tool schemas in `BeraTools` and the massif → bounding box mapping
3. **Phase 3:** Build `AgentOrchestrator` — test with a real BERA PDF from Météo-France, iterate on the system prompt until results are good
4. **Phase 4:** Build the Rails UI — upload form, background job, results page with Turbo

## Future Improvements

- **MCP server extraction:** If the Camptocamp tools become useful in other contexts (Claude Desktop, other apps), extract them into a standalone Ruby MCP server
- **BERA auto-fetch:** Instead of manual PDF upload, automatically fetch today's BERA from Météo-France for a selected massif
- **Map visualization:** Display recommended routes on a map with elevation/aspect overlays
- **Historical tracking:** Store past analyses to track conditions over time
- **Multi-massif:** Allow analyzing multiple BERAs at once for a broader area
- **User preferences:** Filter by difficulty, distance, or other personal criteria

## Safety Disclaimer

This tool is a decision-support aid for experienced ski tourers. It does not replace avalanche safety training, local knowledge, on-the-ground observation, or personal judgment. Always carry proper safety equipment (transceiver, probe, shovel), check conditions yourself, and make your own go/no-go decisions.
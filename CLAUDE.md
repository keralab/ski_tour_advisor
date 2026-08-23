# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`ski_tour_advisor` is a Ruby on Rails application that analyzes French BERA (avalanche bulletin) PDFs and recommends safe ski touring routes from Camptocamp.org using Claude as an AI agent with tool use.

## Stack

- **Language/Runtime:** Ruby on Rails
- **AI:** Anthropic Ruby SDK (`anthropic` gem), model `claude-sonnet-5`
- **HTTP client:** Faraday (for Camptocamp API)
- **Background jobs:** Solid Queue (or Sidekiq)
- **Real-time UI:** Turbo/Hotwire

## Commands

```bash
bundle install       # Install gems
rails db:create db:migrate
bin/dev              # Start server (with background workers)
rails console        # Interactive console for testing services
```

## Key Files

- `app/services/camptocamp_client.rb` — Camptocamp REST API wrapper (Faraday); massif name → C2C area ID lookup (`MASSIF_AREA_IDS`, 7 massifs)
- `app/services/camptocamp_tools.rb` — Claude tool definitions, including the mandatory final `submit_recommendation` tool
- `app/services/agent_orchestrator.rb` — Claude agentic tool-use loop; forces `submit_recommendation` via `tool_choice` at `MAX_TURNS` or after a plain-text nudge; uses prompt caching (`cache_control` on system prompt, tools, and trailing message content)
- `app/services/bera_fetcher.rb` — Fetches the current official BERA or one for a specific date, instead of requiring manual upload
- `app/services/bera_season_check.rb` — Detects off-season BERA PDFs (May–Oct) so `AnalysisJob` can skip the agent loop entirely
- `app/services/bera_metadata_extractor.rb` — Regexes the BERA's "Rédigé le…" issued-at timestamp from page 1 (no Claude call) for cache-key dedup
- `app/models/analysis.rb` — `find_or_create_from_pdf` is the single entry point (manual upload, current, or historical); dedupes on `[massif, bera_issued_at]`; status enum pending/processing/complete/failed
- `app/models/recommended_route.rb` — belongs_to :analysis; one row per recommended route (rank, camptocamp_route_id, title, rationale, elevation_summit, orientations, difficulty)
- `app/jobs/analysis_job.rb` — Runs the agent, persists conditions/best_skiing/routes; errors are persisted (no re-raise), not raised
- `app/controllers/analyses_controller.rb` — `new`/`create` (manual upload) plus `latest`/`historical` collection actions that go through `BeraFetcher`
- `app/javascript/controllers/poll_controller.js` — Stimulus controller that reloads the results Turbo Frame every 3s while an analysis is pending/processing
- `config/initializers/anthropic.rb` — Anthropic API client config

## Environment Variables

- `ANTHROPIC_API_KEY` — required for Claude API calls

## Architecture Notes

- Claude is used in an agentic tool-use loop (not streaming): Rails sends BERA PDF + tool definitions, Claude makes tool calls, Rails executes them against the Camptocamp API, loop repeats up to `MAX_TURNS = 10`
- The loop always ends via a mandatory `submit_recommendation` tool call, never plain prose — the orchestrator forces this with `tool_choice` if Claude runs out of turns or tries to answer in text
- Prompt caching (`cache_control: ephemeral`) is used on the system prompt, tool definitions, and the trailing message content to keep the multi-turn loop cheap
- No MCP server — tool use is handled directly in Rails
- Agent loop can take 30–60s; runs in a background job (`AnalysisJob`); the results page polls via a Stimulus controller reloading a Turbo Frame every 3s (not Turbo Stream broadcasts)
- `Analysis.find_or_create_from_pdf` dedupes on `[massif, bera_issued_at]` (the BERA's own "Rédigé le" timestamp, extracted cheaply via `BeraMetadataExtractor`) so repeat requests for an unchanged bulletin reuse the existing analysis instead of re-running the agent; a previously failed analysis is retried in place
- `BeraSeasonCheck` detects the off-season "La saison est terminée" placeholder PDF Météo-France publishes May–Oct and short-circuits `AnalysisJob` before the agent loop runs
- BERA can be sourced three ways: manual PDF upload, `POST /analyses/latest` (fetches today's official bulletin via `BeraFetcher`), or `POST /analyses/historical` (fetches the bulletin for a specific past date)
- BERA reports are in French; Claude analyzes in French but responds in English (or French if user writes French)

## Build Status

All 4 phases are built (see README for the original phase breakdown): `CamptocampClient`, `CamptocampTools` + `AgentOrchestrator`, and the Rails UI. Since then: BERA auto-fetch (current/historical), off-season detection, intraday-revision-aware dedup/caching, and structured (non-prose) recommendation output have been added on top.

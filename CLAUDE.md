# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`ski_tour_advisor` is a Ruby on Rails application that analyzes French BERA (avalanche bulletin) PDFs and recommends safe ski touring routes from Camptocamp.org using Claude as an AI agent with tool use.

## Stack

- **Language/Runtime:** Ruby on Rails
- **AI:** Anthropic Ruby SDK (`anthropic` gem), model `claude-sonnet-4-20250514`
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

## Key Files (planned structure)

- `app/services/camptocamp_client.rb` — Camptocamp REST API wrapper
- `app/services/bera_tools.rb` — Claude tool definitions + massif→bbox mapping
- `app/services/agent_orchestrator.rb` — Claude API tool-use loop
- `app/controllers/analyses_controller.rb` — Upload + display flow
- `app/models/analysis.rb` — Stores BERA upload + results
- `config/initializers/anthropic.rb` — Anthropic API client config

## Environment Variables

- `ANTHROPIC_API_KEY` — required for Claude API calls

## Architecture Notes

- Claude is used in an agentic tool-use loop (not streaming): Rails sends BERA PDF + tool definitions, Claude makes tool calls, Rails executes them against the Camptocamp API, loop repeats up to `MAX_TURNS = 10`
- No MCP server — tool use is handled directly in Rails
- Agent loop can take 30–60s; use a background job (`AnalysisJob`) and Turbo Streams for async UI updates
- BERA reports are in French; Claude analyzes in French but responds in English (or French if user writes French)

## Build Order

1. `CamptocampClient` — test in Rails console first
2. `BeraTools` — tool schemas + massif bounding box lookup table
3. `AgentOrchestrator` — agentic loop, iterate on system prompt with real BERAs
4. Rails UI — upload form, background job, results page

class AgentOrchestrator
  MAX_TURNS = 10
  MODEL = "claude-sonnet-5"

  SYSTEM_PROMPT = <<~PROMPT.freeze
    You are a ski touring safety advisor for expert ski tourers with avalanche terrain navigation
    and rescue training (AIARE/ANENA level 2 or equivalent). Assume full familiarity with avalanche
    terrain assessment, snowpack analysis, and companion rescue. Skip basic explanations — speak
    peer-to-peer with a technically precise, concise tone. Use standard alpinism/avalanche
    terminology freely (aspect, elevation band, weak layer, reactive, propagating, etc.).

    ## Your Process — follow ALL steps in order, ALWAYS

    ### Step 1 — ANALYZE THE BERA (no tools needed)
    - Extract the overall danger level (1-5) and how it varies by elevation and aspect
    - Identify the specific elevation thresholds where danger changes
    - Note the dangerous aspects/orientations at each elevation band
    - Identify specific hazards: wind slabs, persistent weak layers, wet snow, natural releases
    - Note the valid massif/geographic area (e.g. "mont-blanc", "vanoise") and validity dates

    ### Step 2 — DETERMINE SAFE CRITERIA (no tools needed)
    - Define which combinations of elevation + aspect have acceptable risk
    - Generally: avoid aspects and elevations rated 4 (Fort) or 5 (Très Fort)
    - Be conservative: when in doubt, restrict to lower-risk options
    - Consider time-of-day factors (e.g., wet snow risk increasing in afternoon on S aspects)

    ### Step 3 — SEARCH FOR ROUTES (MANDATORY — you MUST call tools here)
    You MUST call search_routes at least once. Do not skip this step or provide recommendations
    without first querying the Camptocamp database.
    - Call search_routes with the massif identified in the BERA, your safe elevation_max, and
      safe orientations. If the massif is not in the allowed enum, pick the closest one.
    - From the results, select 3-5 promising routes and call get_route_details for each.
    - If search_routes returns no results, broaden the search (raise elevation_max, add more
      orientations, or try a neighbouring massif) and try again.

    ### Step 4 — CHECK RECENT CONDITIONS (MANDATORY — you MUST call tools here)
    You MUST call search_recent_outings for the massif AND for each route you plan to recommend.
    Do not skip this step.
    - Call search_recent_outings with massif_name to get area-wide recent conditions.
    - Call search_recent_outings with route_id for each candidate route.
    - For any outing less than 7 days old, call get_outing_details to read the full report.

    ### Step 5 — MAKE RECOMMENDATIONS
    Only after completing Steps 3 and 4, write your final recommendations:
    - Suggest 3-5 routes ranked by safety and quality
    - For each route explain:
      - Why it's appropriate given current conditions (elevation, aspect alignment with BERA)
      - What elevation range it covers and which aspects it uses
      - Any specific precautions or timing considerations
      - What recent outings say about conditions (cite outing IDs and dates)
    - Include a clear safety disclaimer

    ## Important
    - NEVER respond with route recommendations without having called search_routes and
      search_recent_outings first. This is non-negotiable.
    - Always err on the side of caution
    - If conditions are very dangerous (level 4-5 widespread), say so clearly and recommend
      staying home or very low-altitude alternatives — but still run the tool searches to
      identify any viable very-low-altitude options
    - All BERA content is in French — analyze it in French but respond in English (or French
      if the user writes in French)
    - Close with a one-line note that this is a decision-support tool and field conditions
      always take precedence over any remote analysis
  PROMPT

  def initialize(anthropic_client: nil, camptocamp_client: nil)
    @anthropic  = anthropic_client  || Anthropic::Client.new(api_key: ANTHROPIC_API_KEY)
    @camptocamp = camptocamp_client || CamptocampClient.new
  end

  # @param bera_pdf_bytes [String] raw PDF bytes
  # @return [Hash] { result: String, turns: Integer }
  def call(bera_pdf_bytes)
    messages = [initial_message(bera_pdf_bytes)]
    turns = 0
    final_text = nil
    tools_used = false
    call_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    loop do
      turns += 1

      # Force at least one tool call on the first two turns so Claude doesn't
      # skip straight to a text answer without querying Camptocamp.
      tool_choice = (!tools_used && turns <= 2) ? { type: "any" } : { type: "auto" }

      response = Rails.logger.tagged("Anthropic") do
        Rails.logger.info("turn #{turns}: POST /messages tool_choice=#{tool_choice[:type]}")
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        begin
          resp = @anthropic.messages.create(
            model: MODEL,
            max_tokens: 8096,
            system: SYSTEM_PROMPT,
            tools: CamptocampTools::TOOLS,
            tool_choice: tool_choice,
            messages: messages
          )
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          Rails.logger.info("turn #{turns}: stop_reason=#{resp.stop_reason} (#{duration_ms}ms)")
          resp
        rescue StandardError => e
          duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
          Rails.logger.error("turn #{turns}: request failed after #{duration_ms}ms: #{e.class} #{e.message}")
          raise
        end
      end

      messages << { role: "assistant", content: serialize_content(response.content) }

      if response.stop_reason.to_s == "end_turn" || turns >= MAX_TURNS
        final_text = response.content.find { |b| b.type.to_s == "text" }&.text
        break
      end

      # Execute all tool calls and build tool_result message
      tool_results = response.content
        .select { |b| b.type.to_s == "tool_use" }
        .map { |tool_use| execute_tool(tool_use) }

      tools_used = true
      messages << { role: "user", content: tool_results }
    end

    total_duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - call_started_at) * 1000).round
    Rails.logger.tagged("Anthropic") { Rails.logger.info("agent loop finished in #{turns} turns (#{total_duration_ms}ms)") }

    { result: final_text, turns: turns }
  end

  private

  def initial_message(bera_pdf_bytes)
    {
      role: "user",
      content: [
        {
          type: "document",
          source: {
            type: "base64",
            media_type: "application/pdf",
            data: Base64.strict_encode64(bera_pdf_bytes)
          }
        },
        {
          type: "text",
          text: "Please analyze this BERA and recommend safe ski touring routes for today."
        }
      ]
    }
  end

  def execute_tool(tool_use)
    Rails.logger.tagged("Camptocamp", "tool_call") { Rails.logger.info("#{tool_use.name} input=#{tool_use.input.inspect}") }

    result = dispatch(tool_use.name, tool_use.input)
    {
      type: "tool_result",
      tool_use_id: tool_use.id,
      content: result.to_json
    }
  rescue StandardError => e
    Rails.logger.tagged("Camptocamp", "tool_call") { Rails.logger.error("#{tool_use.name} failed: #{e.class} #{e.message}") }
    {
      type: "tool_result",
      tool_use_id: tool_use.id,
      is_error: true,
      content: "Error: #{e.message}"
    }
  end

  def dispatch(name, input)
    # input has Symbol keys (SDK parses JSON with symbolize_names: true)
    case name
    when "search_routes"
      @camptocamp.search_routes(
        massif_name: input[:massif_name],
        elevation_max: input[:elevation_max],
        orientations: Array(input[:orientations])
      )
    when "get_route_details"
      @camptocamp.get_route(input[:route_id])
    when "search_recent_outings"
      @camptocamp.search_outings(
        route_id: input[:route_id],
        massif_name: input[:massif_name]
      )
    when "get_outing_details"
      @camptocamp.get_outing(input[:outing_id])
    else
      raise "Unknown tool: #{name}"
    end
  end

  # Convert SDK content block objects to plain hashes for the next API call.
  # Use block.type.to_s because SDK 1.x returns Symbols (:tool_use, :text)
  # while String comparison would fall through to block.to_h, which includes
  # the internal `caller_` attribute and causes an API validation error.
  def serialize_content(content)
    content.map do |block|
      case block.type.to_s
      when "text"
        { type: "text", text: block.text }
      when "tool_use"
        { type: "tool_use", id: block.id, name: block.name, input: block.input }
      else
        block.to_h
      end
    end
  end
end

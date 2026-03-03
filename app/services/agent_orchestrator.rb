class AgentOrchestrator
  MAX_TURNS = 10
  MODEL = "claude-sonnet-4-20250514"

  SYSTEM_PROMPT = <<~PROMPT.freeze
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

    loop do
      turns += 1

      response = @anthropic.messages.create(
        model: MODEL,
        max_tokens: 8096,
        system: SYSTEM_PROMPT,
        tools: CamptocampTools::TOOLS,
        messages: messages
      )

      messages << { role: "assistant", content: serialize_content(response.content) }

      if response.stop_reason.to_s == "end_turn" || turns >= MAX_TURNS
        final_text = response.content.find { |b| b.type.to_s == "text" }&.text
        break
      end

      # Execute all tool calls and build tool_result message
      tool_results = response.content
        .select { |b| b.type.to_s == "tool_use" }
        .map { |tool_use| execute_tool(tool_use) }

      messages << { role: "user", content: tool_results }
    end

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
    result = dispatch(tool_use.name, tool_use.input)
    {
      type: "tool_result",
      tool_use_id: tool_use.id,
      content: result.to_json
    }
  rescue StandardError => e
    {
      type: "tool_result",
      tool_use_id: tool_use.id,
      is_error: true,
      content: "Error: #{e.message}"
    }
  end

  def dispatch(name, input)
    case name
    when "search_routes"
      @camptocamp.search_routes(
        massif_name: input["massif_name"],
        elevation_max: input["elevation_max"],
        orientations: Array(input["orientations"])
      )
    when "get_route_details"
      @camptocamp.get_route(input["route_id"])
    when "search_recent_outings"
      @camptocamp.search_outings(
        route_id: input["route_id"],
        massif_name: input["massif_name"]
      )
    when "get_outing_details"
      @camptocamp.get_outing(input["outing_id"])
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

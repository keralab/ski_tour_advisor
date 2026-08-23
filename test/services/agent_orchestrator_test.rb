require "test_helper"

class AgentOrchestratorTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Lightweight test doubles for Anthropic SDK response objects
  # ---------------------------------------------------------------------------

  FakeTextBlock    = Struct.new(:type, :text)
  FakeToolUseBlock = Struct.new(:type, :id, :name, :input)
  FakeUsage        = Struct.new(:input_tokens, :output_tokens, :cache_creation_input_tokens, :cache_read_input_tokens)
  FakeResponse     = Struct.new(:content, :stop_reason, :usage)

  # Captures all keyword-arg calls to #create and replays pre-set responses.
  class FakeMessages
    attr_reader :create_calls

    def initialize(*responses)
      @responses   = responses
      @create_calls = []
      @index       = 0
    end

    def create(**kwargs)
      # Snapshot the messages array so later mutations don't affect the record.
      @create_calls << kwargs.merge(messages: kwargs[:messages]&.dup)
      response = @responses[@index] || raise("Unexpected extra call to messages.create (index #{@index})")
      @index += 1
      response
    end
  end

  class FakeAnthropicClient
    attr_reader :messages

    def initialize(messages)
      @messages = messages
    end
  end

  # Records every call for later assertion.
  class FakeCamptocampClient
    attr_reader :calls

    def initialize
      @calls = []
    end

    def search_routes(**kwargs)
      @calls << [:search_routes, kwargs]
      { "documents" => [] }
    end

    def get_route(id)
      @calls << [:get_route, id]
      { "document_id" => id }
    end

    def search_outings(**kwargs)
      @calls << [:search_outings, kwargs]
      { "documents" => [] }
    end

    def get_outing(id)
      @calls << [:get_outing, id]
      { "document_id" => id }
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  setup do
    @fake_camptocamp = FakeCamptocampClient.new
  end

  # Builds an orchestrator whose internal clients are replaced by our fakes
  # via keyword-argument dependency injection.
  def build_orchestrator(fake_messages)
    AgentOrchestrator.new(
      anthropic_client:  FakeAnthropicClient.new(fake_messages),
      camptocamp_client: @fake_camptocamp
    )
  end

  def fake_usage
    FakeUsage.new(100, 50, 0, 0)
  end

  def submit_input(overrides = {})
    {
      conditions: "Danger 3 above 2200m.",
      best_skiing: "North faces below 2200m are safest.",
      routes: [
        { route_id: 111, title: "Route A", rationale: "Safe aspect and elevation.",
          elevation_summit: 2800, orientations: ["N"], difficulty: "3.1" }
      ]
    }.merge(overrides)
  end

  def submit_response(input = submit_input, id: "tu_submit")
    block = FakeToolUseBlock.new("tool_use", id, "submit_recommendation", input)
    FakeResponse.new([block], "tool_use", fake_usage)
  end

  def tool_use_response(tool_name, tool_id, input)
    block = FakeToolUseBlock.new("tool_use", tool_id, tool_name, input)
    FakeResponse.new([block], "tool_use", fake_usage)
  end

  def text_response(text = "Here are my recommendations.")
    FakeResponse.new([FakeTextBlock.new("text", text)], "end_turn", fake_usage)
  end

  # ---------------------------------------------------------------------------
  # 1. submit_recommendation on the first turn
  # ---------------------------------------------------------------------------

  test "returns structured recommendation and turn count when Claude submits on first turn" do
    messages     = FakeMessages.new(submit_response)
    orchestrator = build_orchestrator(messages)

    result = orchestrator.call("fake pdf bytes")

    assert_equal "Danger 3 above 2200m.", result[:conditions]
    assert_equal "North faces below 2200m are safest.", result[:best_skiing]
    assert_equal 1, result[:routes].length
    assert_equal 111, result[:routes].first[:route_id]
    assert_equal 1, result[:turns]
    assert_equal 0, @fake_camptocamp.calls.count
  end

  # ---------------------------------------------------------------------------
  # 2. One tool call then submit_recommendation
  # ---------------------------------------------------------------------------

  test "executes tool call, passes tool_result back, then returns the submitted recommendation" do
    input    = { massif_name: "vanoise", elevation_max: 2500, orientations: ["S", "SW"] }
    messages = FakeMessages.new(
      tool_use_response("search_routes", "tu_001", input),
      submit_response
    )
    orchestrator = build_orchestrator(messages)

    result = orchestrator.call("fake pdf bytes")

    assert_equal "Danger 3 above 2200m.", result[:conditions]
    assert_equal 2, result[:turns]
    assert_equal 1, @fake_camptocamp.calls.count
    assert_equal({ massif_name: "vanoise", elevation_max: 2500, orientations: ["S", "SW"] }, result[:search_params])

    # Verify the second API call included the tool_result in the messages list
    second_call_messages = messages.create_calls.last[:messages]
    tool_results_content = second_call_messages.last[:content]
    assert tool_results_content.any? { |tr| tr[:type] == "tool_result" && tr[:tool_use_id] == "tu_001" }
  end

  # ---------------------------------------------------------------------------
  # 3. Plain-text answer gets nudged into calling submit_recommendation
  # ---------------------------------------------------------------------------

  test "nudges Claude to call submit_recommendation when it answers in plain text" do
    messages = FakeMessages.new(
      text_response("Here's my analysis in prose."),
      submit_response
    )
    orchestrator = build_orchestrator(messages)

    result = orchestrator.call("fake pdf bytes")

    assert_equal "Danger 3 above 2200m.", result[:conditions]
    assert_equal 2, result[:turns]

    # The nudge turn forces tool_choice to submit_recommendation
    forced_tool_choice = messages.create_calls.last[:tool_choice]
    assert_equal({ type: "tool", name: "submit_recommendation" }, forced_tool_choice)

    # And the nudge message was appended for Claude to see
    second_call_messages = messages.create_calls.last[:messages]
    assert_includes second_call_messages.last[:content].first[:text], "submit_recommendation"
  end

  # ---------------------------------------------------------------------------
  # 4. MAX_TURNS forces submit_recommendation
  # ---------------------------------------------------------------------------

  test "forces submit_recommendation on the final turn so the loop always ends with structured output" do
    looping_response = tool_use_response("get_route_details", "tu_loop", { route_id: 42 })
    responses = Array.new(AgentOrchestrator::MAX_TURNS - 1, looping_response) + [submit_response]
    messages     = FakeMessages.new(*responses)
    orchestrator = build_orchestrator(messages)

    result = orchestrator.call("fake pdf bytes")

    assert_equal AgentOrchestrator::MAX_TURNS, result[:turns]
    assert_equal AgentOrchestrator::MAX_TURNS, messages.create_calls.count
    assert_equal({ type: "tool", name: "submit_recommendation" }, messages.create_calls.last[:tool_choice])
    assert_equal "Danger 3 above 2200m.", result[:conditions]
  end

  test "stops after MAX_TURNS even if Claude keeps calling other tools instead of submitting" do
    looping_response = tool_use_response("get_route_details", "tu_loop", { route_id: 42 })
    responses        = Array.new(AgentOrchestrator::MAX_TURNS, looping_response)
    messages         = FakeMessages.new(*responses)
    orchestrator     = build_orchestrator(messages)

    result = orchestrator.call("fake pdf bytes")

    assert_equal AgentOrchestrator::MAX_TURNS, result[:turns]
    assert_equal AgentOrchestrator::MAX_TURNS, messages.create_calls.count
    assert_nil result[:conditions]
    assert_equal [], result[:routes]
  end

  # ---------------------------------------------------------------------------
  # 5. Tool errors returned as is_error tool_result (not raised)
  # ---------------------------------------------------------------------------

  test "catches tool dispatch errors and sends is_error tool_result to Claude" do
    messages     = FakeMessages.new(
      tool_use_response("nonexistent_tool", "tu_bad", {}),
      submit_response
    )
    orchestrator = build_orchestrator(messages)

    # Should not raise — errors are handled inside execute_tool
    result = orchestrator.call("fake pdf bytes")

    assert_equal 2, result[:turns]

    # The second API call's message list must include an is_error tool_result
    second_call_messages = messages.create_calls.last[:messages]
    tool_results_content = second_call_messages.last[:content]
    error_result = tool_results_content.find { |tr| tr[:is_error] == true }
    assert error_result, "Expected an is_error tool_result but found none"
    assert_includes error_result[:content], "Unknown tool"
  end

  # ---------------------------------------------------------------------------
  # 6. Dispatch — each tool name routes to the correct CamptocampClient method
  # ---------------------------------------------------------------------------

  test "dispatches search_routes to CamptocampClient#search_routes" do
    input        = { massif_name: "oisans", elevation_max: 3000, orientations: ["N", "NE"] }
    messages     = FakeMessages.new(tool_use_response("search_routes", "tu1", input), submit_response)
    orchestrator = build_orchestrator(messages)

    orchestrator.call("pdf")

    assert_equal 1, @fake_camptocamp.calls.count
    method, kwargs = @fake_camptocamp.calls.first
    assert_equal :search_routes, method
    assert_equal "oisans",     kwargs[:massif_name]
    assert_equal 3000,         kwargs[:elevation_max]
    assert_equal ["N", "NE"], kwargs[:orientations]
  end

  test "dispatches get_route_details to CamptocampClient#get_route" do
    messages     = FakeMessages.new(tool_use_response("get_route_details", "tu2", { route_id: 123 }), submit_response)
    orchestrator = build_orchestrator(messages)

    orchestrator.call("pdf")

    assert_equal [[:get_route, 123]], @fake_camptocamp.calls
  end

  test "dispatches search_recent_outings to CamptocampClient#search_outings" do
    input        = { route_id: 456 }
    messages     = FakeMessages.new(tool_use_response("search_recent_outings", "tu3", input), submit_response)
    orchestrator = build_orchestrator(messages)

    orchestrator.call("pdf")

    assert_equal 1, @fake_camptocamp.calls.count
    method, kwargs = @fake_camptocamp.calls.first
    assert_equal :search_outings, method
    assert_equal 456, kwargs[:route_id]
  end

  test "dispatches get_outing_details to CamptocampClient#get_outing" do
    messages     = FakeMessages.new(tool_use_response("get_outing_details", "tu4", { outing_id: 789 }), submit_response)
    orchestrator = build_orchestrator(messages)

    orchestrator.call("pdf")

    assert_equal [[:get_outing, 789]], @fake_camptocamp.calls
  end
end

require "test_helper"

class CamptocampToolsTest < ActiveSupport::TestCase
  EXPECTED_TOOL_NAMES = %w[search_routes get_route_details search_recent_outings get_outing_details submit_recommendation].freeze
  MASSIF_ENUM = CamptocampClient::MASSIF_AREA_IDS.keys.freeze

  test "TOOLS is an array of 5 hashes" do
    assert_instance_of Array, CamptocampTools::TOOLS
    assert_equal 5, CamptocampTools::TOOLS.length
    CamptocampTools::TOOLS.each { |t| assert_instance_of Hash, t }
  end

  test "each tool has required keys" do
    CamptocampTools::TOOLS.each do |tool|
      assert tool.key?(:name), "Tool missing :name"
      assert tool.key?(:description), "Tool missing :description"
      assert tool.key?(:input_schema), "Tool missing :input_schema"
    end
  end

  test "tool names match expected set" do
    names = CamptocampTools::TOOLS.map { |t| t[:name] }
    assert_equal EXPECTED_TOOL_NAMES, names
  end

  test "search_routes massif_name enum matches MASSIF_AREA_IDS keys" do
    tool = CamptocampTools::TOOLS.find { |t| t[:name] == "search_routes" }
    enum = tool[:input_schema][:properties][:massif_name][:enum]
    assert_equal MASSIF_ENUM.sort, enum.sort
  end

  test "search_recent_outings massif_name enum matches MASSIF_AREA_IDS keys" do
    tool = CamptocampTools::TOOLS.find { |t| t[:name] == "search_recent_outings" }
    enum = tool[:input_schema][:properties][:massif_name][:enum]
    assert_equal MASSIF_ENUM.sort, enum.sort
  end

  test "search_routes requires massif_name" do
    tool = CamptocampTools::TOOLS.find { |t| t[:name] == "search_routes" }
    assert_equal ["massif_name"], tool[:input_schema][:required]
  end

  test "get_route_details requires route_id" do
    tool = CamptocampTools::TOOLS.find { |t| t[:name] == "get_route_details" }
    assert_equal ["route_id"], tool[:input_schema][:required]
  end

  test "search_recent_outings has no required fields" do
    tool = CamptocampTools::TOOLS.find { |t| t[:name] == "search_recent_outings" }
    assert_nil tool[:input_schema][:required]
  end

  test "get_outing_details requires outing_id" do
    tool = CamptocampTools::TOOLS.find { |t| t[:name] == "get_outing_details" }
    assert_equal ["outing_id"], tool[:input_schema][:required]
  end

  test "submit_recommendation requires conditions, best_skiing, and routes" do
    tool = CamptocampTools::TOOLS.find { |t| t[:name] == "submit_recommendation" }
    assert_equal %w[conditions best_skiing routes], tool[:input_schema][:required]
  end

  test "submit_recommendation routes items require route_id, title, and rationale" do
    tool = CamptocampTools::TOOLS.find { |t| t[:name] == "submit_recommendation" }
    assert_equal %w[route_id title rationale], tool[:input_schema][:properties][:routes][:items][:required]
  end
end

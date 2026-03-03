require "test_helper"
require "webmock/minitest"

class CamptocampClientTest < ActiveSupport::TestCase
  BASE_URL = "https://api.camptocamp.org"

  setup do
    @client = CamptocampClient.new
  end

  # ---------------------------------------------------------------------------
  # search_routes
  # ---------------------------------------------------------------------------

  test "search_routes sends skitouring activity and vanoise area_id" do
    stub = stub_get("/routes", { act: "skitouring", a: 14409, limit: 10 }, routes_payload(3))

    result = @client.search_routes(massif_name: "vanoise")

    assert_requested stub
    assert_equal 3, result["documents"].count
  end

  test "search_routes is case-insensitive for massif name" do
    stub = stub_get("/routes", { act: "skitouring", a: 14409, limit: 10 }, routes_payload(1))

    @client.search_routes(massif_name: "Vanoise")

    assert_requested stub
  end

  test "search_routes adds rmaxa when elevation_max is given" do
    stub = stub_get("/routes", { act: "skitouring", a: 14409, limit: 10, rmaxa: 2500 }, routes_payload(2))

    @client.search_routes(massif_name: "vanoise", elevation_max: 2500)

    assert_requested stub
  end

  test "search_routes adds fac when orientations are given" do
    stub = stub_get("/routes", { act: "skitouring", a: 14409, limit: 10, fac: "S,SW,W" }, routes_payload(2))

    @client.search_routes(massif_name: "vanoise", orientations: ["S", "SW", "W"])

    assert_requested stub
  end

  test "search_routes omits fac when orientations list is empty" do
    stub = stub_get("/routes", { act: "skitouring", a: 14409, limit: 10 }, routes_payload(1))

    @client.search_routes(massif_name: "vanoise", orientations: [])

    assert_requested stub
  end

  test "search_routes respects custom limit" do
    stub = stub_get("/routes", { act: "skitouring", a: 14409, limit: 5 }, routes_payload(5))

    @client.search_routes(massif_name: "vanoise", limit: 5)

    assert_requested stub
  end

  test "search_routes uses correct area_id for each massif" do
    CamptocampClient::MASSIF_AREA_IDS.each do |massif, area_id|
      stub = stub_get("/routes", { act: "skitouring", a: area_id, limit: 10 }, routes_payload(1))
      @client.search_routes(massif_name: massif)
      assert_requested stub, message: "Wrong area_id for #{massif}"
    end
  end

  test "search_routes raises KeyError for unknown massif" do
    assert_raises(KeyError) { @client.search_routes(massif_name: "atlantis") }
  end

  test "search_routes returns parsed JSON" do
    stub_get("/routes", { act: "skitouring", a: 14409, limit: 10 }, routes_payload(2))

    result = @client.search_routes(massif_name: "vanoise")

    assert_instance_of Hash, result
    assert_equal 2, result["total"]
    assert_equal 2, result["documents"].length
  end

  # ---------------------------------------------------------------------------
  # get_route
  # ---------------------------------------------------------------------------

  test "get_route calls the correct URL" do
    stub = stub_get("/routes/123456", {}, route_detail_payload(123456))

    @client.get_route(123456)

    assert_requested stub
  end

  test "get_route returns parsed JSON" do
    stub_get("/routes/123456", {}, route_detail_payload(123456))

    result = @client.get_route(123456)

    assert_instance_of Hash, result
    assert_equal 123456, result["document_id"]
  end

  # ---------------------------------------------------------------------------
  # search_outings
  # ---------------------------------------------------------------------------

  test "search_outings with route_id sends r param" do
    stub = stub_get("/outings", { r: 99999, limit: 5 }, outings_payload(2))

    @client.search_outings(route_id: 99999)

    assert_requested stub
  end

  test "search_outings with massif_name sends area_id" do
    stub = stub_get("/outings", { a: 14398, limit: 5 }, outings_payload(3))

    @client.search_outings(massif_name: "belledonne")

    assert_requested stub
  end

  test "search_outings with no filters sends only limit" do
    stub = stub_get("/outings", { limit: 5 }, outings_payload(0))

    @client.search_outings

    assert_requested stub
  end

  test "search_outings prefers route_id over massif_name when both given" do
    stub = stub_get("/outings", { r: 77777, limit: 5 }, outings_payload(1))

    @client.search_outings(route_id: 77777, massif_name: "vanoise")

    assert_requested stub
  end

  test "search_outings respects custom limit" do
    stub = stub_get("/outings", { limit: 3 }, outings_payload(3))

    @client.search_outings(limit: 3)

    assert_requested stub
  end

  test "search_outings raises KeyError for unknown massif" do
    assert_raises(KeyError) { @client.search_outings(massif_name: "atlantis") }
  end

  test "search_outings returns parsed JSON" do
    stub_get("/outings", { limit: 5 }, outings_payload(2))

    result = @client.search_outings

    assert_instance_of Hash, result
    assert_equal 2, result["documents"].length
  end

  # ---------------------------------------------------------------------------
  # get_outing
  # ---------------------------------------------------------------------------

  test "get_outing calls the correct URL" do
    stub = stub_get("/outings/555", {}, outing_detail_payload(555))

    @client.get_outing(555)

    assert_requested stub
  end

  test "get_outing returns parsed JSON" do
    stub_get("/outings/555", {}, outing_detail_payload(555))

    result = @client.get_outing(555)

    assert_instance_of Hash, result
    assert_equal 555, result["document_id"]
  end

  # ---------------------------------------------------------------------------
  # HTTP error handling
  # ---------------------------------------------------------------------------

  test "raises Faraday::Error on HTTP 404" do
    stub_request(:get, /api\.camptocamp\.org\/routes\/0/)
      .to_return(status: 404, body: '{"errors":[{"status":"404"}]}')

    assert_raises(Faraday::Error) { @client.get_route(0) }
  end

  test "raises Faraday::Error on HTTP 500" do
    stub_request(:get, /api\.camptocamp\.org\/routes/)
      .to_return(status: 500, body: "Internal Server Error")

    assert_raises(Faraday::Error) { @client.search_routes(massif_name: "vanoise") }
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  private

  def stub_get(path, params, response_body)
    stub_request(:get, "#{BASE_URL}#{path}")
      .with(query: params.transform_values(&:to_s))
      .to_return(status: 200, body: response_body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def routes_payload(count)
    docs = count.times.map { |i| { "document_id" => i + 1, "locales" => [ { "title" => "Route #{i + 1}" } ] } }
    { "total" => count, "documents" => docs }
  end

  def route_detail_payload(id)
    {
      "document_id" => id,
      "activities"  => [ "skitouring" ],
      "locales"     => [ { "title" => "Test Route" } ],
      "elevation_max" => 2400,
      "orientations"  => [ "S" ]
    }
  end

  def outings_payload(count)
    docs = count.times.map { |i| { "document_id" => i + 100, "date" => "2026-02-#{i + 1}" } }
    { "total" => count, "documents" => docs }
  end

  def outing_detail_payload(id)
    {
      "document_id" => id,
      "date"        => "2026-02-15",
      "locales"     => [ { "description" => "Good conditions" } ]
    }
  end
end

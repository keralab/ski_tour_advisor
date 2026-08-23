require "test_helper"
require "webmock/minitest"

class BeraFetcherTest < ActiveSupport::TestCase
  CURRENT_URL    = "https://en.chamonix.com/bulletin-avalanche/BRA_MONT-BLANC.pdf"
  HISTORICAL_URL = "https://chamonix-meteo.com/snow/avalanche"

  setup do
    @fetcher = BeraFetcher.new
  end

  # ---------------------------------------------------------------------------
  # call_current
  # ---------------------------------------------------------------------------

  test "call_current returns the always-up-to-date bulletin" do
    stub_pdf(CURRENT_URL, "%PDF current")

    result = @fetcher.call_current

    assert_equal "%PDF current", result.pdf_bytes
    assert_equal "BRA_MONT-BLANC.pdf", result.filename
    assert_nil result.released_on
  end

  test "call_current returns nil when the bulletin is unavailable" do
    stub_missing(CURRENT_URL)

    assert_nil @fetcher.call_current
  end

  test "call_current raises on unexpected HTTP errors" do
    stub_request(:get, CURRENT_URL).to_return(status: 500, body: "Internal Server Error")

    assert_raises(Faraday::Error) { @fetcher.call_current }
  end

  # ---------------------------------------------------------------------------
  # call_for_date
  # ---------------------------------------------------------------------------

  test "call_for_date fetches the bulletin released the day before the given date" do
    stub_pdf("#{HISTORICAL_URL}/BRA2601181600.pdf", "%PDF historical")

    result = @fetcher.call_for_date(Date.new(2026, 1, 19))

    assert_equal "%PDF historical", result.pdf_bytes
    assert_equal "BRA2601181600.pdf", result.filename
    assert_equal Date.new(2026, 1, 18), result.released_on
  end

  test "call_for_date returns nil when nothing was released for that date" do
    stub_missing("#{HISTORICAL_URL}/BRA2601181600.pdf")

    assert_nil @fetcher.call_for_date(Date.new(2026, 1, 19))
  end

  test "call_for_date raises on unexpected HTTP errors" do
    stub_request(:get, "#{HISTORICAL_URL}/BRA2601181600.pdf")
      .to_return(status: 500, body: "Internal Server Error")

    assert_raises(Faraday::Error) { @fetcher.call_for_date(Date.new(2026, 1, 19)) }
  end

  private

  def stub_pdf(url, body)
    stub_request(:get, url)
      .to_return(status: 200, body: body, headers: { "Content-Type" => "application/pdf" })
  end

  def stub_missing(url)
    stub_request(:get, url).to_return(status: 404, body: "Not Found")
  end
end

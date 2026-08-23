require "test_helper"
require "minitest/mock"

class AnalysesControllerTest < ActionDispatch::IntegrationTest
  # ---------------------------------------------------------------------------
  # latest
  # ---------------------------------------------------------------------------

  test "latest creates and enqueues an analysis when a BERA is currently available" do
    fetched = BeraFetcher::Result.new(
      pdf_bytes: "%PDF-1.4 fake", filename: "BRA_MONT-BLANC.pdf", released_on: nil
    )
    fetcher = Object.new
    fetcher.define_singleton_method(:call_current) { fetched }

    assert_enqueued_with(job: AnalysisJob) do
      BeraFetcher.stub(:new, -> { fetcher }) do
        post latest_analyses_path
      end
    end

    analysis = Analysis.order(:created_at).last
    assert_redirected_to analysis_path(analysis)
    assert analysis.bera_pdf.attached?
    assert_equal "BRA_MONT-BLANC.pdf", analysis.bera_pdf.filename.to_s
  end

  test "latest redirects with an alert when no BERA is currently available" do
    fetcher = Object.new
    fetcher.define_singleton_method(:call_current) { nil }

    BeraFetcher.stub(:new, -> { fetcher }) do
      post latest_analyses_path
    end

    assert_redirected_to new_analysis_path
    assert_equal "No BERA currently available.", flash[:alert]
  end

  # ---------------------------------------------------------------------------
  # historical
  # ---------------------------------------------------------------------------

  test "historical creates and enqueues an analysis for the given date" do
    fetched = BeraFetcher::Result.new(
      pdf_bytes: "%PDF-1.4 fake", filename: "BRA2601181600.pdf", released_on: Date.new(2026, 1, 18)
    )
    fetcher = Object.new
    fetcher.define_singleton_method(:call_for_date) { |date| date == Date.new(2026, 1, 19) ? fetched : nil }

    assert_enqueued_with(job: AnalysisJob) do
      BeraFetcher.stub(:new, -> { fetcher }) do
        post historical_analyses_path, params: { date: "2026-01-19" }
      end
    end

    analysis = Analysis.order(:created_at).last
    assert_redirected_to analysis_path(analysis)
    assert analysis.bera_pdf.attached?
    assert_equal "BRA2601181600.pdf", analysis.bera_pdf.filename.to_s
  end

  test "historical redirects with an alert when no BERA was released for that date" do
    fetcher = Object.new
    fetcher.define_singleton_method(:call_for_date) { |_date| nil }

    BeraFetcher.stub(:new, -> { fetcher }) do
      post historical_analyses_path, params: { date: "2026-07-19" }
    end

    assert_redirected_to new_analysis_path
    assert_equal "No BERA available for 2026-07-19.", flash[:alert]
  end

  test "historical redirects with an alert when the date is invalid" do
    post historical_analyses_path, params: { date: "not-a-date" }

    assert_redirected_to new_analysis_path
    assert_equal "Please choose a valid date.", flash[:alert]
  end

  test "historical redirects with an alert when the date is blank" do
    post historical_analyses_path, params: { date: "" }

    assert_redirected_to new_analysis_path
    assert_equal "Please choose a valid date.", flash[:alert]
  end
end

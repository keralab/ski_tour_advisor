require "test_helper"
require "minitest/mock"

class AnalysisJobTest < ActiveJob::TestCase
  setup do
    @analysis = Analysis.new(status: :pending)
    @analysis.bera_pdf.attach(
      io: StringIO.new("%PDF-1.4 fake"),
      filename: "bera.pdf",
      content_type: "application/pdf"
    )
    @analysis.save!
  end

  test "transitions to processing then complete on success, persisting conditions/best_skiing/routes/search_params" do
    result_data = {
      conditions: "Danger 3 above 2200m.",
      best_skiing: "North faces below 2200m are safest.",
      routes: [
        { route_id: 111, title: "Route A", rationale: "Safe today.",
          elevation_summit: 2800, orientations: ["N"], difficulty: "3.1" },
        { route_id: 222, title: "Route B", rationale: "Also safe.",
          elevation_summit: 2600, orientations: ["N", "NE"], difficulty: "2.3" }
      ],
      search_params: { massif_name: "mont-blanc", elevation_max: 2800, orientations: ["N", "NE"] },
      turns: 3
    }
    orchestrator = Object.new
    orchestrator.define_singleton_method(:call) { |_pdf_bytes| result_data }

    AgentOrchestrator.stub(:new, -> { orchestrator }) do
      AnalysisJob.perform_now(@analysis.id)
    end

    @analysis.reload
    assert @analysis.complete?
    assert_equal "Danger 3 above 2200m.", @analysis.conditions
    assert_equal "North faces below 2200m are safest.", @analysis.best_skiing
    assert_equal({ "massif_name" => "mont-blanc", "elevation_max" => 2800, "orientations" => ["N", "NE"] }, @analysis.search_params)
    assert_equal 3, @analysis.turns

    assert_equal 2, @analysis.recommended_routes.count
    first, second = @analysis.recommended_routes.order(:rank)
    assert_equal 1, first.rank
    assert_equal 111, first.camptocamp_route_id
    assert_equal "Route A", first.title
    assert_equal 2, second.rank
    assert_equal 222, second.camptocamp_route_id
  end

  test "transitions to failed when AgentOrchestrator raises" do
    orchestrator = Object.new
    orchestrator.define_singleton_method(:call) { |_| raise "API error" }

    AgentOrchestrator.stub(:new, -> { orchestrator }) do
      AnalysisJob.perform_now(@analysis.id)
    end

    @analysis.reload
    assert @analysis.failed?
    assert_equal "API error", @analysis.error_message
  end

  test "logs the failure when the job raises" do
    orchestrator = Object.new
    orchestrator.define_singleton_method(:call) { |_| raise "API error" }

    log_output = StringIO.new
    original_logger = Rails.logger
    Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new(log_output))

    begin
      AgentOrchestrator.stub(:new, -> { orchestrator }) do
        AnalysisJob.perform_now(@analysis.id)
      end
    ensure
      Rails.logger = original_logger
    end

    logged = log_output.string
    assert_includes logged, "analysis_id=#{@analysis.id}"
    assert_includes logged, "API error"
  end

  test "transitions to failed when analysis not found" do
    assert_nothing_raised do
      AnalysisJob.perform_now(-1)
    end
  end

  test "skips the agent orchestrator and completes immediately for an off-season BERA" do
    @analysis.bera_pdf.attach(
      io: file_fixture("bera_off_season.pdf").open,
      filename: "bera_off_season.pdf",
      content_type: "application/pdf"
    )
    @analysis.save!

    orchestrator = Object.new
    orchestrator.define_singleton_method(:call) { |_| raise "AgentOrchestrator should not be called off-season" }

    AgentOrchestrator.stub(:new, -> { orchestrator }) do
      AnalysisJob.perform_now(@analysis.id)
    end

    @analysis.reload
    assert @analysis.complete?
    assert_equal BeraSeasonCheck::MESSAGE, @analysis.conditions
    assert_equal 0, @analysis.turns
    assert_equal 0, @analysis.recommended_routes.count
  end
end

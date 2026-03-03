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

  test "transitions to processing then complete on success" do
    result_data = { result: "Go ski route A.", turns: 3 }
    orchestrator = Object.new
    orchestrator.define_singleton_method(:call) { |_pdf_bytes| result_data }

    AgentOrchestrator.stub(:new, -> { orchestrator }) do
      AnalysisJob.perform_now(@analysis.id)
    end

    @analysis.reload
    assert @analysis.complete?
    assert_equal "Go ski route A.", @analysis.result
    assert_equal 3, @analysis.turns
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

  test "transitions to failed when analysis not found" do
    assert_nothing_raised do
      AnalysisJob.perform_now(-1)
    end
  end
end

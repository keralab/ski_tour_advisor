require "test_helper"

class AnalysisTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "default status is pending" do
    analysis = Analysis.new
    assert_equal "pending", analysis.status
  end

  test "status enum has all expected values" do
    assert_equal %w[pending processing complete failed], Analysis.statuses.keys
  end

  test "done? returns false for pending" do
    analysis = Analysis.new(status: :pending)
    assert_not analysis.done?
  end

  test "done? returns false for processing" do
    analysis = Analysis.new(status: :processing)
    assert_not analysis.done?
  end

  test "done? returns true for complete" do
    analysis = Analysis.new(status: :complete)
    assert analysis.done?
  end

  test "done? returns true for failed" do
    analysis = Analysis.new(status: :failed)
    assert analysis.done?
  end

  test "invalid without bera_pdf attachment" do
    analysis = Analysis.new
    assert_not analysis.valid?
    assert_includes analysis.errors[:bera_pdf], "must be attached"
  end

  test "invalid with non-PDF attachment" do
    analysis = Analysis.new
    analysis.bera_pdf.attach(
      io: StringIO.new("not a pdf"),
      filename: "test.txt",
      content_type: "text/plain"
    )
    assert_not analysis.valid?
    assert_includes analysis.errors[:bera_pdf], "must be a PDF file"
  end

  test "valid with PDF attachment" do
    analysis = Analysis.new
    analysis.bera_pdf.attach(
      io: StringIO.new("%PDF-1.4 fake content"),
      filename: "bera.pdf",
      content_type: "application/pdf"
    )
    assert analysis.valid?
  end

  test "defaults to the mont-blanc massif" do
    assert_equal "mont-blanc", Analysis.new.massif
  end

  # ---------------------------------------------------------------------------
  # find_or_create_from_pdf
  # ---------------------------------------------------------------------------

  def stub_issued_at(time_or_nil, &block)
    BeraMetadataExtractor.stub(:issued_at, time_or_nil, &block)
  end

  test "find_or_create_from_pdf creates a new analysis and enqueues a job when none exists yet" do
    issued_at = ActiveSupport::TimeZone["Europe/Paris"].local(2026, 1, 14, 16, 0)

    assert_enqueued_with(job: AnalysisJob) do
      stub_issued_at(issued_at) do
        @analysis = Analysis.find_or_create_from_pdf("%PDF-1.4 fake", filename: "bera.pdf")
      end
    end

    assert @analysis.persisted?
    assert_equal "mont-blanc", @analysis.massif
    assert_equal issued_at, @analysis.bera_issued_at
  end

  test "find_or_create_from_pdf reuses an existing analysis for the same massif and issued_at" do
    issued_at = ActiveSupport::TimeZone["Europe/Paris"].local(2026, 1, 14, 16, 0)

    existing = stub_issued_at(issued_at) { Analysis.find_or_create_from_pdf("%PDF-1.4 fake", filename: "bera.pdf") }

    assert_no_enqueued_jobs do
      found = stub_issued_at(issued_at) { Analysis.find_or_create_from_pdf("%PDF-1.4 fake again", filename: "bera2.pdf") }
      assert_equal existing.id, found.id
    end
  end

  test "find_or_create_from_pdf retries a failed analysis in place instead of returning it as terminal" do
    issued_at = ActiveSupport::TimeZone["Europe/Paris"].local(2026, 1, 14, 16, 0)

    existing = stub_issued_at(issued_at) { Analysis.find_or_create_from_pdf("%PDF-1.4 fake", filename: "bera.pdf") }
    existing.update!(status: :failed, error_message: "API error")

    found = nil
    assert_enqueued_with(job: AnalysisJob, args: [existing.id]) do
      found = stub_issued_at(issued_at) { Analysis.find_or_create_from_pdf("%PDF-1.4 fake again", filename: "bera2.pdf") }
    end

    assert_equal existing.id, found.id
    assert found.pending?
    assert_nil found.error_message
  end

  test "find_or_create_from_pdf treats a revised bulletin (different issued_at) as a new analysis" do
    morning   = ActiveSupport::TimeZone["Europe/Paris"].local(2026, 1, 14, 8, 0)
    afternoon = ActiveSupport::TimeZone["Europe/Paris"].local(2026, 1, 14, 16, 0)

    first  = stub_issued_at(morning)   { Analysis.find_or_create_from_pdf("%PDF-1.4 fake", filename: "bera.pdf") }
    second = stub_issued_at(afternoon) { Analysis.find_or_create_from_pdf("%PDF-1.4 fake", filename: "bera.pdf") }

    assert_not_equal first.id, second.id
  end

  test "find_or_create_from_pdf never dedupes when the issued_at timestamp can't be extracted" do
    first  = stub_issued_at(nil) { Analysis.find_or_create_from_pdf("%PDF-1.4 fake", filename: "bera.pdf") }
    second = stub_issued_at(nil) { Analysis.find_or_create_from_pdf("%PDF-1.4 fake", filename: "bera.pdf") }

    assert_not_equal first.id, second.id
  end
end

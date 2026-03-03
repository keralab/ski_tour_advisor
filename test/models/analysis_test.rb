require "test_helper"

class AnalysisTest < ActiveSupport::TestCase
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
end

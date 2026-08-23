require "test_helper"
require "minitest/mock"

class BeraMetadataExtractorTest < ActiveSupport::TestCase
  FakePage   = Struct.new(:text)
  FakeReader = Struct.new(:pages)

  def stub_page_text(text, &block)
    fake_reader = FakeReader.new([FakePage.new(text)])
    PDF::Reader.stub(:new, fake_reader, &block)
  end

  test "parses the issued-at timestamp from real BERA wording, honoring Europe/Paris" do
    text = "MASSIF : Mont-Blanc\n\nRédigé le mercredi 14 janvier 2026 à 16h\n"

    issued_at = stub_page_text(text) { BeraMetadataExtractor.issued_at("irrelevant") }

    expected = ActiveSupport::TimeZone["Europe/Paris"].local(2026, 1, 14, 16, 0)
    assert_equal expected, issued_at
  end

  test "parses minutes when present" do
    text = "Rédigé le jeudi 5 février 2026 à 8h30\n"

    issued_at = stub_page_text(text) { BeraMetadataExtractor.issued_at("irrelevant") }

    expected = ActiveSupport::TimeZone["Europe/Paris"].local(2026, 2, 5, 8, 30)
    assert_equal expected, issued_at
  end

  test "returns nil when the page has no issued-at line" do
    issued_at = stub_page_text("MASSIF: Mont-Blanc - Risque avalanche niveau 3") do
      BeraMetadataExtractor.issued_at("irrelevant")
    end

    assert_nil issued_at
  end

  test "returns nil for the off-season notice" do
    pdf_bytes = file_fixture("bera_off_season.pdf").binread

    assert_nil BeraMetadataExtractor.issued_at(pdf_bytes)
  end

  test "fails open (returns nil) when the PDF can't be parsed" do
    assert_nil BeraMetadataExtractor.issued_at("not a pdf")
  end
end

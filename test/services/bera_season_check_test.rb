require "test_helper"

class BeraSeasonCheckTest < ActiveSupport::TestCase
  test "detects the off-season notice" do
    pdf_bytes = file_fixture("bera_off_season.pdf").binread

    assert BeraSeasonCheck.off_season?(pdf_bytes)
  end

  test "does not flag a real bulletin" do
    pdf_bytes = file_fixture("bera_in_season.pdf").binread

    assert_not BeraSeasonCheck.off_season?(pdf_bytes)
  end

  test "fails open (treats as in-season) when the PDF can't be parsed" do
    assert_not BeraSeasonCheck.off_season?("not a pdf")
  end
end

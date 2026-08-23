require "pdf/reader"

# BERA PDFs published outside the ski touring season (roughly May-October) are
# replaced with a 1-page notice reading "La saison est terminée, retrouvez nos
# BERA début novembre" instead of a real bulletin. Detecting that up front lets
# AnalysisJob skip the Claude agent loop entirely for a bulletin with nothing to
# analyze.
class BeraSeasonCheck
  OFF_SEASON_MARKER = "La saison est terminée"

  MESSAGE = "The avalanche season is over — Météo-France stops publishing BERA " \
            "bulletins over summer and resumes in November. Check back then."

  def self.off_season?(pdf_bytes)
    text = PDF::Reader.new(StringIO.new(pdf_bytes)).pages.first&.text
    text.to_s.include?(OFF_SEASON_MARKER)
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
    Rails.logger.tagged("BeraSeasonCheck") { Rails.logger.warn("could not parse PDF, assuming in-season: #{e.class} #{e.message}") }
    false
  end
end

require "pdf/reader"

# Cheaply extracts the BERA's publication timestamp from page 1 text — the
# "Rédigé le mercredi 14 janvier 2026 à 16h" line — without invoking Claude.
# Météo-France republishes an updated bulletin intraday (e.g. a morning
# revision after overnight activity), so this timestamp, not the calendar
# date, is what Analysis dedupes on.
class BeraMetadataExtractor
  MONTHS = {
    "janvier" => 1, "février" => 2, "mars" => 3, "avril" => 4, "mai" => 5,
    "juin" => 6, "juillet" => 7, "août" => 8, "septembre" => 9,
    "octobre" => 10, "novembre" => 11, "décembre" => 12
  }.freeze

  ISSUED_AT_PATTERN = /
    Rédigé\ le\ \S+\s+       # "Rédigé le mercredi"
    (\d{1,2})\s+             # day
    (#{MONTHS.keys.join('|')})\s+  # month name
    (\d{4})\s+à\s+           # year "à"
    (\d{1,2})h(\d{2})?       # hour, optional minutes
  /x

  def self.issued_at(pdf_bytes)
    text = PDF::Reader.new(StringIO.new(pdf_bytes)).pages.first&.text.to_s.delete("﻿")
    match = ISSUED_AT_PATTERN.match(text)
    return nil unless match

    day, month_name, year, hour, minute = match.captures
    ActiveSupport::TimeZone["Europe/Paris"].local(
      year.to_i, MONTHS.fetch(month_name), day.to_i, hour.to_i, minute.to_i, 0
    )
  rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError => e
    Rails.logger.tagged("BeraMetadataExtractor") { Rails.logger.warn("could not parse PDF: #{e.class} #{e.message}") }
    nil
  end
end

class Analysis < ApplicationRecord
  DEFAULT_MASSIF = "mont-blanc"

  has_one_attached :bera_pdf
  has_many :recommended_routes, -> { order(:rank) }, dependent: :destroy

  enum :status, { pending: "pending", processing: "processing",
                  complete: "complete", failed: "failed" }

  validates :massif, presence: true
  validate :bera_pdf_present_and_valid

  def done? = complete? || failed?

  # Single entry point for all three ways a BERA reaches the app (manual
  # upload, "use current", "use this date"). Dedupes on (massif,
  # bera_issued_at) — the bulletin's own "Rédigé le" timestamp — so a same-day
  # bulletin that gets revised intraday is treated as a new analysis, while
  # repeat requests for an unchanged bulletin reuse the existing one and skip
  # both the agent loop and a new AnalysisJob.
  #
  # A failed existing row is retried in place (reset + re-enqueued) rather
  # than returned as-is: the unique index means we can't create a second row
  # for the same bulletin, and a stale failure (e.g. a transient API error)
  # shouldn't permanently block every future visitor from getting a result.
  def self.find_or_create_from_pdf(pdf_bytes, filename:, content_type: "application/pdf", massif: DEFAULT_MASSIF)
    issued_at = BeraMetadataExtractor.issued_at(pdf_bytes)

    if issued_at
      existing = find_by(massif: massif, bera_issued_at: issued_at)
      if existing
        retry!(existing) if existing.failed?
        return existing
      end
    end

    analysis = new(massif: massif, bera_issued_at: issued_at)
    analysis.bera_pdf.attach(io: StringIO.new(pdf_bytes), filename: filename, content_type: content_type)

    AnalysisJob.perform_later(analysis.id) if analysis.save
    analysis
  end

  def self.retry!(analysis)
    analysis.update!(status: :pending, error_message: nil)
    AnalysisJob.perform_later(analysis.id)
  end
  private_class_method :retry!

  private

  def bera_pdf_present_and_valid
    if !bera_pdf.attached?
      errors.add(:bera_pdf, "must be attached")
    elsif bera_pdf.content_type != "application/pdf"
      errors.add(:bera_pdf, "must be a PDF file")
    end
  end
end

class Analysis < ApplicationRecord
  has_one_attached :bera_pdf

  enum :status, { pending: "pending", processing: "processing",
                  complete: "complete", failed: "failed" }

  validate :bera_pdf_present_and_valid

  def done? = complete? || failed?

  private

  def bera_pdf_present_and_valid
    if !bera_pdf.attached?
      errors.add(:bera_pdf, "must be attached")
    elsif bera_pdf.content_type != "application/pdf"
      errors.add(:bera_pdf, "must be a PDF file")
    end
  end
end

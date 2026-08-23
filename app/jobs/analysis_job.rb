class AnalysisJob < ApplicationJob
  queue_as :default

  def perform(analysis_id)
    analysis = Analysis.find(analysis_id)
    analysis.update!(status: :processing)

    pdf_bytes = analysis.bera_pdf.download

    if BeraSeasonCheck.off_season?(pdf_bytes)
      analysis.update!(status: :complete, result: BeraSeasonCheck::MESSAGE, turns: 0)
      return
    end

    result = AgentOrchestrator.new.call(pdf_bytes)

    analysis.update!(status: :complete, result: result[:result], turns: result[:turns])
  rescue => e
    analysis&.update!(status: :failed, error_message: e.message)
  end
end

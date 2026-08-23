class AnalysisJob < ApplicationJob
  queue_as :default

  def perform(analysis_id)
    analysis = Analysis.find(analysis_id)
    analysis.update!(status: :processing)

    pdf_bytes = analysis.bera_pdf.download

    if BeraSeasonCheck.off_season?(pdf_bytes)
      analysis.update!(status: :complete, conditions: BeraSeasonCheck::MESSAGE, turns: 0)
      return
    end

    result = AgentOrchestrator.new.call(pdf_bytes)

    analysis.transaction do
      analysis.update!(
        status: :complete,
        conditions: result[:conditions],
        best_skiing: result[:best_skiing],
        search_params: result[:search_params],
        turns: result[:turns]
      )

      result[:routes].each_with_index do |route, index|
        analysis.recommended_routes.create!(
          rank: index + 1,
          camptocamp_route_id: route[:route_id],
          title: route[:title],
          rationale: route[:rationale],
          elevation_summit: route[:elevation_summit],
          orientations: route[:orientations],
          difficulty: route[:difficulty]
        )
      end
    end
  rescue => e
    Rails.logger.tagged("AnalysisJob") do
      Rails.logger.error("analysis_id=#{analysis_id} failed: #{e.class} #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
    end
    analysis&.update!(status: :failed, error_message: e.message)
  end
end

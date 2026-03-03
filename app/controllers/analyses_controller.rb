class AnalysesController < ApplicationController
  def new
    @analysis = Analysis.new
  end

  def show
    @analysis = Analysis.find(params[:id])
  end

  def create
    @analysis = Analysis.new(analysis_params)
    if @analysis.save
      AnalysisJob.perform_later(@analysis.id)
      redirect_to @analysis
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def analysis_params
    params.require(:analysis).permit(:bera_pdf)
  end
end

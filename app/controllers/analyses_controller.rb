class AnalysesController < ApplicationController
  def new
    @analysis = Analysis.new
  end

  def show
    @analysis = Analysis.find(params[:id])
  end

  def create
    uploaded = params.dig(:analysis, :bera_pdf)

    if uploaded.blank?
      @analysis = Analysis.new
      @analysis.errors.add(:bera_pdf, "must be attached")
      render :new, status: :unprocessable_entity
      return
    end

    @analysis = Analysis.find_or_create_from_pdf(
      uploaded.read, filename: uploaded.original_filename, content_type: uploaded.content_type
    )

    if @analysis.persisted?
      redirect_to @analysis
    else
      render :new, status: :unprocessable_entity
    end
  end

  def latest
    fetched = BeraFetcher.new.call_current
    create_from_fetched(fetched, not_found_alert: "No BERA currently available.")
  end

  def historical
    date = Date.parse(params[:date]) rescue nil

    if date.nil?
      redirect_to new_analysis_path, alert: "Please choose a valid date."
      return
    end

    fetched = BeraFetcher.new.call_for_date(date)
    create_from_fetched(fetched, not_found_alert: "No BERA available for #{date}.")
  end

  private

  def create_from_fetched(fetched, not_found_alert:)
    if fetched.nil?
      redirect_to new_analysis_path, alert: not_found_alert
      return
    end

    @analysis = Analysis.find_or_create_from_pdf(fetched.pdf_bytes, filename: fetched.filename)

    if @analysis.persisted?
      redirect_to @analysis
    else
      redirect_to new_analysis_path, alert: @analysis.errors.full_messages.to_sentence
    end
  end
end

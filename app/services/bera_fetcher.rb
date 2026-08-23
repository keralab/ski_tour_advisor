class BeraFetcher
  CURRENT_URL         = "https://en.chamonix.com/bulletin-avalanche/BRA_MONT-BLANC.pdf"
  HISTORICAL_BASE_URL = "https://chamonix-meteo.com/snow/avalanche/"
  RELEASE_TIME        = "1600"

  Result = Struct.new(:pdf_bytes, :filename, :released_on, keyword_init: true)

  # Always the most up-to-date bulletin, whatever today's date is.
  def call_current
    pdf_bytes = download(CURRENT_URL)
    return nil unless pdf_bytes

    Result.new(pdf_bytes: pdf_bytes, filename: "BRA_MONT-BLANC.pdf", released_on: nil)
  end

  # The BERA valid for `date`, released the afternoon before. Used for
  # historical lookups / testing against a specific day's bulletin.
  def call_for_date(date)
    release_date = date - 1
    filename = "BRA#{release_date.strftime('%y%m%d')}#{RELEASE_TIME}.pdf"
    pdf_bytes = download("#{HISTORICAL_BASE_URL}#{filename}")
    return nil unless pdf_bytes

    Result.new(pdf_bytes: pdf_bytes, filename: filename, released_on: release_date)
  end

  private

  def download(url)
    conn = Faraday.new { |f| f.response :raise_error }

    Rails.logger.tagged("BeraFetcher") do
      Rails.logger.info("GET #{url}")
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        response = conn.get(url)
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        Rails.logger.info("GET #{url} -> #{response.status} (#{duration_ms}ms)")
        response.body
      rescue Faraday::ResourceNotFound
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        Rails.logger.info("GET #{url} -> 404 (#{duration_ms}ms)")
        nil
      rescue Faraday::Error => e
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        Rails.logger.error("GET #{url} failed after #{duration_ms}ms: #{e.class} #{e.message}")
        raise
      end
    end
  end
end

class CamptocampClient
  BASE_URL = "https://api.camptocamp.org"

  # Camptocamp area IDs for French BERA massifs.
  # The C2C API filters routes by area using the `a=` parameter (not bbox).
  MASSIF_AREA_IDS = {
    "chablais"    => 14411,
    "mont-blanc"  => 14410,
    "beaufortain" => 14400,
    "vanoise"     => 14409,
    "belledonne"  => 14398,
    "oisans"      => 14403,  # Called "Écrins" on C2C
    "chartreuse"  => 14401,
  }.freeze

  def search_routes(massif_name:, elevation_max: nil, orientations: [], limit: 10)
    area_id = MASSIF_AREA_IDS.fetch(massif_name.downcase)
    params = { act: "skitouring", a: area_id, limit: limit }
    params[:rmaxa] = elevation_max if elevation_max
    params[:fac]   = orientations.join(",") if orientations.any?
    get("/routes", params)
  end

  def get_route(route_id)
    get("/routes/#{route_id}")
  end

  def search_outings(route_id: nil, massif_name: nil, limit: 5)
    params = { limit: limit }
    if route_id
      params[:r] = route_id
    elsif massif_name
      params[:a] = MASSIF_AREA_IDS.fetch(massif_name.downcase)
    end
    get("/outings", params)
  end

  def get_outing(outing_id)
    get("/outings/#{outing_id}")
  end

  private

  def get(path, params = {})
    conn = Faraday.new(BASE_URL) do |f|
      f.response :raise_error
    end
    response = conn.get(path, params)
    JSON.parse(response.body)
  end
end

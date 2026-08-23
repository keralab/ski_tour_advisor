class RecommendedRoute < ApplicationRecord
  belongs_to :analysis

  validates :rank, :camptocamp_route_id, :title, presence: true
end

class RedesignAnalysesForDailyCaching < ActiveRecord::Migration[8.0]
  def change
    change_table :analyses, bulk: true do |t|
      t.remove :result, type: :text
      t.string :massif, null: false, default: "mont-blanc"
      t.datetime :bera_issued_at
      t.text :conditions
      t.text :best_skiing
      t.json :search_params
    end

    add_index :analyses, [:massif, :bera_issued_at], unique: true,
              where: "bera_issued_at IS NOT NULL", name: "index_analyses_on_massif_and_bera_issued_at"

    create_table :recommended_routes do |t|
      t.references :analysis, null: false, foreign_key: true
      t.integer :rank, null: false
      t.integer :camptocamp_route_id, null: false
      t.string :title, null: false
      t.text :rationale
      t.integer :elevation_summit
      t.json :orientations
      t.string :difficulty

      t.timestamps
    end

    add_index :recommended_routes, [:analysis_id, :rank], unique: true
  end
end

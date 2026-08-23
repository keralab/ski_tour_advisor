# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_08_23_195844) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "analyses", force: :cascade do |t|
    t.string "status", default: "pending", null: false
    t.text "error_message"
    t.integer "turns"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "massif", default: "mont-blanc", null: false
    t.datetime "bera_issued_at"
    t.text "conditions"
    t.text "best_skiing"
    t.json "search_params"
    t.index ["massif", "bera_issued_at"], name: "index_analyses_on_massif_and_bera_issued_at", unique: true, where: "bera_issued_at IS NOT NULL"
  end

  create_table "recommended_routes", force: :cascade do |t|
    t.integer "analysis_id", null: false
    t.integer "rank", null: false
    t.integer "camptocamp_route_id", null: false
    t.string "title", null: false
    t.text "rationale"
    t.integer "elevation_summit"
    t.json "orientations"
    t.string "difficulty"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["analysis_id", "rank"], name: "index_recommended_routes_on_analysis_id_and_rank", unique: true
    t.index ["analysis_id"], name: "index_recommended_routes_on_analysis_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "recommended_routes", "analyses"
end

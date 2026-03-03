class CreateAnalyses < ActiveRecord::Migration[8.0]
  def change
    create_table :analyses do |t|
      t.string  :status,        null: false, default: "pending"
      t.text    :result
      t.text    :error_message
      t.integer :turns
      t.timestamps
    end
  end
end

class CreateEscribaTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :escriba_translations do |t|
      t.string  :key,                 null: false, limit: 32
      t.string  :locale,              null: false, limit: 16
      t.text    :value
      t.text    :source_copy,         null: false
      t.text    :meaning
      t.text    :interpolation_names
      t.boolean :plural,              null: false, default: false
      t.timestamps
    end

    add_index :escriba_translations, [:key, :locale], unique: true
    add_index :escriba_translations, :key
  end
end

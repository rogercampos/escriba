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

ActiveRecord::Schema[8.1].define(version: 2026_06_10_120000) do
  create_table "escriba_translations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "interpolation_names"
    t.text "issues"
    t.string "key", limit: 32, null: false
    t.string "locale", limit: 16, null: false
    t.text "meaning"
    t.boolean "plural", default: false, null: false
    t.text "source_copy", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key", "locale"], name: "index_escriba_translations_on_key_and_locale", unique: true
    t.index ["key"], name: "index_escriba_translations_on_key"
    t.index ["locale"], name: "index_escriba_translations_issue_rows", where: "issues IS NOT NULL"
    t.index ["updated_at"], name: "index_escriba_translations_on_updated_at"
  end
end

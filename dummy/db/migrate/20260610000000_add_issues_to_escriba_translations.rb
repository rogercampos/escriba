# frozen_string_literal: true

class AddIssuesToEscribaTranslations < ActiveRecord::Migration[8.1]
  def up
    add_column :escriba_translations, :issues, :text
    add_index :escriba_translations, :locale, where: "issues IS NOT NULL",
      name: "index_escriba_translations_issue_rows"

    # Backfill: re-saving lets the model callback compute the cached issues.
    Escriba::Translation.reset_column_information
    Escriba::Translation.find_each { |row| row.save!(touch: false) }
  end

  def down
    remove_index :escriba_translations, name: "index_escriba_translations_issue_rows"
    remove_column :escriba_translations, :issues
  end
end

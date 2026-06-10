# frozen_string_literal: true

class AddUpdatedAtIndexToEscribaTranslations < ActiveRecord::Migration[8.1]
  def change
    add_index :escriba_translations, :updated_at # the dashboard's pending-deploy count
  end
end

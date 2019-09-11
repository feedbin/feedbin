class AddSettingsToEntries < ActiveRecord::Migration[5.1]
  def change
    add_column :entries, :settings, :jsonb
  end
end

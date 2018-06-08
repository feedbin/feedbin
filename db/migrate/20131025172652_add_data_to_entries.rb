class AddDataToEntries < ActiveRecord::Migration[4.2]
  def change
    add_column :entries, :data, :json
  end
end

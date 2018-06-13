class AddDefaultValueToImportDefault < ActiveRecord::Migration[4.2]
  def up
    change_column :imports, :complete, :boolean, default: false
  end

  def down
    change_column :imports, :complete, :boolean, default: nil
  end
end

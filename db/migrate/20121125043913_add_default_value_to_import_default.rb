class AddDefaultValueToImportDefault < ActiveRecord::Migration
  def up
    change_column :imports, :complete, :boolean, default: false
  end

  def down
    change_column :imports, :complete, :boolean, default: nil
  end
end

class ChangeImportItemsStatusDefault < ActiveRecord::Migration[5.1]
  def up
    change_column_default(:import_items, :status, 0)
  end
  def down
    change_column_default(:import_items, :status, 1)
  end
end

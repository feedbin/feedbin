class AddImagesToEntries < ActiveRecord::Migration
  def change
    change_table :entries do |t|
      t.string :images, array: true
    end
  end
end

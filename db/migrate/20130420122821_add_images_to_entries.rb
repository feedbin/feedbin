class AddImagesToEntries < ActiveRecord::Migration[4.2]
  def change
    change_table :entries do |t|
      t.string :images, array: true
    end
  end
end

class AddImagesToEntriesAgain < ActiveRecord::Migration[4.2]
  def change
    change_table :entries do |t|
      t.text :images, array: true
    end
  end
end

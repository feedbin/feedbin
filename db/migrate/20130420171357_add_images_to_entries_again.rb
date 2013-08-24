class AddImagesToEntriesAgain < ActiveRecord::Migration
  def change
    change_table :entries do |t|
      t.text :images, array: true
    end
  end
end

class ChangeEtagToText < ActiveRecord::Migration[4.2]
  def up
    change_table :feeds do |t|
      t.change :etag, :text
    end
  end

  def down
    change_table :feeds do |t|
      t.change :etag, :string
    end
  end
end

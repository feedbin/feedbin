class ChangeEtagToText < ActiveRecord::Migration
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

class AddHstoreExtension < ActiveRecord::Migration
  def up
    execute 'CREATE EXTENSION hstore'
  end

  def down
    execute 'DROP EXTENSION hstore'
  end
end
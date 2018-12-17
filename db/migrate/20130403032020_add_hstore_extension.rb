class AddHstoreExtension < ActiveRecord::Migration[4.2]
  def up
    execute "CREATE EXTENSION hstore"
  end

  def down
    execute "DROP EXTENSION hstore"
  end
end

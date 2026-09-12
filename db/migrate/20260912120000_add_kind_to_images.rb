# What the picture is, as opposed to provider, which keys the row. See
# Image.kinds. NOT NULL with a default: on Postgres 11+ that is a catalog
# change with no table rewrite, so the ACCESS EXCLUSIVE lock is momentary
# regardless of table size. The default is poster, the kind of most rows;
# BackfillImageKinds labels the rest from data->>'preset'.
class AddKindToImages < ActiveRecord::Migration[8.1]
  def change
    add_column :images, :kind, :bigint, null: false, default: 3
  end
end

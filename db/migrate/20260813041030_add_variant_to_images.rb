class AddVariantToImages < ActiveRecord::Migration[8.1]
  def up
    add_column :images, :variant, :text

    # Pre-launch backfill: only development databases have rows, all produced
    # by the 542x304 entry presets. Their url_fingerprints were hashed without
    # a variant, so dedup will miss them once and replace them organically;
    # display and garbage collection read stored columns and keep working.
    # safety_assured: the table is empty everywhere but development.
    safety_assured do
      execute "UPDATE images SET variant = '542x304' WHERE variant IS NULL"
      change_column_null :images, :variant, false
    end
  end

  def down
    remove_column :images, :variant
  end
end

class CreateRProfilesTags < ActiveRecord::Migration[7.0]
  def change
    create_table :r_profiles_tags do |t|
      t.references :profile, foreign_key: true, null: false
      t.references :tag, foreign_key: true, null: false
    end
  end
end

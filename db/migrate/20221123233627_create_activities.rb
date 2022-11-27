class CreateActivities < ActiveRecord::Migration[7.0]
  def change
    create_table :activities do |t|
      t.text  :activity_type
      t.text  :url, index: {unique: true}
      t.jsonb :data

      t.timestamps
    end
  end
end

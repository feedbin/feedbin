class CreateNextEntries < ActiveRecord::Migration[7.0]
  def change
    create_table :next_entries do |t|
      t.references :entry,                         null: false, index: true, foreign_key: { on_delete: :cascade }
      t.references :feed,                          null: false, index: true, foreign_key: { on_delete: :cascade }
      t.bigint     :entry_ids,                     null: false, index: true, array: true, default: []
      t.text       :title,                         null: true
      t.text       :url,                           null: false
      t.text       :author,                        null: true
      t.text       :source_id,                     null: true
      t.uuid       :public_id,                     null: false, index: {unique: true}
      t.uuid       :title_id,                      null: false, index: {unique: true}
      t.uuid       :url_id,                        null: false, index: {unique: true}
      t.bigint     :tweet_id,                      null: true,  index: {where: "tweet_id IS NOT NULL"}
      t.bigint     :tweet_thread_id,               null: true,  index: {where: "tweet_thread_id IS NOT NULL"}
      t.bigint     :starred_entries_count,         null: false, default: 0
      t.bigint     :recently_played_entries_count, null: false, default: 0
      t.bigint     :queued_entries_count,          null: false, default: 0
      t.datetime   :published_at,                  null: false
      t.datetime   :source_updated_at,             null: true
      t.datetime   :created_at,                    null: false
      t.datetime   :updated_at,                    null: false
      t.text       :summary,                       null: true
      t.text       :content,                       null: true
      t.jsonb      :image,                         null: true
      t.jsonb      :tweet,                         null: true
      t.jsonb      :newsletter,                    null: true
      t.jsonb      :original,                      null: true
      t.jsonb      :settings,                      null: false, default: {}
      t.jsonb      :data,                          null: false, default: {}
    end
  end
end

# CREATE TABLE public.entries (
#     id bigint NOT NULL,
#     feed_id bigint,
#     title text,
#     url text,
#     author text,
#     summary text,
#     content text,
#     published timestamp without time zone,
#     updated timestamp without time zone,
#     created_at timestamp without time zone NOT NULL,
#     updated_at timestamp without time zone NOT NULL,
#     entry_id text,
#     public_id character varying(255),
#     old_public_id character varying(255),
#     data json,
#     original json,
#     source text,
#     image_url text,
#     processed_image_url text,
#     image json,
#     main_tweet_id text,
#     thread_id bigint,
#     settings jsonb,
#     starred_entries_count bigint DEFAULT 0 NOT NULL,
#     recently_played_entries_count bigint DEFAULT 0,
#     queued_entries_count bigint DEFAULT 0 NOT NULL
# );

class EntryCopier
  include Sidekiq::Worker
  sidekiq_options queue: :worker_slow

  def perform(entry_id)
    @entry = Entry.find(entry_id)
    NextEntry.create!(
      id:                               @entry.id
      entry_id:                         @entry.id
      feed_id:                          @entry.feed_id
      entry_ids:                        entry_ids
      title:                            @entry.title&.strip
      url:                              @entry.url.strip
      author:                           @entry.author.strip
      source_id:                        @entry.source_id.strip
      public_id:                        public_id
      title_id:                         title_id
      url_id:                           url_id
      tweet_id:                         @entry.main_tweet_id
      tweet_thread_id:                  @entry.thread_id
      starred_entries_count:            @entry.starred_entries_count
      recently_played_entries_count:    @entry.recently_played_entries_count
      queued_entries_count:             @entry.queued_entries_count
      published_at:                     @entry.published
      source_updated_at:                @entry.updated
      created_at:                       @entry.created_at
      updated_at:                       @entry.updated_at
      summary:                          summary
      content:                          @entry.content&.strip
      image:                            @entry.image
      tweet:                            @entry.data&.dig("tweet")
      newsletter:                       @entry.data&.dig("newsletter")
      original:                         @entry.original
      settings:                         @entry.settings
      data:                             @entry.data
    )
  end
  
  def data
    @entry.data.except!("tweet", "newsletter")
  end
  
  def entry_ids
    [@entry.entry_ids]
  end
  
  def public_id
    Digest::MD5.hexdigest(@entry.public_id)
  end
  
  def title_id
    title = @entry.title&.strip
    if title.blank?
      title = @entry.content
    end
    parts = [
      @entry.feed.feed_url,
      title,
    ]
    Digest::MD5.hexdigest(parts.join(""))
  end

  def url_id
    url = Addressable::URI.heuristic_parse
    url.scheme = nil
    url.host   = nil
    url        = url.to_s
    parts = [
      @entry.feed.feed_url,
      url
    ]    
    Digest::MD5.hexdigest(parts.join(""))
  end
  
  def summary
    ContentFormatter.summary(@entry.content, 256)
  end
end


CREATE TABLE public.next_entries (
    id bigint NOT NULL,
    entry_id bigint NOT NULL,
    feed_id bigint NOT NULL,
    entry_ids bigint[] DEFAULT '{}'::bigint[] NOT NULL,
    title text,
    url text NOT NULL,
    author text,
    source_id text,
    public_id uuid NOT NULL,
    title_id uuid NOT NULL,
    url_id uuid NOT NULL,
    tweet_id bigint,
    tweet_thread_id bigint,
    starred_entries_count bigint DEFAULT 0 NOT NULL,
    recently_played_entries_count bigint DEFAULT 0 NOT NULL,
    queued_entries_count bigint DEFAULT 0 NOT NULL,
    published_at timestamp(6) without time zone NOT NULL,
    source_updated_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    summary text,
    content text,
    image jsonb,
    tweet jsonb,
    newsletter jsonb,
    original jsonb,
    settings jsonb DEFAULT '{}'::jsonb NOT NULL,
    data jsonb DEFAULT '{}'::jsonb NOT NULL
);

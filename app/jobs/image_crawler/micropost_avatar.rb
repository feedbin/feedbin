module ImageCrawler
  # A micropost entry's author avatar, as an entry_icon row keyed by the
  # entry. Runs per feed: it groups row-less micropost entries by avatar
  # url, attaches the groups whose url the table already holds (no request),
  # and downloads once per unknown url. The callback attaches the rest of
  # that url's group, so a pass costs one request per distinct avatar.
  class MicropostAvatar
    include Sidekiq::Worker
    sidekiq_options retry: false

    SUFFIX = "-avatar".freeze
    PRESET = "micropost_avatar".freeze

    # id is a feed id when scheduling and "<entry public_id>-avatar" when the
    # pipeline calls back with the landed row. entry_ids limits a pass to
    # those entries; without it the pass covers the whole feed.
    def perform(id, image = nil, entry_ids = nil)
      if image
        receive(image)
      else
        self.class.schedule(Feed.find(id), entry_ids:)
      end
    rescue ActiveRecord::RecordNotFound
    end

    # The pass for the entries a crawl or a subscribe just created, when any
    # is a micropost. The entries decide, one by one, as the readers do;
    # nothing depends on the parser's feed marker. Limited to these entries,
    # so an older entry whose avatar never landed is not fetched again.
    def self.for_new_entries(feed, entries)
      ids = entries.filter_map { it.id if author_avatar(feed, it) }
      perform_async(feed.id, nil, ids) if ids.any?
    end

    # Returns [attached, scheduled].
    def self.schedule(feed, entry_ids: nil)
      entries = pending_entries(feed)
      entries = entries.where(id: entry_ids) if entry_ids
      entries = entries.to_a
      groups = avatar_groups(feed, entries)
      attached = 0
      scheduled = 0

      groups.each do |url, group|
        # An earlier post's row for the same url.
        if (existing = ::Image.avatar_row(url))
          attach(group, url, existing)
          attached += group.size
        else
          enqueue(feed, group, url)
          scheduled += 1
        end
      end

      Sidekiq.logger.info "MicropostAvatar: feed=#{feed.id} scanned=#{entries.size} urls=#{groups.size} attached=#{attached} scheduled=#{scheduled}"
      [attached, scheduled]
    end

    # The feed's untitled entries with no entry_icon row, an anti-join on
    # the cast entry id (Image.outer_join). A titled entry is never a
    # micropost, so it is not loaded. Ordered by id: the feed_id index
    # carries no sort, so an unordered scan can hand back entries
    # newest-first, and avatar_groups' "first" entry (the one that pays for
    # the download) would otherwise vary run to run.
    def self.pending_entries(feed)
      entries = Entry.arel_table
      join = ::Image.outer_join(entries, provider: :entry_icon, key: ::Image.as_text(entries[:id])).join_sources

      feed.entries.where(title: [nil, ""]).joins(join).where(::Image.arel_table[:id].eq(nil)).select(:id, :feed_id, :url, :data, :title, :public_id).order(:id)
    end

    # Entries by absolute avatar url.
    def self.avatar_groups(feed, entries)
      entries.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |entry, groups|
        avatar = author_avatar(feed, entry)
        url = avatar && entry.rebase_url(avatar, strict: true)
        groups[url] << entry if url.present?
      end
    end

    # The author's avatar as the entry carries it, Micropost#author_avatar's
    # rule, or nil: not a micropost, no avatar (the readers treat an empty
    # one as none), a value that is not a url, or an episode, whose
    # entry_icon slot belongs to its podcast art as the feed_icon slot does
    # in FeedIcon. Built from the row's data directly rather than
    # Entry#micropost, which loads the entry's link image row: a query per
    # entry this pass does not need.
    def self.author_avatar(feed, entry)
      return nil if entry.data.is_a?(Hash) && entry.data["itunes_image"].present?

      post = Micropost.new(entry.data, entry.title, feed: feed)
      return nil unless post.valid?

      avatar = post.author_avatar
      avatar.presence if avatar.is_a?(String)
    end

    # A database-only attach of every entry to an object the store already
    # holds, in one statement. kind is these rows' own. upsert_all skips
    # callbacks, so url_fingerprint is computed here.
    def self.attach(entries, url, existing)
      shared = ::Image.stored_object_attributes(existing).merge(
        provider: ::Image.providers[:entry_icon],
        kind: ::Image.kinds[:avatar],
        url: url,
        url_fingerprint: ::Image.url_fingerprint_for(url, existing.variant),
        data: {"preset" => PRESET, "final_url" => existing.final_url.presence || url}
      )
      rows = entries.map { shared.merge(provider_id: it.id.to_s, feed_id: it.feed_id) }
      ::Image.upsert_all(rows, unique_by: %i[provider provider_id]) if rows.any?
    end

    # One download for the group, landing on its first entry. Find tries
    # candidates in order: the strict reading of the avatar url, then the
    # heuristic one (see FeedIcon.schedule). The context tells the callback
    # which url it asked for and who else waits on it.
    def self.enqueue(feed, group, url)
      entry = group.first
      raw = author_avatar(feed, entry)
      image = Image.new_with_attributes(
        id: "#{entry.public_id}#{SUFFIX}",
        kind: ::Image.kinds[:avatar],
        preset_name: PRESET,
        image_urls: [url, entry.rebase_url(raw)].compact_blank.uniq,
        provider: ::Image.providers[:entry_icon],
        provider_id: entry.id,
        feed_id: entry.feed_id,
        context: {"url" => url, "entry_ids" => group.drop(1).map(&:id)}
      )
      Pipeline::Find.perform_async(image.to_h)
    end

    # Upload attached the group's first entry; attach the rest, which the
    # context names, under the url the pass asked for. Nothing is recomputed
    # from the feed: an RSS micropost's avatar is the feed's image url, which
    # can change while the download waits. No touch: the entries cache key
    # digests the row.
    def receive(image)
      context = image["context"] or return
      url = context.fetch("url")
      row = ::Image.provider_entry_icon.find_by(provider_id: image.fetch("provider_id").to_s)
      # The entry_icon slot is shared with podcast art; only an avatar continues.
      return unless row&.kind_avatar?

      # Find lands the row on whichever candidate answered. Key it on the
      # asked url, the one every entry and later lookup uses, so
      # Image.avatar_row finds it. update_columns: the touch rule is that
      # images.updated_at moves only when the stored bytes move, and
      # re-keying the url does not.
      if row.url != url
        row.update_columns(url: url, url_fingerprint: ::Image.url_fingerprint_for(url, row.variant))
      end

      self.class.attach(Entry.where(id: context["entry_ids"]).select(:id, :feed_id).to_a, url, row)
    end
  end
end

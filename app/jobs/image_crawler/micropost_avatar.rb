module ImageCrawler
  # A micropost entry's author avatar, as an entry_icon row keyed by the
  # entry. Runs per feed, once per crawl with new posts: it groups the
  # feed's row-less entries by avatar url, attaches the groups whose url the
  # table already holds (no request), and downloads once per unknown url.
  # The callback attaches the rest of that url's group, so a feed pass
  # costs one request per distinct avatar.
  class MicropostAvatar
    include Sidekiq::Worker
    sidekiq_options retry: false

    SUFFIX = "-avatar".freeze
    PRESET = "micropost_avatar".freeze
    VARIANT = "200x200".freeze

    # id is a feed id when scheduling and "<entry public_id>-avatar" when the
    # pipeline calls back with the landed row.
    def perform(id, image = nil)
      if image
        receive(image)
      else
        self.class.schedule(Feed.find(id))
      end
    rescue ActiveRecord::RecordNotFound
    end

    # Returns [attached, scheduled]. critical: a live crawl runs on the
    # critical queues; the backfill passes false.
    def self.schedule(feed, critical: true)
      return [0, 0] unless feed.micropost?

      # The feed's own icon on the same pass, once: a request per crawl
      # would be too many, so only a feed with no row asks.
      FeedIcon.schedule(feed, critical: critical) if feed.icon_image_record.nil?

      entries = pending_entries(feed).to_a
      groups = avatar_groups(feed, entries)
      attached = 0
      scheduled = 0

      groups.each do |url, group|
        if (existing = existing_row(url))
          group.each { |entry| attach(entry, url, existing) }
          attached += group.size
        else
          enqueue(feed, group.first, url, critical)
          scheduled += 1
        end
      end

      Sidekiq.logger.info "MicropostAvatar: feed=#{feed.id} scanned=#{entries.size} urls=#{groups.size} attached=#{attached} scheduled=#{scheduled}"
      [attached, scheduled]
    end

    # The feed's entries with no entry_icon row: a LEFT JOIN anti-join on
    # the cast entry id (provider_id is text), never NOT IN, which Postgres
    # cannot turn into an anti-join. After the first pass this is the new
    # entries. Arel.sql carries only the type keyword. Ordered by id: the
    # feed_id index carries no sort, so an unordered scan can hand back
    # entries newest-first, and avatar_groups' "first" entry (the one that
    # pays for the download) would otherwise vary run to run.
    def self.pending_entries(feed)
      entries = Entry.arel_table
      images = ::Image.arel_table
      entry_id_text = Arel::Nodes::NamedFunction.new("CAST", [entries[:id].as(Arel.sql("text"))])
      join = entries.join(images, Arel::Nodes::OuterJoin).on(
        images[:provider].eq(::Image.providers[:entry_icon]).and(images[:provider_id].eq(entry_id_text))
      ).join_sources

      feed.entries.joins(join).where(images[:id].eq(nil)).select(:id, :feed_id, :url, :data, :title, :public_id).order(:id)
    end

    # Entries by absolute avatar url, Micropost#author_avatar's rule. Built
    # from the row's data directly rather than Entry#micropost, which loads
    # the entry's link image row: a query per entry this pass does not need.
    def self.avatar_groups(feed, entries)
      entries.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |entry, groups|
        post = Micropost.new(entry.data, entry.title, feed: feed)
        next unless post.valid?

        url = entry.rebase_url(post.author_avatar, strict: true)
        groups[url] << entry if url.present?
      end
    end

    # The newest row already holding this url's picture at the avatar
    # variant: an earlier post's row, or a copy of the proxy's cache. One
    # indexed read on url_fingerprint; the preset comes out of data through
    # Arel, nothing is interpolated. icon rows exist once the copy backfill
    # runs; until then only micropost_avatar rows match.
    def self.existing_row(url)
      ::Image.where(url_fingerprint: ::Image.url_fingerprint_for(url, VARIANT))
        .where(::Image.data_projection("preset").in([PRESET, "icon"]))
        .order(id: :desc)
        .first
    end

    # A DB-only attach to an object the store already holds, the shape
    # Dedupe uses. kind is this row's own.
    def self.attach(entry, url, existing)
      ::Image.attach!(
        provider: :entry_icon,
        provider_id: entry.id,
        kind: :avatar,
        feed_id: entry.feed_id,
        url: url,
        variant: existing.variant,
        image_fingerprint: existing.image_fingerprint,
        original_fingerprint: existing.original_fingerprint,
        storage_path: existing.storage_path,
        width: existing.width,
        height: existing.height,
        bytesize: existing.bytesize,
        placeholder_color: existing.placeholder_color,
        data: {"preset" => PRESET, "final_url" => existing.final_url.presence || url}
      )
    end

    # Find tries candidates in order: the strict reading of the avatar url,
    # then the heuristic one (see FeedIcon.schedule), then the object the
    # proxy cached, so a dead source still lands as a copy of what was served
    # before. Deploy A only: the legacy object goes with remote_files. The
    # proxy was handed the url exactly as the entry carries it.
    def self.enqueue(feed, entry, url, critical)
      raw = Micropost.new(entry.data, entry.title, feed: feed).author_avatar
      image = Image.new_with_attributes(
        id: "#{entry.public_id}#{SUFFIX}",
        kind: ::Image.kinds[:avatar],
        preset_name: PRESET,
        image_urls: [url, entry.rebase_url(raw), RemoteFile.legacy_object_url(raw)].compact_blank.uniq,
        provider: ::Image.providers[:entry_icon],
        provider_id: entry.id,
        feed_id: entry.feed_id,
        critical: critical
      )
      Pipeline::Find.perform_async(image.to_h)
    end

    # Upload attached the first entry's row; attach every sibling that
    # shares its url. Re-keys the row to the avatar url when Find landed it
    # under the legacy object url instead. No touch: the entries cache key
    # digests the row.
    def receive(image)
      image.fetch("storage_path")
      row = ::Image.provider_entry_icon.find_by(provider_id: image.fetch("provider_id").to_s)
      return if row.nil? || row.feed_id.nil?
      # The entry_icon slot is shared with podcast art; only an avatar continues.
      return unless row.kind_avatar?

      feed = Feed.find(row.feed_id)
      entry = feed.entries.select(:id, :feed_id, :url, :data, :title, :public_id).find_by(id: row.provider_id)
      return if entry.nil?

      post = Micropost.new(entry.data, entry.title, feed: feed)
      asked = post.valid? ? entry.rebase_url(post.author_avatar, strict: true) : nil
      return if asked.blank?

      # Find tries the avatar url first and the legacy object second; when
      # the legacy object wins, the row lands keyed on that url, not the
      # avatar url every entry and later lookup asks for. Re-key it here so
      # avatar_groups and existing_row find it. update_columns: the touch
      # rule is that images.updated_at moves only when the stored bytes
      # move, and re-keying the url does not.
      if row.url != asked
        row.update_columns(url: asked, url_fingerprint: ::Image.url_fingerprint_for(asked, row.variant))
      end

      siblings = self.class.avatar_groups(feed, self.class.pending_entries(feed).to_a).fetch(asked, [])
      siblings.each { |sibling| self.class.attach(sibling, asked, row) }
    end
  end
end

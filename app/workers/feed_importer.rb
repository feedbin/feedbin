class FeedImporter
  include Sidekiq::Worker
  sidekiq_options queue: :critical, retry: false

  def perform(import_item_id)
    import_item = ImportItem.find(import_item_id)

    if import_item.item_type == 'starred'
      import_starred(import_item)
    else
      import_feed(import_item)
    end
  end

  def import_feed(import_item)
    user = import_item.import.user
    result = FeedFetcher.new(import_item.details[:xml_url], import_item.details[:html_url]).create_feed!
    if result.feed
      subscription = user.safe_subscribe(result.feed)
      if import_item.details[:title] && subscription
        subscription.title = import_item.details[:title]
        subscription.save
      end
      if import_item.details[:tag]
        result.feed.tag(import_item.details[:tag], user, false)
      end
    end
  rescue ActiveRecord::RecordNotFound
    # Ignore not found
  end

  def import_starred(import_item)
    item = import_item.details
    user = import_item.import.user

    public_id = Digest::SHA1.hexdigest(item[:id])
    entry = Entry.where(public_id: public_id).first

    unless entry.present?
      feed_url = item[:origin][:streamId].sub('feed/', '')
      feed = Feed.where(feed_url: feed_url).first_or_create!(
        title: item[:origin][:title],
        site_url: item[:origin][:htmlUrl],
      )

      url = item[:canonical] ? item[:canonical][0][:href] : item[:alternate][0][:href]
      if item[:content]
        content = item[:content][:content]
      elsif item[:summary]
        content = item[:summary][:content]
      else
        content = nil
      end

      if feed.present?
        entry = Entry.where(feed_id: feed.id, url: url).first_or_create!(
          author:        item[:author],
          title:         item[:title],
          content:       content,
          entry_id:      item[:id],
          published:     Time.at(item[:published]).to_datetime,
          updated:       Time.at(item[:updated]).to_datetime,
          public_id:     public_id,
          created_at:    Time.at(item[:published]).to_datetime,
          skip_mark_as_unread: true
        )
      end

    end

    if entry.present?
      StarredEntry.create_from_owners(user, entry)
    end

  end

end

xml.instruct!
xml.opml version: "1.0" do
  xml.head do
    xml.title "RSS subscriptions for #{@user.email}"
    xml.dateCreated Time.now.rfc2822
    xml.ownerEmail @user.email
  end
  xml.body do
    @feeds.each do |feed|
      xml << render(partial: "feeds/feed", locals: {feed: feed, titles: @titles})
    end
    @tags.each do |tag|
      xml.outline text: tag.name, title: tag.name do
        Feed.xml.where(id: @user.taggings.where(tag_id: tag).pluck(:feed_id)).each do |feed|
          xml << render(partial: "feeds/feed", locals: {feed: feed, titles: @titles})
        end
      end
    end
  end
end

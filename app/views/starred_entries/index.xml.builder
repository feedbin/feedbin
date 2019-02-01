cache [@user.id, @entries] do
  xml.instruct! :xml, version: "1.0"
  xml.rss :version => "2.0", "xmlns:dc" => "http://purl.org/dc/elements/1.1/", "xmlns:atom" => "http://www.w3.org/2005/Atom" do
    xml.channel do
      xml.title @title
      xml.atom :link, href: starred_url(@user.starred_token, format: :xml), rel: "self", type: "application/rss+xml"
      xml.lastBuildDate @starred_entries.maximum(:created_at).to_s(:rfc822) if @starred_entries.present?
      @entries.each do |entry|
        xml.item do
          xml.title entry.title
          xml.description entry.content
          xml.pubDate entry.published.to_s(:rfc822)
          xml.link entry.fully_qualified_url
          xml.dc :creator, entry.feed.title
          xml.guid "https://feedbin.me#{entry_path(entry)}", isPermaLink: false
        end
      end
    end
  end
end

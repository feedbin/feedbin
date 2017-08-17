require 'socket'

class ParsedEntry

  ENTRY_ATTRIBUTES = %i(author content data entry_id public_id published source title url).freeze

  def initialize(entry, feed_url, feed = nil)
    @entry = entry
    @feed_url = feed_url
    @feed = feed
  end

  def to_entry
    @to_entry ||= begin
      ENTRY_ATTRIBUTES.each_with_object({}) do |attribute, hash|
        hash[attribute] = self.send(attribute)
      end
    end
  end

  def build_id(base_entry_id)
    parts = []
    parts.push(@feed_url)
    parts.push(base_entry_id)
    if !entry_id
      parts.push(url)
      parts.push(published.iso8601) if published.respond_to?(:iso8601)
      parts.push(title)
    end
    Digest::SHA1.hexdigest(parts.compact.join)
  end

  def public_id
    @public_id ||= build_id(entry_id)
  end

  def public_id_alt
    @public_id_alt ||= begin
      if entry_id_alt
        build_id(entry_id_alt)
      end
    end
  end

  def entry_id_alt
    @entry_id_alt ||= begin
      if entry_id
        begin
          parsed_uri(entry_id)
        rescue Exception
          if entry_id.include?("http:")
            entry_id.sub("http:", "https:")
          elsif entry_id.include?("https:")
            entry_id.sub("https:", "http:")
          end
        end
      end
    end
  end

  def parsed_uri(entry_id)
    uri = URI(entry_id)
    result = [uri.userinfo, uri.path, uri.query, uri.fragment].join
    result == "" ? nil : result
  end

  def source
    Socket.gethostname
  end

end

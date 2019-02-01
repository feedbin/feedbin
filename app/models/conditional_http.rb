class ConditionalHTTP
  attr_reader :etag, :last_modified

  def initialize(etag, last_modified)
    @etag = etag
    @last_modified = last_modified
  end

  def to_h
    headers = {}
    headers["If-None-Match"] = if_none_match if if_none_match
    headers["If-Modified-Since"] = if_modified_since if if_modified_since
    headers
  end

  private

  def if_none_match
    @if_none_match ||= begin
      etag
    end
  end

  def if_modified_since
    @if_modified_since ||= begin
      if last_modified.respond_to?(:httpdate)
        last_modified.httpdate
      else
        Time.parse(last_modified).httpdate if last_modified
      end
    end
  rescue
    nil
  end
end

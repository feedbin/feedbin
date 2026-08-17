module EntriesHelper
  # The entry summary renders the feed's title as well as its icon and
  # favicon, so key on the feed record rather than enumerating the attributes
  # the partial happens to use today.
  #
  # The favicon and the preview image are separate rows with their own
  # timestamps, and both render into this partial. Digesting the records is
  # what lets one row update invalidate every view referencing it: the
  # alternative is touching every owner row, which is what TouchFeeds did for
  # a favicon change -- 100,000 writes to invalidate views on a host like
  # medium.com.
  #
  # Every part must come from something already loaded, or the key becomes an
  # N+1 per render: favicons is the collection-wide map (Favicon.for_entries),
  # and feed.favicon and preview_image_record both come from
  # Entry.with_list_associations, which every path rendering this partial
  # attaches -- through Entry.entries_list where the narrow column select also
  # applies, on its own where it cannot.
  def self.entries_cache_key(entry, favicons = {})
    [entry, entry.feed, entry_favicon(entry, favicons), entry.preview_image_record, "v8"]
  end

  # The same two sources FaviconComponent renders from, resolved the same way:
  # a Pages feed is one row holding articles from everywhere, so its entries
  # key on their own host via the map; everything else keys on the feed's own
  # favicon. Mirroring the component is what keeps the digest from drifting
  # away from what actually got rendered.
  def self.entry_favicon(entry, favicons)
    return favicons[entry.hostname] if entry.feed&.pages?
    entry.feed&.favicon
  end

  # The one render invocation for the entry list, shared by the view
  # (shared/_entries.js.erb) and the cache warmer (CacheEntryViews). The two
  # once drifted -- the warmer passed `cached: true` and warmed keys no view
  # ever read -- and sharing the options is what rules that out.
  def self.entry_collection(entries, favicons)
    {
      partial: "entries/entry",
      collection: entries,
      locals: {favicons: favicons},
      cached: ->(entry) { entries_cache_key(entry, favicons) }
    }
  end

  def entries_cache_key(entry, favicons = {})
    EntriesHelper.entries_cache_key(entry, favicons)
  end

  def format_text(text)
    text ||= ""
    decoder = HTMLEntities.new
    text = ActionController::Base.helpers.strip_tags(text)
    text = text.delete("\n")
    text = text.delete("\t")
    text = decoder.decode(text)
    text
  end

  def self.text_format(text)
    decoder = HTMLEntities.new
    content_text = Sanitize.fragment(text,
      remove_contents: true,
      elements: %w[html body div span
        h1 h2 h3 h4 h5 h6 p blockquote pre
        a abbr acronym address big cite code
        del dfn em ins kbd q s samp
        small strike strong sub sup tt var
        b u i center
        dl dt dd ol ul li
        fieldset form label legend
        table caption tbody tfoot thead tr th td
        article aside canvas details embed
        figure figcaption footer header hgroup
        menu nav output ruby section summary])

    content_text = ReverseMarkdown.convert(content_text)
    content_text = ActionController::Base.helpers.strip_tags(content_text)
    decoder.decode(content_text)
  end

  def text_format(text)
    EntriesHelper.text_format(text)
  end
end

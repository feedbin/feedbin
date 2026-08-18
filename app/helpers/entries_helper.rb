module EntriesHelper
  # Digests the rows the partial renders, so one row update invalidates
  # every view referencing it without touching owner rows. Every part must
  # come from something already loaded (Favicon.for_entries map,
  # with_list_associations) or the key is an N+1 per render.
  def self.entries_cache_key(entry, favicons = {})
    [entry, entry.feed, entry_favicon(entry, favicons), entry.preview_image_record, entry.channel_image_record, "v9"]
  end

  # The same sources FaviconComponent renders from, resolved the same way:
  # Pages entries key on their own host, everything else on the feed's
  # favicon. Mirroring the component keeps the digest from drifting.
  def self.entry_favicon(entry, favicons)
    return favicons[entry.hostname] if entry.feed&.pages?
    entry.feed&.favicon
  end

  # The one render invocation for the entry list, shared by the view and the
  # cache warmer so the warmer cannot warm keys no view reads.
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

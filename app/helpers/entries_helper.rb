module EntriesHelper
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

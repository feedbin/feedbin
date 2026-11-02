class ContentFormatter
  ALLOWLIST_BASE = {}.tap do |hash|
    hash[:elements] = %w[
      h1 h2 h3 h4 h5 h6 h7 h8 br b i strong em a pre code img tt div ins del sup sub
      p ol ul table thead tbody tfoot blockquote dl dt dd kbd q samp var hr ruby rt
      rp li tr td th s strike summary details figure figcaption audio video source
      small iframe
    ]

    hash[:attributes] = {
      "a" => ["href"],
      "img" => ["src", "longdesc"],
      "div" => ["itemscope", "itemtype"],
      "blockquote" => ["cite"],
      "del" => ["cite"],
      "ins" => ["cite"],
      "q" => ["cite"],
      "source" => ["src"],
      "video" => ["src", "poster", "playsinline", "loop", "muted", "controls", "preload"],
      "audio" => ["src"],
      "td" => ["align"],
      "th" => ["align"],
      "iframe" => ["src", "width", "height"],
      :all => %w[
        abbr accept accept-charset accesskey action alt axis border cellpadding
        cellspacing char charoff charset checked clear cols colspan color compact
        coords datetime dir disabled enctype for frame headers height hreflang hspace
        ismap label lang maxlength media method multiple name nohref noshade nowrap
        open prompt readonly rel rev rows rowspan rules scope selected shape size span
        start summary tabindex target title type usemap valign value vspace width
        itemprop id
      ]
    }

    hash[:protocols] = {
      "a" => {
        "href" => ["http", "https", "mailto", :relative]
      },
      "blockquote" => {
        "cite" => ["http", "https", :relative]
      },
      "del" => {
        "cite" => ["http", "https", :relative]
      },
      "ins" => {
        "cite" => ["http", "https", :relative]
      },
      "q" => {
        "cite" => ["http", "https", :relative]
      },
      "img" => {
        "src" => ["http", "https", :relative, "data"],
        "longdesc" => ["http", "https", :relative]
      },
      "video" => {
        "src" => ["http", "https"],
        "poster" => ["http", "https"]
      },
      "audio" => {
        "src" => ["http", "https"]
      },
      # Sanitize only enforces a scheme where :protocols names one, so every
      # attribute above that can hold a URL needs an entry here or it accepts
      # javascript: and data: unchallenged.
      "iframe" => {
        "src" => ["http", "https"]
      },
      "source" => {
        "src" => ["http", "https"]
      }
    }

    hash[:remove_contents] = %w[script style iframe object embed]
  end

  ALLOWLIST_DEFAULT = ALLOWLIST_BASE.clone.tap do |hash|
    transformers = Transformers.new
    hash[:transformers] = [transformers.class_allowlist, transformers.table_elements, transformers.top_level_li, transformers.video, transformers.links]
  end

  ALLOWLIST_EVERNOTE = {
    elements: %w[
      a abbr acronym address area b bdo big blockquote br caption center cite code col colgroup dd
      del dfn div dl dt em font h1 h2 h3 h4 h5 h6 hr i img ins kbd li map ol p pre q s samp small
      strike strong sub sup table tbody td tfoot th thead tr tt u ul var xmp
    ],
    remove_contents: ["script", "style", "iframe", "object", "embed", "title"],
    attributes: {
        "a"     => ["href"],
        "img"   => ["src", "width", "height", "alt"],
        "ol"    => Sanitize::Config::RELAXED[:attributes]["ol"],
        "ul"    => Sanitize::Config::RELAXED[:attributes]["ul"],
        "table" => Sanitize::Config::RELAXED[:attributes]["table"],
        "td"    => Sanitize::Config::RELAXED[:attributes]["td"],
        "th"    => Sanitize::Config::RELAXED[:attributes]["th"]
    },
    protocols: {
      "a" => {"href" => ["http", "https", :relative]},
      "img" => {"src" => ["http", "https", :relative]}
    }
  }

  # Sanitize merges into the config it is handed. Frozen, a config shared by
  # every call can't accumulate anything between calls.
  [ALLOWLIST_BASE, ALLOWLIST_DEFAULT, ALLOWLIST_EVERNOTE].each { Sanitize::Config.freeze_config(_1) }

  # A format is a filter chain and the context those filters read. The context
  # comes from the entry, or an explicit base URL, and never from a user, so
  # one rendering serves everyone and can be stored. Anything that varies per
  # user, such as whether images go through the proxy, is left to JavaScript,
  # which reads the data attributes the filters write.
  class Format
    attr_reader :entry, :base_url

    def initialize(entry: nil, base_url: nil)
      @entry = entry
      @base_url = base_url
    end

    def call(content)
      result = HTML::Pipeline.new(filters, context).call(ContentFormatter.document(content))
      serialize(result[:output])
    end

    def filters
      raise NotImplementedError
    end

    def context
      {}
    end

    # The finished fragment as a string.
    def serialize(output)
      output.to_s
    end

    private

    def newsletter?
      entry&.feed&.newsletter? || false
    end

    # Relative links and image sources resolve against the entry or an
    # explicit base URL. With neither there is nothing to resolve from, so
    # the filters that need one are left out rather than failing the render.
    def resolves_urls?
      !!(entry || base_url)
    end

    # Where relative links and image sources resolve from.
    def url_context
      {
        image_base_url:    base_url || entry.base_url,
        image_subpage_url: base_url || entry.fully_qualified_url || "",
        href_base_url:     base_url || entry.base_url,
        href_subpage_url:  base_url || entry.fully_qualified_url || ""
      }
    end

    # CamoFilter moves each image source to data-camo-src and keeps the
    # original in data-canonical-src. The page's JavaScript picks one.
    def camo_context
      return {} unless ENV["CAMO_HOST"] && ENV["CAMO_KEY"]
      {
        asset_proxy: ENV["CAMO_HOST"],
        asset_proxy_secret_key: ENV["CAMO_KEY"],
        asset_src_attribute: "data-camo-src"
      }
    end

    def camo?
      camo_context.any?
    end
  end

  # What the site renders. Iframes become placeholders and images are proxied,
  # both of which the page's JavaScript finishes.
  class Web < Format
    def filters
      [
        HTML::Pipeline::LazyLoadFilter,
        ContentFilters::FigureControls,
        (ContentFilters::Substack if substack?),
        (HTML::Pipeline::AbsoluteHrefFilter if resolves_urls?),
        (HTML::Pipeline::AbsoluteSourceFilter if resolves_urls?),
        HTML::Pipeline::SmileyFilter,
        ContentFilters::Scrub,
        ContentFilters::Attributes,
        HTML::Pipeline::SrcFixer,
        HTML::Pipeline::IframeFilter,
        ContentFilters::GhostCard,
        (HTML::Pipeline::CamoFilter if camo?)
      ].compact
    end

    def context
      base = {
        scrub_mode: newsletter? ? :newsletter : :default,
        embed_url: Rails.application.routes.url_helpers.iframe_embeds_path,
        embed_classes: "iframe-placeholder entry-callout system-content"
      }
      base.merge!(camo_context)
      base.merge!(url_context) if resolves_urls?
      base
    end

    private

    def substack?
      entry&.newsletter_from =~ /@substack\.com/
    end
  end

  # What API clients get: sanitized HTML with absolute URLs and nothing that
  # needs Feedbin's JavaScript to finish. Clients depend on this staying put.
  class Api < Format
    def filters
      [
        (HTML::Pipeline::AbsoluteSourceFilter if resolves_urls?),
        (HTML::Pipeline::AbsoluteHrefFilter if resolves_urls?),
        HTML::Pipeline::ProtocolFilter,
        ContentFilters::Scrub,
        ContentFilters::Attributes,
        (HTML::Pipeline::CamoFilter if camo?)
      ].compact
    end

    # API clients load src as before; data-camo-src is there for the ones
    # that honor the proxy_images preference.
    def context
      context = {scrub_mode: newsletter? ? :newsletter : :default}
      context.merge!(url_context) if resolves_urls?
      context.merge!(camo_context, asset_keep_src: true) if camo?
      context
    end
  end

  # A newsletter as sent: the full HTML email, sanitized and proxied, for the
  # "show original" view.
  class Full < Format
    def filters
      [HTML::Pipeline::SanitizationFilter, (HTML::Pipeline::CamoFilter if camo?)].compact
    end

    def context
      {whitelist: Sanitize::Config::RELAXED}.merge(camo_context)
    end

    def call(content)
      super(self.class.media_queries(content))
    end

    # Email layouts switch to a narrow single column below a max-width
    # breakpoint. Shown in the reader pane, which is narrower than the email
    # was designed for, that column would win, so any breakpoint of 400px or
    # more is pushed out of reach.
    def self.media_queries(html)
      regex = /@media(.*?)\(max-width:(.*?)px\)(.*?){/
      html.gsub(regex) do |string|
        matches = string.match(regex)
        width = matches[2].strip
        if width.to_i.to_s == width
          width = width.to_i >= 400 ? 10_000 : width.to_i
          string = "@media#{matches[1]}(max-width:#{width}px)#{matches[3]}{"
        end
        string
      end
    rescue
      html
    end
  end

  class Evernote < Format
    def filters
      [
        HTML::Pipeline::SanitizationFilter,
        HTML::Pipeline::SrcFixer,
        HTML::Pipeline::AbsoluteSourceFilter,
        HTML::Pipeline::AbsoluteHrefFilter,
        HTML::Pipeline::ProtocolFilter
      ]
    end

    def context
      url_context.merge(whitelist: ALLOWLIST_EVERNOTE)
    end

    def serialize(output)
      output.to_xml
    end
  end

  class Absolute < Format
    def filters
      [HTML::Pipeline::AbsoluteSourceFilter, HTML::Pipeline::AbsoluteHrefFilter]
    end

    def context
      url_context
    end
  end

  # The version stored renderings are written with. A stored rendering with
  # another version is re-rendered on read. Bump it with any change that
  # alters output; the fingerprint test fails until you do.
  VERSION = 2

  # redcarpet paragraphs text entries; addressable normalizes every URL the
  # filters rewrite.
  FINGERPRINT_GEMS = %w[html-pipeline html_diff sanitize nokogiri loofah zstd-ruby redcarpet addressable].freeze

  # Not covered, so a change to them needs a VERSION bump by hand: the URL
  # helpers on Entry and Feed (base_url, fully_qualified_url,
  # site_relative_url) and Entry#content_format.
  def self.fingerprint_files
    root = Rails.root
    [
      root.join("app/models/content_formatter.rb"),
      *Dir[root.join("app/models/content_filters/*.rb")].sort.map { Pathname(it) },
      root.join("app/models/entry_rendering.rb"),
      root.join("config/initializers/transformers.rb")
    ]
  end

  # A digest of everything that decides what a rendering contains: the
  # formatter, its filters, the sanitizer's transformers, the storage format,
  # and the gems they call.
  def self.fingerprint
    digest = Digest::SHA256.new
    fingerprint_files.select(&:exist?).each { digest << it.read }
    specs = Bundler.locked_gems.specs.index_by(&:name)
    FINGERPRINT_GEMS.each do |name|
      spec = specs.fetch(name)
      revision = spec.source.respond_to?(:revision) ? spec.source.revision : ""
      digest << "#{name} #{spec.version} #{revision}\n"
    end
    digest.hexdigest
  end

  # The formats an entry can be stored in. Storage decides which of these an
  # entry needs; this is the complete list of what can be built ahead of time.
  FORMATS = {
    web: Web,
    api: Api,
    full: Full
  }.freeze

  # The versions EntryRendering stores for every entry, in storage order.
  # full is only for a newsletter, diff only for an edited entry, and
  # extracted only for an entry with saved pages; for any other entry those
  # are nil.
  VERSIONS = %i[web api full diff extracted].freeze

  def self.render(format, content, entry: nil, base_url: nil)
    FORMATS.fetch(format).new(entry: entry, base_url: base_url).call(content)
  end

  # Every stored version of an entry, by name, made from the entry alone.
  def self.versions(entry)
    source = source_html(entry)
    web = render(:web, source, entry: entry)
    {
      web: web,
      api: render(:api, source, entry: entry),
      full: (render(:full, source, entry: entry) if entry.feed&.newsletter?),
      diff: diff(entry, web),
      extracted: extracted(entry)
    }
  end

  # The api rendering of each page HarvestLinks saved for the entry, as a
  # JSON object of URL to HTML. A saved page has no entry of its own, so its
  # URL is the base for its links. Pages that failed to extract or format
  # are left out; nil when none are left.
  def self.extracted(entry)
    pages = entry.data&.dig("saved_pages")
    return nil unless pages.respond_to?(:each)
    rendered = pages.each_with_object({}) do |(url, data), hash|
      next unless data.respond_to?(:dig) && data["result"]
      hash[url] = render(:api, MercuryParser.new(nil, data: data).content, base_url: url)
    rescue => exception
      Rails.logger.info { "ContentFormatter.extracted failed entry=#{entry.id} url=#{url} #{exception.inspect}" }
    end
    JSON.generate(rendered) if rendered.any?
  end

  # The HTML an entry's web and api versions are formatted from. Text entries
  # are paragraphed first, and a YouTube entry gets its player ahead of the
  # description.
  def self.source_html(entry, html = entry.content)
    if entry.content_format == "text"
      text_email(html).to_s
    elsif entry.data && entry.data["youtube_video_id"].present?
      player = ActionController::Base.helpers.content_tag(:iframe, "", src: "https://www.youtube.com/embed/#{entry.data["youtube_video_id"]}?rel=0&amp;showinfo=0", frameborder: 0, allowfullscreen: true, width: 1280, height: 720)
      player.to_str + text_email(html).to_s
    else
      html.to_s
    end
  end

  # The web rendering of an edited entry's original content against its
  # current one. Only for an entry whose first version was kept and differs
  # in length, the rule the diff view has always used; a failed diff is no
  # diff. Pass the entry's web rendering when it is already in hand.
  def self.diff(entry, web = render(:web, source_html(entry), entry: entry))
    content = entry.content
    original = entry.original_content
    return nil unless content && original.present? && original.length != content.length
    before = render(:web, source_html(entry, original), entry: entry)
    HTMLDiff::Diff.new("<div>#{before}</div>", "<div>#{web}</div>").inline_html
  rescue => exception
    Rails.logger.info { "ContentFormatter.diff failed entry=#{entry.id} #{exception.inspect}" }
    nil
  end

  def self.format!(content, entry = nil, base_url = nil)
    Web.new(entry: entry, base_url: base_url).call(content)
  end

  def self.api_format(content, entry, base_url = nil)
    Api.new(entry: entry, base_url: base_url).call(content)
  rescue
    content
  end

  def self.newsletter_format(content)
    Full.new.call(content)
  end

  def self.evernote_format(content, entry)
    Evernote.new(entry: entry).call(content)
  rescue
    content
  end

  def self.absolute_source(content, entry, base_url = nil)
    Absolute.new(entry: entry, base_url: base_url).call(content)
  rescue
    content
  end

  def self.summary(content, length = nil)
    return "" if content.nil?

    content = HTML::Pipeline.new([ContentFilters::Scrub])
      .call(document(content))[:output]
      .to_text(encode_special_chars: false).gsub(/\s+/, " ").squish
    content = content.truncate(length, separator: " ", omission: "") if length
    content
  rescue HTML::Pipeline::Filter::InvalidDocumentException
    ""
  end

  def self.text_email(content)
    markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML.new(hard_wrap: true), autolink: true)
    content = markdown.render(content)
    Sanitize.fragment(content, ALLOWLIST_DEFAULT).html_safe
  rescue
    content
  end

  def self.document(html)
    Loofah.html5_fragment(html)
  rescue => exception
    if parser_limit?(exception)
      return Loofah.html4_fragment(html)
    end
    raise
  end

  # Gumbo stops at 400 levels of nesting. HTML email is the worst case for that
  # limit — mail templates lay a message out by nesting tables inside tables —
  # so retry past it rather than let the newsletter fail to render at all.
  #
  # The retry raises the same parser's limit instead of dropping to HTML4: HTML4
  # survives the depth by discarding the body, which loses the newsletter.
  HTML5_MAX_TREE_DEPTH = 10_000

  # Gumbo also stops at 400 attributes on one element, which broken markup
  # reaches when an unclosed quote turns the rest of a tag into attributes.
  # Each new attribute is checked against the element's others, so the cost
  # grows with the square of the count: about 0.3 s at 10,000 and 30 s at
  # 100,000. The parse holds the GVL that long, stalling every thread in the
  # process, so the retry raises the limit but never removes it. Past it,
  # HTML4 parses the rest at the same square-law cost.
  HTML5_MAX_ATTRIBUTES = 10_000

  def self.html_document(html)
    Nokogiri::HTML5(html)
  rescue => exception
    raise unless parser_limit?(exception)
    begin
      Nokogiri::HTML5(html, max_tree_depth: HTML5_MAX_TREE_DEPTH, max_attributes: HTML5_MAX_ATTRIBUTES)
    rescue => exception
      raise unless parser_limit?(exception)
      Nokogiri::HTML4(html)
    end
  end

  def self.parser_limit?(exception)
    exception.message =~ /Document tree depth limit exceeded|Attributes per element limit exceeded|stack level too deep/i
  end
end

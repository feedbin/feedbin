class Whitelist
  def base
    {}.tap do |hash|
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
        "video" => ["src", "poster"],
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
        ],
      }

      hash[:protocols] = {
        "a" => {
          "href" => ["http", "https", "mailto", :relative],
        },
        "blockquote" => {
          "cite" => ["http", "https", :relative],
        },
        "del" => {
          "cite" => ["http", "https", :relative],
        },
        "ins" => {
          "cite" => ["http", "https", :relative],
        },
        "q" => {
          "cite" => ["http", "https", :relative],
        },
        "img" => {
          "src" => ["http", "https", :relative, "data"],
          "longdesc" => ["http", "https", :relative],
        },
        "video" => {
          "src" => ["http", "https"],
          "poster" => ["http", "https"],
        },
        "audio" => {
          "src" => ["http", "https"],
        },
      }

      hash[:remove_contents] = %w[script style iframe object embed]
    end
  end

  def default
    transformers = Transformers.new
    base.clone.tap do |hash|
      hash[:transformers] = [transformers.class_whitelist, transformers.table_elements, transformers.top_level_li]
    end
  end

  def newsletter
    base.clone.tap do |hash|
      hash[:elements] = hash[:elements] - %w[table thead tbody tfoot tr td]
    end
  end
end

whitelist = Whitelist.new
Feedbin::Application.config.base = whitelist.base
Feedbin::Application.config.whitelist = whitelist.default
Feedbin::Application.config.newsletter_whitelist = whitelist.newsletter

Feedbin::Application.config.evernote_whitelist = {
  elements: %w[
    a abbr acronym address area b bdo big blockquote br caption center cite code col colgroup dd
    del dfn div dl dt em font h1 h2 h3 h4 h5 h6 hr i img ins kbd li map ol p pre q s samp small
    span strike strong sub sup table tbody td tfoot th thead title tr tt u ul var xmp
  ],
  remove_contents: ["script", "style", "iframe", "object", "embed"],
  attributes: {
    "a" => ["href"],
    "img" => ["src"],
    :all => ["align", "alt", "border", "cellpadding", "cellspacing", "cite", "cols", "colspan", "color",
             "coords", "datetime", "dir", "disabled", "enctype", "for", "height", "hreflang", "label", "lang",
             "longdesc", "name", "rel", "rev", "rows", "rowspan", "selected", "shape", "size", "span", "start",
             "summary", "target", "title", "type", "valign", "value", "vspace", "width",],
  },
  protocols: {
    "a" => {"href" => ["http", "https", :relative]},
    "img" => {"src" => ["http", "https", :relative]},
  },
}

Feedbin::Application.config.whitelist = HTML::Pipeline::SanitizationFilter::WHITELIST.clone
Feedbin::Application.config.whitelist[:attributes][:all] += ['id']
Feedbin::Application.config.whitelist[:attributes]['source'] = ['src']
Feedbin::Application.config.whitelist[:elements] += ['figure', 'figcaption', 'audio', 'video', 'source']
Feedbin::Application.config.whitelist[:protocols]['img']['src'] += ['data']

Feedbin::Application.config.evernote_whitelist = {
  :elements => %w(
    a abbr acronym address area b bdo big blockquote br caption center cite code col colgroup dd
    del dfn div dl dt em font h1 h2 h3 h4 h5 h6 hr i img ins kbd li map ol p pre q s samp small
    span strike strong sub sup table tbody td tfoot th thead title tr tt u ul var xmp
  ),
  :remove_contents => ['script', 'style', 'iframe', 'object', 'embed'],
  :attributes => {
    'a' => ['href'],
    'img' => ['src'],
    :all => ['align', 'alt', 'border', 'cellpadding', 'cellspacing', 'cite', 'cols', 'colspan', 'color',
      'coords', 'datetime', 'dir', 'disabled', 'enctype', 'for', 'height', 'hreflang', 'label', 'lang',
      'longdesc', 'name', 'rel', 'rev', 'rows', 'rowspan', 'selected', 'shape', 'size', 'span', 'start',
      'summary', 'target', 'title', 'type','valign', 'value', 'vspace', 'width']
  },
  :protocols => {
    'a'   => {'href' => ['http', 'https', :relative]},
    'img' => {'src'  => ['http', 'https', :relative]}
  }
}



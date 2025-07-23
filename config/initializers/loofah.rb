Loofah::HTML5::SafeList::ALLOWED_ELEMENTS_WITH_LIBXML2.merge %w[
  iframe
  picture
  source
]

Loofah::HTML5::SafeList::ALLOWED_PROTOCOLS.merge %w[
  apollo
  drafts
  ivory
  omnifocus
  pocket
  things
  todoist
  winstonapp
]

Loofah::HTML5::SafeList::ALLOWED_ATTRIBUTES.merge %w[
  srcset
  sizes
]

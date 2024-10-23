Feedbin::Application.config.youtube_embed_urls = [
  %r{.*?//(?:www|m)\.youtube-nocookie\.com/embed/(.*?)(\?|$)},
  %r{.*?//(?:www|m)\.youtube\.com/embed/(.*?)(\?|$)},
  %r{.*?//(?:www|m)\.youtube\.com/user/.*?#\w/\w/\w/\w/(.+)\b},
  %r{.*?//(?:www|m)\.youtube\.com/v/(.*?)(#|\?|$)},
  %r{.*?//(?:www|m)\.youtube\.com/watch\?(?:.*?&)?v=([^&#]*)(?:&|#|$)},
  %r{.*?//youtube-nocookie\.com/embed/(.*?)(\?|$)},
  %r{.*?//youtube\.com/embed/(.*?)(\?|$)},
  %r{.*?//youtu\.be/(.*?)(\?|$)}
]

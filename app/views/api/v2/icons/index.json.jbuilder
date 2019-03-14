json.array!(@favicons) do |favicon|
  json.extract! favicon, :host
  json.url favicon.cdn_url
end

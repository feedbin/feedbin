json.array!(@favicons) do |favicon|
  json.extract! favicon, :host, :favicon
end

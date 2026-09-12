json.array!(@icons) do |icon|
  json.host icon[:host]
  json.url icon[:url]
end

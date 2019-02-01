json.array!(@taggings) do |tagging|
  json.partial! "api/v2/taggings/tagging", tagging: tagging
end

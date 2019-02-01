json.array!(@suggested_categories) do |suggested_category|
  json.partial! "api/v2/suggested_categories/suggested_category", suggested_category: suggested_category
end

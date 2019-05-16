json.extract! import, :id, :complete, :created_at
json.import_items import.import_items do |import_item|
  json.title import_item.details[:title]
  json.feed_url import_item.details[:xml_url]
  json.status import_item.status
end
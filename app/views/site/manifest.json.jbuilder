json.name "Feedbin"
json.scope root_path
json.start_url login_path
json.display "standalone"
json.background_color @color
json.theme_color @color
json.description "Follow your passions with RSS, YouTube, and email newsletters."
json.icons @icons do |icon|
  json.extract! icon, :src, :sizes, :type, :purpose
end
json.share_target do
  json.action pages_path
  json.params do
    json.title "title"
    json.text "url"
    json.url "url"
  end
end

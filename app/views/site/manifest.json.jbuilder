json.name "Feedbin"
json.scope root_path
json.start_url login_path
json.display "standalone"
json.background_color @color
json.theme_color @color
json.description "Follow your passions with RSS, Twitter, and email newsletters."
json.icons @icons do |icon|
  json.extract! icon, :src, :sizes, :type, :purpose
end
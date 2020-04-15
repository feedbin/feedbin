if params.key?(:private)
  json.partial! "api/v2/entries/entry_private", entry: entry
elsif params.key?(:mode) && params[:mode] == "extended"
  json.partial! "api/v2/entries/entry_extended", entry: entry
else
  json.partial! "api/v2/entries/entry_default", entry: entry
end

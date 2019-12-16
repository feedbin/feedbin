json.cache! [@entries, params[:mode], params[:include_content_diff], params[:include_original], params[:include_enclosure], params[:private]] do
  if params.key?(:private)
    json.array!(@entries) do |entry|
      json.partial! "api/v2/entries/entry_private", entry: entry
    end
  elsif params.key?(:mode) && params[:mode] == "extended"
      json.array!(@entries) do |entry|
        json.partial! "api/v2/entries/entry_extended", entry: entry
      end
  else
    json.array!(@entries) do |entry|
      json.partial! "api/v2/entries/entry", entry: entry
    end
  end
end

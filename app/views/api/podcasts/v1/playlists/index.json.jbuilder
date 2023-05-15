json.array!(@playlists) do |playlist|
  json.partial! "playlist", playlist: playlist
end

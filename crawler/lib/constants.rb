pigo_name = "pigo_#{Etc.uname[:sysname].downcase}_#{Etc.uname[:machine]}"
CASCADE = File.expand_path("cascade/facefinder", __dir__)
PIGO = File.expand_path("../bin/#{pigo_name}", __dir__)
raise "Architecture not supported. Add #{pigo_name} to ./bin from https://github.com/esimov/pigo" unless File.executable?(PIGO)

IMAGE_PRESETS = {
  primary: {
    width: 542,
    height: 304,
    minimum_size: 20_000,
    crop: :smart_crop,
    job_class: "EntryImage"
  },
  twitter: {
    width: 542,
    height: 304,
    minimum_size: 10_000,
    crop: :smart_crop,
    job_class: "TwitterLinkImage"
  },
  youtube: {
    width: 542,
    height: 304,
    minimum_size: nil,
    crop: :fill_crop,
    job_class: "EntryImage"
  },
  podcast: {
    width: 200,
    height: 200,
    minimum_size: nil,
    crop: :fill_crop,
    job_class: "ItunesImage"
  }
}

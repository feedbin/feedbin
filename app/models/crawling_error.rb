class CrawlingError
  ERRORS = {
    "Addressable::URI::InvalidURIError" => "Invalid URL",
    "Feedkit::ClientError"              => "Connection error",
    "Feedkit::ConnectionError"          => "Connection error",
    "Feedkit::InvalidUrl"               => "Invalid URL",
    "Feedkit::NotFound"                 => "Not found",
    "Feedkit::ServerError"              => "Server error",
    "Feedkit::SSLError"                 => "Server error",
    "Feedkit::TimeoutError"             => "Connection timed out",
    "Feedkit::TooManyRedirects"         => "Server error",
    "Feedkit::Unauthorized"             => "Unauthorized",
    "HTTP::TimeoutError"                => "Connection timed out",
    "NoMethodError"                     => "Server error",
  }

  def self.message(error_code)
    ERRORS[error_code] || "Connection error"
  end
end

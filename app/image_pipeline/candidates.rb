class Candidates
  NETWORK_EXCEPTIONS = [Encoding::InvalidByteSequenceError,
                        Encoding::UndefinedConversionError,
                        Errno::ECONNRESET,
                        HTTParty::RedirectionTooDeep,
                        Net::OpenTimeout,
                        Net::ReadTimeout,
                        OpenSSL::SSL::SSLError,
                        Timeout::Error,
                        URI::InvalidURIError,
                        Zlib::DataError]


  def initialize(entry, feed)
    @entry = entry
    @feed = feed
  end

  def try_candidates(candidates)
    download = nil
    candidates.each do |candidate|
      begin
        break if download = download_candidate(candidate)
      rescue *NETWORK_EXCEPTIONS
        Librato.increment 'entry_image.exception'
      rescue Exception => exception
        Librato.increment 'entry_image.exception'
        Honeybadger.notify(exception)
      end
    end
    download
  end

  def download_candidate(candidate)
    download = nil
    if candidate.valid?
      attempt = DownloadImage.new(candidate.original_url)
      if attempt.download
        download = attempt
      end
    end
    download
  end

end

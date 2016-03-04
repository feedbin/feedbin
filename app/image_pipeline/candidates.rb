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
    attempt = nil
    if candidate.valid? && candidate.original_url
      attempt = DownloadImage.new(candidate.original_url)
      if attempt.file
        processed_image = ProcessedImage.new(attempt.file)
        if processed_image.process
          download = {
            original_url: candidate.original_url.to_s,
            processed_url: processed_image.url.to_s,
            width: processed_image.width,
            height: processed_image.height,
          }
        end
      end
    end
    download
  ensure
    attempt && attempt.file && File.exist?(attempt.file) && File.delete(attempt.file)
  end

end

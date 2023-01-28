class ConditionalSassCompressor
  def compress(string)
    return string if string =~ /tailwindcss/
    options = { syntax: :scss, cache: false, read_cache: false, style: :compressed}
    begin
      Sprockets::Autoload::SassC::Engine.new(string, options).render
    rescue => e
      puts "Could not compress '#{string[0..65]}'...: #{e.message}, skipping compression"
      string
    end
  end
end
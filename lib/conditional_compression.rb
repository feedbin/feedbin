class ConditionalCompression
  def compress(string)
    if string.include? "lib.js"
      Uglifier.compile(string)
    else
      string
    end
  end
end

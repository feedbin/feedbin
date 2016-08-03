require 'socket'
require 'uri'
require 'net/http'

class DummyServer

  WEB_ROOT = 'www'
  HOST = 'localhost'

  CONTENT_TYPE_MAPPING = {
    'html' => 'text/html',
    'txt' => 'text/plain',
    'png' => 'image/png',
    'jpg' => 'image/jpeg'
  }

  DEFAULT_CONTENT_TYPE = 'application/octet-stream'

  attr_accessor :on_req

  def initialize
    @port = 9595
    @listen_thread = nil
    @threads = []
  end

  def listen
    @server = new_server

    @listen_thread = Thread.new do
      loop do
        Thread.start(@server.accept) do |socket|
          @threads << Thread.current
          handle(socket)
        end
      end
    end.tap { |t| t.abort_on_exception = true }
  end

  def stop
    exit_thread(@listen_thread)
    @threads.each { |t| exit_thread(t) }
    @server.close
    @server = nil
    @listen_thread = nil
    @threads = []
  end

  def url(path)
    URI::HTTP.build(host: HOST, port: @port, path: path).to_s
  end

  private

  def content_type(path)
    ext = File.extname(path).split(".").last
    CONTENT_TYPE_MAPPING.fetch(ext, DEFAULT_CONTENT_TYPE)
  end

  def requested_file(request_line)
    request_uri  = request_line.split(" ")[1]
    path = URI.unescape(URI(request_uri).path)

    clean = []

    parts = path.split("/")

    parts.each do |part|
      next if part.empty? || part == '.'
      part == '..' ? clean.pop : clean << part
    end

    File.join(File.dirname(__FILE__), WEB_ROOT, *clean)
  end

  def respond(status, headers)
    h = headers.each_with_object(["HTTP/1.1 #{status}"]) do |(header, value), array|
      array.push("#{header}: #{value}")
    end.concat(["", ""]).join("\r\n")
  end

  def handle(socket)
    request_line = socket.gets

    path = requested_file(request_line)
    path = File.join(path, 'index.html') if File.directory?(path)

    if File.exist?(path) && !File.directory?(path)
      File.open(path, "rb") do |file|
        headers = {
          "Content-Type" => content_type(file),
          "Content-Length" => file.size,
          "Connection" => "close"
        }
        socket.print respond("200 OK", headers)
        IO.copy_stream(file, socket)
      end
    else
      message = "File not found\n"
      headers = {
        "Content-Type" => "text/plain",
        "Content-Length" => message.size,
        "Connection" => "close"
      }
      socket.print respond("404 Not Found", headers)
      socket.print message
    end

    socket.close unless socket.closed?
  end

  def new_server
    TCPServer.new(HOST, @port)
  end

  def exit_thread(thread)
    return unless thread && thread.alive?
    thread.exit
    thread.join
  end
end

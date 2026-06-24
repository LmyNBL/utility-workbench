#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "open3"
require "socket"
require "tempfile"
require "time"
require "uri"

SCRIPT_DIR = File.expand_path(__dir__)

BIND = ENV.fetch("WRAPPER_BIND", "0.0.0.0")
PORT = Integer(ENV.fetch("WRAPPER_PORT", "25502"))
SUBCONVERTER_URL = ENV.fetch("SUBCONVERTER_URL", "http://127.0.0.1:25501/sub")
SUBCONVERTER_TARGET = ENV.fetch("SUBCONVERTER_TARGET", "clash")
SUBSTORE_URL = ENV.fetch(
  "SUBSTORE_URL",
  "http://192.168.11.142:25500/55431c604f1b9832efca16da5493d4c8/download/collection/All"
)
SUBCONVERTER_CONFIG_URL = ENV.fetch(
  "SUBCONVERTER_CONFIG_URL",
  "https://raw.githubusercontent.com/LmyNBL/utility-workbench/main/profile-overlays/acl4ssr/full-noauto-plus.ini"
)
GROUPS_FILE = ENV.fetch("GROUPS_FILE", File.join(SCRIPT_DIR, "groups.yml"))
APPLY_SCRIPT = ENV.fetch("APPLY_SCRIPT", File.join(SCRIPT_DIR, "apply-profile-overlay.rb"))
FETCH_TIMEOUT_SECONDS = Integer(ENV.fetch("FETCH_TIMEOUT_SECONDS", "120"))

def log(message)
  $stderr.puts("#{Time.now.utc.iso8601} #{message}")
end

def required_env(name)
  value = ENV[name]
  raise "missing required environment variable: #{name}" if value.nil? || value.empty?

  value
end

def build_subconverter_uri
  uri = URI(SUBCONVERTER_URL)
  params = URI.decode_www_form(uri.query.to_s)
  params << ["target", SUBCONVERTER_TARGET]
  params << ["url", SUBSTORE_URL]
  params << ["config", SUBCONVERTER_CONFIG_URL]
  uri.query = URI.encode_www_form(params)
  uri
end

def fetch_converted_yaml
  uri = build_subconverter_uri
  Net::HTTP.start(
    uri.hostname,
    uri.port,
    use_ssl: uri.scheme == "https",
    open_timeout: 10,
    read_timeout: FETCH_TIMEOUT_SECONDS
  ) do |http|
    response = http.request(Net::HTTP::Get.new(uri))
    unless response.is_a?(Net::HTTPSuccess)
      raise "subconverter returned HTTP #{response.code}"
    end

    body = response.body.to_s
    raise "subconverter returned an empty body" if body.empty?

    body
  end
end

def overlay_environment
  env = {
    "DIALER_SERVER" => required_env("DIALER_SERVER"),
    "DIALER_PORT" => required_env("DIALER_PORT")
  }

  %w[
    DIALER_USERNAME
    DIALER_PASSWORD
    DIALER_NAME
    DIALER_TYPE
    DIALER_SUFFIX
  ].each do |name|
    value = ENV[name]
    env[name] = value if value && !value.empty?
  end

  env
end

def render_overlay_yaml
  input = Tempfile.new(["subconverter", ".yaml"])
  output = Tempfile.new(["overlay", ".yaml"])
  input.binmode
  output.binmode

  begin
    input.write(fetch_converted_yaml)
    input.flush

    _stdout, stderr, status = Open3.capture3(
      overlay_environment,
      "ruby",
      APPLY_SCRIPT,
      GROUPS_FILE,
      input.path,
      output.path
    )
    raise "overlay script failed: #{stderr.lines.last(3).join.strip}" unless status.success?

    File.binread(output.path)
  ensure
    input.close!
    output.close!
  end
end

def write_response(socket, status, reason, headers, body, head_only: false)
  body = body.b
  socket.write("HTTP/1.1 #{status} #{reason}\r\n")
  headers.merge(
    "Content-Length" => body.bytesize.to_s,
    "Connection" => "close"
  ).each do |key, value|
    socket.write("#{key}: #{value}\r\n")
  end
  socket.write("\r\n")
  socket.write(body) unless head_only
end

def handle_client(socket)
  request_line = socket.gets&.strip
  return unless request_line

  method, raw_path, = request_line.split(" ", 3)
  while (line = socket.gets)
    break if line == "\r\n" || line == "\n"
  end

  path = URI(raw_path).path
  head_only = method == "HEAD"

  case [method, path]
  in ["GET" | "HEAD", "/health"]
    write_response(
      socket,
      200,
      "OK",
      { "Content-Type" => "text/plain; charset=utf-8", "Cache-Control" => "no-store" },
      "ok\n",
      head_only: head_only
    )
  in ["GET" | "HEAD", "/sub-overlay/all"]
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    body = render_overlay_yaml
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    log("served path=/sub-overlay/all bytes=#{body.bytesize} elapsed_ms=#{elapsed_ms}")
    write_response(
      socket,
      200,
      "OK",
      {
        "Content-Type" => "text/yaml; charset=utf-8",
        "Cache-Control" => "no-store",
        "Content-Disposition" => "inline; filename=\"ALL.overlay.yaml\""
      },
      body,
      head_only: head_only
    )
  else
    write_response(
      socket,
      method == "GET" || method == "HEAD" ? 404 : 405,
      method == "GET" || method == "HEAD" ? "Not Found" : "Method Not Allowed",
      { "Content-Type" => "text/plain; charset=utf-8", "Cache-Control" => "no-store" },
      "not found\n",
      head_only: head_only
    )
  end
rescue StandardError => e
  log("request failed class=#{e.class} message=#{e.message}")
  write_response(
    socket,
    500,
    "Internal Server Error",
    { "Content-Type" => "text/plain; charset=utf-8", "Cache-Control" => "no-store" },
    "overlay failed\n"
  )
ensure
  socket.close
end

server = TCPServer.new(BIND, PORT)
log("listening bind=#{BIND} port=#{PORT}")

loop do
  client = server.accept
  Thread.new(client) { |socket| handle_client(socket) }
end

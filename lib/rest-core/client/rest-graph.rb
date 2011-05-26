
require 'rest-core'

# optional http client
begin; require 'restclient'     ; rescue LoadError; end
begin; require 'em-http-request'; rescue LoadError; end

# optional gem
begin; require 'rack'           ; rescue LoadError; end

# stdlib
require 'openssl'

require 'cgi'

RestCore::Builder.client('RestGraph',
                         :app_id, :secret,
                         :old_site,
                         :old_server, :graph_server) do

  use DefaultSite   ,  'https://graph.facebook.com/'
  use ErrorDetector , lambda{ |env| env[RESPONSE_BODY]['error'] ||
                                    env[RESPONSE_BODY]['error_code'] }
  use AutoJsonDecode, true

  use Cache         , {}
  use Timeout       ,  10
  use DefaultHeaders, {'Accept'          => 'application/json',
                       'Accept-Language' => 'en-us'}

  use ErrorHandler  , lambda{ |env| raise ::RestGraph::Error.call(env) }
  use CommonLogger  , method(:puts)

  run RestClient
end

class RestGraph::Error < RuntimeError
  include RestCore
  class AccessToken        < RestGraph::Error; end
  class InvalidAccessToken < AccessToken     ; end
  class MissingAccessToken < AccessToken     ; end

  attr_reader :error, :url
  def initialize error, url=''
    @error, @url = error, url
    super("#{error.inspect} from #{url}")
  end

  def self.call env
    error, url = env[RESPONSE_BODY], env[REQUEST_URI]
    return new(error, url) unless error.kind_of?(Hash)
    if    invalid_token?(error)
      InvalidAccessToken.new(error, url)
    elsif missing_token?(error)
      MissingAccessToken.new(error, url)
    else
      new(error, url)
    end
  end

  def self.invalid_token? error
    (%w[OAuthInvalidTokenException
        OAuthException].include?((error['error'] || {})['type'])) ||
    (error['error_code'] == 190) # Invalid OAuth 2.0 Access Token
  end

  def self.missing_token? error
    (error['error'] || {})['message'] =~ /^An active access token/ ||
    (error['error_code'] == 104) # Requires valid signature
  end
end

module RestGraph::Client
  def next_page hash, opts={}, &cb
    if hash['paging'].kind_of?(Hash) && hash['paging']['next']
      request(opts, [:get, URI.encode(hash['paging']['next'])], &cb)
    else
      yield(nil) if block_given?
    end
  end

  def prev_page hash, opts={}, &cb
    if hash['paging'].kind_of?(Hash) && hash['paging']['previous']
      request(opts, [:get, URI.encode(hash['paging']['previous'])], &cb)
    else
      yield(nil) if block_given?
    end
  end
  alias_method :previous_page, :prev_page

  def for_pages hash, pages=1, opts={}, kind=:next_page, &cb
    if pages > 1
      merge_data(send(kind, hash, opts){ |result|
        yield(result.freeze) if block_given?
        for_pages(result, pages - 1, opts, kind, &cb) if result
      }, hash)
    else
      yield(nil) if block_given?
      hash
    end
  end

  # cookies, app_id, secrect related below

  def parse_rack_env! env
    env['HTTP_COOKIE'].to_s =~ /fbs_#{app_id}=([^\;]+)/
    self.data = parse_fbs!($1)
  end

  def parse_cookies! cookies
    self.data = parse_fbs!(cookies["fbs_#{app_id}"])
  end

  def parse_fbs! fbs
    self.data = check_sig_and_return_data(
      # take out facebook sometimes there but sometimes not quotes in cookies
      Rack::Utils.parse_query(fbs.to_s.gsub('"', '')))
  end

  def parse_json! json
    self.data = json &&
      check_sig_and_return_data(AutoJsonDecode.json_decode(json))
  rescue ParseError
    self.data = nil
  end

  def fbs
    "#{fbs_without_sig(data).join('&')}&sig=#{calculate_sig(data)}"
  end

  # facebook's new signed_request...

  def parse_signed_request! request
    sig_encoded, json_encoded = request.split('.')
    sig,  json = [sig_encoded, json_encoded].map{ |str|
      "#{str.tr('-_', '+/')}==".unpack('m').first
    }
    self.data = check_sig_and_return_data(
                  AutoJsonDecode.json_decode(json).merge('sig' => sig)){
                    self.class.hmac_sha256(secret, json_encoded)
                  }
  rescue ParseError
    self.data = nil
  end

  # oauth related

  def authorize_url opts={}
    query = {:client_id => app_id, :access_token => nil}.merge(opts)
    "#{site}oauth/authorize#{build_query_string(query)}"
  end

  def authorize! opts={}
    query = {:client_id => app_id, :client_secret => secret}.merge(opts)
    self.data = Rack::Utils.parse_query(
                  request({:auto_decode => false}.merge(opts),
                          [:get, url('oauth/access_token', query)]))
  end

  # old rest facebook api, i will definitely love to remove them someday

  def old_rest path, query={}, opts={}, &cb
    uri = url("method/#{path}", {:format => 'json'}.merge(query),
              old_server, opts)
    if opts[:post]
      request(
        opts.merge(:uri => uri),
        [:post,
         url("method/#{path}", {:format => 'json'}, old_server, opts),
         query],
        &cb)
    else
      request(opts, [:get, uri], &cb)
    end
  end

  def secret_old_rest path, query={}, opts={}, &cb
    old_rest(path, query, {:secret => true}.merge(opts), &cb)
  end

  def fql code, query={}, opts={}, &cb
    old_rest('fql.query', {:query => code}.merge(query), opts, &cb)
  end

  def fql_multi codes, query={}, opts={}, &cb
    old_rest('fql.multiquery',
      {:queries => AutoJsonDecode.json_encode(codes)}.merge(query), opts, &cb)
  end

  def exchange_sessions query={}, opts={}, &cb
    q = {:client_id => app_id, :client_secret => secret,
         :type => 'client_cred'}.merge(query)
    request(opts, [:post, url('oauth/exchange_sessions', q)], &cb)
  end
end

RestGraph.send(:include, RestGraph::Client)

#   module Hmac
#     # Fallback to ruby-hmac gem in case system openssl
#     # lib doesn't support SHA256 (OSX 10.5)
#     def hmac_sha256 key, data
#       OpenSSL::HMAC.digest('sha256', key, data)
#     rescue RuntimeError
#       require 'hmac-sha2'
#       HMAC::SHA256.digest(key, data)
#     end
#   end
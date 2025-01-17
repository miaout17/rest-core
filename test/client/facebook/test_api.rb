
require 'rest-core/test'

describe RestCore::Facebook do
  after do
    WebMock.reset!
    RR.verify
  end

  should 'generate correct url' do
    TestHelper.normalize_url(
    RestCore::Facebook.new(:access_token => 'awesome').
      url('path', :query => 'str')).should.eq \
      'https://graph.facebook.com/path?access_token=awesome&query=str'
  end

  should 'request to correct server' do
    stub_request(:get, 'http://nothing.godfat.org/me').with(
      :headers => {'Accept'          => 'text/plain',
                   'Accept-Language' => 'zh-tw',
                   'Accept-Encoding' => 'gzip, deflate', # this is by ruby
                  }.merge(RUBY_VERSION < '1.9.2' ?
                  {} :
                  {'User-Agent'      => 'Ruby'})).       # this is by ruby
      to_return(:body => '{"data": []}')

    RestCore::Facebook.new(:site   => 'http://nothing.godfat.org/',
                           :lang   => 'zh-tw',
                           :accept => 'text/plain').
                           get('me').should.eq({'data' => []})
  end

  should 'pass custom headers' do
    stub_request(:get, 'http://example.com/').with(
      :headers => {'Accept'          => 'application/json',
                   'Accept-Language' => 'en-us',
                   'Accept-Encoding' => 'gzip, deflate', # this is by ruby
                   'X-Forwarded-For' => '127.0.0.1',
                  }.merge(RUBY_VERSION < '1.9.2' ?
                  {} :
                  {'User-Agent'      => 'Ruby'})).       # this is by ruby
      to_return(:body => '{"data": []}')

    RestCore::Facebook.new.request(
      {:headers => {'X-Forwarded-For' => '127.0.0.1'}},
      [:get, 'http://example.com']).should.eq({'data' => []})
  end

  should 'post right' do
    stub_request(:post, 'https://graph.facebook.com/feed/me').
      with(:body => 'message=hi%20there').to_return(:body => 'ok')

    RestCore::Facebook.new(:json_decode => false).
      post('feed/me', :message => 'hi there').should == 'ok'
  end

  should 'use secret_access_token' do
    stub_request(:get,
      'https://graph.facebook.com/me?access_token=1|2').
      to_return(:body => 'ok')

    rg = RestCore::Facebook.new(
      :json_decode => false, :access_token => 'wrong',
      :app_id => '1', :secret => '2')
    rg.get('me', {}, :secret => true).should.eq 'ok'
    rg.url('me', {}, :secret => true).should.eq \
      'https://graph.facebook.com/me?access_token=1%7C2'
    rg.url('me', {}, :secret => true, :site => '/').should.eq \
      '/me?access_token=1%7C2'
  end

  should 'suppress auto-decode in an api call' do
    stub_request(:get, 'https://graph.facebook.com/woot').
      to_return(:body => 'bad json')

    rg = RestCore::Facebook.new(:json_decode => true)
    rg.get('woot', {}, :json_decode => false).should.eq 'bad json'
    rg.json_decode.should == true
  end

  should 'not raise exception when encountering error' do
    [500, 401, 402, 403].each{ |status|
      stub_request(:delete, 'https://graph.facebook.com/123').to_return(
        :body => '[]', :status => status)

      RestCore::Facebook.new.delete('123').should.eq []
    }
  end

  should 'convert query to string' do
    stub(o = Object.new).to_s{ 'i am mock' }
    stub_request(:get, "https://graph.facebook.com/search?q=i%20am%20mock").
      to_return(:body => 'ok')
    RestCore::Facebook.new(:json_decode => false).
      get('search', :q => o).should.eq 'ok'
  end
end


require 'rest-core/test'

describe RestCore::Facebook do
  after do
    WebMock.reset!
    RR.verify
  end

  describe 'cache' do
    before do
      @url, @body = "https://graph.facebook.com/cache", '{"message":"ok"}'
      @cache_key  = Digest::MD5.hexdigest(@url)
      @cache = {}
      @rg = RestCore::Facebook.new(:cache => @cache, :json_decode => false)
      stub_request(:get, @url).to_return(:body => @body).times(1)
    end

    should 'enable cache if passing cache' do
      3.times{ @rg.get('cache').should.eq @body }
      @cache.should.eq({@cache_key => @body})
    end

    should 'respect expires_in' do
      mock(@cache).method(:store){ mock!.arity{ -3 } }
      mock(@cache).store(@cache_key, @body, :expires_in => 3)
      @rg.get('cache', {}, :expires_in => 3).should.eq @body
    end

    should 'update cache if there is cache option set to false' do
      @rg.get('cache')                     .should.eq @body
      stub_request(:get, @url).to_return(:body => @body.reverse).times(2)
      @rg.get('cache')                     .should.eq @body
      @rg.get('cache', {}, :cache => false).should.eq @body.reverse
      @rg.get('cache')                     .should.eq @body.reverse
      @rg.cache = nil
      @rg.get('cache', {}, :cache => false).should.eq @body.reverse
    end
  end

  should 'not cache post/put/delete' do
    [:put, :post, :delete].each{ |meth|
      url, body = "https://graph.facebook.com/cache", '{"message":"ok"}'
      stub_request(meth, url).to_return(:body => body).times(3)

      cache = {}
      rg = RestCore::Facebook.new(:cache => cache)
      3.times{
        if meth == :delete
          rg.send(meth, 'cache').should.eq({'message' => 'ok'})
        else
          rg.send(meth, 'cache', 'payload').should.eq({'message' => 'ok'})
        end
      }
      cache.should.eq({})
    }
  end
end

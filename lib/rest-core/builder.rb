
require 'rest-core/client'
require 'rest-core/wrapper'

class RestCore::Builder
  include RestCore
  include Wrapper

  def self.client *attrs, &block
    new(&block).to_client(*attrs)
  end

  def to_client *attrs
    # struct = Struct.new(*members, *attrs) if RUBY_VERSION >= 1.9.2
    struct = Struct.new(*(members + attrs))
    client = Class.new(struct)
    client.send(:include, Client)
    client.const_set('Struct', struct)
    class << client; attr_reader :builder; end
    client.instance_variable_set(:@builder, self)
    client
  end
end

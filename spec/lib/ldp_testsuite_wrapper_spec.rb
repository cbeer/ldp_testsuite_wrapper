require 'spec_helper'

describe LdpTestsuiteWrapper do
  describe '.default_instance_options=' do
    it 'sets default options' do
      LdpTestsuiteWrapper.default_instance_options = { port: '1234' }
      expect(LdpTestsuiteWrapper.default_instance_options[:port]). to eq '1234'
    end
  end
end

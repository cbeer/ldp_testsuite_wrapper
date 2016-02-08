require 'ldp_testsuite_wrapper/version'
require 'ldp_testsuite_wrapper/instance'

module LdpTestsuiteWrapper
  def self.default_test_suite_version
    '0.1.1'
  end

  def self.default_instance_options
    @default_instance_options ||= {
      port: '8983',
      version: LdpTestsuiteWrapper.default_test_suite_version
    }
  end

  def self.default_instance_options=(options)
    @default_instance_options = options
  end

  def self.default_instance(options = {})
    @default_instance ||= LdpTestsuiteWrapper::Instance.new default_instance_options.merge(options)
  end
end

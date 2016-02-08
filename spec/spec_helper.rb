require 'coveralls'
Coveralls.wear!

require 'ldp_testsuite_wrapper'

require 'rspec'
FIXTURES_DIR = File.expand_path('fixtures', File.dirname(__FILE__))

RSpec.configure do |_config|
end

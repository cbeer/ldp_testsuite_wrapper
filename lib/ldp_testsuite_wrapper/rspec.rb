require 'nokogiri'
require 'faraday'

RSpec.shared_examples 'ldp test suite' do
  let(:report_path) { File.expand_path('test-output/testng-results.xml') }
  let(:report) { Nokogiri::XML(File.read(report_path)) }
  let(:url) { "#{server_url}/#{SecureRandom.hex}" }

  let(:container_type) do
    case
    when test_suite_options[:basic]
      'http://www.w3.org/ns/ldp#BasicContainer'
    when test_suite_options[:direct]
      'http://www.w3.org/ns/ldp#DirectContainer'
    when test_suite_options[:indirect]
      'http://www.w3.org/ns/ldp#IndirectContainer'
    end
  end

  let(:ldp_testsuite) do
    LdpTestsuiteWrapper.default_instance
  end

  before do
    response = Faraday.put do |req|
      req.url url
      req.headers['Link'] = "<#{container_type}>; rel=\"type\"" if container_type
      req.headers['Content-Type'] = 'text/turtle'
    end

    expect(response.status).to eq 201
  end

  before do
    $response ||= {}
    $response[test_suite_options] ||= begin
      File.delete(report_path) if File.exist? report_path
      status, stdout = ldp_testsuite.exec(test_suite_options.merge(server: url))

      # exitstatus 0: OK
      # exitstatus 1: hard error
      # exitstatus 2+: test suite failure
      raise stdout.string if status.exitstatus == 1

      status
    end
    
    expect(File).to exist(report_path)
  end

  describe 'LDP test suite' do
    it 'passes tests' do
      # Report PASS / FAIL tests
      aggregate_failures 'test suite response' do
        report.xpath('//test-method').each do |method|
          next if method['status'] == 'SKIP' || skipped_tests.include?(method['name'])
          expect(method['status']).to eq('PASS'), <<-EOF.gsub(/^\s+/, '')
            #{method['name']}: #{method['description']}
            #{method.xpath('exception/@class')}
            #{method.xpath('exception/message').text}
          EOF
        end
      end
    end

    it 'skips skipped tests' do
      pending 'skipped LDP tests'

      # Report skipped tests as pending
      aggregate_failures 'skipped test suite response' do
        report.xpath('//test-method').each do |method|
          next unless method['status'] == 'SKIP' || skipped_tests.include?(method['name'])
          expect(method['status']).to eq('PASS'), <<-EOF.gsub(/^\s+/, '')
            #{method['name']}: #{method['description']}
            #{method.xpath('exception/@class')}
            #{method.xpath('exception/message').text}
          EOF
        end
      end
    end
  end
end

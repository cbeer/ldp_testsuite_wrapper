require 'digest'
require 'fileutils'
require 'json'
require 'open-uri'
require 'ruby-progressbar'
require 'securerandom'
require 'socket'
require 'stringio'
require 'tmpdir'
require 'zip'

module LdpTestsuiteWrapper
  class Instance
    attr_reader :options, :pid

    ##
    # @param [Hash] options
    # @option options [String] :url
    # @option options [String] :download_dir Local directory to store the downloaded Solr zip and its md5 file in (overridden by :download_path)
    # @option options [String] :download_path Local path for storing the downloaded Solr zip file
    # @option options [Boolean] :verbose return verbose info when running commands
    # @option options [Hash] :env
    def initialize(options = {})
      @options = options
    end

    ##
    # Run a bin/solr command
    # @param [Hash] options key-value pairs to transform into command line arguments
    # @return [StringIO] an IO object for the executed shell command
    # @see https://github.com/apache/lucene-solr/blob/trunk/solr/bin/solr
    # If you want to pass a boolean flag, include it in the +options+ hash with its value set to +true+
    # the key will be converted into a boolean flag for you.
    def exec(options = {})
      extract_and_configure

      silence_output = !options.delete(:output)

      args = if options.is_a? Array
               options
             else
               ldp_testsuite_options.merge(options).map do |k, v|
                 case v
                 when true
                   "-#{k}"
                 when false, nil
                   # don't return anything
                 else
                   ["-#{k}", v.to_s]
                 end
               end.flatten.compact
      end

      args = ['java', '-jar', ldp_testsuite_binary] + args

      if IO.respond_to? :popen4
        # JRuby
        env_str = env.map { |k, v| "#{Shellwords.escape(k)}=#{Shellwords.escape(v)}" }.join(' ')
        pid, input, output, error = IO.popen4(env_str + ' ' + args.join(' '))
        @pid = pid
        stringio = StringIO.new
        if verbose? && !silence_output
          IO.copy_stream(output, $stderr)
          IO.copy_stream(error, $stderr)
        else
          IO.copy_stream(output, stringio)
          IO.copy_stream(error, stringio)
        end

        input.close
        output.close
        error.close
        exit_status = Process.waitpid2(@pid).last
      else
        IO.popen(env, args + [err: [:child, :out]]) do |io|
          stringio = StringIO.new

          if verbose? && !silence_output
            IO.copy_stream(io, $stderr)
          else
            IO.copy_stream(io, stringio)
          end

          @pid = io.pid

          _, exit_status = Process.wait2(io.pid)
        end
      end

      stringio.rewind
      if exit_status != 0
        raise "Failed to execute ldp testsuite: #{stringio.read}"
      end

      stringio
    end

    ##
    # Clean up any files ldp_testsuite_wrapper may have downloaded
    def clean!
      stop
      remove_instance_dir!
      FileUtils.remove_entry(download_path) if File.exist?(download_path)
      FileUtils.remove_entry(tmp_save_dir, true) if File.exist? tmp_save_dir
      FileUtils.remove_entry(md5sum_path) if File.exist? md5sum_path
      FileUtils.remove_entry(version_file) if File.exist? version_file
    end

    def configure
      return if File.exist? ldp_testsuite_binary

      Dir.chdir(instance_dir) do
        `mvn package`
      end
    end

    def instance_dir
      @instance_dir ||= options.fetch(:instance_dir, File.join(Dir.tmpdir, File.basename(download_url, '.zip')))
    end

    def extract_and_configure
      instance_dir = extract
      configure
      instance_dir
    end

    # rubocop:disable Lint/RescueException

    # extract a copy of solr to instance_dir
    # Does noting if solr already exists at instance_dir
    # @return [String] instance_dir Directory where solr has been installed
    def extract
      return instance_dir if extracted?

      zip_path = download

      begin
        Zip::File.open(zip_path) do |zip_file|
          # Handle entries one by one
          zip_file.each do |entry|
            dest_file = File.join(tmp_save_dir, entry.name)
            FileUtils.remove_entry(dest_file, true)
            entry.extract(dest_file)
          end
        end

      rescue Exception => e
        abort "Unable to unzip #{zip_path} into #{tmp_save_dir}: #{e.message}"
      end

      begin
        FileUtils.remove_dir(instance_dir, true)
        FileUtils.cp_r File.join(tmp_save_dir, "ldp-testsuite-#{version}"), instance_dir
      rescue Exception => e
        abort "Unable to copy #{tmp_save_dir} to #{instance_dir}: #{e.message}"
      end

      instance_dir
    ensure
      FileUtils.remove_entry tmp_save_dir if File.exist? tmp_save_dir
    end
    # rubocop:enable Lint/RescueException

    def version
      options.fetch(:version)
    end

    protected

    def extracted?
      File.exist?(ldp_testsuite_binary)
    end

    def download
      unless File.exist?(download_path)
        fetch_with_progressbar download_url, download_path
      end
      download_path
    end

    def ldp_testsuite_options
      {}
    end

    private

    def download_url
      @download_url ||= options.fetch(:url, default_download_url)
    end

    def default_download_url
      "https://github.com/w3c/ldp-testsuite/archive/#{version}.zip"
    end

    def env
      options.fetch(:env, {})
    end

    def download_path
      @download_path ||= options.fetch(:download_path, default_download_path)
    end

    def default_download_path
      File.join(download_dir, File.basename(download_url))
    end

    def download_dir
      @download_dir ||= options.fetch(:download_dir, Dir.tmpdir)
      FileUtils.mkdir_p @download_dir
      @download_dir
    end

    def verbose?
      !!options.fetch(:verbose, false)
    end

    def ldp_testsuite_binary
      File.join(instance_dir, 'target', "ldp-testsuite-#{version}-shaded.jar")
    end

    def tmp_save_dir
      @tmp_save_dir ||= Dir.mktmpdir
    end

    def fetch_with_progressbar(url, output)
      pbar = ProgressBar.create(title: File.basename(url), total: nil, format: '%t: |%B| %p%% (%e )')
      open(url, content_length_proc: lambda do |t|
        pbar.total = t if t && 0 < t
      end,
                progress_proc: lambda do |s|
                  pbar.progress = s
                end) do |io|
        IO.copy_stream(io, output)
      end
    end
  end
end

require 'fileutils'
require 'json'
require 'uri'
require "vagrant/util/subprocess"
require "vagrant/util/downloader"
require 'vagrant/box'
require 'vagrant/box_metadata'

module VagrantMutate
  class BoxLoader

    def initialize( env )
      @env = env
      @logger = Log4r::Logger.new('vagrant::mutate')
      @tmp_files = []
    end

    def prepare_for_output(name, provider_name, version)
      @logger.info "Preparing #{name} for output as #{provider_name} with version #{version}."
      safe_name = sanitize_name(name)
      dir = create_output_dir(safe_name, provider_name, version)
      box = create_box(provider_name, name, version, dir)

      if box.supported_output
        return box
      else
        raise Errors::ProviderNotSupported, :provider => provider_name, :direction => 'output'
      end
    end

    def load(box_arg, provider_name, input_version)
      if box_arg =~ /:\/\//
        box = load_from_url(box_arg)
      elsif File.file?(box_arg)
        box = load_from_file(box_arg)
      #elsif box_arg =~ /\//
      # TODO: Support pulling boxes from VagrantCloud? 
      #  raise Errors::CloudNotSupported
      else
        box = load_from_boxes_path(box_arg, provider_name, input_version)
      end

      if box.supported_input
        return box
      else
        raise Errors::ProviderNotSupported, :provider => box.provider_name, :direction => 'input'
      end
    end

    def load_from_url(url)
      @logger.info "Loading box from url #{url}"

      # test that we have a valid url
      url = URI(url)
      unless url.scheme and url.host and url.path
        raise Errors::URLError, :url => url
      end

      # extract the name of the box from the url
      # if it ends in .box remove that extension
      # if not just remove leading slash
      name = nil
      if url.path =~ /(\w+).box$/
        name = $1
      else
        name = url.path.sub(/^\//, '')
      end
      if name.empty?
        raise Errors::URLError, :url => url
      end

      # Extract the version of the box from the URL
      if url.path =~ /\/([\d.]+)\//
        version = $1
        @logger.info "Pulled version from URL (#{version})"
      else 
        version = '0'
        @logger.info "No version found in URL, assuming '0'"
      end

      # using same path as in vagrants box add action
      download_path = File.join(@env.tmp_path, 'box' + Digest::SHA1.hexdigest(url.to_s))
      @tmp_files << download_path

      # if this fails it will raise an error and we'll quit
      @env.ui.info "Downloading box #{name} from #{url}"
      downloader = Vagrant::Util::Downloader.new(url, download_path, { :ui => @env.ui })
      downloader.download!

      dir = unpack(download_path)
      provider_name = determine_provider(dir)
      #version = determine_version(dir)

      return box = create_box(provider_name, name, version, dir)
    end

    def load_from_file(file)
      @logger.info "Loading box from file #{file}"
      name = File.basename( file, File.extname(file) )

      dir = unpack(file)
      provider_name = determine_provider(dir)
      version = determine_version(dir)

      return box = create_box(provider_name, name, version, dir)
    end

    def load_from_boxes_path(name, provider_name, input_version)
      @logger.info "Loading box #{name} from vagrants box path using provider #{provider_name} and version #{input_version}."
      safe_name = sanitize_name(name)
      if provider_name
        @logger.info "Checking directory for provider #{provider_name}."
        if input_version
          @logger.info "Input version provided, using it."
          version = input_version
        else
          @logger.info "No version provided, getting it."
          version = get_version(safe_name)
          @logger.info "Version = #{version}"
        end
        dir = verify_input_dir(provider_name, safe_name, version)
      else
        @logger.info "Working out provider, version and directory..."
        provider_name, version, dir = find_input_dir(safe_name)
      end
      @logger.info "Creating #{name} box using provider #{provider_name} with version #{version} in #{dir}."
      return box = create_box(provider_name, name, version, dir)
    end

    def cleanup
      unless @tmp_files.empty?
        @env.ui.info "Cleaning up temporary files."
        @tmp_files.each do |f|
          @logger.info "Deleting #{f}"
          FileUtils.remove_entry_secure(f)
        end
      end
    end

    private

    def create_box(provider_name, name, version, dir)
        @logger.info "Creating box #{name} with provider #{provider_name} and version #{version} in #{dir}"
        case provider_name
        when 'kvm'
          require_relative 'box/kvm'
          Box::Kvm.new(@env, name, version, dir)
        when 'libvirt'
          require_relative 'box/libvirt'
          Box::Libvirt.new(@env, name, version, dir)
        when 'virtualbox'
          require_relative 'box/virtualbox'
          Box::Virtualbox.new(@env, name, version, dir)
        else
          raise Errors::ProviderNotSupported, :provider => provider_name, :direction => 'input or output'
        end
    end

    def create_output_dir(name, provider_name, version)
      # e.g. $HOME/.vagrant.d/boxes/fedora-19/0/libvirt
      @logger.info "Attempting to create output dir for #{name} with version #{version} and provider #{provider_name}."
      out_dir = File.join( @env.boxes_path, name, version, provider_name )
      @logger.info "Creating out_dir #{out_dir}."
      begin
        FileUtils.mkdir_p(out_dir)
      rescue => e
        raise Errors::CreateBoxDirFailed, :error_message => e.message
      end
      @logger.info "Created output directory #{out_dir}"
      return out_dir
    end

    def unpack(file)
      @env.ui.info "Extracting box file to a temporary directory."
      unless File.exist? file
        raise Errors::BoxNotFound, :box => file
      end
      tmp_dir = Dir.mktmpdir(nil, @env.tmp_path)
      @tmp_files << tmp_dir
      result = Vagrant::Util::Subprocess.execute(
       "bsdtar", "-v", "-x", "-m", "-C", tmp_dir.to_s, "-f", file)
      if result.exit_code != 0
        raise Errors::ExtractBoxFailed, :error_message => result.stderr.to_s
      end
      @logger.info "Unpacked box to #{tmp_dir}"
      return tmp_dir
    end

    def determine_provider(dir)
      metadata_file = File.join(dir, 'metadata.json')
      if File.exist? metadata_file
        begin
          metadata = JSON.load( File.new( metadata_file, 'r') )
        rescue => e
          raise Errors::LoadMetadataFailed, :error_message => e.message
        end
        @logger.info "Determined input provider is #{metadata['provider']}"
        return metadata['provider']
      else
        @logger.info "No metadata found, so assuming input provider is virtualbox"
        return 'virtualbox'
      end
    end

    def determine_version(dir)
      metadata_file = File.join(dir, 'metadata.json')
      if File.exist? metadata_file
        begin
          metadata = JSON.load( File.new( metadata_file, 'r') )
        rescue => e
          raise Errors::LoadMetadataFailed, :error_message => e.message
        end
        # Handle single or multiple versions
        if metadata['versions'].nil?
          @logger.info "No versions provided by metadata, asuming version 0"
          version = '0'
        elsif metadata['versions'].length > 1
          metadata['versions'].each do |metadata_version|
            @logger.info "Itterating available metadata versions for active version."
            next unless metadata_version['status'] == 'active'
            version = metadata_version['version']
          end
        else
          @logger.info "Only one metadata version, grabbing version."
          version = metadata['versions'][0]['version']
        end
        @logger.info "Determined input version is #{version}"
        return version 
      else
        @logger.info "No metadata found, so assuming version is 0"
        return '0'
      end
    end

    def verify_input_dir(provider_name, name, version)
      input_dir = File.join( @env.boxes_path, name, version, provider_name)
      if File.directory?(input_dir)
        @logger.info "Found input directory #{input_dir}"
        return input_dir
      else
        raise Errors::BoxNotFound, :box => input_dir
      end
    end

    def find_input_dir(name)
      @logger.info "Looking for input dir for box #{name}."
      version = get_version(name)
      box_parent_dir = File.join( @env.boxes_path, name, version)

      if Dir.exist?(box_parent_dir)
        providers = Dir.entries(box_parent_dir).reject { |entry| entry =~ /^\./ }
        @logger.info "Found potential providers #{providers}"
      else
        providers = []
      end

      case
      when providers.length < 1
        raise Errors::BoxNotFound, :box => name
      when providers.length > 1
        raise Errors::TooManyBoxesFound, :box => name
      else
        provider_name = providers.first
        input_dir = File.join( box_parent_dir, provider_name)
        @logger.info "Found source for box #{name} from provider #{provider_name} with version #{version} at #{input_dir}"
        return provider_name, version, input_dir
      end
    end

    def get_version(name)
      # Need to download the metadata
      metadata = download_metadata(name)
      @logger.info "Metadata loaded... #{metadata}"
      @logger.info "Versions = #{metadata.versions}."

      # Handle multiple metadata versions or no versions at-all
      if metadata.versions.length > 1 
        @logger.info "Got multiple versions from metadata, picking max value"
        version = metadata.versions.max
        # version = metadata.versions.each do |metadata_version|
        #   # Only interested in 'active' box...
        #   next unless metadata_version['state'] == 'active' 
        #   version = metadata_version
        #   @logger.info "Got version #{version}"
        #   break version
        # end
      elsif metadata.versions.empty?
        @logger.info "Got no versions from metadata, assuming version '0'"
        version = '0'
      else
        @logger.info "Pulling first version entry as it's the only one"
        version = metadata.versions.first
      end
    
      @logger.info "Returning version #{version}"
      return version
    end

    def download_metadata(name)
      metadata_file = File.join( @env.boxes_path, name, 'metadata_url' )
      if !File.exists?(metadata_file)
        @logger.info "Metadata_file not found at #{metadata_file}."
        raise Errors::MetadataNotFound, :box => name
      end
      @logger.info "Found a metadata_file at #{metadata_file}."
      metadata_url = File.read(metadata_file)
      @logger.info "Metadata_url = #{metadata_url}"

      tf = Tempfile.new("vagrant")
      tf.close

      url = metadata_url
      if File.file?(url) || url !~ /^[a-z0-9]+:.*$/i
        url = File.expand_path(url)
        url = Vagrant::Util::Platform.cygwin_windows_path(url)
        url = "file:#{url}"
      end

      # Download the metadata JSON file from url
      opts = { headers: ["Accept: application/json"] }
      Vagrant::Util::Downloader.new(url, tf.path, **opts).download!
      # Load the Metadata into a BoxMetadata object
      Vagrant::BoxMetadata.new(File.open(tf.path, "r"))
      rescue Vagrant::Errors::DownloaderError => e
        raise Vagrant::Errors::BoxMetadataDownloadError,
          message: e.extra_data[:message]
      ensure
        tf.unlink if tf
    end

    def sanitize_name(name)
      if name =~ /\// 
        @logger.info "Replacing / with -VAGRANTSLASH-."
        name = name.dup
        name.gsub!("/", "-VAGRANTSLASH-")
        @logger.info "New name = #{name}."
      end
      return name
    end
  end
end

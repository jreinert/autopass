# frozen_string_literal: true

require 'date'
require 'json'
require 'digest'
require 'ostruct'

module Autopass
  # A single entry in the password store
  class Entry
    # Signals a missing url
    class URLNotFoundError < RuntimeError
      def initialize
        super('No URL found for this entry')
      end
    end

    attr_reader :name, :path, :checksum

    def initialize(attributes, decrypted: false)
      @name = attributes[:name]
      @path = Pathname(attributes[:path])
      @checksum = attributes.fetch(:checksum, calculate_checksum)

      @attributes = (attributes[:user_attributes] || {}).merge('path' => @path)
      @decrypted = decrypted
    end

    def ==(other)
      checksum == other.checksum && path == other.path
    end

    alias eql? ==

    def hash
      [checksum, path].hash
    end

    def attributes
      OpenStruct.new(@attributes)
    end

    def to_json(*args)
      {
        name: @name, path: @path, checksum: @checksum,
        user_attributes: @attributes
      }.to_json(*args)
    end

    def exist?
      @path.exist?
    end

    def decrypt!
      return if @decrypted
      content = Util::Pass.show(@name)
      @attributes = parse_content(content).merge('path' => @path)
      @name = @attributes.fetch('name', @name)
      @decrypted = true
    end

    def reload!
      checksum = calculate_checksum
      return if @checksum == checksum && @decrypted
      @checksum = checksum
      @decrypted = false
      decrypt!
    end

    def match(window_name)
      basename = File.basename(name)
      matcher = attributes.window || Regexp.escape(attributes.url || basename)
      window_name.match(/#{matcher}/i)
    end

    def self.load(file)
      relative_path = file.relative_path_from(CONFIG.password_store)
      name = relative_path.sub(/\.gpg$/, '').to_s
      new(name: name, path: file)
    end

    def open_url!
      raise URLNotFoundError if attributes.url.to_s.empty?
      Process.spawn(ENV['BROWSER'] || 'xdg-open', attributes.url)
    end

    private

    def calculate_checksum
      return unless exist?
      Digest::MD5.file(@path.to_s).hexdigest
    end

    def parse_content(content)
      password, *yaml = content.split("\n")
      yaml = yaml.join("\n")
      (YAML.safe_load(yaml, [Date]) || {}).tap do |metadata|
        metadata[CONFIG.password_key] = password
      end
    rescue StandardError => e
      message = "Failed parsing entry '#{@name}': #{e.message}"
      Util.notify(message, console_info: [password, yaml, e.message])
      { error: true }
    end
  end
end

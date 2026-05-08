# frozen_string_literal: true

require "digest"
require "fileutils"

require_relative "file_atomic_swap"

module OllamaAgent
  module Runtime
    # Content-addressed blobs under +kernel_dir+/blobs/+aa+/+rest+.
    class BlobStore
      def initialize(kernel_dir:)
        @root = File.join(File.expand_path(kernel_dir), "blobs")
      end

      # @param content [String]
      # @return [String] lowercase hex SHA256
      def put(content)
        bytes = content.b
        hex = Digest::SHA256.hexdigest(bytes)
        path = blob_path(hex)
        FileUtils.mkdir_p(File.dirname(path))
        return verify_existing!(path, bytes, hex) if File.exist?(path)

        FileAtomicSwap.write_bytes!(path, bytes)
        hex
      end

      # @param sha256 [String] 64-char hex (with or without sha256: prefix — normalized)
      # @return [String] raw bytes
      def get(sha256:)
        path = blob_path(normalize_sha(sha256))
        raise BlobNotFound, path unless File.exist?(path)

        bytes = File.binread(path)
        verify_bytes!(bytes, normalize_sha(sha256))
        bytes
      end

      # @param sha256 [String]
      def exist?(sha256:)
        File.exist?(blob_path(normalize_sha(sha256)))
      end

      # @return [String] absolute filesystem path for a normalized hex digest
      def path_for_hex(sha256)
        blob_path(normalize_sha(sha256))
      end

      # Yields each lowercase 64-hex digest that exists on disk under +@root+.
      def each_stored_hex
        return enum_for(:each_stored_hex) unless block_given?

        return unless File.directory?(@root)

        Dir.each_child(@root) do |dir2|
          sub = File.join(@root, dir2)
          next unless dir2.length == 2 && File.directory?(sub)

          Dir.each_child(sub) do |tail|
            hex = "#{dir2}#{tail}"
            yield hex if hex.match?(/\A[0-9a-f]{64}\z/)
          end
        end
      end

      private

      def verify_existing!(path, bytes, hex)
        got = File.binread(path)
        raise BlobIntegrityFault, hex unless got == bytes

        hex
      end

      def verify_bytes!(bytes, hex)
        actual = Digest::SHA256.hexdigest(bytes)
        raise BlobIntegrityFault, hex unless actual == hex
      end

      def normalize_sha(sha256)
        s = sha256.to_s.downcase
        s = s.delete_prefix("sha256:")
        raise ArgumentError, "invalid sha256" unless s.match?(/\A[0-9a-f]{64}\z/)

        s
      end

      def blob_path(hex)
        File.join(@root, hex[0..1], hex[2..])
      end
    end
  end
end

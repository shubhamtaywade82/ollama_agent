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

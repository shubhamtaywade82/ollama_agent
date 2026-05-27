# frozen_string_literal: true

require "digest"

module OllamaAgent
  module Runtime
    # Compare-and-swap helper for {AtomicMutator}: fencing lease + content precondition.
    #
    # Content digests use SHA256 over raw bytes. When +current_content_or_nil+ is +nil+ (path absent
    # on disk), the digest is the same as for an empty file (+SHA256("")+) so a missing file and a
    # zero-byte file are indistinguishable by hash alone. To require absence, use
    # +expected_pre_hash: NEW_FILE_SENTINEL+ (+"__new_file__"+).
    class CASGuard
      NEW_FILE_SENTINEL = "__new_file__"

      # @return [:ok, :stale_token, :precondition_failed]
      def self.check(current_content_or_nil:, expected_pre_hash:, fencing_token_provided:,
                     fencing_token_current:)
        return :stale_token unless fence_allows?(fencing_token_provided, fencing_token_current)

        pre_hash_result(expected_pre_hash, current_content_or_nil)
      end

      def self.fence_allows?(provided, allocated)
        prov = provided.to_i
        curr = allocated.to_i
        return false if prov < 1
        return false if curr < 2

        prov == curr - 1
      end

      def self.pre_hash_result(expected, current_content_or_nil)
        if expected == NEW_FILE_SENTINEL
          return :ok if current_content_or_nil.nil?

          return :precondition_failed
        end

        actual = sha256_hex_for_content(current_content_or_nil)
        return :ok if actual == expected

        :precondition_failed
      end

      def self.sha256_hex_for_content(content_or_nil)
        bytes = content_or_nil.nil? ? +"" : content_or_nil.b
        Digest::SHA256.hexdigest(bytes)
      end
    end
  end
end

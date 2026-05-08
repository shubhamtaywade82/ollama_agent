# frozen_string_literal: true

require "digest"
require "json"

require_relative "signature_normalizer"

module OllamaAgent
  module Topology
    # Stable opaque ids for topology symbols (extractor-versioned).
    module SymbolIdentity
      module_function

      def compute(fqcn:, signature:, extractor_version:)
        canon = canonical_signature(signature)
        digest = Digest::SHA256.new
        append_lp(digest, fqcn.to_s)
        append_lp(digest, JSON.generate(canon))
        append_lp(digest, extractor_version.to_s)
        digest.hexdigest
      end

      def canonical_signature(signature)
        return SignatureNormalizer.normalize(signature) unless signature.is_a?(Hash)

        if signature.key?(:fqcn) || signature.key?("fqcn")
          fq = signature[:fqcn] || signature["fqcn"]
          meth = signature[:methods] || signature["methods"]
          SignatureNormalizer.normalize_class(class_fqcn: fq, methods: meth)
        else
          SignatureNormalizer.normalize(signature)
        end
      end

      def append_lp(digest, str)
        bytes = str.to_s.b
        digest.update([bytes.bytesize].pack("Q>"))
        digest.update(bytes)
      end
    end
  end
end

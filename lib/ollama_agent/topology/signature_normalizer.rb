# frozen_string_literal: true

module OllamaAgent
  module Topology
    # Canonical method/class shapes for deterministic +symbol_id+ hashing.
    module SignatureNormalizer
      PARAM_KIND_ORDER = {
        "positional" => 0,
        "optional_positional" => 1,
        "keyword_required" => 2,
        "keyword_optional" => 3,
        "rest" => 4,
        "kwrest" => 5,
        "block" => 6
      }.freeze

      module_function

      def normalize(method_signature_hash)
        h = stringify_keys(method_signature_hash || {})
        params = normalize_parameters(Array(h["parameters"]))
        out = {
          "name" => h["name"].to_s,
          "kind" => h["kind"].to_s,
          "parameters" => params
        }
        out["types"] = normalize_types(h["types"]) if h.key?("types")
        sort_top_level(out)
      end

      def normalize_class(class_fqcn:, methods:)
        normalized_methods = Array(methods).map { |m| normalize(m) }.sort_by { |m| m["name"] }
        sort_top_level(
          {
            "fqcn" => class_fqcn.to_s,
            "methods" => normalized_methods
          }
        )
      end

      def normalize_parameters(params)
        params.map { |p| normalize_one_param(p) }.sort_by do |p|
          [PARAM_KIND_ORDER.fetch(p["kind"], 99), p["name"].to_s]
        end
      end

      def normalize_one_param(param)
        p = stringify_keys(param)
        kind = p["kind"].to_s
        out = { "kind" => kind, "name" => p["name"].to_s }
        out["type"] = p["type"].to_s if p["type"] && !p["type"].to_s.empty?
        out
      end

      def normalize_types(types)
        t = stringify_keys(types)
        t.keys.sort.to_h { |key| [key, t[key].to_s] }
      end

      def stringify_keys(obj)
        case obj
        when Hash
          obj.transform_keys(&:to_s)
        else
          {}
        end
      end

      def sort_top_level(canonical)
        canonical.keys.sort.to_h { |key| [key, canonical[key]] }
      end
    end
  end
end

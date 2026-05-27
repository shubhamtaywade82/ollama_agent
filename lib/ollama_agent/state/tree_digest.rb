# frozen_string_literal: true

module OllamaAgent
  module State
    # Length-prefixed hashing for tree entries so adjacent path/content bytes cannot
    # be confused across file boundaries (e.g. `lib/sample` + `.rbX` vs `lib/sample.rb` + `X`).
    module TreeDigest
      module_function

      def append_entry(digest, relative_path, content)
        path = relative_path.to_s.b
        body = content.to_s.b
        digest.update([path.bytesize].pack("Q>"))
        digest.update(path)
        digest.update([body.bytesize].pack("Q>"))
        digest.update(body)
      end
    end
  end
end

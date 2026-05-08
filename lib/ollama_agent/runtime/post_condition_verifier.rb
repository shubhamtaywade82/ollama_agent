# frozen_string_literal: true

module OllamaAgent
  module Runtime
    # Runs declarative post-condition checks through {IsolatedValidator} (array exec only).
    class PostConditionVerifier
      def initialize(isolated_validator:)
        @isolated_validator = isolated_validator
      end

      # @param manifest_id [String]
      # @param checks [Array<Hash>] each hash: +:name+, +:command+ (Array<String>); optional +:expect_exit+ (default 0).
      # @param logical_stamp [String]
      # @return [Hash] +:passed+ (Boolean), +:results+ (Array of result hashes).
      def verify(manifest_id:, checks:, logical_stamp:)
        results = checks.map { |check| run_check(manifest_id, check, logical_stamp) }
        { passed: results.all? { |row| row[:ok] }, results: results }
      end

      private

      def run_check(manifest_id, check, logical_stamp)
        name = string_from(check, :name)
        command = check[:command] || check["command"]
        expect_exit = integer_from(check, :expect_exit, default: 0)

        raw = @isolated_validator.run(
          command: command,
          manifest_id: manifest_id,
          logical_stamp: logical_stamp
        )
        ok = check_ok?(raw, expect_exit)
        { name: name, status: raw[:status], exit_code: raw[:exit_code], ok: ok }
      end

      def check_ok?(raw, expect_exit)
        return false unless %i[ok nonzero_exit].include?(raw[:status])

        raw[:exit_code] == expect_exit
      end

      def string_from(check, key)
        (check[key] || check[key.to_s]).to_s
      end

      def integer_from(check, key, default:)
        v = check[key] || check[key.to_s]
        v.nil? ? default : v.to_i
      end
    end
  end
end

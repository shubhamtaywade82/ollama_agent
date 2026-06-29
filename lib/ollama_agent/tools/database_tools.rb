# frozen_string_literal: true

require_relative "base"
require_relative "enhanced_registry"

module OllamaAgent
  module Tools
    class DbQuery < Base
      tool_name        "db_query"
      tool_description "Execute a SELECT SQL query and return rows as JSON. Mutations are rejected."
      tool_risk        :medium
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      sql: { type: "string", description: "SELECT SQL statement" },
                      params: {
                        type: "array",
                        items: {},
                        description: "Optional bound parameters"
                      }
                    },
                    required: ["sql"]
                  })

      def call(args, _context = {})
        sql = args["sql"].to_s.strip
        return "Error: SQL is required" if sql.empty?
        return "Error: only SELECT and WITH queries are allowed" unless sql.match?(/\A\s*(SELECT|WITH)\s/i)

        require "active_record" unless defined?(ActiveRecord::Base)

        rows = ActiveRecord::Base.connection.exec_query(sql, "Agent", Array(args["params"])).to_a
        { rows: rows, count: rows.size }
      rescue LoadError
        "Error: ActiveRecord not available"
      rescue ActiveRecord::StatementInvalid => e
        "SQL Error: #{e.message}"
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end

    class DbSchema < Base
      tool_name        "db_schema"
      tool_description "Return schema definition for a table (or all tables) from ActiveRecord."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      table: { type: "string", description: "Table name (omit for all tables)" }
                    },
                    required: []
                  })

      MAX_COLUMNS = 50

      def call(args, _context = {})
        require "active_record" unless defined?(ActiveRecord::Base)

        conn   = ActiveRecord::Base.connection
        tables = args["table"] ? [args["table"]] : conn.tables.sort

        schemas = tables.map do |t|
          cols = conn.columns(t).map { |c|
            { name: c.name, type: c.type, null: c.null, default: c.default, limit: c.limit }
          }
          idx = conn.indexes(t).map { |i|
            { name: i.name, columns: i.columns, unique: i.unique }
          }
          { table: t, columns: cols.first(MAX_COLUMNS), indexes: idx.first(20) }
        end

        { tables: schemas, count: tables.size }
      rescue LoadError
        "Error: ActiveRecord not available"
      rescue StandardError => e
        "Error: #{e.message}"
      end
    end

    class RunMigration < Base
      tool_name        "run_migration"
      tool_description "Run pending ActiveRecord migrations or check migration status."
      tool_risk        :high
      tool_requires_approval true
      tool_schema({
                    type: "object",
                    properties: {
                      direction: {
                        type: "string",
                        enum: %w[up down status],
                        description: "up = migrate, down = rollback, status = check"
                      }
                    },
                    required: ["direction"]
                  })

      def call(args, context: {})
        return "run_migration is disabled in read-only mode" if context[:read_only]

        dir = args["direction"]
        root = context[:root] || Dir.pwd

        out = case dir
              when "up"     then `cd #{Shellwords.shellescape(root)} && bundle exec rails db:migrate 2>&1`
              when "down"   then `cd #{Shellwords.shellescape(root)} && bundle exec rails db:rollback 2>&1`
              when "status" then `cd #{Shellwords.shellescape(root)} && bundle exec rails db:migrate:status 2>&1`
              else return "Error: unknown direction #{dir}"
              end

        {
          direction: dir,
          exit_code: $?.exitstatus,
          output: out.lines.first(100).join.strip
        }
      rescue StandardError => e
        { error: e.message }
      end
    end

    EnhancedRegistry.register(DbQuery)
    EnhancedRegistry.register(DbSchema)
    EnhancedRegistry.register(RunMigration)
  end
end

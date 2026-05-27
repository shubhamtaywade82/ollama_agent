# frozen_string_literal: true

require_relative "base"

module OllamaAgent
  module Tools
    # Safe arithmetic evaluator using the Shunting-yard algorithm.
    #
    # Supports +, -, *, /, ** and parentheses on numeric literals.
    # Does NOT use eval — the expression is parsed into tokens, converted
    # to reverse-Polish notation, and evaluated on a stack.
    class SafeCalculator < Base
      tool_name        "calculate"
      tool_description "Evaluate an arithmetic expression and return the numeric result. " \
                       "Supports +, -, *, /, ** (power) and parentheses. " \
                       "Use for precise computation rather than mental arithmetic."
      tool_risk        :low
      tool_requires_approval false
      tool_schema({
                    type: "object",
                    properties: {
                      expression: {
                        type: "string",
                        description: "Arithmetic expression, e.g. '(12 + 8) / 5' or '2 ** 10'"
                      }
                    },
                    required: ["expression"]
                  })

      # Operator table: precedence, associativity, arity.
      # Unary +/- are prefixed with 'u' to distinguish from binary operators.
      OPERATORS = {
        "+"  => { precedence: 1, assoc: :left,  arity: 2 },
        "-"  => { precedence: 1, assoc: :left,  arity: 2 },
        "*"  => { precedence: 2, assoc: :left,  arity: 2 },
        "/"  => { precedence: 2, assoc: :left,  arity: 2 },
        "**" => { precedence: 3, assoc: :right, arity: 2 },
        "u+" => { precedence: 4, assoc: :right, arity: 1 },
        "u-" => { precedence: 4, assoc: :right, arity: 1 }
      }.freeze

      def call(args, context: {})
        expression = args["expression"].to_s
        tokens = tokenize(expression)
        rpn    = to_rpn(tokens)
        value  = eval_rpn(rpn)
        value.finite? ? value.to_s : "Error: result is non-finite (division by zero?)"
      rescue StandardError => e
        "Error: #{e.message}"
      end

      private

      # Tokenize the expression string into Floats, operator strings, and parentheses.
      # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize
      def tokenize(expr)
        raise ArgumentError, "expression is empty" if expr.strip.empty?

        tokens    = []
        i         = 0
        last_type = :operator # treat start-of-input like an operator for unary detection

        while i < expr.length
          ch = expr[i]

          case ch
          when " ", "\t", "\n", "\r"
            i += 1

          when "0".."9", "."
            start = i
            i += 1 while i < expr.length && expr[i] =~ /[0-9.]/
            raw = expr[start...i]
            raise ArgumentError, "invalid number #{raw.inspect}" if raw.count(".") > 1

            tokens << raw.to_f
            last_type = :number

          when "("
            tokens << "("
            i += 1
            last_type = :left_paren

          when ")"
            tokens << ")"
            i += 1
            last_type = :right_paren

          when "*"
            if expr[i + 1] == "*"
              tokens << "**"
              i += 2
            else
              tokens << "*"
              i += 1
            end
            last_type = :operator

          when "+", "-"
            is_unary = %i[operator left_paren].include?(last_type)
            tokens << (is_unary ? "u#{ch}" : ch)
            i += 1
            last_type = :operator

          when "/"
            tokens << "/"
            i += 1
            last_type = :operator

          else
            raise ArgumentError, "invalid character #{ch.inspect} in expression"
          end
        end

        tokens
      end
      # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize

      # Convert infix token list to reverse-Polish notation via Shunting-yard.
      def to_rpn(tokens)
        output = []
        stack  = []

        tokens.each do |token|
          case token
          when Numeric
            output << token
          when "("
            stack << token
          when ")"
            output << stack.pop until stack.empty? || stack.last == "("
            raise ArgumentError, "mismatched parentheses" if stack.empty?

            stack.pop # discard the matching "("
          else
            op1 = OPERATORS.fetch(token)
            while (top = stack.last) && OPERATORS.key?(top)
              op2 = OPERATORS[top]
              # Pop when op2 has strictly higher precedence, or equal precedence and
              # op1 is left-associative (right-assoc operators like ** defer to their right).
              should_pop = op2[:precedence] > op1[:precedence] ||
                           (op2[:precedence] == op1[:precedence] && op1[:assoc] == :left)
              break unless should_pop

              output << stack.pop
            end
            stack << token
          end
        end

        until stack.empty?
          top = stack.pop
          raise ArgumentError, "mismatched parentheses" if top == "("

          output << top
        end

        output
      end

      # Evaluate an RPN token list on a numeric stack.
      def eval_rpn(rpn)
        stack = []

        rpn.each do |token|
          if token.is_a?(Numeric)
            stack << token.to_f
            next
          end

          op = OPERATORS.fetch(token)
          if op[:arity] == 1
            a = stack.pop
            raise ArgumentError, "invalid expression" if a.nil?

            stack << (token == "u-" ? -a : +a)
          else
            b = stack.pop
            a = stack.pop
            raise ArgumentError, "invalid expression" if a.nil? || b.nil?

            stack << apply_binary(token, a, b)
          end
        end

        raise ArgumentError, "invalid expression" unless stack.size == 1

        stack.first
      end

      def apply_binary(op, a, b)
        case op
        when "+"  then a + b
        when "-"  then a - b
        when "*"  then a * b
        when "/"  then a / b
        when "**" then a**b
        else raise ArgumentError, "unknown operator #{op.inspect}"
        end
      end
    end
  end
end

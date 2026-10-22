# frozen_string_literal: true

require "railway_cli/error"

module RailwayCli
  # Classifies a GraphQL document and enforces the gql write guard.
  module GqlGuard
    Operation = Data.define(:type, :name, :fields)

    # Strings, comments, punctuation, and names; strings and comments are dropped.
    TOKEN = /"""(?:[^"\\]|\\.|"(?!""))*"""|"(?:[^"\\\n]|\\.)*"|#[^\n]*|\.\.\.|[A-Za-z_][A-Za-z0-9_]*|[{}()\[\]:$@!=,]|\S/m

    def self.tokens(doc)
      doc.scan(TOKEN).reject { |t| t.start_with?("#", '"') }
    end

    def self.classify(doc)
      toks = tokens(doc)
      ops = []
      i = 0
      while i < toks.length
        t = toks[i]
        if t == "{"
          fields, i = selection(toks, i)
          ops << Operation.new(type: "query", name: nil, fields: fields)
        elsif %w[query mutation subscription].include?(t)
          name = toks[i + 1]&.match?(/\A[A-Za-z_]\w*\z/) ? toks[i + 1] : nil
          i += 1 until i >= toks.length || toks[i] == "{" || toks[i] == "("
          i = skip_group(toks, i, "(", ")") if toks[i] == "("
          i += 1 until i >= toks.length || toks[i] == "{"
          fields, i = selection(toks, i)
          ops << Operation.new(type: t, name: name, fields: fields)
        elsif t == "fragment"
          i += 1 until i >= toks.length || toks[i] == "{"
          _, i = selection(toks, i)
        else
          i += 1
        end
      end
      ops
    end

    # Top-level field names of the selection set starting at toks[i] == "{"; returns [fields, next index].
    def self.selection(toks, i)
      return [[], toks.length] if i >= toks.length

      fields = []
      depth = 0
      while i < toks.length
        t = toks[i]
        case t
        when "{" then depth += 1
        when "}"
          depth -= 1
          return [fields, i + 1] if depth.zero?
        when "(" then i = skip_group(toks, i, "(", ")") - 1
        else
          if depth == 1 && t.match?(/\A[A-Za-z_]\w*\z/) && toks[i - 1] != "..." && toks[i - 1] != "@" && toks[i - 1] != "on"
            if toks[i + 1] == ":"
              fields << toks[i + 2]
              i += 2
            else
              fields << t
            end
          end
        end
        i += 1
      end
      [fields, i]
    end

    def self.skip_group(toks, i, open, close)
      depth = 0
      while i < toks.length
        depth += 1 if toks[i] == open
        depth -= 1 if toks[i] == close
        i += 1
        return i if depth.zero?
      end
      i
    end

    # Raises UsageError when the document is not allowed; returns the operations otherwise.
    def self.check!(doc, write:, confirm:)
      ops = classify(doc)
      raise UsageError, "no GraphQL operation found" if ops.empty?
      raise UsageError, "subscriptions are not supported" if ops.any? { |o| o.type == "subscription" }

      muts = ops.select { |o| o.type == "mutation" }
      raise UsageError, "mutation refused: pass --write to run it" if muts.any? && !write

      muts.each do |m|
        next unless ([m.name] + m.fields).compact.any? { |n| n.include?("Delete") }
        raise UsageError, "anonymous delete mutation refused: name the operation and pass --confirm <name>" unless m.name
        next if confirm == m.name

        raise ConfirmRefused, "delete mutation #{m.name}: pass --confirm #{m.name}"
      end
      ops
    end
  end
end

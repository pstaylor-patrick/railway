# frozen_string_literal: true

require "railway_cli/commands/context"
require "railway_cli/error"
require "railway_cli/confirm"
require "railway_cli/mask"
require "railway_cli/queries"

module RailwayCli
  module Commands
    # vars (list), vars diff, vars set, vars delete.
    module Variables
      STDIN_MARKER = "-"

      def self.run(ctx)
        sub = ctx.args.first
        case sub
        when nil, "list" then list(ctx)
        when "diff" then diff(ctx)
        when "set" then set(ctx, ctx.args.drop(1))
        when "delete" then delete(ctx, ctx.args[1])
        else raise UsageError, "unknown vars subcommand: #{sub} (list, diff, set, delete)"
        end
      end

      def self.list(ctx)
        vars = fetch(ctx, ctx.resolver.environment)
        shown = display(vars, ctx.opts[:reveal])
        rows = shown.sort.map { |k, v| { "key" => k, "value" => v } }
        ctx.emit("vars", shown, rows: rows, cols: %w[key value])
      end

      def self.diff(ctx)
        a_env = ctx.resolver.environment
        b_env = Resolver.pick(ctx.resolver.environments, ctx.opts[:env2], "env2")
        result = classify(fetch(ctx, a_env), fetch(ctx, b_env))
        result = mask_diff(result) unless ctx.opts[:reveal]
        return ctx.emit("vars diff", result) if ctx.opts[:json]

        ctx.out.puts diff_text(result, a_env["name"], b_env["name"])
        0
      end

      def self.set(ctx, pairs, stdin: $stdin)
        vars = parse_pairs(pairs, stdin: stdin)
        r = ctx.resolver
        input = { "projectId" => r.project["id"], "environmentId" => r.environment["id"] }
        svc = r.service(required: false)
        input["serviceId"] = svc["id"] if svc
        input["skipDeploys"] = true if ctx.opts[:skip_deploys]
        if vars.size == 1
          name, value = vars.first
          ctx.client.mutate(Queries::VARIABLE_UPSERT, { "input" => input.merge("name" => name, "value" => value) })
        else
          ctx.client.mutate(Queries::VARIABLE_COLLECTION_UPSERT, { "input" => input.merge("variables" => vars) })
        end
        ctx.emit("vars set", { "set" => vars.keys })
      end

      # Resolves the key first so a typo fails before the prompt.
      def self.delete(ctx, key, confirm: Confirm)
        raise UsageError, "vars delete needs KEY" if key.nil? || key.empty?

        r = ctx.resolver
        env = r.environment
        raise UsageError, "no variable #{key} in #{env['name']}" unless fetch(ctx, env).key?(key)

        confirm.require!(expected: key, kind: "variable", flag: ctx.opts[:confirm])
        input = { "projectId" => r.project["id"], "environmentId" => env["id"], "name" => key }
        svc = r.service(required: false)
        input["serviceId"] = svc["id"] if svc
        ctx.client.mutate(Queries::VARIABLE_DELETE, { "input" => input })
        ctx.emit("vars delete", { "deleted" => key })
      end

      # ["A=1", "B=-"] -> {"A"=>"1", "B"=>stdin}. At most one KEY=- per call.
      def self.parse_pairs(pairs, stdin: $stdin)
        raise UsageError, "vars set needs KEY=VALUE arguments" if pairs.empty?

        from_stdin = pairs.count { |p| p.partition("=")[2] == STDIN_MARKER }
        raise UsageError, "only one KEY=- may read stdin" if from_stdin > 1

        pairs.each_with_object({}) do |pair, acc|
          key, sep, value = pair.partition("=")
          raise UsageError, "expected KEY=VALUE, got #{key.inspect}" if sep.empty? || key.empty?

          value = stdin.read.to_s.chomp if value == STDIN_MARKER
          acc[key] = value
        end
      end

      # {only_a: [keys], only_b: [keys], differing: {key => [a, b]}}
      def self.classify(a, b)
        {
          "only_a" => (a.keys - b.keys).sort,
          "only_b" => (b.keys - a.keys).sort,
          "differing" => (a.keys & b.keys).sort.reject { |k| a[k] == b[k] }.to_h { |k| [k, [a[k], b[k]]] }
        }
      end

      def self.mask_diff(result)
        result.merge("differing" => result["differing"].transform_values { |pair| pair.map { |v| Mask.call(v) } })
      end

      def self.display(vars, reveal) = reveal ? vars : vars.transform_values { |v| Mask.call(v) }

      def self.fetch(ctx, env)
        r = ctx.resolver
        svc = r.service(required: false)
        vars = { "projectId" => r.project["id"], "environmentId" => env["id"] }
        vars["serviceId"] = svc["id"] if svc
        ctx.client.query(Queries::VARIABLES, vars)["variables"] || {}
      end

      def self.diff_text(result, a_name, b_name)
        lines = []
        lines << "only in #{a_name}: #{result['only_a'].join(', ')}" unless result["only_a"].empty?
        lines << "only in #{b_name}: #{result['only_b'].join(', ')}" unless result["only_b"].empty?
        result["differing"].each { |k, (a, b)| lines << "differs #{k}: #{a_name}=#{a} #{b_name}=#{b}" }
        lines.empty? ? "(no differences)" : lines.join("\n")
      end
    end
  end
end

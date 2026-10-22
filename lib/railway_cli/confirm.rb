# frozen_string_literal: true

require "railway_cli/error"

module RailwayCli
  module Confirm
    # expected: the resource's exact name. flag: value of --confirm or nil.
    def self.require!(expected:, kind:, flag:, input: $stdin, output: $stderr, tty: input.tty?)
      return true if flag == expected
      raise ConfirmRefused, "--confirm #{flag.inspect} does not match #{kind} name" if flag
      raise ConfirmRefused, "no TTY: pass --confirm <exact #{kind} name>" unless tty
      output.print "Type the #{kind} name (#{expected}) to delete: "
      answer = input.gets&.chomp
      return true if answer == expected
      raise ConfirmRefused, "name did not match; nothing deleted"
    end
  end
end

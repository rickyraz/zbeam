defmodule ZbeamResearch.Native do
  use Zig,
    otp_app: :zbeam_research,
    optimize: :safe,
    nifs: [
      echo: [],
      echo_dirty: [:dirty_cpu, alias: :echo],
      echo_threaded_send: [:threaded],
      hash: [return: :binary],
      hash_dirty: [:dirty_cpu, alias: :hash, return: :binary],
      hash_threaded: [:threaded, alias: :hash, return: :binary]
    ]

  # A term allocated in the worker environment cannot escape as a raw term.
  # enif_send (via beam.send) copies it into this caller's environment instead.
  def echo_threaded(input) do
    :ok = echo_threaded_send(input, self())

    receive do
      {:zbeam_research_echo, reply} -> reply
    after
      5_000 -> raise "threaded echo reply timeout"
    end
  end

  ~Z"""
  const std = @import("std");
  const beam = @import("beam");

  pub fn echo(input: []const u8) !beam.term {
      if (input.len > 1048576) return error.TooLarge;
      return beam.make(input, .{.as = .binary});
  }

  pub fn echo_threaded_send(input: []const u8, recipient: beam.pid) !void {
      if (input.len > 1048576) return error.TooLarge;
      try beam.send(recipient, .{.zbeam_research_echo, input}, .{});
  }

  pub fn hash(input: []const u8) ![32]u8 {
      if (input.len > 1048576) return error.TooLarge;
      var digest: [32]u8 = undefined;
      std.crypto.hash.sha2.Sha256.hash(input, &digest, .{});
      return digest;
  }
  """
end

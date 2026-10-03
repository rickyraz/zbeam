defmodule ZbeamResearch.Native do
  use Zig,
    otp_app: :zbeam_research,
    optimize: :safe,
    nifs: [
      echo: [],
      echo_dirty: [:dirty_cpu, alias: :echo],
      echo_threaded: [:threaded, alias: :echo],
      hash: [return: :binary],
      hash_dirty: [:dirty_cpu, alias: :hash, return: :binary],
      hash_threaded: [:threaded, alias: :hash, return: :binary]
    ]

  ~Z"""
  const std = @import("std");
  const beam = @import("beam");

  pub fn echo(input: []const u8) !beam.term {
      if (input.len > 1048576) return error.TooLarge;
      return beam.make(input, .{.as = .binary});
  }

  pub fn hash(input: []const u8) ![32]u8 {
      if (input.len > 1048576) return error.TooLarge;
      var digest: [32]u8 = undefined;
      std.crypto.hash.sha2.Sha256.hash(input, &digest, .{});
      return digest;
  }
  """
end

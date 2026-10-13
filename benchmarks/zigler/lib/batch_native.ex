defmodule ZbeamResearch.BatchNative do
  use Zig,
    otp_app: :zbeam_research,
    optimize: :safe,
    nifs: [hash_batch: [:dirty_cpu]]

  ~Z"""
  const std = @import("std");
  const beam = @import("beam");
  pub fn hash_batch(input: []const u8, count: u32) !beam.term {
      if (count == 0 or count > 32 or input.len > 1048576 or input.len % count != 0) return error.InvalidBatch;
      const size = input.len / count;
      var output: [1024]u8 = undefined;
      for (0..count) |i| std.crypto.hash.sha2.Sha256.hash(input[i * size ..][0..size], output[i * 32 ..][0..32], .{});
      return beam.make(output[0 .. count * 32], .{.as = .binary});
  }
  """
end

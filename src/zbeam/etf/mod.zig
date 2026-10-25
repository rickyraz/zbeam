//! Standalone External Term Format battery.
//!
//! Decoding owns all variable-sized values and enforces explicit limits before
//! allocation. Networking and actor behavior are outside this module.

pub const codec = @import("codec.zig");
pub const Term = codec.Term;
pub const Pid = codec.Pid;
pub const Reference = codec.Reference;
pub const Limits = codec.Limits;
pub const decode = codec.decode;
pub const decodePrefix = codec.decodePrefix;
pub const Decoded = codec.Decoded;
pub const encode = codec.encode;
pub const version = codec.version;

test {
    _ = @import("reference_test.zig");
    @import("std").testing.refAllDecls(@This());
}

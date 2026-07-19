//! Standalone External Term Format battery.
//!
//! Decoding owns all variable-sized values and enforces explicit limits before
//! allocation. Networking and actor behavior are outside this module.

pub const codec = @import("codec.zig");
pub const Term = codec.Term;
pub const Pid = codec.Pid;
pub const Limits = codec.Limits;
pub const decode = codec.decode;
pub const encode = codec.encode;
pub const version = codec.version;

test {
    @import("std").testing.refAllDecls(@This());
}

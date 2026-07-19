//! Standalone bounded mailbox, actor identity, and demand contracts.
//!
//! Protocol, socket, and distribution semantics are outside this battery.

pub const mailbox = @import("mailbox.zig");
pub const Mailbox = mailbox.Mailbox;
pub const Token = mailbox.Token;
pub const Demand = @import("demand.zig").Demand;

test {
    @import("std").testing.refAllDecls(@This());
}

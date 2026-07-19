const std = @import("std");
const actor = @import("zbeam-actor");

/// Minimal in-process actor registry parameterized by message type. It owns
/// names and registry tables, while callers own mailbox storage and task
/// scheduling; separating those lifetimes avoids an unrequested scheduler.
pub fn Runtime(comptime Message: type) type {
    return struct {
        const Self = @This();
        const MessageMailbox = actor.Mailbox(Message);

        allocator: std.mem.Allocator,
        io: std.Io,
        mutex: std.Io.Mutex = .init,
        next_id: std.atomic.Value(u64) = .init(1),
        actors: std.AutoHashMap(u64, Entry),
        names: std.StringHashMap(u64),

        const Entry = struct {
            mailbox: *MessageMailbox,
            name: ?[]const u8,
        };

        pub const Handle = struct {
            id: u64,
            token: actor.Token,
            mailbox: *MessageMailbox,
        };

        /// Captures allocator and I/O capabilities once so locking, queue close,
        /// and registry allocation use the same explicit runtime context.
        pub fn init(allocator: std.mem.Allocator, io: std.Io) Self {
            return .{
                .allocator = allocator,
                .io = io,
                .actors = .init(allocator),
                .names = .init(allocator),
            };
        }

        /// Closes every live mailbox before releasing owned names and maps.
        /// The mutex spans teardown so no concurrent lookup can observe a table
        /// while it is being destroyed.
        pub fn deinit(self: *Self) void {
            self.mutex.lockUncancelable(self.io);
            var iterator = self.actors.valueIterator();
            while (iterator.next()) |entry| {
                entry.mailbox.close(self.io);
                if (entry.name) |name| self.allocator.free(name);
            }
            self.actors.deinit();
            self.names.deinit();
            self.mutex.unlock(self.io);
            self.* = undefined;
        }

        /// Registers a bounded mailbox as one logical actor. Task scheduling is
        /// deliberately separate from registry ownership.
        pub fn spawn(self: *Self, name: ?[]const u8, mailbox: *MessageMailbox) !Handle {
            const owned_name = if (name) |value| try self.allocator.dupe(u8, value) else null;
            errdefer if (owned_name) |value| self.allocator.free(value);

            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            if (owned_name) |value| {
                if (self.names.contains(value)) return error.NameTaken;
            }
            // IDs only need uniqueness, not cross-thread memory publication;
            // registry insertion under the mutex provides the ordering.
            const id = self.next_id.fetchAdd(1, .monotonic);
            try self.actors.put(id, .{ .mailbox = mailbox, .name = owned_name });
            errdefer _ = self.actors.remove(id);
            if (owned_name) |value| try self.names.put(value, id);
            return .{ .id = id, .token = .init(id), .mailbox = mailbox };
        }

        /// Atomically removes identity and name, then closes the mailbox after
        /// unlocking. Closing outside the registry critical section avoids
        /// waking queue waiters while unrelated name operations are blocked.
        pub fn terminate(self: *Self, id: u64) bool {
            self.mutex.lockUncancelable(self.io);
            const removed = self.actors.fetchRemove(id) orelse {
                self.mutex.unlock(self.io);
                return false;
            };
            if (removed.value.name) |name| {
                _ = self.names.remove(name);
                self.allocator.free(name);
            }
            self.mutex.unlock(self.io);
            removed.value.mailbox.close(self.io);
            return true;
        }

        /// Resolves under the mutex but performs potentially blocking delivery
        /// after unlock. A full mailbox must backpressure this sender without
        /// freezing every registry lookup.
        pub fn sendNamed(self: *Self, name: []const u8, message: Message) !void {
            self.mutex.lockUncancelable(self.io);
            const id = self.names.get(name) orelse {
                self.mutex.unlock(self.io);
                return error.ActorNotFound;
            };
            const mailbox = self.actors.get(id).?.mailbox;
            self.mutex.unlock(self.io);
            try mailbox.deliver(self.io, message);
        }

        /// Returns the stable logical ID rather than exposing registry internals.
        pub fn whereis(self: *Self, name: []const u8) ?u64 {
            self.mutex.lockUncancelable(self.io);
            defer self.mutex.unlock(self.io);
            return self.names.get(name);
        }
    };
}

test "runtime registers, addresses, and terminates a bounded mailbox" {
    const io = std.testing.io;
    var storage: [2]u8 = undefined;
    var mailbox = actor.Mailbox(u8).init(&storage);
    var runtime = Runtime(u8).init(std.testing.allocator, io);
    defer runtime.deinit();

    const handle = try runtime.spawn("worker", &mailbox);
    try std.testing.expectEqual(handle.id, runtime.whereis("worker").?);
    try runtime.sendNamed("worker", 42);
    try std.testing.expectEqual(@as(u8, 42), try mailbox.receive(io, handle.token));
    try std.testing.expect(runtime.terminate(handle.id));
    try std.testing.expectError(error.ActorNotFound, runtime.sendNamed("worker", 1));
}

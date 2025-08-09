const std = @import("std");
const Allocator = std.mem.Allocator;

const Handler = struct {
    ptr: *const anyopaque,
    handleFn: fn (*const anyopaque, [][]const u8) []const u8,

    fn handle(self: Handler, extra: [][]const u8) []const u8 {
        return self.handleFn(self.ptr, extra);
    }
};

const DuckDuckGoHandler = struct {
    const url = "https://news.ycombinator.com/";
    const searchUrl = "https://hn.algolia.com/?q=";

    allocator: Allocator,

    fn init(allocator: Allocator) @This() {
        return @This(){
            .allocator = allocator,
        };
    }

    fn handle(ptr: *const anyopaque, extra: [][]const u8) []const u8 {
        const self: *@This() = @ptrCast(@alignCast(ptr));

        if (extra.len > 0) {
            var queries = extra[0];
            for (1..extra.len) |i| {
                queries = std.fmt.allocPrint(self.allocator, "{}+{}", queries, extra[i]);
            }
            return searchUrl;
        } else {
            return url;
        }
    }

    fn handler(self: *DuckDuckGoHandler) Handler {
        return .{
            .ptr = self,
            .handleFn = handler,
        };
    }
};

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const httpz = @import("httpz");

const redirects = @import("redirects.zig");

const ADDR = "127.0.0.1";
const PORT = 8080;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var handler = Handler{};
    var server = try httpz.Server(*Handler).init(allocator, .{
        .port = PORT,
        .address = ADDR,
    }, &handler);

    defer server.deinit();
    defer server.stop();

    var router = try server.router(.{});

    router.get("/*", handleShortcut, .{});

    std.debug.print("listening on http://{s}:{d}/\n", .{ ADDR, PORT });

    try server.listen();
}

const Handler = struct {
    pub fn notFound(_: *Handler, _: *httpz.Request, res: *httpz.Response) !void {
        res.status = 404;
        res.content_type = httpz.ContentType.HTML;
        res.body = "<!DOCTYPE html><html><marquee direction=\"right\">404 ahhahahahahah</marquee></html>";
    }

    pub fn uncaughtError(_: *Handler, req: *httpz.Request, res: *httpz.Response, err: anyerror) void {
        std.debug.print("uncaught http error at {s}: {}\n", .{ req.url.path, err });
        res.content_type = httpz.ContentType.HTML;
        res.status = 500;
        res.body = "<!DOCTYPE html><html><head><title>bruh</title><body><h1>smth went wrong</h1><p>tspmtfofr</p></body></html>";
    }

    pub fn dispatch(self: *Handler, action: httpz.Action(*Handler), req: *httpz.Request, res: *httpz.Response) !void {
        std.debug.print("{d}: {?s} {s}\n", .{
            std.time.timestamp(),
            std.enums.tagName(httpz.Method, req.method),
            req.url.path,
        });

        try action(self, req, res);
    }
};

const Shortcut = enum {
    ddg,
    hn,
};

fn handleShortcut(_: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
    const path = req.url.path;

    var buf: [8]u8 = [_]u8{undefined} ** 8;
    const unescape_result = try httpz.Url.unescape(res.arena, &buf, path);
    var unescaped_path = unescape_result.value;
    defer if (!unescape_result.buffered) {
        res.arena.free(unescape_result.value);
    };

    var tokens = std.mem.tokenizeScalar(u8, unescaped_path[1..], ' ');

    const shortcut_name = tokens.next() orelse {
        unreachable;
    };
    std.debug.print("path: {s}\tshortcut name: {s}\tbuffered: {}\n", .{ unescaped_path, shortcut_name, unescape_result.buffered });

    const shortcut = std.meta.stringToEnum(Shortcut, shortcut_name) orelse {
        // TODO: tell them they're dumb
        res.status = 500;
        return;
    };

    // 302 Found "temporary redirect" status code
    res.status = 302;

    const url_string = switch (shortcut) {
        .ddg => "https://duckduckgo.com/",
        .hn => "https://news.ycombinator.com/",
    };

    var num_tokens: u32 = 0;
    var redirect = try std.fmt.allocPrint(res.arena, "{s}", .{url_string});
    while (tokens.next()) |token| {
        const tmp = redirect;
        switch (shortcut) {
            .ddg => redirect = try std.fmt.allocPrint(res.arena, "{s}{s}{s}", .{
                redirect,
                if (num_tokens == 0) "?q=" else "+",
                token,
            }),
            else => redirect = try std.fmt.allocPrint(res.arena, "{s}{s}", .{ redirect, token }),
        }
        res.arena.free(tmp);
        num_tokens += 1;
    }

    res.header("Location", redirect);
}

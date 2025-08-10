const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const httpz = @import("httpz");
const zlua = @import("zlua");

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
    router.get("/", index, .{});
    router.get("/favicon.ico", favicon, .{});

    std.debug.print("listening on http://{s}:{d}/\n", .{ ADDR, PORT });

    try server.listen();
}

fn index(_: *Handler, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.body = "do a redirect instead";
}
fn favicon(_: *Handler, _: *httpz.Request, res: *httpz.Response) !void {
    res.status = 200;
    res.body = "";
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

fn getNewLuaState(allocator: Allocator) !*zlua.Lua {
    const lua = try zlua.Lua.init(allocator);
    lua.openLibs();
    return lua;
}

fn runLuaAndGetURL(lua: *zlua.Lua, allocator: Allocator, shortcut_name: []const u8, tokens: [][]const u8) ![]const u8 {
    const cwd_path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd_path);
    const lua_file = try std.fmt.allocPrintZ(allocator, "{s}/lua/{s}.lua", .{ cwd_path, shortcut_name });
    defer allocator.free(lua_file);

    lua.doFile(lua_file) catch |err| {
        const info = switch (err) {
            error.OutOfMemory => "out of memory",
            else => lua.toString(-1) catch unreachable,
        };
        std.debug.print("ERROR: failed to doFile: {s}\n", .{info});
        return err;
    };

    if (try lua.getGlobal("REDIRECT") != zlua.LuaType.function) {
        return error.RedirectFnGlobalDoesNotExist;
    }

    lua.createTable(@intCast(tokens.len), 1);

    _ = lua.pushString(shortcut_name);
    lua.setField(-2, "name");

    for (tokens, 1..) |token, i| {
        _ = lua.pushString(token);
        lua.setIndex(-2, @intCast(i));
    }

    lua.protectedCall(.{
        .args = 1,
        .results = 1,
        .msg_handler = 0,
    }) catch |err| {
        const lua_error = lua.toString(-1) catch "no lua error";
        std.debug.print("ERROR: failed to call REDIRECT global ({}): {s}\n", .{ err, lua_error });
        return err;
    };

    const lua_redirect = try lua.toString(-1);
    std.debug.print("got redirected to {s}\n", .{lua_redirect});

    const redirect = try std.fmt.allocPrint(allocator, "{s}", .{lua_redirect});
    return redirect;
}

fn handleShortcut(_: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
    const path = req.url.path;

    var lua = try getNewLuaState(res.arena);
    defer lua.deinit();

    var buf: [8]u8 = [_]u8{undefined} ** 8;
    const unescape_result = try httpz.Url.unescape(res.arena, &buf, path);
    var unescaped_path = unescape_result.value;
    defer if (!unescape_result.buffered) {
        res.arena.free(unescape_result.value);
    };

    var token_iter = std.mem.tokenizeScalar(u8, unescaped_path[1..], ' ');
    const shortcut_name = token_iter.next() orelse {
        res.body = "<h1>provide a path</h1>";
        return;
    };

    var tokens = std.ArrayList([]const u8).init(res.arena);
    defer tokens.deinit();

    var i: usize = 0;
    while (token_iter.next()) |token| {
        std.debug.print("token {d}: {s}\n", .{ i, token });
        try tokens.append(token);
        i += 1;
    }

    const redirect = try runLuaAndGetURL(lua, res.arena, shortcut_name, tokens.items);

    // 302 Found "temporary redirect" status code
    res.status = 302;
    res.header("Location", redirect);
}

const std = @import("std");
const httpz = @import("httpz");
const Allocator = std.mem.Allocator;

const ADDR = "127.0.0.1";
const PORT = 80;

const GO_TO_PARAM_NAME = "to";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var handler = Handler{};
    var server = try httpz.Server(*Handler).init(allocator, .{
        .port = PORT,
        .address = ADDR,
    }, &handler);

    defer server.deinit();
    defer server.stop();

    var router = try server.router(.{});

    router.get("/", index, .{});
    router.get("/go", go, .{});

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

fn index(_: *Handler, _: *httpz.Request, res: *httpz.Response) !void {
    res.body =
        \\<!DOCTYPE html>
        \\ <ul>
        \\ <li><a href="/go?to=g">google</a>
    ;
}

const Redirects = enum {
    g,
    yt,
};

fn go(_: *Handler, req: *httpz.Request, res: *httpz.Response) !void {
    const query = try req.query();
    const goto = query.get(GO_TO_PARAM_NAME) orelse {
        return error.NeedToParam;
    };

    // 302 Found "temporary redirect" status code
    res.status = 302;

    const redirect = std.meta.stringToEnum(Redirects, goto) orelse {
        return error.RedirectNotSupported;
    };

    const redirect_loc = switch (redirect) {
        .g => "https://google.com",
        .yt => "https://youtube.com",
    };
    res.header("Location", redirect_loc);
}

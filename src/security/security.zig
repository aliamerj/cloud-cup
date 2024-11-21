const std = @import("std");
const patterns = @import("security_patterns.zig");

pub fn secure(request: []const u8) !void {
    if (detectSQLInjection(request)) {
        return error.SQLInjection;
    }
    if (detectXSSPatterns(request)) {
        return error.XSS;
    }
    if (detectTraversalPatterns(request)) {
        return error.DirectoryTraversal;
    }
    if (requiredHeaders(request)) {
        return error.MissingRequiredHeaders;
    }
}

fn detectSQLInjection(request: []const u8) bool {
    for (patterns.sql_injection_patterns) |pattern| {
        if (std.mem.indexOf(u8, request, pattern) != null) {
            return true;
        }
    }

    return false;
}

fn detectXSSPatterns(request: []const u8) bool {
    for (patterns.xss_patterns) |pattern| {
        if (std.mem.indexOf(u8, request, pattern) != null) {
            return true;
        }
    }
    return false;
}

fn detectTraversalPatterns(request: []const u8) bool {
    for (patterns.traversal_patterns) |pattern| {
        if (std.mem.indexOf(u8, request, pattern) != null) {
            return true;
        }
    }
    return false;
}

fn detectSuspiciousUserAgent(request: []const u8) bool {
    for (patterns.suspicious_user_agents) |pattern| {
        if (std.mem.indexOf(u8, request, pattern) != null) {
            return true;
        }
    }
    return false;
}

fn requiredHeaders(request: []const u8) bool {
    for (patterns.required_headers) |pattern| {
        if (std.mem.indexOf(u8, request, pattern) == null) {
            return true;
        }
    }
    return false;
}

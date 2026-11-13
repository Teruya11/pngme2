const std = @import("std");
const File = std.Io.File;
const Crc32 = std.hash.Crc32;

const Png = @import("Png.zig");

const Command = enum { encode, decode, remove, print };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    var arg_iter = try init.minimal.args.iterateAllocator(gpa);
    defer arg_iter.deinit();

    var stdout_buff: [1024]u8 = undefined;
    var stdout_writer = File.stdout().writer(io, &stdout_buff);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    _ = arg_iter.next();
    const raw_command = arg_iter.next() orelse return error.InvalidCommand;
    const command = std.meta.stringToEnum(Command, raw_command) orelse return error.InvalidCommand;

    const filepath = arg_iter.next() orelse return error.InvalidFilepath;
    const file = try std.Io.Dir.cwd().openFile(io, filepath, .{ .mode = .read_write });
    defer file.close(io);

    const chunk_type = arg_iter.next();
    const data = arg_iter.next();

    var buffer: [1024]u8 = undefined;
    var file_reader = file.reader(io, &buffer);
    var png = try Png.init(gpa, &file_reader.interface);
    defer png.deinit();

    switch (command) {
        .encode => {
            var ct_buff: [4]u8 = undefined;
            @memmove(&ct_buff, chunk_type orelse return error.InvalidChunkType);
            const ct = try Png.ChunkType.init(ct_buff);
            if (!ct.isValid()) {
                try stdout.print("Invalid chunk type: {s}\n", .{ct_buff});
                return;
            }

            const clean_data = data orelse {
                try stdout.print("Must provide data\n", .{});
                return;
            };

            var chunk = Png.Chunk{
                .chunk_type = ct,
                .data = try gpa.dupe(u8, @constCast(clean_data)),
                .length = @intCast(clean_data.len),
                .crc = undefined,
            };
            chunk.crc = chunk.calculateCrc();
            try png.appendChunk(chunk);

            var write_buffer: [1024]u8 = undefined;
            var file_writer = file.writer(io, &write_buffer);
            defer file_writer.flush() catch {};

            png.writeBytes(&file_writer.interface) catch {
                try stdout.print("Failed to save data :(\n", .{});
                return;
            };
        },
        .decode => {
            var ct_buff: [4]u8 = undefined;
            @memmove(&ct_buff, chunk_type orelse return error.InvalidChunkType);
            const ct = try Png.ChunkType.init(ct_buff);
            if (!ct.isValid()) {
                try stdout.print("Invalid chunk type: {s}\n", .{ct_buff});
                return;
            }

            const found = png.findChunk(ct) orelse {
                try stdout.print("No chunks were found :(\n", .{});
                return;
            };
            try stdout.print("{s}\n", .{found.data});
        },
        .print => {
            try png.writeBytes(stdout);
        },
        else => return error.OhNo,
    }
}

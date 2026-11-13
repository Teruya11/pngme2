const std = @import("std");
const testing = std.testing;

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = Io.Writer;
const ArrayList = std.ArrayList;
const Crc32 = std.hash.Crc32;

const ChunkType = @import("chunk-type.zig");
const Png = @This();

pub const header = [8]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };

chunks: ArrayList(Chunk),
gpa: Allocator,

pub const Chunk = struct {
    data: []u8,
    chunk_type: ChunkType,
    length: u32,
    crc: u32,

    pub fn calculateCrc(self: *const Chunk) u32 {
        var hasher = Crc32.init();
        hasher.update(&self.chunk_type.bytes);
        hasher.update(self.data);
        return hasher.final();
    }

    pub fn writeBytes(self: *const Chunk, writer: *Writer) !void {
        var length_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &length_bytes, self.length, .big);
        try writer.writeAll(&length_bytes);
        try writer.writeAll(&self.chunk_type.bytes);
        try writer.writeAll(self.data);

        var crc_bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &crc_bytes, self.crc, .big);
        try writer.writeAll(&crc_bytes);
    }
};

test "expect calculated crc to be correct" {
    var chunk: Chunk = .{
        .length = 42,
        .chunk_type = try ChunkType.init(.{ 'R', 'u', 'S', 't' }),
        .data = @constCast("This is where your secret message will be!"),
        .crc = 2882656334,
    };
    try testing.expectEqual(chunk.crc, chunk.calculateCrc());
}

pub fn init(gpa: Allocator, reader: *Io.Reader) !Png {
    const received_header = try reader.take(8);
    if (!std.mem.eql(u8, received_header, &header))
        return error.InvalidHeader;

    var result: ArrayList(Chunk) = .empty;
    while (true) {
        const length = reader.takeInt(u32, .big) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        var chunk_type: [4]u8 = undefined;
        try reader.readSliceAll(&chunk_type);
        const data = try reader.readAlloc(gpa, length);
        const crc = try reader.takeInt(u32, .big);

        result.append(gpa, .{
            .length = length,
            // How to deal with slices
            .chunk_type = try ChunkType.init(chunk_type),
            .data = data,
            .crc = crc,
        }) catch {};
    }

    return .{ .chunks = result, .gpa = gpa };
}

pub fn deinit(self: *Png) void {
    for (self.chunks.items) |chunk| {
        self.gpa.free(chunk.data);
    }
    self.chunks.deinit(self.gpa);
}

pub fn appendChunk(self: *Png, chunk: Chunk) !void {
    try self.chunks.append(self.gpa, chunk);
}

pub fn removeFirstChunk(self: *Png, chunk_type: ChunkType) !Chunk {
    for (self.chunks.items, 0..) |*chunk, i| {
        if (std.mem.eql(u8, &chunk.chunk_type.bytes, &chunk_type.bytes)) {
            return self.chunks.orderedRemove(i);
        }
    }
    return error.ChunkNotFound;
}

/// Receives a writer to avoid direct allocation
pub fn writeBytes(self: *Png, writer: *Writer) !void {
    try writer.writeAll(&header);
    for (self.chunks.items) |chunk| {
        try chunk.writeBytes(writer);
    }
}

pub fn findChunk(self: *Png, chunk_type: ChunkType) ?*Chunk {
    for (self.chunks.items) |*chunk| {
        if (std.mem.eql(u8, &chunk.chunk_type.bytes, &chunk_type.bytes)) {
            return chunk;
        }
    }
    return null;
}

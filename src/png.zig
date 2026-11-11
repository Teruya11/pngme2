const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = Io.Writer;
const ArrayList = std.ArrayList;

const Chunk = @import("chunk.zig");
const ChunkType = @import("chunk-type.zig");

const Png = @This();

chunks: ArrayList(Chunk),
gpa: Allocator,

pub const header = [8]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };

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

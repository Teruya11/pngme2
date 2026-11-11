const std = @import("std");
const Writer = std.Io.Writer;
const Crc32 = std.hash.Crc32;
const testing = std.testing;

const ChunkType = @import("chunk-type.zig");
const Chunk = @This();

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

test "expect calculated crc to be correct" {
    var chunk: Chunk = .{
        .length = 42,
        .chunk_type = ChunkType.init(.{ 'R', 'u', 'S', 't' }),
        .data = @constCast("This is where your secret message will be!"),
        .crc = 2882656334,
    };
    try testing.expectEqual(chunk.crc, chunk.calculateCrc());
}

const ChunkType = @This();

bytes: [4]u8,

pub fn init(bytes: [4]u8) !ChunkType {
    if (bytes.len != 4) {
        return error.InvalidChunkType;
    }
    return .{ .bytes = bytes };
}

pub inline fn isCritical(self: ChunkType) bool {
    return self.bytes[0] & (1 >> 4) == 0;
}

pub inline fn isPublic(self: ChunkType) bool {
    return self.bytes[1] & (1 >> 4) == 0;
}

pub inline fn isValid(self: ChunkType) bool {
    return self.bytes[2] & (1 >> 4) == 0;
}

pub inline fn isSafeToCopy(self: ChunkType) bool {
    return self.bytes[3] & (1 >> 4) > 0;
}

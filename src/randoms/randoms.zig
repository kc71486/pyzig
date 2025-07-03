pub var global_prng: *std.Random.Xoroshiro128 = undefined;
pub var global: std.Random = undefined;

pub const Random = struct {
    prng: std.Random.Xoroshiro128,

    pub fn init(init_s: u64) Random {
        return .{
            .prng = .init(init_s),
        };
    }

    pub fn seed(self: *Random, init_s: u64) void {
        self.prng.seed(init_s);
    }

    pub fn random(self: *Random) std.Random {
        return self.prng.random();
    }

    /// Returns an evenly distributed random integer minval <= i <= maxval.
    pub fn intRange(self: *Random, T: type, minval: T, maxval: T) T {
        return self.random().intRangeAtMost(T, minval, maxval);
    }

    pub fn boolean(self: *Random) bool {
        return self.random().boolean();
    }

    /// Return a floating point value evenly distributed in the range [0, 1).
    pub fn float(self: *Random) f64 {
        return self.random().float(f64);
    }

    pub fn floatRange(self: *Random, minval: f64, maxval: f64) f64 {
        return minval + self.random().float(f64) * (maxval - minval);
    }

    /// Return a floating point value normally distributed with mean = 0, stddev = 1.
    pub fn floatNorm(self: *Random) f64 {
        return self.random().floatNorm(f64);
    }

    pub fn floatNorm2(self: *Random, mean: f64, stddev: f64) f64 {
        return self.floatNorm() * stddev + mean;
    }

    /// Return an exponentially distributed float with a rate parameter of 1.
    pub fn floatExp(self: *Random) f64 {
        return self.random().floatExp(f64);
    }

    /// Return 0.8 ~ 1.2 x of mean
    pub fn approx(self: *Random, mean: f64) f64 {
        return mean * (self.random().float(f64) * 0.4 + 0.8);
    }

    pub fn pickSlice(self: *Random, T: type, slice: []T) T {
        if (slice.len == 0) {
            @panic("empty slice in pickSlice");
        }
        const idx: usize = self.intRange(usize, 0, slice.len - 1);
        return slice[idx];
    }
};

const std = @import("std");

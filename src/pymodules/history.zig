pub const history_metrics: [6][:0]const u8 = .{
    "delay",
    "success_rate",
    "cache_usage",
    "choice_local",
    "choice_near",
    "choice_far",
};

pub const History = struct {
    keys_metric: [history_metrics.len][:0]const u8,
    keys_offload: [][:0]const u8,
    keys_cache: [][:0]const u8,
    num_episode: u32,
    /// metric * offload * cache * episode
    records: [history_metrics.len][][][]f64,

    pub const type_obj: py.TypeObjectBasic = .{
        .tp_name = "history.History",
        .tp_doc = null,
        .tp_flags = .DEFAULT,
    };

    pub const py_getset = .{
        .{ .name = "keys_metric", .get = get_keys_metric },
        .{ .name = "keys_offload", .get = get_keys_offload },
        .{ .name = "keys_cache", .get = get_keys_cache },
    };

    pub const py_methods = .{
        .{
            .ml_name = "recordReinforce",
            .ml_meth = recordReinforce,
            .ml_flags = py.PyMethodDef.Flag.default,
        },
        .{
            .ml_name = "recordHeuristic",
            .ml_meth = recordHeuristic,
            .ml_flags = py.PyMethodDef.Flag.default,
        },
        .{
            .ml_name = "toPlotData",
            .ml_meth = toPlotData,
            .ml_flags = py.PyMethodDef.Flag.default,
        },
        .{
            .ml_name = "toFile",
            .ml_meth = toFile,
            .ml_flags = py.PyMethodDef.Flag.default,
        },
        .{
            .ml_name = "fromFile",
            .ml_meth = fromFile,
            .ml_flags = py.PyMethodDef.Flag.static,
        },
    };

    pub fn py_new(self: *History) void {
        self.* = .{
            .keys_metric = history_metrics,
            .keys_offload = &.{},
            .keys_cache = &.{},
            .num_episode = 0,
            .records = .{&.{}} ** history_metrics.len,
        };
    }

    pub fn py_init(self: *History, args: struct {
        keys_offload: *py.ListObject,
        keys_cache: *py.ListObject,
        num_episode: *py.LongObject,
    }) !void {
        const offload_list: [][:0]const u8 = try py.strArrayFromList(
            allocators.global,
            args.keys_offload,
            [][:0]const u8,
        );
        const cache_list: [][:0]const u8 = try py.strArrayFromList(
            allocators.global,
            args.keys_cache,
            [][:0]const u8,
        );
        const num_episode: u32 = try args.num_episode.toInt(u32);
        self.* = .{
            .keys_metric = history_metrics,
            .keys_offload = offload_list,
            .keys_cache = cache_list,
            .num_episode = num_episode,
            .records = .{&.{}} ** history_metrics.len,
        };
        for (&self.records) |*record_1| {
            record_1.* = allocators.alloc([][]f64, self.keys_offload.len) catch
                return py.Err.outOfMemory();
            for (record_1.*) |*record_2| {
                record_2.* = allocators.alloc([]f64, self.keys_cache.len) catch
                    return py.Err.outOfMemory();
                for (record_2.*) |*record_3| {
                    record_3.* = allocators.alloc(f64, self.num_episode) catch
                        return py.Err.outOfMemory();
                    @memset(record_3.*, 0);
                }
            }
        }
    }

    pub fn py_dealloc(self: *History) void {
        for (self.keys_offload) |str| {
            allocators.free(str);
        }
        allocators.free(self.keys_offload);
        for (self.keys_cache) |str| {
            allocators.free(str);
        }
        allocators.free(self.keys_cache);
        for (&self.records) |*record_1| {
            for (record_1.*) |*record_2| {
                for (record_2.*) |*record_3| {
                    allocators.free(record_3.*);
                }
                allocators.free(record_2.*);
            }
            allocators.free(record_1.*);
        }
    }

    pub fn get_keys_metric(self: *History) !*py.ListObject {
        return try py.listFromStrArray(self.keys_metric);
    }

    pub fn get_keys_offload(self: *History) !*py.ListObject {
        return try py.listFromStrArray(self.keys_offload);
    }

    pub fn get_keys_cache(self: *History) !*py.ListObject {
        return try py.listFromStrArray(self.keys_cache);
    }

    pub fn recordReinforce(self: *History, args: struct {
        key: *KeyObject,
        record: *RecordObject,
    }) !*py.Object {
        const key: *Key = &args.key.inner;
        const record: *Record = &args.record.inner;
        try self.checkKey(key);
        for (0..history_metrics.len) |idx| {
            self.records[idx][key.offload][key.cache][key.episode] = record.data[idx];
        }
        py.IncRef(py.Py_None());
        return py.Py_None();
    }

    pub fn recordHeuristic(self: *History, args: struct { *KeyObject, *RecordObject }) !*py.Object {
        const key_object, const record_object = args;
        const key, const record = .{ key_object.inner, record_object.inner };
        try self.checkKey(&key);
        for (0..self.num_episode) |episode| {
            for (0..history_metrics.len) |idx| {
                self.records[idx][key.offload][key.cache][episode] = record.data[idx];
            }
        }
        py.IncRef(py.Py_None());
        return py.Py_None();
    }

    /// args:
    /// * compare_offload: whether compares between offload method
    /// * index: fixed part index
    /// * title: plot title.
    pub fn toPlotData(self: *History, args: struct {
        compare_offload: *py.BoolObject,
        index: *py.LongObject,
        title: *py.UnicodeObject,
    }) !*py.Object {
        const compare_offload: bool = args.compare_offload.toBool();
        const fixed_index: u32 = try args.index.toInt(u32);
        const title: [:0]const u8 = try args.title.toOwnedSlice(allocators.global); // used in return struct
        var methods: [][:0]const u8 = undefined;
        var y_data: [history_metrics.len][][]f64 = .{undefined} ** history_metrics.len;
        if (compare_offload) {
            methods = allocators.alloc([:0]const u8, self.keys_offload.len) catch
                return py.Err.outOfMemory();
            for (methods, self.keys_offload) |*legend, key_offload| {
                legend.* = allocators.dupeZ(u8, key_offload) catch
                    return py.Err.outOfMemory();
            }
            for (&y_data, 0..) |*metric, metric_idx| {
                metric.* = allocators.alloc([]f64, self.keys_offload.len) catch
                    return py.Err.outOfMemory();
                for (metric.*, 0..) |*metric_1, idx| {
                    metric_1.* = allocators.dupe(f64, self.records[metric_idx][idx][fixed_index]) catch
                        return py.Err.outOfMemory();
                }
            }
        } else {
            methods = allocators.alloc([:0]const u8, self.keys_cache.len) catch
                return py.Err.outOfMemory();
            for (methods, self.keys_cache) |*legend, key_cache| {
                legend.* = allocators.dupeZ(u8, key_cache) catch
                    return py.Err.outOfMemory();
            }
            for (&y_data, 0..) |*metric, metric_idx| {
                metric.* = allocators.alloc([]f64, self.keys_cache.len) catch
                    return py.Err.outOfMemory();
                for (metric.*, 0..) |*metric_1, idx| {
                    metric_1.* = allocators.dupe(f64, self.records[metric_idx][fixed_index][idx]) catch
                        return py.Err.outOfMemory();
                }
            }
        }
        const plotdata_obj: *PlotDataObject = try py.callNew(PlotDataObject, &PlotDataObject.type_obj);
        plotdata_obj.inner = .{
            .title = title,
            .methods = methods,
            .y_data = y_data,
        };
        return plotdata_obj.toObject();
    }

    // should be kept in sync with History
    const Serialized = struct {
        keys_offload: [][:0]const u8,
        keys_cache: [][:0]const u8,
        num_episode: u32,
        records: [history_metrics.len][][][]f64,

        fn fromHistory(history: History) Serialized {
            return .{
                .keys_offload = history.keys_offload,
                .keys_cache = history.keys_cache,
                .num_episode = history.num_episode,
                .records = history.records,
            };
        }

        fn toHistory(serialized: Serialized) History {
            return .{
                .keys_metric = history_metrics,
                .keys_offload = serialized.keys_offload,
                .keys_cache = serialized.keys_cache,
                .num_episode = serialized.num_episode,
                .records = serialized.records,
            };
        }
    };

    pub fn toFile(self: *History, args: struct { *py.UnicodeObject }) !*py.Object {
        const path: [:0]u8 = try args[0].toOwnedSlice(allocators.global);
        defer allocators.free(path);

        const file = std.fs.cwd().createFile(path, .{}) catch |e| {
            py.Err.setString(py.PyExc_OSError, "create error");
            return e;
        };
        defer file.close();
        var arrlist: std.ArrayListUnmanaged(u8) = .empty;
        defer arrlist.deinit(allocators.global);

        const serialized: Serialized = .fromHistory(self.*);
        serialize.serializeOne(
            Serialized,
            allocators.global,
            &arrlist,
            &serialized,
        ) catch |e| switch (e) {
            error.OutOfMemory => return py.Err.outOfMemory(),
            else => |err| @panic(@errorName(err)),
        };

        const arr: []u8 = arrlist.toOwnedSlice(allocators.global) catch
            return py.Err.outOfMemory();
        defer allocators.free(arr);
        file.writeAll(arr) catch |e| {
            py.Err.setString(py.PyExc_OSError, "write error");
            return e;
        };

        return py.Py_None();
    }

    pub fn fromFile(args: struct { *py.UnicodeObject }) !*py.Object {
        const path: [:0]u8 = args[0].toOwnedSlice(allocators.global) catch
            return py.Err.outOfMemory();
        defer allocators.free(path);

        const file = std.fs.cwd().openFile(path, .{}) catch |e| {
            py.Err.setString(py.PyExc_OSError, "open error");
            return e;
        };
        defer file.close();
        const buf: []u8 = file.readToEndAlloc(allocators.global, 1024 * 1024) catch |e| {
            py.Err.setString(py.PyExc_OSError, "read error");
            return e;
        };
        defer allocators.free(buf);

        const serialized: Serialized = serialize.deserializeOne(
            Serialized,
            allocators.global,
            buf,
        ) catch |e| switch (e) {
            error.OutOfMemory => return py.Err.outOfMemory(),
            else => |err| @panic(@errorName(err)),
        };
        const self_obj: *HistoryObject = try py.callNew(HistoryObject, &HistoryObject.type_obj);
        self_obj.inner = serialized.toHistory();

        return self_obj.toObject();
    }

    fn checkKey(self: *History, key: *const Key) !void {
        if (key.offload >= self.keys_offload.len) {
            py.Err.setString(py.PyExc_IndexError, "offload index out of range");
            return error.OutOfBound;
        }
        if (key.cache >= self.keys_cache.len) {
            py.Err.setString(py.PyExc_IndexError, "cache index out of range");
            return error.OutOfBound;
        }
        if (key.episode >= self.num_episode) {
            py.Err.setString(py.PyExc_IndexError, "episode index out of range");
            return error.OutOfBound;
        }
    }
};

pub const HistoryObject = py.WrapObject(
    History,
    History.type_obj,
    History,
);

pub const Key = struct {
    offload: u32,
    cache: u32,
    episode: u32,

    pub const type_obj: py.TypeObjectBasic = .{
        .tp_name = "history.Key",
    };

    pub fn py_init(self: *Key, args: struct { *py.LongObject, *py.LongObject, *py.LongObject }) !void {
        const offload, const cache, const episode = args;
        self.offload = try offload.toInt(u32);
        self.cache = try cache.toInt(u32);
        self.episode = try episode.toInt(u32);
    }
};

pub const KeyObject = py.WrapObject(Key, Key.type_obj, Key);

pub const Record = struct {
    data: [history_metrics.len]f64, // histoty_metrics data

    pub const type_obj: py.TypeObjectBasic = .{
        .tp_name = "history.Record",
        .tp_doc = null,
        .tp_flags = .DEFAULT,
    };

    pub fn py_init(self: *Record, args: struct { *py.FloatObject, *py.FloatObject, *py.FloatObject, *py.ListObject }) !void {
        const delay, const success_rate, const cache_usage, const choices_obj = args;
        self.data[0] = try delay.tof64();
        self.data[1] = try success_rate.tof64();
        self.data[2] = try cache_usage.tof64();
        const choice: []f64 = try py.ndarrayFromList(allocators.global, choices_obj, []f64);
        defer allocators.free(choice);
        for (choice, self.data[3..]) |choice_target, *data| {
            data.* = choice_target;
        }
    }
};

pub const RecordObject = py.WrapObject(Record, Record.type_obj, Record);

pub const PlotData = struct {
    title: [:0]const u8,
    methods: [][:0]const u8,
    y_data: [history_metrics.len][][]f64,

    pub const type_obj: py.TypeObjectBasic = .{
        .tp_name = "history.PlotData",
        .tp_flags = .DEFAULT,
    };

    pub const py_getset = .{
        .{ .name = "title", .get = py_get_title },
        .{ .name = "methods", .get = py_get_methods },
        .{ .name = "delay", .get = py_get_delay },
        .{ .name = "success_rate", .get = py_get_success_rate },
        .{ .name = "cache_usage", .get = py_get_cache_usage },
        .{ .name = "choice", .get = py_get_choice },
    };

    pub fn init(
        title: [:0]const u8,
        legends: [][:0]const u8,
        delay_py: [][]f64,
        success_rate_py: [][]f64,
        cache_usage_py: [][]f64,
        choice_py: [3][][]f64,
    ) PlotData {
        return .{
            .title = title,
            .methods = legends,
            .y_data = .{
                delay_py,
                success_rate_py,
                cache_usage_py,
                choice_py[0],
                choice_py[1],
                choice_py[2],
            },
        };
    }

    pub fn py_init(self: *PlotData, args: struct { *py.UnicodeObject, *py.ListObject, *py.ListObject, *py.ListObject, *py.ListObject, *py.ListObject }) !void {
        const title_py, const legends_py, const delay_py, const success_rate_py, const cache_usage_py, const choice_py = args;
        const _choice: [][][]f64 = try py.ndarrayFromList(allocators.global, choice_py, [][][]f64);
        if (_choice.len != 3) {
            py.Err.setString(py.PyExc_IndexError, "incorrect choice length (requires 3)");
        }
        self.* = PlotData.init(
            try title_py.toOwnedSlice(allocators.global),
            try py.strArrayFromList(allocators.global, legends_py, [][:0]const u8),
            try py.ndarrayFromList(allocators.global, delay_py, [][]f64),
            try py.ndarrayFromList(allocators.global, success_rate_py, [][]f64),
            try py.ndarrayFromList(allocators.global, cache_usage_py, [][]f64),
            .{ _choice[0], _choice[1], _choice[2] },
        );
    }

    pub fn py_dealloc(self: *PlotData) void {
        allocators.free(self.title);
        for (self.methods) |str| {
            allocators.free(str);
        }
        allocators.free(self.methods);
        for (self.y_data) |metric| {
            for (metric) |metric_1| {
                allocators.free(metric_1);
            }
            allocators.free(metric);
        }
    }

    pub fn py_get_title(self: *PlotData) !*py.UnicodeObject {
        return py.UnicodeObject.fromString(self.title);
    }

    pub fn py_get_methods(self: *PlotData) !*py.ListObject {
        const legends_list: *py.ListObject = try .new(self.methods.len);
        for (self.methods, 0..) |legend, idx| {
            const legend_py: *py.UnicodeObject = .fromString(legend);
            legends_list.setItem(@intCast(idx), legend_py.toObject()) catch unreachable;
            py.DecRef(legend_py.toObject());
        }
        return legends_list;
    }

    fn get_y_data(self: *PlotData, idx: usize) !*py.ListObject {
        return try py.listFromNdarray(self.y_data[idx]);
    }

    pub fn py_get_delay(self: *PlotData) !*py.ListObject {
        return try self.get_y_data(0);
    }

    pub fn py_get_success_rate(self: *PlotData) !*py.ListObject {
        return try self.get_y_data(1);
    }

    pub fn py_get_cache_usage(self: *PlotData) !*py.ListObject {
        return try self.get_y_data(2);
    }

    pub fn py_get_choice(self: *PlotData) !*py.ListObject {
        // transpose choice: [metric][method][episode] -> [metric][method]
        var choices: [3][]f64 = undefined;
        for (&choices) |*choices_item| {
            choices_item.* = allocators.alloc(f64, self.y_data[0].len) catch
                return py.Err.outOfMemory();
        }
        defer {
            for (choices) |choices_item| {
                allocators.free(choices_item);
            }
        }
        const num_episodes = self.y_data[0][0].len;
        for (choices, 3..6) |choices_item, metric_idx| {
            for (choices_item, 0..) |*choice_item, method| {
                choice_item.* = self.y_data[metric_idx][method][num_episodes - 1];
            }
        }

        const choice_py: *py.ListObject = try .new(0);
        for (choices) |choice| {
            const choice_item_list: *py.ListObject = try .new(0);
            for (choice) |choice_item| {
                const choice_item_py: *py.FloatObject = try .fromf64(choice_item);
                try choice_item_list.append(choice_item_py.toObject());
                py.DecRef(choice_item_py.toObject());
            }
            try choice_py.append(choice_item_list.toObject());
            py.DecRef(choice_item_list.toObject());
        }
        return choice_py;
    }
};

pub const PlotDataObject = py.WrapObject(PlotData, PlotData.type_obj, PlotData);

pub var module_def: py.PyModuleDef = .init("history", null, &module_methods, freefunc);
pub var module_methods: [1]py.PyMethodDef = .{
    py.PyMethodDef.Sentinal,
};

fn freefunc(_: ?*anyopaque) callconv(.c) void {
    const stderr = std.io.getStdErr();
    allocators.deinit();
    stderr.writeAll("info: end of history module\n") catch {};
}

pub export fn PyInit_history() callconv(.c) ?*py.c.PyObject {
    allocators.init() catch {
        py.Err.setString(py.PyExc_OSError, "allocators.dll not found");
        return null;
    };
    HistoryObject.type_obj.ready() catch return null;
    KeyObject.type_obj.ready() catch return null;
    RecordObject.type_obj.ready() catch return null;
    PlotDataObject.type_obj.ready() catch return null;
    const module: *py.Object = module_def.create() catch return null;
    py.Module.AddObjectRef(module, "History", HistoryObject.type_obj.toObject()) catch {
        py.DecRef(module);
        return null;
    };
    py.Module.AddObjectRef(module, "Key", KeyObject.type_obj.toObject()) catch {
        py.DecRef(module);
        return null;
    };
    py.Module.AddObjectRef(module, "Record", RecordObject.type_obj.toObject()) catch {
        py.DecRef(module);
        return null;
    };
    py.Module.AddObjectRef(module, "PlotData", PlotDataObject.type_obj.toObject()) catch {
        py.DecRef(module);
        return null;
    };
    return module.toC();
}

const py = @import("py");
const std = @import("std");

const serialize = @import("serialize");
const allocators = @import("allocators");

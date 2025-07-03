pub const Environment = struct {
    random: Random,
    clock_rate: f64,
    task_arrival_interval: f64,
    task_complexity: f64,
    task_data_size: f64,
    data_rate_wireless: f64,
    data_rate_backhaul: f64,
    delay_cloud: f64,
    task_time_limit: f64,
    cache_hit_chance: f64,
    cache_types: u32,
    cache_limit: f64,
    cache_sizes: []f64,
    edge_spacing: f64,
    edge_coverage: f64,
    edge_compute_capacity: f64,
    num_vehicles: u32,
    vehicle_speed: f64,
    vehicle_compute_capacity: f64,

    cur_clock: f64,
    prev_clock: f64,
    max_clock: f64,

    cloud: Cloud,
    /// The only strong reference of Edge
    edges: []Edge,
    /// The only strong reference of Vehicle
    vehicles: []Vehicle,
    /// The only strong reference of Task
    tasks: ArrayList(*Task),
    max_tid: i32,
    is_ready: bool,

    total_tasks: f64,
    finished_tasks: f64,
    failed_tasks: f64,
    total_delay: f64,
    choices_count: [3]f64,
    total_cache_used: f64,
    total_cache_missed: f64,

    pub const type_obj: py.TypeObjectBasic = .{
        .tp_name = "environment.Environment",
        .tp_flags = .DEFAULT,
    };

    pub const py_getset = .{
        .{ .name = "cur_clock", .get = get_cur_clock },
        .{ .name = "max_clock", .get = get_max_clock },
        .{ .name = "total_tasks", .get = get_total_tasks },
        .{ .name = "finished_tasks", .get = get_finished_tasks },
        .{ .name = "failed_tasks", .get = get_failed_tasks },
        .{ .name = "total_delay", .get = get_total_delay },
        .{ .name = "choices_count", .get = get_choices_count },
        .{ .name = "total_cache_used", .get = get_total_cache_used },
        .{ .name = "total_cache_missed", .get = get_total_cache_missed },
    };

    pub const py_methods = .{
        .{
            .ml_name = "setAgents",
            .ml_meth = setAgents,
            .ml_flags = py.PyMethodDef.Flag.default,
        },
        .{
            .ml_name = "reset",
            .ml_meth = reset,
            .ml_flags = py.PyMethodDef.Flag.default,
        },
        .{
            .ml_name = "simulate",
            .ml_meth = simulate,
            .ml_flags = py.PyMethodDef.Flag.default,
        },
        .{
            .ml_name = "step",
            .ml_meth = step,
            .ml_flags = py.PyMethodDef.Flag.default,
        },
        .{
            .ml_name = "optimizeAllAgents",
            .ml_meth = optimizeAllAgents,
            .ml_flags = py.PyMethodDef.Flag.default,
        },
        .{
            .ml_name = "aggregateReport",
            .ml_meth = aggregateReport,
            .ml_flags = py.PyMethodDef.Flag.default,
        },
    };

    /// Configure the environment.
    ///
    /// Args:
    /// * num_servers: number of servers
    /// * vehicle_connections: closest server index of each vehicle
    /// * agent: custom agent
    pub fn py_init(
        self: *Environment,
        args: struct {
            seed: *py.LongObject,
            max_clock: *py.FloatObject,
            num_edges: *py.LongObject,
            num_cache_types: *py.LongObject,
            edge_connections: *py.ListObject,
            num_vehicles: *py.LongObject,
        },
    ) !void {
        const seed: u64 = try args.seed.toInt(u64);
        py_imports = try .init();

        const num_edges: u32 = try args.num_edges.toInt(u32);
        const num_cache_types: u32 = try args.num_cache_types.toInt(u32);
        const edge_connections: [][]u32 = try py.ndarrayFromList(
            allocators.global,
            args.edge_connections,
            [][]u32,
        );
        defer {
            for (edge_connections) |connection| {
                allocators.free(connection);
            }
            allocators.free(edge_connections);
        }
        const num_vehicles: u32 = try args.num_vehicles.toInt(u32);

        self.* = .{
            .random = .init(seed),
            .clock_rate = 1000, // 1000 clock per second
            .task_arrival_interval = 1, // 1 s
            .task_complexity = 1e9, // 1 s for 1 GHz device
            .task_data_size = 1e7, // 10 MB
            .data_rate_wireless = 1e8, // 100 mbps
            .data_rate_backhaul = 1e9, // 1 gbps
            .delay_cloud = 1, // 1 s
            .task_time_limit = 5, // 5 s for now
            .cache_hit_chance = 0.6, // 60% to cache hit (a lot higher than random)
            .cache_types = num_cache_types,
            .cache_limit = 4e9, // 4 GB
            .cache_sizes = allocators.alloc(f64, num_cache_types) catch
                return py.Err.outOfMemory(),
            .edge_spacing = 100, // 100 m
            .edge_coverage = 120, // 120 m
            .edge_compute_capacity = 5e9, // 5 GHz
            .num_vehicles = num_vehicles,
            .vehicle_speed = 40.0 / 3.6, // 40 km/h --> m/s
            .vehicle_compute_capacity = 1e9, // 1 GHz
            .cur_clock = 0,
            .prev_clock = 0,
            .max_clock = try args.max_clock.tof64(),
            .cloud = undefined, // declare later in this function
            .edges = allocators.alloc(Edge, num_edges) catch
                return py.Err.outOfMemory(), // declare later in this function
            .vehicles = allocators.alloc(Vehicle, num_vehicles) catch
                return py.Err.outOfMemory(), // declared in reset()
            .tasks = .empty,
            .max_tid = 0,
            .is_ready = false,
            .total_tasks = 0,
            .finished_tasks = 0,
            .failed_tasks = 0,
            .total_delay = 0,
            .choices_count = .{ 0, 0, 0 },
            .total_cache_used = 0,
            .total_cache_missed = 0,
        };
        for (self.cache_sizes) |*cache_size| {
            cache_size.* = self.random.floatRange(1e7, 1e9); // 10 MB ~ 1 GB
        }
        self.cloud = Cloud.init(self.delay_cloud);

        for (0..num_edges) |idx| {
            const location: Vec2D = .init(@as(f64, @floatFromInt(idx + 1)) * self.edge_spacing, 0);
            const compute_capacity = self.random.approx(self.edge_compute_capacity);
            self.edges[idx] = try Edge.init(
                @intCast(idx),
                location,
                self.data_rate_backhaul,
                compute_capacity,
                self.cache_types,
                self.cache_limit,
            );
        }
        if (self.edges.len != edge_connections.len) {
            py.Err.setString(py.PyExc_IndexError, "incorrect edge_connections len");
            return py.IndexError.ListIndex;
        }
        for (self.edges, edge_connections) |*edge, connection| {
            const connected: []*Edge = allocators.alloc(*Edge, connection.len) catch
                return py.Err.outOfMemory();
            for (connection, 0..) |idx_other, idx| {
                if (idx_other >= self.edges.len) {
                    py.Err.setString(py.PyExc_IndexError, "edge_connections oob");
                    return py.IndexError.ListIndex;
                }
                connected[idx] = &self.edges[idx_other];
            }
            edge.connect_edges = connected;
        }
    }

    pub fn py_dealloc(self: *Environment) void {
        allocators.free(self.cache_sizes);
        self.cloud.deinit();
        for (self.edges) |*edge| {
            edge.deinit();
        }
        allocators.free(self.edges);
        if (self.is_ready) { // vehicle is undefined when not ready
            for (self.vehicles) |*vehicle| {
                vehicle.deinit();
            }
        }
        allocators.free(self.vehicles);
        for (self.tasks.items) |task| {
            // task don't need deinit
            allocators.destroy(task);
        }
        self.tasks.deinit(allocators.global);
    }

    pub fn get_cur_clock(self: *Environment) !*py.FloatObject {
        return try .fromf64(self.cur_clock);
    }

    pub fn get_max_clock(self: *Environment) !*py.FloatObject {
        return try .fromf64(self.max_clock);
    }

    pub fn get_total_tasks(self: *Environment) !*py.FloatObject {
        return try .fromf64(self.total_tasks);
    }

    pub fn get_finished_tasks(self: *Environment) !*py.FloatObject {
        return try .fromf64(self.finished_tasks);
    }

    pub fn get_failed_tasks(self: *Environment) !*py.FloatObject {
        return try .fromf64(self.failed_tasks);
    }

    pub fn get_total_delay(self: *Environment) !*py.FloatObject {
        return try .fromf64(self.total_delay);
    }

    pub fn get_choices_count(self: *Environment) !*py.ListObject {
        return try py.listFromNdarray(self.choices_count);
    }

    pub fn get_total_cache_used(self: *Environment) !*py.FloatObject {
        return try .fromf64(self.total_cache_used);
    }

    pub fn get_total_cache_missed(self: *Environment) !*py.FloatObject {
        return try .fromf64(self.total_cache_missed);
    }

    /// python method
    pub fn setAgents(self: *Environment, args: struct {
        agent_offload_gen: *py.Object,
        agent_cache_gen: *py.Object,
    }) !*py.Object {
        for (self.edges) |*edge| {
            const connect_edges_len_obj: *py.LongObject = try .fromInt(usize, edge.connect_edges.len);
            defer py.DecRef(connect_edges_len_obj.toObject());
            const agent_offload: *py.Object = try py.call(
                args.agent_offload_gen,
                .{connect_edges_len_obj.toObject()},
            );
            const agent_cache: *py.Object = try py.call(
                args.agent_cache_gen,
                .{connect_edges_len_obj.toObject()},
            );
            edge.setAgent(agent_offload, agent_cache);
        }
        return py.Py_None();
    }

    /// python method
    ///
    /// Reset the dynamic part of the system, without touching the static configuration.
    pub fn reset(self: *Environment, args: struct {
        seed_obj: *py.LongObject,
    }) !*py.Object {
        const seed: u64 = try args.seed_obj.toInt(u64);
        self.random.seed(seed);
        self.cur_clock = 0;
        self.prev_clock = 0;
        self.cloud.reset();
        for (self.edges) |*edge| {
            try edge.reset();
        }
        for (self.vehicles, 0..) |*vehicle, idx| {
            const x_max: f64 = @as(f64, @floatFromInt(self.edges.len + 1)) * self.edge_spacing;
            const location: Vec2D = .init(self.random.float() * x_max, 0);
            const velocity: Vec2D = if (self.random.boolean())
                .init(self.vehicle_speed, 0)
            else
                .init(0 - self.vehicle_speed, 0);
            if (self.is_ready) {
                vehicle.deinit();
            }
            vehicle.* = try Vehicle.init(
                &self.random,
                @intCast(idx),
                location,
                velocity,
                self.data_rate_wireless,
                self.random.approx(self.vehicle_compute_capacity),
                self.task_arrival_interval,
                self.cache_types,
                self.cache_limit,
                self.cache_sizes,
            );
            vehicle.setConnect(self.edges, self.edge_coverage);
        }
        self.max_tid = 0;
        self.total_tasks = 0;
        self.finished_tasks = 0;
        self.failed_tasks = 0;
        self.total_delay = 0;
        self.choices_count = .{ 0, 0, 0 };
        self.total_cache_used = 0;
        self.total_cache_missed = 0;
        self.is_ready = true;
        return py.Py_None();
    }

    /// python method
    ///
    /// Start a new simulate and aggregate the result.
    pub fn simulate(self: *Environment, args: struct {
        seed_obj: *py.LongObject,
    }) !*py.Object {
        _ = try self.reset(.{ .seed_obj = args.seed_obj });
        while (self.cur_clock < self.max_clock) {
            _ = try self.step(.{});
        }
        _ = try self.aggregateReport(.{});
        return py.Py_None();
    }

    /// python method
    pub fn step(self: *Environment, _: struct {}) !*py.Object {
        // uses timestep based approach
        const cur_clock_obj: *py.FloatObject = try .fromf64(self.cur_clock);
        defer py.DecRef(cur_clock_obj.toObject());
        const self_obj: *EnvironmentObject = @fieldParentPtr("inner", self);

        var scheduled_tasks: ArrayList(*Task) = .empty;
        defer scheduled_tasks.deinit(allocators.global);

        // std.log.info("environment.step.generate", .{});
        for (self.vehicles) |*vehicle| {
            // only generate task when vehicle can connect to system
            if (vehicle.next_arrival_time <= self.cur_clock) {
                if (vehicle.connect_edge) |near| {
                    const cachetype: u32 = vehicle.getCacheType(self.cache_hit_chance);
                    const incoming: *Task = allocators.create(Task) catch
                        return py.Err.outOfMemory();
                    incoming.* = Task.init(
                        self.max_tid,
                        cachetype,
                        self.random.approx(self.task_complexity),
                        self.random.approx(self.task_data_size),
                        self.cache_sizes[cachetype],
                        self.task_time_limit,
                        vehicle,
                        near,
                        self.cur_clock,
                    );
                    self.max_tid += 1;
                    near.total_tasks += 1;
                    self.tasks.append(allocators.global, incoming) catch
                        return py.Err.outOfMemory();
                    vehicle.pending_task.append(allocators.global, incoming) catch
                        return py.Err.outOfMemory();
                    vehicle.next_arrival_time = self.cur_clock + self.random.approx(vehicle.mean_arrival_interval);
                    scheduled_tasks.append(allocators.global, incoming) catch
                        return py.Err.outOfMemory();

                    const agent_offload: *py.Object = near.agent_offload orelse
                        return py.Err.NoneError("near.agent_offload is None");
                    const state_offload: *py.Object = try self.getStateOffload(incoming);
                    defer py.DecRef(state_offload.toObject());
                    const decision_obj = try py.callMethod(
                        agent_offload,
                        "getOffloadDecision",
                        .{state_offload},
                    );
                    defer py.DecRef(decision_obj);
                    const _decision_obj: *py.LongObject = try .fromObject(decision_obj);
                    const decision: u32 = try _decision_obj.toInt(u32);

                    try self.setRoute(incoming, decision);
                }
            }
        }
        // std.log.info("environment.step.scheduled_tasks", .{});
        for (scheduled_tasks.items) |scheduled_task| {
            // std.log.info("environment.step.scheduled_tasks: {}", .{scheduled_task.tid});
            const near: *Edge = scheduled_task.near;
            const local: *Vehicle = scheduled_task.local;
            const cloud: *Cloud = &self.cloud;
            switch (scheduled_task.choice) {
                .local => {
                    // start static cloud -> near
                    if (near.cache_current[scheduled_task.cachetype] == 1) {
                        near.cache_used[scheduled_task.cachetype] += 1;

                        const _cache_latest: *py.LongObject = try .fromInt(u32, scheduled_task.cachetype);
                        defer py.DecRef(_cache_latest.toObject());
                        const state_cache_minor: *py.Object = try py.call(py_imports.StateCacheMinorObject, .{
                            cur_clock_obj,
                            _cache_latest,
                        });
                        defer py.DecRef(state_cache_minor);
                        const agent_cache: *py.Object = near.agent_cache orelse
                            return py.Err.NoneError("edge.agent_cache is None");
                        _ = try py.callMethod(agent_cache, "updateCacheMinor", .{state_cache_minor});
                    } else {
                        near.cache_missed[scheduled_task.cachetype] += 1;
                        try near.nextCache(self, scheduled_task.cachetype);
                    }
                    if (local.cache_current[scheduled_task.cachetype] == 1) {
                        scheduled_task.has_static = true;
                    } else {
                        try cloud.startTaskStatic(self.cur_clock, scheduled_task);
                    }
                    // start compute local
                    scheduled_task.has_dynamic = true;
                    try local.startTaskCompute(self.cur_clock, scheduled_task);
                },
                .near => {
                    // start static cloud -> near/far
                    if (near.cache_current[scheduled_task.cachetype] == 1) {
                        scheduled_task.has_static = true;
                        near.cache_used[scheduled_task.cachetype] += 1;

                        const _cache_latest: *py.LongObject = try .fromInt(u32, scheduled_task.cachetype);
                        defer py.DecRef(_cache_latest.toObject());
                        const state_cache_minor: *py.Object = try py.call(py_imports.StateCacheMinorObject, .{
                            cur_clock_obj,
                            _cache_latest,
                        });
                        defer py.DecRef(state_cache_minor);
                        const agent_cache: *py.Object = near.agent_cache orelse
                            return py.Err.NoneError("edge.agent_cache is None");
                        _ = try py.callMethod(agent_cache, "updateCacheMinor", .{state_cache_minor});
                    } else {
                        near.cache_missed[scheduled_task.cachetype] += 1;
                        try cloud.startTaskStatic(self.cur_clock, scheduled_task);
                        try near.nextCache(self, scheduled_task.cachetype);
                    }
                    // start dynamic local -> near
                    try local.startTaskDynamic(self.cur_clock, scheduled_task);
                },
                .far => {
                    // start static cloud -> near/far
                    const far: *Edge = scheduled_task.far orelse
                        return py.Err.NoneError("scheduled_task.far is None");
                    if (far.cache_current[scheduled_task.cachetype] == 1) {
                        scheduled_task.has_static = true;
                        far.cache_used[scheduled_task.cachetype] += 1;

                        const _cache_latest: *py.LongObject = try .fromInt(u32, scheduled_task.cachetype);
                        defer py.DecRef(_cache_latest.toObject());
                        const state_cache_minor: *py.Object = try py.call(py_imports.StateCacheMinorObject, .{
                            cur_clock_obj,
                            _cache_latest,
                        });
                        defer py.DecRef(state_cache_minor);
                        const agent_cache: *py.Object = far.agent_cache orelse
                            return py.Err.NoneError("edge.agent_cache is None");
                        _ = try py.callMethod(agent_cache, "updateCacheMinor", .{state_cache_minor});
                    } else {
                        far.cache_missed[scheduled_task.cachetype] += 1;
                        try cloud.startTaskStatic(self.cur_clock, scheduled_task);
                        try far.nextCache(self, scheduled_task.cachetype);
                    }
                    // start dynamic local -> near
                    try local.startTaskDynamic(self.cur_clock, scheduled_task);
                },
                .unknown => {
                    py.Err.setString(py.PyExc_Exception, "unknown choice");
                    return error.UnknownChoice;
                },
            }
        }
        // cloud step
        try self.cloud.endTaskStatic(self.cur_clock, self_obj);

        // vehicle step
        for (self.vehicles) |*vehicle| {
            // end dynamic local -> near
            try vehicle.endTaskDynamic(self.cur_clock);
            // end compute local
            const task_opt: ?*Task = try vehicle.endTaskCompute(self.cur_clock);
            if (task_opt) |task| {
                try self.processFinishedTask(task);
            }
        }

        // edge step
        for (self.edges) |*edge| {
            // end dynamic near -> far
            try edge.endTaskDynamic(self.cur_clock);
            // end static near -> local
            try edge.endTaskStatic(self.cur_clock);
            // end compute near/far
            const task_opt: ?*Task = try edge.endTaskCompute(self.cur_clock);
            if (task_opt) |task| {
                try self.processFinishedTask(task);
            }
        }

        // vehicle movement and connection
        // std.log.info("environment.step.move, clock: {}", .{self.cur_clock});
        for (self.vehicles, 0..) |*vehicle, idx| {
            vehicle.move(self.clock_rate);
            vehicle.setConnect(self.edges, self.edge_coverage);
            // replace old vehicle when no connection and no pending task
            if (vehicle.connect_edge == null and vehicle.pending_task.items.len == 0) {
                // new vehicle starts at near edge of the map
                const x_max: f64 = @as(f64, @floatFromInt(self.edges.len + 1)) * self.edge_spacing;
                const go_positive: bool = self.random.boolean();
                const location: Vec2D = if (go_positive)
                    Vec2D.init(0, 0)
                else
                    Vec2D.init(x_max, 0);
                const velocity: Vec2D = if (go_positive)
                    Vec2D.init(self.vehicle_speed, 0)
                else
                    Vec2D.init(0 - self.vehicle_speed, 0);
                vehicle.deinit();
                vehicle.* = try Vehicle.init(
                    &self.random,
                    @intCast(idx),
                    location,
                    velocity,
                    self.data_rate_wireless,
                    self.random.approx(self.vehicle_compute_capacity),
                    self.task_arrival_interval,
                    self.cache_types,
                    self.cache_limit,
                    self.cache_sizes,
                );
                vehicle.setConnect(self.edges, self.edge_coverage);
            }
        }

        self.cur_clock += (1 / self.clock_rate);
        return py.Py_None();
    }

    fn processFinishedTask(self: *Environment, task: *Task) !void {
        const near: *Edge = task.near;
        const elapse_time: f64 = self.cur_clock - task.request_clock;
        near.total_delay += elapse_time;
        switch (task.status) {
            .success => {
                near.finished_tasks += 1;
            },
            .fail => {
                near.failed_tasks += 1;
            },
            .pending => {
                py.Err.setString(py.PyExc_Exception, "task should finish");
                return error.PendingTask;
            },
        }
        const agent_offload: *py.Object = near.agent_offload orelse
            return py.Err.NoneError("near.agent_offload is None");
        const tid: *py.LongObject = try .fromInt(i32, task.tid);
        defer py.DecRef(tid.toObject());
        const success: i32 = switch (task.status) {
            .success => 1,
            .fail => 0,
            .pending => {
                py.Err.setString(py.PyExc_Exception, "task should finish");
                return error.PendingTask;
            },
        };
        const success_obj: *py.LongObject = try .fromInt(i32, success);
        defer py.DecRef(success_obj.toObject());
        const elapse_time_obj: *py.FloatObject = try .fromf64(elapse_time);
        defer py.DecRef(elapse_time_obj.toObject());
        const reward_offload: *py.Object = try py.call(py_imports.RewardOffloadObject, .{
            success_obj,
            elapse_time_obj,
        });
        defer py.DecRef(reward_offload.toObject());
        const state_offload: *py.Object = try self.getStateOffload(task);
        defer py.DecRef(state_offload.toObject());
        _ = try py.callMethod(agent_offload, "updateAgent", .{
            tid,
            reward_offload,
            state_offload,
        });
    }

    /// python method
    pub fn optimizeAllAgents(self: *Environment, _: struct {}) !*py.Object {
        for (self.edges) |edge| {
            if (edge.agent_offload) |agent_offload| {
                _ = try py.callMethod(agent_offload, "optimize", .{});
            } else return py.Err.NoneError("edge.agent_offload is None");

            if (edge.agent_cache) |agent_cache| {
                _ = try py.callMethod(agent_cache, "optimize", .{});
            } else return py.Err.NoneError("edge.agent_cache is None");
        }
        return py.Py_None();
    }

    /// python method
    pub fn aggregateReport(self: *Environment, _: struct {}) !*py.Object {
        for (self.edges) |edge| {
            self.total_tasks += @floatFromInt(edge.total_tasks);
            self.finished_tasks += @floatFromInt(edge.finished_tasks);
            self.total_delay += edge.total_delay;
        }
        return py.Py_None();
    }

    pub fn getStateOffload(self: *Environment, task: *Task) !*py.Object {
        const local: *Vehicle = task.local;
        const near: *Edge = task.near;

        const cur_clock: *py.FloatObject = try .fromf64(self.cur_clock);
        defer py.DecRef(cur_clock.toObject());
        const tid: *py.LongObject = try .fromInt(i32, task.tid);
        const TaskInfoObject: *py.Object = try py.getAttrString(py_imports.StateOffloadObject, "TaskInfo");
        const ServerInfoObject: *py.Object = try py.getAttrString(py_imports.StateOffloadObject, "ServerInfo");
        const CloudInfoObject: *py.Object = try py.getAttrString(py_imports.StateOffloadObject, "CloudInfo");
        const task_data_size: *py.FloatObject = try .fromf64(task.data_size);
        defer py.DecRef(task_data_size.toObject());
        const task_service_size: *py.FloatObject = try .fromf64(task.cache_size);
        defer py.DecRef(task_service_size.toObject());
        const task_complexity: *py.FloatObject = try .fromf64(task.complexity);
        defer py.DecRef(task_complexity.toObject());
        const taskinfo: *py.Object = try py.call(TaskInfoObject, .{
            task_data_size,
            task_service_size,
            task_complexity,
        });
        defer py.DecRef(taskinfo);
        const local_data_rate: *py.FloatObject = try .fromf64(local.data_rate);
        defer py.DecRef(local_data_rate.toObject());
        const local_compute_capacity: *py.FloatObject = try .fromf64(local.compute_capacity);
        defer py.DecRef(local_compute_capacity.toObject());
        const local_cached: *py.LongObject = try .fromInt(i32, local.cache_current[task.cachetype]);
        defer py.DecRef(local_cached.toObject());
        const localinfo: *py.Object = try py.call(ServerInfoObject, .{
            local_data_rate,
            local_compute_capacity,
            local_cached,
        });
        defer py.DecRef(localinfo);
        const nearest_data_rate: *py.FloatObject = try .fromf64(near.data_rate);
        defer py.DecRef(nearest_data_rate.toObject());
        const nearest_compute_capacity: *py.FloatObject = try .fromf64(near.compute_capacity);
        defer py.DecRef(nearest_compute_capacity.toObject());
        const nearest_cached: *py.LongObject = try .fromInt(i32, near.cache_current[task.cachetype]);
        defer py.DecRef(nearest_cached.toObject());
        const nearestinfo: *py.Object = try py.call(ServerInfoObject, .{
            nearest_data_rate,
            nearest_compute_capacity,
            nearest_cached,
        });
        defer py.DecRef(nearestinfo);
        const othersinfo: *py.ListObject = blk: {
            var _others_info: *py.ListObject = try .new(near.connect_edges.len);
            for (near.connect_edges, 0..) |other, idx| {
                const other_data_rate: *py.FloatObject = try .fromf64(other.data_rate);
                defer py.DecRef(other_data_rate.toObject());
                const other_compute_capacity: *py.FloatObject = try .fromf64(other.compute_capacity);
                defer py.DecRef(other_compute_capacity.toObject());
                const other_cached: *py.LongObject = try .fromInt(i32, other.cache_current[task.cachetype]);
                defer py.DecRef(other_cached.toObject());
                const _otherinfo: *py.Object = try py.call(ServerInfoObject, .{
                    other_data_rate,
                    other_compute_capacity,
                    other_cached,
                });
                defer py.DecRef(_otherinfo);
                _others_info.setItem(@intCast(idx), _otherinfo.toObject()) catch unreachable;
            }
            break :blk _others_info;
        };
        defer py.DecRef(othersinfo.toObject());
        const latency: *py.FloatObject = try .fromf64(self.cloud.latency);
        defer py.DecRef(latency.toObject());
        const cloudinfo: *py.Object = try py.call(CloudInfoObject, .{
            latency,
        });
        defer py.DecRef(cloudinfo);
        const cachetype: *py.LongObject = try .fromInt(u32, task.cachetype);
        defer py.DecRef(cachetype.toObject());
        const others_cached: *py.ListObject = blk: {
            var _others_cached: *py.ListObject = try .new(near.connect_edges.len);
            for (near.connect_edges, 0..) |other, idx| {
                const _cached: *py.LongObject = try .fromInt(i32, other.cache_current[task.cachetype]);
                _others_cached.setItem(@intCast(idx), _cached.toObject()) catch unreachable;
            }
            break :blk _others_cached;
        };
        defer py.DecRef(others_cached.toObject());
        return try py.call(py_imports.StateOffloadObject, .{
            cur_clock,
            tid,
            taskinfo,
            localinfo,
            nearestinfo,
            othersinfo,
            cloudinfo,
            cachetype,
        });
    }

    /// Increment choice_count and setup far if it is far.
    pub fn setRoute(
        self: *Environment,
        task: *Task,
        decision: u32,
    ) !void {
        const near: *Edge = task.near;
        if (decision == 0) {
            self.choices_count[0] += 1;
            task.choice = Choice.local;
        } else if (decision == 1) {
            self.choices_count[1] += 1;
            task.choice = Choice.near;
        } else {
            const far: *Edge = near.connect_edges[decision - 2];
            self.choices_count[2] += 1;
            task.choice = Choice.far;
            task.far = far;
        }
    }
};

pub const EnvironmentObject = py.WrapObject(
    Environment,
    Environment.type_obj,
    Environment,
);

pub const Cloud = struct {
    latency: f64,
    /// Weak reference.
    tasks: ArrayList(*Task),

    pub const type_obj: py.TypeObjectBasic = .{
        .tp_name = "environment.Cloud",
        .tp_flags = .DEFAULT,
    };

    pub const py_getset = .{};

    pub const py_methods = .{};

    pub fn init(latency: f64) Cloud {
        return .{
            .latency = latency,
            .tasks = .empty,
        };
    }

    pub fn deinit(self: *Cloud) void {
        self.tasks.deinit(allocators.global);
    }

    pub fn reset(self: *Cloud) void {
        self.tasks = .empty;
    }

    pub fn startTaskStatic(
        self: *Cloud,
        cur_clock: f64,
        task: *Task,
    ) !void {
        // std.log.info("cloud.startTaskStatic: {}", .{task.tid});
        task.clock = cur_clock + self.latency;
        try self.tasks.append(allocators.global, task);
    }

    pub fn endTaskStatic(self: *Cloud, cur_clock: f64, env_obj: *EnvironmentObject) !void {
        _ = env_obj; // not used in python either
        var new_tasks: ArrayList(*Task) = .empty;
        for (self.tasks.items) |task| {
            if (task.clock <= cur_clock) { // task finished
                // std.log.info("cloud.endTaskStatic: {}", .{task.tid});
                switch (task.choice) {
                    .local => {
                        try task.near.startTaskStatic(cur_clock, task);
                    },
                    .near => {
                        task.has_static = true;
                        try task.near.startTaskCompute(cur_clock, task);
                    },
                    .far => {
                        task.has_static = true;
                        const far: *Edge = task.far orelse
                            return py.Err.NoneError("task.far is None");
                        try far.startTaskCompute(cur_clock, task);
                    },
                    .unknown => {
                        py.Err.setString(py.PyExc_Exception, "unknown choice");
                        return error.UnknownChoice;
                    },
                }
            } else {
                new_tasks.append(allocators.global, task) catch
                    return py.Err.outOfMemory();
            }
        }
        self.tasks.deinit(allocators.global);
        self.tasks = new_tasks;
    }
};

pub const Edge = struct {
    index: i32,
    location: Vec2D,
    /// Weak reference.
    connect_edges: []*Edge,
    data_rate: f64,
    compute_capacity: f64,
    /// Weak reference.
    queue_dynamic: ArrayList(*Task),
    /// Weak reference.
    queue_static: ArrayList(*Task),
    /// Weak reference.
    queue_compute: ArrayList(*Task),
    task_limit: i32,
    ///Stores task if server is transfering, or None otherwise. Weak reference.
    task_dynamic: ?*Task,
    ///Stores task if server is transfering, or None otherwise. Weak reference.
    task_static: ?*Task,
    ///Stores task if server is busy, or None otherwise. Weak reference.
    task_compute: ?*Task,
    /// For each task type, stores 1 if server has cache, or 0 otherwise. Weak reference.
    cache_current: []i32,
    cache_limit: f64,
    /// Stores when last cache update happens.
    prev_cache_clock: f64,
    /// Uses agents.Offload. Strong Reference.
    agent_offload: ?*py.Object,
    /// Uses agents.Cache. Strong Reference.
    agent_cache: ?*py.Object,
    total_tasks: i32,
    finished_tasks: i32,
    failed_tasks: f64,
    total_delay: f64,

    /// Accumulated tasks by type between two cache update period.
    cache_used: []i32,
    cache_missed: []i32,

    pub fn init(
        index: i32,
        location: Vec2D,
        data_rate: f64,
        compute_capacity: f64,
        cache_types: usize,
        cache_limit: f64,
    ) !Edge {
        const _cache_current: []i32 = allocators.alloc(i32, cache_types) catch
            return py.Err.outOfMemory();
        @memset(_cache_current, 0);
        const _cache_used: []i32 = allocators.alloc(i32, cache_types) catch
            return py.Err.outOfMemory();
        @memset(_cache_used, 0);
        const _cache_missed: []i32 = allocators.alloc(i32, cache_types) catch
            return py.Err.outOfMemory();
        @memset(_cache_missed, 0);
        return .{
            .index = index,
            .location = location,
            .connect_edges = &.{},
            .data_rate = data_rate,
            .compute_capacity = compute_capacity,
            .queue_dynamic = .empty,
            .queue_static = .empty,
            .queue_compute = .empty,
            .task_limit = 1000,
            .task_dynamic = null,
            .task_static = null,
            .task_compute = null,
            .cache_current = _cache_current,
            .cache_limit = cache_limit,
            .prev_cache_clock = 0,
            .agent_offload = null,
            .agent_cache = null,
            .total_tasks = 0,
            .finished_tasks = 0,
            .failed_tasks = 0,
            .total_delay = 0,
            .cache_used = _cache_used,
            .cache_missed = _cache_missed,
        };
    }

    pub fn deinit(self: *Edge) void {
        allocators.free(self.connect_edges);
        self.queue_dynamic.deinit(allocators.global);
        self.queue_static.deinit(allocators.global);
        self.queue_compute.deinit(allocators.global);
        allocators.free(self.cache_current);
        if (self.agent_offload) |agent| {
            py.DecRef(agent.toObject());
        }
        if (self.agent_cache) |agent| {
            py.DecRef(agent.toObject());
        }
        allocators.free(self.cache_used);
        allocators.free(self.cache_missed);
    }

    pub fn setAgent(self: *Edge, agent_offload: *py.Object, agent_cache: *py.Object) void {
        if (self.agent_offload) |agent| {
            py.DecRef(agent.toObject());
        }
        self.agent_offload = agent_offload;
        if (self.agent_cache) |agent| {
            py.DecRef(agent.toObject());
        }
        self.agent_cache = agent_cache;
    }

    pub fn reset(self: *Edge) !void {
        self.queue_dynamic.deinit(allocators.global);
        self.queue_dynamic = .empty;
        self.queue_static.deinit(allocators.global);
        self.queue_static = .empty;
        self.queue_compute.deinit(allocators.global);
        self.queue_compute = .empty;
        self.task_dynamic = null;
        self.task_static = null;
        self.task_compute = null;
        @memset(self.cache_current, 0);
        self.prev_cache_clock = 0;
        if (self.agent_offload) |agent_offload| {
            _ = try py.callMethod(agent_offload, "reset", .{});
        } else {
            return py.Err.NoneError("agent_offload is None");
        }
        if (self.agent_cache) |agent_cache| {
            _ = try py.callMethod(agent_cache, "reset", .{});
        } else {
            return py.Err.NoneError("agent_cache is None");
        }
        self.total_tasks = 0;
        self.finished_tasks = 0;
        self.failed_tasks = 0;
        self.total_delay = 0;
        @memset(self.cache_used, 0);
        @memset(self.cache_missed, 0);
    }

    pub fn startTaskDynamic(self: *Edge, cur_clock: f64, task: *Task) !void {
        assert(self.task_dynamic != null or self.queue_dynamic.items.len == 0);
        // std.log.info("edge.startTaskDynamic: {}", .{task.tid});
        if (self.task_dynamic) |_| {
            if (self.queue_dynamic.items.len < self.task_limit) {
                self.queue_dynamic.append(allocators.global, task) catch
                    return py.Err.outOfMemory();
            }
        } else {
            task.clock = cur_clock + task.data_size / self.data_rate;
            self.task_dynamic = task;
        }
    }

    pub fn endTaskDynamic(self: *Edge, cur_clock: f64) !void {
        if (self.task_dynamic) |task_transfer| { // task transfer or finished
            if (task_transfer.clock <= cur_clock) { // task finished
                // std.log.info("edge.endTaskDynamic: {}", .{task_transfer.tid});
                if (self.queue_dynamic.items.len > 0) { // queue has task
                    var queue_task: *Task = self.queue_dynamic.orderedRemove(0);
                    queue_task.clock = cur_clock + queue_task.data_size / self.data_rate;
                    self.task_dynamic = queue_task;
                } else {
                    self.task_dynamic = null;
                }
                // start next step
                switch (task_transfer.choice) {
                    .local => {
                        py.Err.setString(py.PyExc_Exception, "local in endTaskDynamic");
                        return error.BanLocal;
                    },
                    .near => {
                        py.Err.setString(py.PyExc_Exception, "near in edge's endTaskDynamic");
                        return error.BanNear;
                    },
                    .far => {
                        task_transfer.has_dynamic = true;
                        const far: *Edge = task_transfer.far orelse
                            return py.Err.NoneError("task.far is None");
                        try far.startTaskCompute(cur_clock, task_transfer);
                    },
                    .unknown => {
                        py.Err.setString(py.PyExc_Exception, "unknown choice");
                        return error.UnknownChoice;
                    },
                }
            }
        }
    }

    pub fn startTaskStatic(self: *Edge, cur_clock: f64, task: *Task) !void {
        assert(self.task_static != null or self.queue_static.items.len == 0);
        // std.log.info("edge.startTaskStatic: {}", .{task.tid});
        if (self.task_static) |_| {
            if (self.queue_static.items.len < self.task_limit) {
                self.queue_static.append(allocators.global, task) catch
                    return py.Err.outOfMemory();
            }
        } else {
            task.clock = cur_clock + task.data_size / self.data_rate;
            self.task_static = task;
        }
    }

    pub fn endTaskStatic(self: *Edge, cur_clock: f64) !void {
        if (self.task_static) |task_transfer| { // task transfer or finished
            if (task_transfer.clock <= cur_clock) { // task finished
                // std.log.info("edge.endTaskStatic: {}", .{task_transfer.tid});
                if (self.queue_static.items.len > 0) { // queue has task
                    var queue_task: *Task = self.queue_static.orderedRemove(0);
                    queue_task.clock = cur_clock + queue_task.cache_size / self.data_rate;
                    self.task_static = queue_task;
                } else {
                    self.task_static = null;
                }
                // start next step
                task_transfer.has_static = true;
                const local: *Vehicle = task_transfer.local;
                try local.startTaskCompute(cur_clock, task_transfer);
            }
        }
    }

    pub fn startTaskCompute(self: *Edge, cur_clock: f64, task: *Task) !void {
        assert(self.task_compute != null or self.queue_compute.items.len == 0);
        if (task.has_dynamic and task.has_static) {
            // std.log.info("edge.startTaskCompute: {}", .{task.tid});
            if (self.task_compute) |_| {
                if (self.queue_compute.items.len < self.task_limit) {
                    self.queue_compute.append(allocators.global, task) catch
                        return py.Err.outOfMemory();
                } else {
                    task.finish(false);
                }
            } else {
                task.clock = cur_clock + task.data_size / self.data_rate;
                self.task_compute = task;
            }
        }
    }

    pub fn endTaskCompute(self: *Edge, cur_clock: f64) !?*Task {
        assert(self.task_compute != null or self.queue_compute.items.len == 0);
        if (self.task_compute) |task_compute| { // task processing or finished
            if (task_compute.clock <= cur_clock) { // task finished
                // std.log.info("edge.endTaskCompute: {}", .{task_compute.tid});
                if (self.queue_compute.items.len > 0) { // queue has task
                    var queue_task: *Task = self.queue_compute.orderedRemove(0);
                    queue_task.clock = cur_clock + queue_task.complexity / self.compute_capacity;
                    self.task_compute = queue_task;
                } else {
                    self.task_compute = null;
                }
                const elapse_time: f64 = cur_clock - task_compute.request_clock;
                const success: bool = elapse_time <= task_compute.time_limit;
                task_compute.finish(success);
                return task_compute;
            }
        }
        return null;
    }

    pub fn nextCache(self: *Edge, env: *Environment, cachetype_latest: u32) !void {
        // std.log.info("edge.nextCache", .{});
        var other_cache_current: [][]i32 = allocators.alloc([]i32, self.connect_edges.len) catch
            return py.Err.outOfMemory();
        defer allocators.free(other_cache_current);
        for (self.connect_edges, 0..) |other, idx| {
            other_cache_current[idx] = other.cache_current;
        }

        var cache_referenced: []i32 = allocators.alloc(i32, self.cache_used.len) catch
            return py.Err.outOfMemory();
        defer allocators.free(cache_referenced);
        for (self.cache_used, self.cache_missed, 0..) |used, missed, idx| {
            cache_referenced[idx] = used + missed;
        }

        var cur_clock: *py.FloatObject = try .fromf64(env.cur_clock);
        defer py.DecRef(cur_clock.toObject());
        var prev_clock: *py.FloatObject = try .fromf64(self.prev_cache_clock);
        defer py.DecRef(prev_clock.toObject());
        var cache_limit: *py.FloatObject = try .fromf64(self.cache_limit);
        defer py.DecRef(cache_limit.toObject());
        var caches_size_obj: *py.ListObject = try py.listFromNdarray(env.cache_sizes);
        defer py.DecRef(caches_size_obj.toObject());
        var caches_current_self: *py.ListObject = try py.listFromNdarray(self.cache_current);
        defer py.DecRef(caches_current_self.toObject());
        var caches_current_other: *py.ListObject = try py.listFromNdarray(other_cache_current);
        defer py.DecRef(caches_current_other.toObject());
        var caches_used: *py.ListObject = try py.listFromNdarray(cache_referenced);
        defer py.DecRef(caches_used.toObject());
        var cache_latest: *py.LongObject = try .fromInt(u32, cachetype_latest);
        defer py.DecRef(cache_latest.toObject());
        const state_cache: *py.Object = try py.call(py_imports.StateCacheObject, .{
            cur_clock,
            prev_clock,
            cache_limit,
            caches_size_obj,
            caches_current_self,
            caches_current_other,
            caches_used,
            cache_latest,
        });
        defer py.DecRef(state_cache);
        self.prev_cache_clock = env.cur_clock;

        const cache_total: []i32 = allocators.alloc(i32, self.cache_used.len) catch
            return py.Err.outOfMemory();
        defer allocators.free(cache_total);
        for (cache_total, self.cache_used, self.cache_missed) |*item, used, missed| {
            item.* = used + missed;
        }
        const cache_total_obj = try py.listFromNdarray(cache_total);
        defer py.DecRef(cache_total_obj.toObject());
        const cache_used = try py.listFromNdarray(self.cache_used);
        defer py.DecRef(cache_used.toObject());
        const reward_cache = try py.call(py_imports.RewardCacheObject, .{
            cache_total_obj,
            cache_used,
        });
        defer py.DecRef(reward_cache);
        const agent_cache = self.agent_cache orelse
            return py.Err.NoneError("edge.agent_cache is None");
        _ = try py.callMethod(agent_cache, "updateAgent", .{ reward_cache, state_cache });
        for (0..@as(usize, env.cache_types)) |idx| {
            env.total_cache_used += @floatFromInt(self.cache_used[idx]);
            env.total_cache_missed += @floatFromInt(self.cache_missed[idx]);
        }
        @memset(self.cache_used, 0);
        @memset(self.cache_missed, 0);

        const cache_next_obj: *py.Object = try py.callMethod(agent_cache, "updateCacheMajor", .{state_cache});
        defer py.DecRef(cache_next_obj);
        const cache_next: *py.ListObject = try .fromObject(cache_next_obj);
        if (cache_next.getSize() != self.cache_current.len) {
            py.Err.setString(py.PyExc_IndexError, "cache size doesn't match");
            return error.pyList;
        }
        try py.ndarrayFromListFill(cache_next, self.cache_current);
    }
};

pub const Vehicle = struct {
    random: *Random,
    index: i32,
    location: Vec2D,
    velocity: Vec2D,
    data_rate: f64,
    compute_capacity: f64,
    mean_arrival_interval: f64,
    task_limit: usize,
    /// Weak reference.
    queue_dynamic: ArrayList(*Task),
    /// Weak reference.
    queue_compute: ArrayList(*Task),
    /// Stores next task arrival time.
    next_arrival_time: f64,
    /// Stores all pending tasks. Weak reference.
    pending_task: ArrayList(*Task),
    /// Stores task if server is transfering, or null otherwise. Weak reference.
    task_dynamic: ?*Task,
    /// Stores task if server is busy, or null otherwise. Weak reference.
    task_compute: ?*Task,
    /// For each task type, stores 1 if server has cache, or 0 otherwise.
    cache_current: []i32,
    cache_hit_type: []u32,
    cache_miss_type: []u32,
    /// Weak reference.
    connect_edge: ?*Edge,

    pub fn init(
        random: *Random,
        index: i32,
        location: Vec2D,
        velocity: Vec2D,
        data_rate: f64,
        compute_capacity: f64,
        mean_arrival_interval: f64,
        cache_types: usize,
        cache_limit: f64,
        cache_sizes: []const f64,
    ) !Vehicle {
        const _cache_current: []i32 = allocators.alloc(i32, cache_types) catch
            return py.Err.outOfMemory();
        @memset(_cache_current, 0);
        var self: Vehicle = .{
            .random = random,
            .index = index,
            .location = location,
            .velocity = velocity,
            .data_rate = data_rate,
            .compute_capacity = compute_capacity,
            .mean_arrival_interval = mean_arrival_interval,
            .task_limit = 1000,
            .queue_dynamic = .empty,
            .queue_compute = .empty,
            .next_arrival_time = 0,
            .pending_task = .empty,
            .task_dynamic = null,
            .task_compute = null,
            .cache_current = _cache_current,
            .cache_hit_type = &.{},
            .cache_miss_type = &.{},
            .connect_edge = null,
        };
        self.next_arrival_time += self.random.approx(self.mean_arrival_interval);
        try self.fillCache(cache_limit, cache_sizes);
        return self;
    }

    fn setCacheHitMissType(self: *Vehicle) !void {
        var cache_hit_type: ArrayList(u32) = ArrayList(u32).initCapacity(
            allocators.global,
            self.cache_current.len,
        ) catch return py.Err.outOfMemory();
        defer cache_hit_type.deinit(allocators.global);
        var cache_miss_type: ArrayList(u32) = ArrayList(u32).initCapacity(
            allocators.global,
            self.cache_current.len,
        ) catch return py.Err.outOfMemory();
        defer cache_miss_type.deinit(allocators.global);
        for (self.cache_current, 0..) |cache_current, idx| {
            if (cache_current == 1) {
                cache_hit_type.appendAssumeCapacity(@intCast(idx));
            } else {
                cache_miss_type.appendAssumeCapacity(@intCast(idx));
            }
        }
        self.cache_hit_type = cache_hit_type.toOwnedSlice(allocators.global) catch
            return py.Err.outOfMemory();
        self.cache_miss_type = cache_miss_type.toOwnedSlice(allocators.global) catch
            return py.Err.outOfMemory();
    }

    pub fn deinit(self: *Vehicle) void {
        self.queue_dynamic.deinit(allocators.global);
        self.queue_compute.deinit(allocators.global);
        self.pending_task.deinit(allocators.global);
        allocators.free(self.cache_current);
        allocators.free(self.cache_hit_type);
        allocators.free(self.cache_miss_type);
    }

    pub fn setConnect(self: *Vehicle, edges: []Edge, coverage: f64) void {
        var near_edge: ?*Edge = null;
        var near_dist_sq: f64 = std.math.inf(f64);
        const coverage_sq: f64 = coverage * coverage;
        for (edges) |*edge| {
            const dist_sq: f64 = (self.location.x - edge.location.x) * (self.location.x - edge.location.x) +
                (self.location.y - edge.location.y) * (self.location.y - edge.location.y);
            if (dist_sq < near_dist_sq and dist_sq < coverage_sq) {
                near_edge = edge;
                near_dist_sq = dist_sq;
            }
        }
        if (std.math.isFinite(near_dist_sq)) {
            self.connect_edge = near_edge;
        } else {
            self.connect_edge = null;
        }
    }

    pub fn fillCache(self: *Vehicle, cache_limit: f64, cache_sizes: []const f64) !void {
        var cache_size_used: f64 = 0;
        const max_attempt: usize = cache_sizes.len * 2;
        var attempt: usize = 0;
        while (cache_size_used <= cache_limit * 0.8 and attempt < max_attempt) {
            const random_idx: usize = self.random.intRange(usize, 0, self.cache_current.len - 1);
            if (self.cache_current[random_idx] == 0) {
                cache_size_used += cache_sizes[random_idx];
                if (cache_size_used > cache_limit) {
                    break;
                }
                self.cache_current[random_idx] = 1;
            }
            attempt += 1;
        }
        try self.setCacheHitMissType();
    }

    pub fn getCacheType(self: *Vehicle, cache_hit_chance: f64) u32 {
        const trigger_hit: f64 = self.random.float();
        if (self.cache_hit_type.len == 0) {
            return self.random.pickSlice(u32, self.cache_miss_type);
        } else if (self.cache_miss_type.len == 0) {
            return self.random.pickSlice(u32, self.cache_hit_type);
        } else if (trigger_hit < cache_hit_chance) {
            return self.random.pickSlice(u32, self.cache_hit_type);
        } else {
            return self.random.pickSlice(u32, self.cache_miss_type);
        }
    }

    pub fn move(self: *Vehicle, clock_rate: f64) void {
        self.location = self.location.add(self.velocity.multiply(1 / clock_rate));
    }

    pub fn startTaskDynamic(self: *Vehicle, cur_clock: f64, task: *Task) !void {
        assert(self.task_dynamic != null or self.queue_dynamic.items.len == 0);
        // std.log.info("vehicle.startTaskDynamic: {}", .{task.tid});
        if (self.task_dynamic) |_| {
            if (self.queue_dynamic.items.len <= self.task_limit) {
                self.queue_dynamic.append(allocators.global, task) catch
                    return py.Err.outOfMemory();
            }
        } else {
            task.clock = cur_clock + task.data_size / self.data_rate;
            self.task_dynamic = task;
        }
    }

    pub fn endTaskDynamic(self: *Vehicle, cur_clock: f64) !void {
        if (self.task_dynamic) |task_transfer| {
            if (task_transfer.clock <= cur_clock) { // task finished
                // std.log.info("vehicle.endTaskDynamic: {}", .{task_transfer.tid});
                if (self.queue_dynamic.items.len > 0) {
                    var queue_task: *Task = self.queue_dynamic.orderedRemove(0);
                    queue_task.clock = cur_clock + queue_task.data_size / self.data_rate;
                    self.task_dynamic = queue_task;
                } else {
                    self.task_dynamic = null;
                }
                // start next step
                const near: *Edge = task_transfer.near;
                switch (task_transfer.choice) {
                    .local => {
                        py.Err.setString(py.PyExc_Exception, "local in endTaskDynamic");
                        return error.BanLocal;
                    },
                    .near => {
                        task_transfer.has_dynamic = true;
                        try near.startTaskCompute(cur_clock, task_transfer);
                    },
                    .far => {
                        try near.startTaskDynamic(cur_clock, task_transfer);
                    },
                    .unknown => {
                        py.Err.setString(py.PyExc_Exception, "unknown choice");
                        return error.UnknownChoice;
                    },
                }
            }
        }
    }

    pub fn startTaskCompute(self: *Vehicle, cur_clock: f64, task: *Task) !void {
        assert(self.task_compute != null or self.queue_compute.items.len == 0);
        if (task.has_dynamic and task.has_static) {
            // std.log.info("vehicle.startTaskCompute: {}", .{task.tid});
            if (self.task_compute) |_| {
                if (self.queue_compute.items.len <= self.task_limit) {
                    self.queue_compute.append(allocators.global, task) catch
                        return py.Err.outOfMemory();
                } else {
                    task.finish(false);
                }
            } else {
                // remove (if self.cache_current[task.cachetype] == 1)
                task.clock = cur_clock + task.complexity / self.compute_capacity;
                self.task_compute = task;
            }
        }
    }

    pub fn endTaskCompute(self: *Vehicle, cur_clock: f64) !?*Task {
        if (self.task_compute) |task_compute| { // task processing or finished
            if (task_compute.clock <= cur_clock) { // task finished
                // std.log.info("vehicle.endTaskCompute: {}", .{task_compute.tid});
                if (self.queue_compute.items.len > 0) { // queue has task
                    var queue_task: *Task = self.queue_compute.orderedRemove(0);
                    queue_task.clock = cur_clock + queue_task.complexity / self.compute_capacity;
                    self.task_compute = queue_task;
                } else {
                    self.task_compute = null;
                }
                const elapse_time: f64 = cur_clock - task_compute.request_clock;
                const success: bool = elapse_time <= task_compute.time_limit;
                task_compute.finish(success);
                return task_compute;
            } else {
                return null;
            }
        } else {
            return null;
        }
    }
};

pub const Task = struct {
    tid: i32,
    cachetype: u32,
    complexity: f64,
    data_size: f64,
    cache_size: f64,
    time_limit: f64,
    /// Weak reference.
    local: *Vehicle,
    /// Weak reference.
    near: *Edge,
    /// Weak reference.
    far: ?*Edge,
    /// Next leg due time when not in queue. Has no effect when in queue.
    clock: f64,
    request_clock: f64,
    choice: Choice,

    has_dynamic: bool,
    has_static: bool,
    status: TaskStatus,

    pub fn init(
        tid: i32,
        cachetype: u32,
        complexity: f64,
        data_size: f64,
        cache_size: f64,
        time_limit: f64,
        local: *Vehicle,
        near: *Edge,
        request_clock: f64,
    ) Task {
        return .{
            .tid = tid,
            .cachetype = cachetype,
            .complexity = complexity,
            .data_size = data_size,
            .cache_size = cache_size,
            .time_limit = time_limit,
            .local = local,
            .near = near,
            .far = null,
            .clock = request_clock,
            .request_clock = request_clock,
            .choice = .unknown,
            .has_dynamic = false,
            .has_static = false,
            .status = .pending,
        };
    }

    pub fn finish(self: *Task, success: bool) void {
        // std.log.info("vehicle.finish, task: {}", .{self.tid});
        self.status = if (success)
            .success
        else
            .fail;
        var pending_task: *ArrayList(*Task) = &self.local.pending_task;
        var remove_idx: i32 = -1;
        for (pending_task.items, 0..) |item, idx| {
            if (item.tid == self.tid) {
                remove_idx = @intCast(idx);
            }
        }
        if (remove_idx == -1) {
            @panic("remove_idx == -1");
        }
        assert(remove_idx >= 0);
        _ = pending_task.orderedRemove(@intCast(remove_idx));
    }
};

/// Immutable Vec2D object.
pub const Vec2D = struct {
    x: f64,
    y: f64,

    pub fn init(x: f64, y: f64) Vec2D {
        return .{
            .x = x,
            .y = y,
        };
    }

    pub fn add(self: Vec2D, other: Vec2D) Vec2D {
        return Vec2D.init(self.x + other.x, self.y + other.y);
    }

    pub fn multiply(self: Vec2D, scale: f64) Vec2D {
        return Vec2D.init(self.x * scale, self.y * scale);
    }
};

pub const Choice = enum(i32) {
    local = 0,
    near = 1,
    far = 2,
    unknown = 3,
};

pub const TaskStatus = enum(i32) {
    fail = 0,
    success = 1,
    pending = 2,
};

const ObjectList: [1]type = .{
    EnvironmentObject,
};

// globals
pub var module_def: py.PyModuleDef = .init("environment", null, &module_methods, freefunc);
pub var module_methods: [1]py.PyMethodDef = .{
    py.PyMethodDef.Sentinal,
};

fn freefunc(_: ?*anyopaque) callconv(.c) void {
    const stderr = std.io.getStdErr();
    allocators.deinit();
    // If this doesn't appear, this means some references has not properly
    // decremented.
    stderr.writeAll("info: end of environment module\n") catch {};
}

pub export fn PyInit_environment() callconv(.c) ?*py.c.PyObject {
    allocators.init() catch {
        py.Err.setString(py.PyExc_OSError, "allocators.dll not found");
        return null;
    };
    inline for (ObjectList) |Object| {
        Object.type_obj.ready() catch return null;
    }
    const module = module_def.create() catch return null;
    inline for (ObjectList) |Object| {
        const module_head = "environment.";
        const tp_name: [*:0]const u8 = Object.type_obj.tp_name orelse {
            py.Err.setString(py.PyExc_TypeError, "tp_name is None");
            return null;
        };
        const name: [*:0]const u8 = tp_name[module_head.len..];
        py.Module.AddObjectRef(module, name, Object.type_obj.toObject()) catch {
            py.DecRef(module);
            return null;
        };
    }
    return module.toC();
}

// imported python module and definition
var py_imports: PyImports = undefined;
pub const PyImports = struct {
    state_reward: *py.Object,
    StateOffloadObject: *py.Object,
    RewardOffloadObject: *py.Object,
    StateCacheObject: *py.Object,
    StateCacheMinorObject: *py.Object,
    RewardCacheObject: *py.Object,
    agents: *py.Object,
    typeshed: *py.Object,
    fn init() !PyImports {
        const state_reward: *py.Object = try py.import("state_reward");
        return .{
            .state_reward = state_reward,
            .StateOffloadObject = try py.getAttrString(state_reward, "StateOffload"),
            .RewardOffloadObject = try py.getAttrString(state_reward, "RewardOffload"),
            .StateCacheObject = try py.getAttrString(state_reward, "StateCache"),
            .StateCacheMinorObject = try py.getAttrString(state_reward, "StateCacheMinor"),
            .RewardCacheObject = try py.getAttrString(state_reward, "RewardCache"),
            .agents = try py.import("agents"),
            .typeshed = try py.import("typeshed"),
        };
    }
};

pub fn assert(ok: bool) void {
    if (!ok) {
        @panic("environment.zig assertion failure");
    }
}

const py = @import("py");
const std = @import("std");
const ArrayList = std.ArrayListUnmanaged;

const allocators = @import("allocators");
const Random = @import("randoms").Random;

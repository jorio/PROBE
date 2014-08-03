--- PROBE: Profile Rabidly Obnoxious Bottlenecks Effortlessly!
--
-- Simple profiler for use with LÖVE.
--
-- https://github.com/jorio/PROBE
--
-- Features:
--
-- * Realtime graphical visualization
--
-- * Timing averaged with a sliding window to reduce jitter in the
-- visualization
--
-- * The functions to be profiled don't need to be modified thanks to the
-- hook mechanism
--
-- * Profiler overhead factored out of the statistics as much as possible
--
-- @author Iliyas Jorio

local now

if love.timer.getMicroTime then
	print("warning: pre-0.9.0 LOVE timer")
	now = love.timer.getMicroTime
else
	now = love.timer.getTime
end

local ROOT_EVENT = '<ROOT>'

local PROBE = {}
PROBE.__index = PROBE

function PROBE.new(...)
	local prof = setmetatable({}, PROBE)
	PROBE.init(prof, ...)
	return prof
end

function PROBE:init(slidingWindowSize)
	self.eventNames = {}
	self.hooks = {}

	self.warmingUp = true
	self.window = {
		size = slidingWindowSize or 60,
		pos = 1,
	}
	self.avg = {
		events = {},
		delta = 0
	}

	self.events = {}
	self.stack = {}
	self.delta = 0

	self.cycleStarted = false
end

function PROBE:slideWindow()
	assert(not self.cycleStarted)

	-- slide window
	local out = self.window[self.window.pos]
	self.window[self.window.pos] = {
		events = self.events,
		delta = self.delta,
	}
	local ws = self.window.size
	self.warmingUp = #self.window < ws

	-- cancel out old values
	if out then
		self.avg.delta = self.avg.delta - out.delta/ws
		for k, event in pairs(out.events) do
			local avg = self.avg.events[k]
			avg.delta = avg.delta - event.delta/ws
			avg.count = avg.count - event.count/ws
		end
	end

	-- insert new values into the averages
	self.avg.delta = self.avg.delta + self.delta/ws
	for k, event in pairs(self.events) do
		local avg = self.avg.events[k]
		if not avg then
			avg = {delta=0, count=0}
			self.avg.events[k] = avg
		end
		avg.delta = avg.delta + event.delta/ws
		avg.count = avg.count + event.count/ws
	end

	-- values have been replaced, finish sliding window
	self.window.pos = 1 + (self.window.pos) % self.window.size

	self.events = {}
	self.stack = {}
	self.delta = 0
end

function PROBE:pauseTopEvent(time)
	assert(self.cycleStarted)
	local top = self.stack[#self.stack]
	local newDelta = time - top.start
	top.delta = top.delta + newDelta
	top.start = nil
	self.delta = self.delta + newDelta
end

-- Returns self.events[k] or creates it if needed.
-- For internal use only.
function PROBE:find(k)
	local event = self.events[k]
	if not event then
		event = {delta=0, count=0, start=now()}
		self.events[k] = event
	end
	return event
end

--- Starts a profiling cycle.
-- Must be called before pushing/popping any events.
-- You should typically call this at the start of each frame.
function PROBE:startCycle()
	assert(not self.cycleStarted, "current cycle not ended yet")
	assert(#self.stack == 0)
	self.cycleStarted = true
	self:pushEvent(ROOT_EVENT)
end

--- Ends a profiling cycle.
-- Must be called before retrieving statistics (e.g. draw()).
-- No events (except for the root event) must remain on the stack.
-- You should typically call this at the end of each frame.
function PROBE:endCycle()
	local time = now()
	assert(self.cycleStarted, "no cycle started yet")
	assert(#self.stack == 1,
		"all events (except root) must be finished before ending a cycle")
	assert(self.stack[1] == self.events[ROOT_EVENT])
	self:pauseTopEvent(time)
	self.cycleStarted = false
	self:slideWindow()
end

--- Pauses the current event and starts profiling a new event immediately.
-- If an event bearing the same key already exists, the profiler picks up the
-- existing run time for that event (i.e. resume profiling the event).
--
-- You must start a profiling cycle before calling this method.
-- @param k unique event key
function PROBE:pushEvent(k)
	local time = now()
	assert(self.cycleStarted, "start a cycle before profiling")
	if #self.stack > 0 then
		self:pauseTopEvent(time)
	end
	event = self:find(k)
	table.insert(self.stack, event)
	event.count = event.count + 1
	event.start = now()
end

--- Pauses the current event, pops it off the stack and resumes profiling the
-- event underneath.
function PROBE:popEvent()
	local time = now()
	assert(self.cycleStarted, "start a cycle before profiling")
	self:pauseTopEvent(time)
	self.stack[#self.stack] = nil
	assert(#self.stack >= 1, "event stack underflow - can't pop root")
	self.stack[#self.stack].start = now()
end

--- Draws a graphical representation of the current profile.
-- Can only be called outside of a cycle.
function PROBE:draw(x, y, w, h, title)
	assert(not self.cycleStarted,
		"can't render profile when a cycle is active")

	local fh = love.graphics.getFont():getHeight()

	love.graphics.rectangle('line', x, y, w, h)

	if self.warmingUp then
		love.graphics.print(title.."\nwarming up...", x, y-fh)
		return
	end

	local total = self.avg.delta

	love.graphics.print(
		string.format("%s: %.3f ms", title, 1000*total),
		x, y-fh)

	for k, event in pairs(self.avg.events) do
		local dh = h*event.delta / total
		love.graphics.line(x, y+dh, x+w, y+dh)
		name = self.eventNames[k] or tostring(k)
		text = string.format("%.0fx %s\n%.3f ms (%.1f %%)",
			event.count, name, 1000*event.delta, 100*event.delta/total)
		love.graphics.print(text, x+5, y+dh/2, 0, 1,
			math.min(1, dh/(2*fh)), 0, 2*fh/2)
		y = y+dh
	end
end

--- Turn function `t[fk]` into a profilable event.
-- @param t Table.
-- @param fk Key for the function in the table.
-- @param parentName Name of the table. Optional but recommended.
function PROBE:hook(t, fk, parentName)
	local qp = self
	local func = t[fk]

	local human = (parentName or '') .. '.' .. fk .. '()'

	assert(type(func) == 'function',
		human.." is not a function")

	local eventName = self.eventNames[func]
	if not eventName then
		self.eventNames[func] = human
	else
		self.eventNames[func] = (parentName or '') .. '/' .. eventName
	end

	t[fk] = function(...)
		qp:pushEvent(func)
		func(...)
		qp:popEvent()
	end

	if not self.hooks[t] then
		self.hooks[t] = {[fk] = func}
	else
		self.hooks[t][fk] = func
	end

	print("Hooked: " .. human)
end

--- Turns all functions `t[*][fk]` into profilable events (where `t[*]` means
-- all subtables of t).
--
-- If using `_G` as `t`, make sure you don't have file-local classes that
-- you would like to profile.
--
-- @param t Main table.
-- @param fk Function key. Look for functions bearing this key in `t`'s
-- subtables.
-- @param excludeTables Array of tables to exclude. Useful e.g. if you
-- like to set a shorthand alias for `love.graphics`, so that
-- `love.graphics.draw` doesn't get hooked.
--
-- @usage
-- -- hooks all functions named `'draw'` in subtables of `_G` except `_G.lg`
-- prof:hookAll(_G, 'draw', {lg})
function PROBE:hookAll(t, fk, excludeTables)
	-- turn excludeTables (which is an array) into a lookup table
	local excludeLookup = {}
	for _, v in ipairs(excludeTables or {}) do
		excludeLookup[v] = true
	end

	for k, subtable in pairs(t) do
		if type(subtable) == 'table'
			and not excludeLookup[subtable]
			and type(subtable[fk]) == 'function'
			and subtable[fk] ~= PROBE.draw
		then
			self:hook(subtable, fk, k)
		end
	end
end

--- Removes all hooks placed on functions in t.
function PROBE:unhook(t)
	for fk, func in pairs(self.hooks[t]) do
		t[fk] = self.hooks[t][fk]
		self.hooks[t][fk] = nil
		print("Unhooked: " .. fk .. ' from ' .. tostring(t))
	end
end

-- module
return PROBE


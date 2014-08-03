-- Demo program for PROBE.lua

PROBE = require 'PROBE'

-- Profiler for drawing operations (set up in love.load()) with a sliding
-- window size of 60 cycles. Too few cycles and the visualization will be too
-- jittery to be legible; too many cycles and the visualization will lag
-- behind. 60-ish cycles is a good compromise between smoothness and
-- responsiveness.
dProbe = PROBE.new(60)

-- profiler for update operations (set up in love.load())
uProbe = PROBE.new(60)

---------------------------------------------------------------------
-- A planet that moves around. Nothing fancy here, dProbe will hook onto
-- planet.draw() and uProbe will monitor planet.update(). This demonstrates you
-- can just drop in profilers without touching your entities' code.

planet = {
	x = 400,
	y = 300,
	r = 100,
}

-- monitored by uProbe
function planet:update(dt)
	local time = love.timer.getTime()
	self.x = self.x + math.cos(time) * dt * 100
	self.y = self.y + math.sin(time) * dt * 100
end

-- monitored by dProbe
function planet:draw()
	for i=1,10 do
		love.graphics.setColor(50, 10+i*10, 200+i, i*15)
		love.graphics.circle('fill', self.x, self.y, self.r-i*3)
	end
end

---------------------------------------------------------------------
-- A satellite group that moves along with the planet. This demonstrates that
-- you can set up fine-grained profiling events (see satgroup.draw()).

NSATS = 40
satgroup = {}

-- monitored by uProbe
function satgroup:update(dt)
	local time = 0
	for i=1, NSATS do
		local th = (i*2*math.pi/NSATS + 3*love.timer.getTime()) % (2*math.pi)
		self[i] = {
			above = th < math.pi/2 or th > 3*math.pi/2,
			x = planet.x + 100 * math.sin(th) * math.sin(math.pi*(i-1)/NSATS),
			y = planet.y-1.5*planet.r + 3*planet.r*(i-1)/NSATS,
			r = planet.r / 5
		}
	end
end

-- monitored by dProbe
function satgroup:draw(above)
	-- dProbe will profile satgroup.draw() as expected (as event 'satgroup',
	-- automatically created by PROBE.hookAll()) but we will create a custom
	-- event to measure how much time each individual satellite takes to
	-- render. This is not necessary, but it allows us to profile the loop
	-- overhead and the actual drawing code separately; plus, we get to see
	-- exactly how many times the custom event has been triggered.

	love.graphics.setBlendMode('additive')
	love.graphics.setColor(255, 255, 255, 80)
	for i=1, #self do
		if self[i].above == above then
			-- up until now, we're in the 'satgroup' event

			-- exit 'satgroup' and start counting runtime as 'unique sat' event
			dProbe:pushEvent("unique sat")
			love.graphics.circle('line', self[i].x, self[i].y, self[i].r)
			dProbe:popEvent() -- exit 'unique sat', back to 'satgroup'

			-- runtime counts towards the 'satgroup' event again
		end
	end
	love.graphics.setBlendMode('alpha')
end

---------------------------------------------------------------------
-- A fan that folds and unfolds hypnotically.
-- We go overboard with the custom profiling events in fan.draw().

fan = {
	x = 400,
	y = 300,
	count = 1,
}

-- monitored by uProbe
function fan:update(dt)
	self.count = math.abs(1-math.sin(love.timer.getTime())) * 50
end

-- monitored by dProbe
function fan:draw()
	-- start measuring runtime as event 'fan matrix transform'
	dProbe:pushEvent("fan matrix transform")
	love.graphics.push()
	love.graphics.translate(self.x, self.y)
	love.graphics.rotate(2 * math.pi * math.sin(love.timer.getTime()))
	for i=1, math.ceil(self.count) do
		dProbe:pushEvent("fan square")
		-- measure the two following lines as event 'fan square'
		love.graphics.setColor(0, 200-i, 2*i)
		love.graphics.rectangle('line', 0, 0, 128, 128)
		dProbe:popEvent() -- pop 'fan square', go back to 'fan matrix transform'
		-- the following counts as 'fan matrix transform' again
		love.graphics.translate(2, 2)
		love.graphics.rotate(2*math.pi/100)
		love.graphics.translate(-2, -2)
	end
	love.graphics.pop()
	dProbe:popEvent() -- pop 'fan matrix transform'
end

---------------------------------------------------------------------

blurb = {"Profile", "Rabidly", "Obnoxious", "Bottlenecks", "Effortlessly"}

function drawBlurb()
	love.graphics.push()
	love.graphics.translate(200, 500)
	for i=1, #blurb do
		local a = (-i*math.pi/9+love.timer.getTime()*2) % (2*math.pi)
		local p = (a%math.pi)/(math.pi/6)
		local r, s = 0, 1
		if p < 1 then
			s = 1 + 1-p
			r = (1-p)*p
			love.graphics.setColor(0, math.floor(250-p*100), 100)
		else
			love.graphics.setColor(0, 100, 100)
		end
		love.graphics.print(blurb[i]:sub(1,1), 0, -90*math.abs(math.sin(a)), 0, 5, 5)
		love.graphics.print(blurb[i], 0, 50, r, s)
		love.graphics.translate(80, 0)
	end
	love.graphics.pop()
end

---------------------------------------------------------------------

function love.load()
	-- Now that all our entity tables are defined, it's time to inject the
	-- profiling code.

	-- Place hooks onto all methods named 'draw' in all subtables of _G, except
	-- in _G.love. We don't want to place a hook onto love.draw(), because this
	-- is where the profiling cycle is defined!
	dProbe:hookAll(_G, 'draw', {love})
	dProbe:hook(_G, 'drawBlurb')

	-- Same deal to profile update operations.
	uProbe:hookAll(_G, 'update', {love})
end

function love.update(dt)
	-- Start a profiling cycle. This is MANDATORY before running any functions
	-- hooked to a profiler!!!
	uProbe:startCycle()

	if showPlanet then planet:update(dt) end
	if showSats then satgroup:update(dt) end
	if showFan then fan:update(dt) end

	-- End the profiling cycle.
	uProbe:endCycle()
end


showText   = true
showFan    = true
showPlanet = true
showSats   = true

function love.keypressed(k)
	if k == 't' then showText = not showText
	elseif k == 'f' then showFan = not showFan
	elseif k == 'p' then showPlanet = not showPlanet
	elseif k == 's' then showSats = not showSats
	end
end

function love.draw()
	-- Start profiling cycle.
	dProbe:startCycle()

	love.graphics.setColor(255, 255, 255)
	love.graphics.print("Hit T, F, P, S to toggle the Text, Fan, Planet or " ..
		"Satellites\n...and see how the profiler reacts", 200, 10)

	if showText   then drawBlurb() end
	if showFan    then fan:draw() end
	if showSats   then satgroup:draw(false) end
	if showPlanet then planet:draw() end
	if showSats   then satgroup:draw(true) end

	-- End profiling cycle BEFORE rendering the profilers!!!
	dProbe:endCycle()

	love.graphics.setColor(255, 255, 255)
	dProbe:draw(20, 20, 150, 560, "DRAW CYCLE")
	uProbe:draw(630, 20, 150, 560, "UPDATE CYCLE")

end


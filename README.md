# PROBE: a realtime graphical profiler for LÖVE

Is your LÖVE game running slow? Look no further, now you can profile rabidly
obnoxious bottlenecks effortlessly! Learn what's dragging your performance down
at a glance. Remember, though: premature optimization is the root of all evil!

Written for LÖVE 0.9.1; may also work with 0.8.0.

A demo is included (`main.lua`). It demonstrates simple and advanced uses of
the profiler. The profiler can be seen doing its thing on the sides of the
screenshot below.

![Demo screenshot](http://i.imgur.com/P33MYU0l.png)

## Barebones example

Reports how long it takes to draw 1,000 circles and 1,000 rectangles.

```lua
PROBE = require 'PROBE'
lg = love.graphics
circ = {draw = function() lg.circle('fill', 150, 150, 150) end}
rect = {draw = function() lg.rectangle('fill', 0, 300, 300, 300) end}

function love.load()
	prof = PROBE.new()
	-- Profile all functions named 'draw' in all subtables
	-- of _G except _G.love.draw, _G.lg.draw
	prof:hookAll(_G, 'draw', {love, lg})
	prof:enable(true)
end

function love.draw()
	prof:startCycle()
	for i=1,1000 do rect.draw() end
	for i=1,1000 do circ.draw() end
	prof:endCycle()
	prof:draw(500, 30, 150, 500, "DRAW CYCLE")
end
```

## Further help

You should really look at the demo code (`main.lua`) to see what you can do and
how you're supposed to do it. Fore more information, look at the comments in
`PROBE.lua`.

Don't hesitate to fork/report issues/request features!


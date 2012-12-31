--Event bus implementation that runs handlers asyncronously, replacing a stack of calls to publish with a queue of events to be ran.
local listeners={}
local function subscribe(obj,event)
	if not listeners[event] then
		listeners[event]={}
	end
	listeners[event][obj]=true
end

local function unsubscribe(obj,event)
	if listeners[event] then
		listeners[event][obj]=nil
	end
end

function run_event(event)
	if listeners[event] then
		local copy,n={},0
		for obj in pairs(listeners[event]) do
			table.insert(copy,obj)
			n=n+1
		end
		for i=1,n do
			copy[i]:handle(event)
		end
	end
end

local bus={}
function publish(event)
	table.insert(event,bus)
end

function run()
	while true do
		local event=table.remove(bus,1)
		if not event then break end
		run_event(event)
	end
end


----
bus={'start'}

newObj={handle=function(obj,event) print('I has event:'..tostring(event)) end}
subscribe(newObj,'start')
run()
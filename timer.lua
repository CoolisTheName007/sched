------------------------------------------------------------------------------
-- Timer module
--      supports one time timer timer.new(positive number)
--      supports periodic timer timer.new(negative number)
--      cron-compatible syntax (string conforming to cron syntax)
--      support simple timers
------------------------------------------------------------------------------

linked=require'utils.linked'
check=require'packages.checker'.check
local pprint=pprint
local print=print
PACKAGE_NAME='sched'

local sched=sched
local cells=sched.cells
local os = os
local math = math
local tonumber = tonumber
local assert = assert
local table = table
local pairs = pairs
local next = next
local type = type
local _G=_G
local os_time=os.clock
local setmetatable=setmetatable
local rawset=rawset
env=getfenv()
setmetatable(env,nil)

-------------------------------------------------------------------------------------
-- Common scheduling code
-------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------
-- These functions must be attached as method :nextevent() to timer objects,
-- and return the timer's next due date.
-------------------------------------------------------------------------------------
local function stimer_nextevent (timer) return nil end

local Cell
local events
local array
local n
-------------------------------------------------------------------------------------
-- Take a timer, reference it properly in `events` table
-------------------------------------------------------------------------------------
local Timer={}
Timer.add = function(nd)
	if not events[nd] then
		--insert nd in the right place
		local n = n+1
		for i = 1, n-1 do
			if array[i] > nd then n = i break end
		end
		table.insert(array, n, nd)
	end
end

-------------------------------------------------------------------------------------
-- Signal all elapsed timer events.
-- This must be called by the scheduler every time a due date elapses.
-------------------------------------------------------------------------------------
function Timer.step()
	if not array[1] then return end -- if no timer is set just return and prevent further processing
	local now = os_time()
	while array[1] and now >= array[1] do
		local nd = table.remove(array, 1)
		if events[nd] then
			Cell.step('timer',nd)
		end
	end
end


Timer.kill=function(timer)
	Cell.uniset('timer',timer.nd,timer)
end

--helper for cyclic timer
local function cycle_cell(obj)
	obj.nd=os_time()+obj.delta
	local t=obj.nd
	events[t]=events[t] or {}
	events[t][obj]=true
	obj.f(unpack(obj.args))
end
-------------------------------------------------------------------------------------
-- Cyclic (repetitive) timer
-- @return timer object.
-------------------------------------------------------------------------------------
function Timer.cycle(delta,f,...)
	check('number,function',delta,f)
	local timer={delta=delta,f=f,args={...},kill=kill}
	return timer
end

-------------------------------------------------------------------------------------
-- Simple timer API used by the scheduler;
-- returns the next expiration date
-------------------------------------------------------------------------------------
function Timer.nextevent()
	-- pprint(array)
	return array[1]
end


local meta={
	__newindex=function(t,k,v)
		-- print(t)
		assert(type(k)=='number','timer events must be numbers')
		if v~=nil then
			Timer.add(k)
		end
		rawset(t,k,v)
	end
}
---resets the timer module
Timer._reset=function()
	sched.cells.timer=setmetatable({[{}]='placeholder'},meta)
	events=sched.cells.timer
	Cell=sched.Cell
	array={}
	n=0
end

return Timer
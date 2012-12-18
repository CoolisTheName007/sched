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


local linked=require'utils.linked'

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


local Timer={}
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
local link,link_r
local n
-------------------------------------------------------------------------------------
-- Take a timer, reference it
-------------------------------------------------------------------------------------

Timer.add = function(t)
	if not link_r[t] then
		local ind
		for val in linked.next_r,link,val do
			if val>t then
				ind=val
				break
			end
		end
		link:insert_r(t,ind)
	end
end

-------------------------------------------------------------------------------------
-- Take a timer, dereference it
-------------------------------------------------------------------------------------
Timer.remove = function(t)
	link:remove(t)
end

-------------------------------------------------------------------------------------
-- Signal all elapsed timer events.
-- This must be called by the scheduler every time a due date elapses.
-------------------------------------------------------------------------------------
function Timer.step()
	if link_r[0]==-1 then return end -- if no timer is set just return and prevent further processing
	local now = os_time()
	while link_r[0]~=-1 and now >= link_r[0] do --about the aboce redundancy, maybe while loops are heavy?
		local nd = link:remove()
		local copy={}
		for obj,_ in pairs(events[nd]) do
			copy[obj]=true
		end
		events[nd]=nil
		for obj,_ in pairs(copy) do
			obj:handle('timer',nd)
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
	-- print(link)
	if link_r[0]~=-1 then return link_r[0] end
end

local revents
local meta={
	__newindex=function(t,k,v)
		assert(type(k)=='number','timer events must be numbers')
		if v==nil then
			Timer.remove(k)
		else
			revents[k]=v
			Timer.add(k)
		end
	end,
	__index=function(t,k)
		return revents[k]
	end,
	__next=function(t,val)
		return next(revents,val)
	end,
}
---resets the timer module
Timer._reset=function()
	events=setmetatable({[{}]='placeholder'},meta)
	sched.cells.timer=events
	revents={}
	
	Cell=sched.Cell
	link=linked()
	link_r=link.r
	Timer.link=link
end

return Timer
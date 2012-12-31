------------------------------------------------------------------------------
-- Timer module
--      supports one time timer timer.new(positive number)
--      supports periodic timer timer.new(negative number)
--      cron-compatible syntax (string conforming to cron syntax)
--      support simple timers
------------------------------------------------------------------------------

local linked=require'utils.linked'
local check=require'packages.checker'.check
local shcopy=require'utils.table'.shcopy
local pprint=pprint
local print=print
local error=error
local read=read
PACKAGE_NAME='sched'




local sched=sched
local fil
local Obj=sched.Obj
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
local unpack=unpack

env=getfenv()
setmetatable(env,nil)


local function norm(t) --the CC clock moves in steps of 0.05
	t=t-t%0.05
	-- if t<=0 then
		-- error('time values must be non-negative and multiples of 0.05',3)--to be used internally inside Timer functions
	-- end
	return t
end

local Timer={}
Timer.norm=norm
-------------------------------------------------------------------------------------
-- Common scheduling code
-------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------
-- These functions must be attached as method :nextevent() to timer objects,
-- and return the timer's next due date.
-------------------------------------------------------------------------------------
local function stimer_nextevent (timer) return nil end

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
		sched.signal('timer',nd)
	end
end

Timer.meta={__index=Timer}
setmetatable(Timer,{__index=Obj,__tostring=function() return 'Class Timer' end})

local get_o_name=function(a,b,...)
	if type(a)=='string' then
		return b,a
	else
		return a
	end
end

--helper for cyclic timer
local function cycle_handle(obj,_,ev)
	ev=ev+obj.delta
	obj:link{timer={ev}}
	obj.f(unpack(obj.args))
end
-------------------------------------------------------------------------------------
-- Cyclic (repetitive) timer
-- @return timer object.
-------------------------------------------------------------------------------------
function Timer.cycle(delta,...)
	delta=norm(delta)
	local f,name=get_o_name(...)
	check('number,function,?string',delta,f,name)
	local timer=Obj.new(cycle_handle,name)
	shcopy({delta=delta,f=f,args={...}},timer)
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

local meta={
	__newindex=function(t,k,v)
		if type(k)~='number' then
			error(tostring(k)..'timer events must be numbers',2)
		end
		-- k=k-k%0.05 --math.ceil(t/0.05)*0.05 --maybe round up for user comfort? this way it's 1.5 time faster
		-- if k<=0 then
			-- error(k..'time values must be positive',2) 
		-- end
		if v==nil then
			Timer.remove(k)
		else--could move it here...
			Timer.add(k)
		end
		rawset(t,k,v)
	end,
}
---resets the timer module
Timer._reset=function()
	events=setmetatable({[{}]='placeholder'},meta)
	sched.fil.timer=events
	link=linked()
	link_r=link.r
	Timer.link=link
end

return Timer
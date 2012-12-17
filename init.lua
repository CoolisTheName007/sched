local log=require'packages.log'
local pack	=require'utils.table'.pack
local tnil	=require'utils.table'.tnil
local check=require'packages.checker'.check
local sprint =require'utils.print'.sprint
local linked=require 'utils.linked'
local table=table
local pairs=pairs

PACKAGE_NAME='sched'



local timer
local os_time=os.clock

local Cell={}
local weak={__mode='kv'}
local weak_key={__mode='k'}
local cells={}
--[[
3D array of sets, cells[emitter][event][obj]=true
cells are functions, storable in the table @cells
wildcards for emitter, event are '*'; can only be used for listening
reserved values; do not use for custom signals:
	-emitters:
		'timer' 	-timer module;
		'platform'	-events yielded to the scheduler by os.pullEventRaw
]]

---sets the sets  described by @t, a table {[emitter]={ev1,ev2,...},...} (creating them if @val~=nil)
--@obj entries to @val
Cell.multiset = function (t,obj,val) 
	if val~=nil then
		for emitter,events in pairs(t) do
			local eml=cells[emitter]
			if not eml then
				eml={}
				cells[emitter]=eml
			end
			local event
			for i=1,#events do
				event=events[i]
				local evl=eml[event]
				if not evl then
					evl={}
					eml[event]=evl
				end
				evl[obj]=val
			end
		end
	else
		for emitter,events in pairs(t) do
			local eml=cells[emitter]
			if eml then
				local event
				for i=1,#events do
					event=events[i]
					local evl=eml[event]
					if evl then
						evl[obj]=nil
						if not next(evl) then eml[event]=nil end
					end
				end
				if not next(eml) then cells[emitter]=nil end
			end
		end
	end
	return true
end

---same, but accepts only the alternate description of emitter,event
Cell.uniset = function (emitter,event,obj,val)
	local eml=cells[emitter]
	if val~=nil then
		if not eml then
			eml={}
			cells[emitter]=eml
		end
		local evl=eml[event]
		if not evl then
			evl={}
			eml[event]=evl
		end
		evl[obj]=val
	else
		if eml then
			local evl=eml[event]
			if evl then
				evl[obj]=val
				if not next(evl) then eml[event]=nil end
			end
			if not next(eml) then cells[emitter]=nil end
		end
	end
end

---both functions in one, chosen by number of args
Cell.set = function(...)
	if select('#',...)==4 then
		Cell.uniset(...)
	else
		Cell.multiset(...)
	end
end


---emits a signal with emitter @emitter, event @event and parameters @vararg (...)
--can be called recursively; be careful not to signal the same entry which is being run
Cell.step = function (emitter,event,...) 
	log('sched', 'DEBUG', "SIGNAL %s.%s.%s", tostring(emitter), tostring(event),sprint(...))
	--pprint(cells['platform'] and next(cells['platform'].terminate),'asdfghj')
	local function walk_event(evl,emitter,event,...)
		local copy={}
		for obj,val in pairs(evl) do
			copy[obj]=val
		end
		for obj,val in pairs(copy) do
			obj:handle(emitter,event,...)
		end
	end
	
	local function walk_emitter(eml,emitter,event,...)
		local evl=eml[event]
		if evl then
			walk_event(evl,emitter,event,...)
		end
		evl=eml['*']
		if evl then
			walk_event(evl,emitter,event,...)
		end
	end
	
	local eml=cells[emitter]
	if eml then
		walk_emitter(eml,emitter,event,...)
	end
	local eml=cells['*']
	if eml then
		walk_emitter(eml,emitter,event,...)
	end
	
	return true
end

local Obj={}
---Abstract class that Task,Sync implement.
Obj.meta={__index=Obj}

Obj.new = function (handle)
	local obj=setmetatable({
		handle=handle,
		ts={},
		},Obj.meta)
	return obj
end

---helper
--supports emitter,ev1,ev2,...,timeout
--or {[emt1]={ev1,ev2,...},...},timeout
--timeout is optional and one use only
local function get_args(...)
	
	local nargs=select('#',...)
	local args={...}
	local t,timeout
	if type(args[nargs])=='number' then
			timeout=args[nargs]
			nargs=nargs-1
	end
	if nargs~=0 then
		if nargs==1 then
			t=...
		else
			t={[args[1]]={unpack(args,2,nargs)}}
		end
	end
	return t,timeout
end

local add_timer=function(t,nd)
	t=t or {}
	if nd then
		if not t.timer then
			t.timer={nd}
		else
			table.insert(t.timer,nd)
		end
	end
	return t
end


-- with methods link, unlink
Obj.link = function (obj,t)
	obj.ts[t]=true
	Cell.multiset(t,obj,true)
	return obj
end


Obj.unlink = function (obj,t)
	Cell.multiset(t,obj)
	obj.ts[t]=nil
	return obj
end

Obj.reset = function (obj)
	for t,_ in pairs(obj.ts) do
		Cell.multiset(t,obj)
	end
	obj.ts={}
	return obj
end



 --[[syncronous calls; are called as soon as the signal is received, but can't block
once are one-use,
on are permanent,
timeouts only fire once,
]]
local Sync={}
Sync.meta={__type='sync',__tostring=function(t) return 'sync:'..t.name end,__index=Obj}
setmetatable(Sync,{
	__tostring=function() return 'Class Sync' end,
	__index=Obj,
})

local sync_once_handle = function(sync,...)
	sync.f(...)
	sync:reset()
end

local get_o_name=function(a,b)
	if type(a)=='string' then
		return b,a
	else
		return a
	end
end

Sync.once = function (...)
	local f,name=get_o_name(...)
	check('function,?string',f,name)
	local sync=Obj.new(sync_once_handle)
	sync.f=f
	sync.name='once'..(name or tostring(sync):match(':.(.*)'))
	setmetatable(sync,Sync.meta)
	
	local t,timeout=get_args(select(name and 3 or 2,...))
	if timeout then t=add_timer(t,timeout+os_time()) end
	sync:link(t)
	
	log('sched', 'DETAIL', 'created Sync.once %s from %s with signal descriptor %s', tostring(sync), tostring(f),sprint(...))
	return sync
end

local sync_on_handle=function(obj,...)
	if obj.timeout then
		Cell.uniset('timer',obj.nd,obj)
		-- Timer.removetimer(obj.timer)
		obj.nd=os_time()+obj.timeout
		Cell.uniset('timeout',obj.nd,obj,true)
	end
	obj.f(...)
end

local sync_perm_kill=function(obj)
	obj:reset()
end

Sync.on = function (...)
	local f,name=get_o_name(...)
	check('function,?string',f,name)
	local sync=Obj.new(sync_on_handle)
	sync.f=f
	sync.name='on'..(name or tostring(sync):match(':.(.*)'))
	setmetatable(sync,Sync.meta)
	sync.kill=sync_perm_kill
	local t,timeout=get_args(select(name and 3 or 2,...))
	if timeout then
		sync.timeout=timeout
		sync.nd=os_time()+timeout
		t=add_timer(t,sync.nd)
	end
	sync:link(t)
	log('sched', 'DETAIL', 'created Sync.on %s from %s with signal descriptor %s', tostring(sync), tostring(f),sprint(...))
	return sync
end



--asyncronous calls through coroutines
Task={}
Task.meta={__index=Task,__type='task',__tostring=function(t) return 'task:'..t.name end}

setmetatable(Task,{
	__tostring=function() return 'Class Task' end,
	__index=Obj,
})

Task.running=nil
Task.ready=linked.new()
local KILL_TOKEN={}


Task.kill=Obj.reset

---Creates a task object in paused mode;
---fields set by Task.new are 
--status: 'paused'|'ready'|'dead'
--co: matching coroutine
--args: table of args to unpack and pass on first run; subsequently they are used to pass events internally
--created_by: parent task
--subs: sub tasks (see @{Task.setSub} and @{Task.setParent}
--name: name used for logging and result of tostring(task)
--Can take either (f,...) or (name,f,...) as args
--@param f function used to build a coroutine
--@param vararg initial args for calling @f
--@return task
Task.new = function (...)
	local f,name=get_o_name(...)
	print(name)
	check('function,?string',f,name)
	local task = Obj.new(Task.handle)
	setmetatable(task,Task.meta)
	task.name=name or tostring(task):match(':.(.*)')
	task.co=coroutine.create( f )
	task.status='paused'
	task.args={select(name and 3 or 2,...)}
	task.created_by=Task.running
	task.subs=setmetatable({}, weak_key)
	log('sched', 'INFO', 'Task.new created %s from %s with initial args %s by %s', tostring(task), tostring(f),args and sprint(unpack(args)) or '(no args)',tostring(Task.running or 'scheduler'))
	return task
end

---
function Task.handle(task,...)
	log('sched', 'DETAIL', 'Task.handle rescheduling %s to receive SIGNAL %s.%s.%s', tostring(task),...,select(2,...),sprint(select(3,...)))
	task.args={...}
	Task.ready:insert_r(task)
end


---Runs a task
--@return task
Task.run = function(task,...)
	check('task',task)
	log('sched', 'INFO', "Task.run scheduling %s", tostring(task))
	task.status='ready'
	Task.ready:insert_r(task)
    return task
end



--- Finishes a task and kills it's subs.
-- The killed task will emit a signal task,'die','killed',Task.running Can be 
-- invoked as task:kill().
-- @param task task to terminate (see @{Task.new})
-- @return  task
Task.kill = function ( task )
	check('task',task)
	log('sched', 'INFO', 'Task.kill killing %s from %s', tostring(task), tostring(Task.running or 'scheduler'))
	task.status='dead'
	task:reset()
	for sub, _ in pairs(task.subs) do --do not create an infinite sub loop!
		sub:kill()
	end
	if task==Task.running then
        coroutine.yield(KILL_TOKEN)
		error()
    else
        coroutine.resume (task.co, KILL_TOKEN)
    end
	Cell.step (task, "die", 'killed',Task.running)
	return task
end



--- Waits for a signal
-- @param vararg an entries descriptor for the signal (see @{get_args})
-- @return  emitter, event, parameters
Task.wait= function(...)
	local nd
	local task = (Task.running and Task.running.co==coroutine.running()) and Task.running or
        error ("Don't call Cell.step() while not running a task!")
	if ...==nil then
		log('sched', 'DETAIL', "Task.wait rescheduling %s for resuming ASAP", tostring(task))
		task.status='ready'
		Task.ready:insert_r(task)
	elseif ... then --only set new cells if necessary;
		log('sched', 'DETAIL', "%s waiting with args %s", tostring(task),sprint(...))
		local t,timeout=get_args(...)
		if timeout then nd=timeout+os_time() end
		task:link(add_timer(t,nd))
	else
		log('sched', 'DETAIL', "%s waiting for pre-set signals", tostring(task),sprint(...))
	end
	
	Task.running = nil
    local x = {coroutine.yield ()}
	if ... then
		task:reset()
		-- pprint(cells)
	end
	
	if x[1] == KILL_TOKEN then
		error()
	else
		return unpack(x)
	end
end


local Wait={} --some optimizations

Wait.loop = function (f,...)
	check('function',f)
	local t,timeout=get_args(...)
	local task=Task.running or error("Don't call Wait.loop outside a task!")
	local t=t or {}
	task.ts[t]=true
	Cell.multiset(t,task,true)
	if timeout then 
		local timer,out
		local tt={timer={}}
		task.ts[tt]=true
		local nd
		while true do
			log('Wait','DEBUG','in loop')
			tt.timer[1]=nd
			nd=os_time()+timeout
			Cell.uniset('timer',nd,task,true)
			out=f(sched.wait(false))
			Cell.uniset('timer',nd,task)
			if out then break end
		end
		log('Wait','DEBUG','out loop')
		task.ts[tt]=nil
	else
		while true do
			log('Wait','DEBUG','in loop')
			if f(sched.wait(false)) then break end
		end
		log('Wait','DEBUG','out loop')
	end
	Cell.multiset(t,task)
	task.ts[t]=false
end

---This function runs the coroutines of all tasks in Task.ready,
-- i.e. that received a signal/yielded
Task.step = function()
    local ptr = Task.ready
	Task.ready=linked.new()
    --------------------------------------------------------------------
    -- If there are no task currently running, resume scheduling by
    -- going through `Task.ready` until it's empty.
    --------------------------------------------------------------------
    while true do
		-- print(ptr)
		-- print(Task.ready)
		local task = ptr:remove() --pops first from left->right
		if not task then break end
		
		local co=task.co
		
		Task.running = task
        log('sched', 'DETAIL', "Resuming %s", tostring (task))
        local success, msg = coroutine.resume (co,unpack(task.args))
        task.args={}
		if not success then
            -- report the error msg
            log('sched', 'ERROR', "In %s:%s", tostring (task),tostring(msg))
        elseif msg==KILL_TOKEN then
			coroutine.resume(co)
		end
        ---------------------------------------------
        -- If the coroutine died, signal it for those
        -- who synchronize on its termination.
        ---------------------------------------------
        if coroutine.status (co) == "dead" then
			log('sched', 'INFO', "%s is dead", tostring (task))
			task.status = 'dead'
			task:reset()
			for sub, _ in pairs(task.subs) do --do not create an infinite sub loop!
				sub:kill()
			end
			Cell.step (task, "die", success, msg)
        end
    end

    Task.running = nil
end

--helper
local function get_sigrun_wrapper(f,...)
	local wrapper = function(...)
		while true do
			f(Task.wait(...))
		end
	end
	log('sched', 'INFO', 'sigrun wrapper %s created from %s', 
		tostring(wrapper), tostring(f))
	return wrapper
end

--- Create a task that listens for a signal.
-- @param f function to be called when the signal appears. The signal
-- is passed to f as parameter. The signal will be provided as 
-- _emitter, event, parameters_, just as the result of a @{wait}
-- @param vararg a Wait Descriptor for the signal (see @{get_args})
-- @return task in the scheduler
Task.new_sigrun_task = function (f,...)
	return Task.new( get_sigrun_wrapper(f,...) )
end

--helper
local function get_sigrunonce_wrapper(f,...)
	local wrapper = function(...)
		f(Task.wait(...))
	end
	return wrapper
end

--- Create a task that listens for a signal, once.
-- @param f function to be called when the signal appears. The signal
-- is passed to f as parameter. The signal will be provided as 
-- _emitter, event, parameters_, just as the result of a @{wait}
-- @param vararg a Wait Descriptor for the signal (see @{get_args})
-- @return task in the scheduler
Task.new_sigrunonce_task = function (f,...)
	return Task.new( get_sigrunonce_wrapper(f,...))
end

--- Create and run a task that listens for a signal.
-- @param f function to be called when the signal appears. The signal
-- is passed to f as parameter. The signal will be provided as 
-- _emitter, event, parameters_, just as the result of a @{wait}
-- @param vararg a Wait Descriptor for the signal (see @{get_args})
-- @return task in the scheduler
Task.sigrun = function(...)
	local task = Task.new_sigrun_task(...)
	return task:run()
end

--- Create and run a task that listens for a signal, once.
-- @param vararg a Wait Descriptor for the signal (see @{get_args})
-- @param f function to be called when the signal appears. The signal
-- is passed to f as parameter. The signal will be provided as 
-- _emitter, event, parameters_, just as the result of a @{wait}
-- @param attached if true, the new task will run in attached more
-- @return task in the scheduler (see @{taskd}).
Task.sigrunonce = function(...)
	local task = Task.new_sigrunonce_task(...)
	return task:run()
end


--- Attach a task/Sync object as a sub to another.
-- An attached task will be killed by the scheduler whenever
-- the parent task is finished (returns, errors or is killed). Can be 
-- invoked as task:setSub(sub).
-- @param task The parent task
-- @param sub The sub task.
-- @return the modified task.
Task.setSub = function (task, sub)
	task.subs[sub] = true
	log('sched', 'INFO', '%s is a sub of to %s', tostring(sub), tostring(task))
	return task
end

--- Set a task as attached to the creator task.
-- An attached task will be killed by the scheduler whenever
-- the parent task (the task that created it) is finished (returns, errors or is killed). 
-- Can be invoked as task:setParent().
-- @param task The sub task.
-- @return the modified task.
Task.setParent = function(task)
	if task.created_by then Task.setSub(task.created_by, task) end
	log('sched', 'INFO', '%s is a subtask of to %s', tostring(sub), tostring(task))
	return task
end

Task._reset=function()
	Task.ready=linked.new()
end




sched={
--modules and respective shortcuts
Cell=Cell,
cells=cells,
Obj=Obj,

Wait=Wait,

Sync=Sync,
once=Sync.once,
on=Sync.on,

Task=Task,
task=Task.new,
me=function() return Task.running end,
wait=Task.wait,
sigrun=Task.sigrun,
sigrunonce=Task.sigrunonce,

--others
signal=Cell.step,

emit=function(...)
	Cell.step(sched.me(),...)
end
}
local renv=setmetatable({sched=sched},{__index=_G})
local platform=require('platform',nil,nil,renv)
Timer=require('timer',nil,nil,renv)

sched.timer=Timer
sched.platform=platform

local loop_state = 'stopped' -- stopped, running or stopping

---Exits the scheduler after the current cycle is completed.
function sched.stop()
	log('sched','INFO','%s toggling loop_state=%s to stopping',tostring(Task.running or 'scheduler'),loop_state)
	if loop_state=='running' then loop_state = 'stopping' end
end

---resets internal vars
function sched.reset()
	tnil(cells)
	Timer._reset()
	Task._reset()
	platform._reset()
	loop_state = 'stopped'
	log('sched','INFO','scheduler cleaned.')
end

---Loops over the scheduler cycle,
--yielding to the caller coroutine for new events
--or returning to the caller function after sched.stop has been called
function sched.loop ()
	log('sched','INFO','Scheduler started')
    loop_state = 'running'
	local Task=Task
	local cells=cells
    local timer_nextevent, timer_step, Task_step, platform_step, os_time =
        Timer.nextevent, Timer.step, Task.step, platform.step, platform.time
		
    while true do
		
		--this block is a scheduler cycle
        timer_step() -- Emit timer signals
        Task_step() -- Run all the ready tasks

        -- Find out when the next timer event is due
        local timeout = nil
        do
            local date = timer_nextevent()
            if date then
                local now=os_time()
                timeout = date<now and 0 or date-now 
            end
        end
		if Task.ready.r[0] then
			timeout=0
		else
			if (not cells.platform) then
				log('sched','INFO','No-one ready to run or listening for signal emitter platform')
				sched.stop()
			end
		end
		if loop_state~='running' then sched.reset() break end
		-- if loop_state~='running' then break end
		platform_step (timeout) -- Wait for platform events until the next timer is due
    end
end
sched.reset()

return sched
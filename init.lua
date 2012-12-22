local log=require'packages.log'
local pack	=require'utils.table'.pack
local tnil	=require'utils.table'.tnil
local checker=require'packages.checker'
local check,conform=checker.check,checker.conform
local sprint =require'utils.print'.sprint
local linked=require 'utils.linked'
local table=table
local pairs=pairs

PACKAGE_NAME='sched'



local sched,Cell,Obj,Sync,Timer,Task,platform
local os_time


local weak={__mode='kv'}
local weak_key={__mode='k'}

local scheduler
local running

local fil
--[[
2D array of sets of objs, fil[emitter][event][obj]=true
wildcards for emitter, event are '*'; can only be used for listening
reserved values; do not use for custom signals:
	-emitters:
		'timer' 	-timer module;
		'platform'	-events yielded to the scheduler by os.pullEventRaw
]]

---sets the sets  described by @t, a table {[emitter]={ev1,ev2,...},...} (creating them if @val~=nil)
--@obj entries to @val
-- Cell.multiset = function (t,obj,val) 
	-- if val~=nil then
		-- for emitter,events in pairs(t) do
			-- local eml=fil[emitter]
			-- if not eml then
				-- eml={}
				-- fil[emitter]=eml
			-- end
			-- local event
			-- for i=1,#events do
				-- event=events[i]
				-- local evl=eml[event]
				-- if not evl then
					-- evl={}
					-- eml[event]=evl
				-- end
				-- evl[obj]=val
			-- end
		-- end
	-- else
		-- for emitter,events in pairs(t) do
			-- local eml=fil[emitter]
			-- if eml then
				-- local event
				-- for i=1,#events do
					-- event=events[i]
					-- local evl=eml[event]
					-- if evl then
						-- evl[obj]=nil
						-- if not next(evl) then eml[event]=nil end
					-- end
				-- end
				-- if not next(eml) then fil[emitter]=nil end
			-- end
		-- end
	-- end
	-- return true
-- end

-- ---same, but accepts only the alternate description of emitter,event
-- Cell.uniset = function (emitter,event,obj,val)
	-- local eml=fil[emitter]
	-- if val~=nil then
		-- if not eml then
			-- eml={}
			-- fil[emitter]=eml
		-- end
		-- local evl=eml[event]
		-- if not evl then
			-- evl={}
			-- eml[event]=evl
		-- end
		-- evl[obj]=val
	-- else
		-- if eml then
			-- local evl=eml[event]
			-- if evl then
				-- evl[obj]=val
				-- if not next(evl) then eml[event]=nil end
			-- end
			-- if not next(eml) then fil[emitter]=nil end
		-- end
	-- end
-- end

-- ---both functions in one, chosen by number of args
-- Cell.set = function(...)
	-- if select('#',...)==4 then
		-- Cell.uniset(...)
	-- else
		-- Cell.multiset(...)
	-- end
-- end

---emits a signal with emitter @emitter, event @event and parameters @vararg (...)
--can be called recursively; be careful not to signal the same entry which is being run
local signal = function (emitter,event,...) 
	log('sched', 'DEBUG', "SIGNAL %s.%s.[%s]", tostring(emitter), tostring(event),sprint(...))
	
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
	
	local eml=fil[emitter]
	if eml then
		walk_emitter(eml,emitter,event,...)
	end
	local eml=fil['*']
	if eml then
		walk_emitter(eml,emitter,event,...)
	end
	
	return true
end



Obj={}
---Abstract class that Task,Sync implement.
Obj.meta={__index=Obj,__tostring=function(t) return getmetatable(t).__type..':'..t.name end,__type='obj'}

Obj.new = function (handle,name)
	local obj={
		handle=handle,
		fil={},
		subs={},
		parent=running,
	}
	obj.parent.subs[obj]=true
	obj.name=(name or tostring(obj):match(':.(.*)'))
	setmetatable(obj,Obj.meta)
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

Obj.link = function (obj,t)
	local ofil=obj.fil
	local fil_tev,ofil_tev,fil_tobj
	for em,tev in pairs(t) do
		fil_tev=fil[em]
		ofil_tev=ofil[em]
		if not ofil_tev then
			ofil[em]={}
			ofil_tev=ofil[em]
			if not fil_tev then fil[em]={} fil_tev=fil[em] end
		end
		local ev
		for i=1,#tev do
			ev=tev[i]
			ofil_tev[ev]=true
			fil_tobj=fil_tev[ev]
			if not fil_tobj then fil_tev[ev]={} fil_tobj=fil_tev[ev] end
			fil_tobj[obj]=true
		end
	end
	-- tprint(fil,3)
	return obj
end

Obj.unlink = function (obj,t)
	local ofil=obj.fil
	local fil_tev,ofil_tev,fil_tobj
	for em,tev in pairs(t) do
		ofil_tev=ofil[em]
		if ofil_tev then
			fil_tev=fil[em]
			local ev
			for i=1,#tev do
				ev=tev[i]
				if ofil_tev[ev] then
					ofil_tev[ev]=nil
					
					fil_tobj=fil_tev[ev]
					fil_tobj[obj]=nil
					if not next(fil_tobj) then fil_tev[ev]=nil end
				end
			end
			if not next(ofil_tev) then ofil[em]=nil end
			if not next(fil_tev) then fil[em]=nil end
		end
	end
	return obj
end

Obj.reset = function (obj)
	local fil_tev
	for em,tev in pairs(obj.fil) do
		fil_tev=fil[em]
		for ev in pairs(tev) do
			-- print(ev,'|',obj,'|',fil_tev[ev],'|',fil_tev[ev][obj])
			fil_tev[ev][obj]=nil
			if not next(fil_tev[ev]) then fil_tev[ev]=nil end
		end
		if not next(fil_tev) then fil[em]=nil end
	end
	obj.fil={}
	return obj
end

Obj.finalize = function(obj)
	--handle subs
	local del
	for sub in next,obj.subs,del do
		if del then del:kill() end --may trigger actions
		del=sub
	end
	if del then del:kill() end
	
	obj.parent.subs[obj]=nil
	
	--remove filters
	obj:reset()
	return obj
end

Obj.kill = function(obj)
	signal(obj,'killedby',running)
	signal(obj,'dying',nil,'killed') --warns subs
	obj:finalize()
	signal(obj,'dead',nil,'killed')
	return obj
end

--Obj.setSub = function(obj,sub) dangerous

Obj.setParent=function(obj,parent)
	obj.parent.subs[obj]=nil
	parent=parent or scheduler
	obj.parent=parent
	parent.subs[obj]=true
	return obj
end

Obj.setTimeout=function(obj,timeout)
	obj.timeout=timeout
	obj.td={timer={timeout+os_time()}}
	obj:link(obj.td)
end

Obj.resetTimeout=function(obj)
	obj:unlink(obj.td)
	obj.td.timer[1]=os_time()+obj.timeout
	obj:link(obj.td)
end

Obj.cancelTimeout=function(obj)
	obj.timeout=nil
	obj:unlink(obj.td)
	obj.td=nil
end


 --[[syncronous calls; are called as soon as the signal is received, but can't block
once are one-use,
on are permanent,
timeouts only fire once,
]]
Sync = setmetatable({},{
	__tostring=function() return 'Class Sync' end,
	__index=Obj,
})
Sync.meta={__index=Sync,__tostring=Obj.meta.__tostring,__type='sync'}

local sync_once_handle = function(sync,...)
	running=obj
	sync.f(...)
	running=scheduler
	sync:reset()
end

local get_o_name=function(a,b,...)
	if type(a)=='string' then
		return b,a
	else
		return a
	end
end

Sync.once = function (...)
	local f,name=get_o_name(...)
	check('function,?string',f,name)
	local sync=Obj.new(sync_once_handle,name)
	sync.f=f
	setmetatable(sync,Sync.meta)

	local t,timeout=get_args(select(name and 3 or 2,...))
	if timeout then t=add_timer(t,timeout+os_time()) end
	if t then sync:link(t) end
	
	log('sched', 'DETAIL', 'created Sync.once %s from %s with signal descriptor %s', tostring(sync), tostring(f),sprint(...))
	return sync
end

local sync_on_handle=function(obj,...)
	running=obj
	if obj.timeout then
		obj.f(...)
		obj:resetTimeout()
	else
		obj.f(...)
	end
	running=scheduler
end

Sync.on = function (...)
	local f,name=get_o_name(...)
	check('function,?string',f,name)
	local sync=Obj.new(sync_on_handle,name)
	sync.f=f
	setmetatable(sync,Sync.meta)
	sync.kill=sync_perm_kill
	local t,timeout=get_args(select(name and 3 or 2,...))
	if timeout then
		sync:setTimeout(timeout)
	end
	if t then sync:link(t) end
	log('sched', 'DETAIL', 'created Sync.on %s from %s with signal descriptor %s', tostring(sync), tostring(f),sprint(...))
	return sync
end

--asyncronous calls through coroutines
Task={}
setmetatable(Task,{
	__tostring=function() return 'Class Task' end,
	__index=Obj,
})
Task.meta={__index=Task,__tostring=Obj.meta.__tostring,__type='task'}

---Creates a task object in paused mode;
---fields set by Task.new are
--co: matching coroutine
--args: table of args to unpack and pass on first run; subsequently they are used to pass events internally
--parent: parent task
--subs: sub tasks (see @{Task.setSub} and @{Task.setParent}
--name: name used for logging and result of tostring(task)
--Can take either (f,...) or (name,f,...) as args
--@param f function used to build a coroutine
--@param vararg initial args for calling @f
--@return task
Task.new = function (...)
	local f,name=get_o_name(...)
	check('function,?string',f,name)
	
	local task = Obj.new(Task.handle,name)
	setmetatable(task,Task.meta)
	
	task.co=coroutine.create( f )
	task.args={select(name and 3 or 2,...)}
	
	log('sched', 'INFO', 'Task.new created %s from %s with initial args %s by %s', tostring(task), tostring(f),args and sprint(unpack(args)) or '(no args)',tostring(running))
	return task
end

---
function Task.handle(task,...)
	check('task',task)
	
	task.args={...}
	Task.ready:insert_r(task)
	
	log('sched', 'DETAIL', 'Task.handle rescheduling %s to receive SIGNAL %s.%s.%s',
	tostring(task),tostring(...),tostring(select(2,...)),sprint(select(3,...)))
	return task
end


---Runs a task
--@return task
Task.run = function(task,...)
	check('task',task)
	Task.ready:insert_r(task)
    log('sched', 'INFO', "Task.run scheduling %s", tostring(task))
	return task
end



--- Finishes a task and kills it's subs.
-- The killed task will emit a signal task,'die','killed',running Can be 
-- invoked as task:kill().
-- @param task task to terminate (see @{Task.new})
-- @return  task
Task.kill = function (task)
	check('task',task)
	if task.status~='dead' then
		log('sched', 'INFO', "Task.kill killing %s from %s", tostring(task),tostring(running))
		signal(task,'killedby',running)
		signal(task,'dying')
		task:finalize()
		Task.ready:remove(task)
		task.status='dead'
		signal(task,'dead')
		if Task.running and Task.running.status=='dead' and Task.running.co==coroutine.running() then
			coroutine.yield()
		end
	end
	return task
end



--- Waits for a signal
-- @param vararg an entries descriptor for the signal (see @{get_args})
-- @return  emitter, event, parameters
Task.wait= function(...)
	local nd
	local task = running
	if task.co~=coroutine.running() then error('calling Task.wait outside a task',2) end
	if ...==nil then
		log('sched', 'DETAIL', "Task.wait rescheduling %s for resuming ASAP", tostring(task))
		Task.ready:insert_r(task)
	elseif ... then
		log('sched', 'DETAIL', "%s waiting with args %s", tostring(task),sprint(...))
		local t,timeout=get_args(...)
		t=timeout and add_timer(t,os_time()+timeout) or t
		task:link(t)
	else
		log('sched', 'DETAIL', "%s waiting for pre-set signals", tostring(task),sprint(...))
	end
	
    coroutine.yield ()
	if ... then
		task:reset()
	end
	return unpack(task.args)
end


local Wait={} --some optimizations

Wait.loop = function (f,...)
	check('function',f)
	local t,timeout=get_args(...)
	check('task',running)
	local task=running
	local t=t or {}
	task:link(t)
	if timeout then 
		local nd=os_time()+timeout
		while true do
			log('Wait','DEBUG','in loop')
			nd=os_time()+timeout
			task:link{timer={nd}}
			out=f(sched.wait(false))
			task:unlink{timer={nd}}
			if out then break end
		end
		log('Wait','DEBUG','out loop')
	else
		while true do
			log('Wait','DEBUG','in loop')
			if f(sched.wait(false)) then break end
		end
		log('Wait','DEBUG','out loop')
	end
	task:unlink(t)
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
		
        log('sched', 'DETAIL', "Resuming %s", tostring (task))
		running = task
		Task.running=task
        local success, msg,target = coroutine.resume (co)
		Task.running=nil
		running = scheduler
        task.args={}
		if not success then
            -- report the error msg
            log('sched', 'ERROR', "In %s:%s", tostring (task),tostring(msg))
			signal(task, "error",success, msg)
			--preserve events/subs for error catchers to analize, and then finalize
			task:finalize()
		elseif coroutine.status (co) == "dead" then --If the coroutine died, signal it for those who synchronize on its termination.
			log('sched', 'INFO', "%s is dead", tostring (task))
			signal(task, "dying", success, msg)
			task:finalize() --kills subs and cleans up filters 
			Task.ready:remove(task)
			signal(task, "dead", success, msg)
		end
    end
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

Task._reset=function()
	Task.running=nil
	Task.ready=linked.new()
end




sched={
--modules and respective shortcuts
-- fil=fil,
signal=signal,
Obj=Obj,

Wait=Wait,

Sync=Sync,
once=Sync.once,
on=Sync.on,

Task=Task,
task=Task.new,
me=function() return running end,
wait=Task.wait,
sigrun=Task.sigrun,
sigrunonce=Task.sigrunonce,
--others
emit=function(...)
	sched.signal(sched.me(),...)
end
}
local renv=setmetatable({sched=sched},{__index=_G})

platform=require('platform',nil,nil,renv)
os_time=platform.time

Timer=require('timer',nil,nil,renv)

sched.Timer=Timer
sched.platform=platform

local loop_state = 'stopped' -- stopped, running or stopping

---Exits the scheduler after the current cycle is completed.
function sched.stop()
	log('sched','INFO','%s toggling loop_state=%s to stopping',tostring(Task.running or 'scheduler'),loop_state)
	if loop_state=='running' then loop_state = 'stopping' end
end

---resets internal vars
function sched.reset()
	if scheduler then
		scheduler:kill()
	end
	
	fil={}
	sched.fil=fil
	
	scheduler=setmetatable(
	{
	subs={},
	name='scheduler',
	kill=function(obj)
		log('sched', 'INFO', "killing %s from %s", tostring(obj),tostring(running))
		signal(obj,'killedby',running)
		signal(obj,'dying',nil,'killed') --warns subs
		local del
		for sub in next,obj.subs,del do
			if del then del:kill() end --may trigger actions
			del=sub
		end
		if del then del:kill() end
		obj.subs={}
		obj.status='dead'
		signal(obj,'dead',nil,'killed')
		if Task.running and Task.running.status=='dead' and Task.running.co==coroutine.running() then
			coroutine.yield()
		end
		return obj
	end
	},{
	__tostring=function(t) return t.name end,
	})
	
	sched.scheduler=scheduler
	running=scheduler
	
	Timer._reset()
	Task._reset()
	
	platform._reset() --after Timer
	
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
    local Timer_nextevent, Timer_step, Task_step, platform_step =
        Timer.nextevent, Timer.step, Task.step, platform.step
		
    while true do --this block is the scheduler step
        Timer_step() -- Emit timer signals
        Task_step() -- Run all the ready tasks
		-- tprint(sched.fil,3)
		-- read()
        -- Find out when the next timer event is due
        local timeout = nil
		
		local date = Timer_nextevent()
		if date then
			local now=os_time()
			timeout = date<now and 0 or date-now 
		end
		-- tprint(sched.fil,2)
		if loop_state~='running' or not next(scheduler.subs) then sched.reset() break end
		-- if loop_state~='running' then break end
		platform_step (timeout,date) -- Wait for platform events until the next timer is due
    end
end
sched.reset()
return sched
local log=require'packages.log'
local pack	=require'utils.table'.pack
local tnil	=require'utils.table'.tnil
local checker=require'packages.checker'
local check,conform=checker.check,checker.conform
local mtostring =require'utils.print'.mtostring
local tprint=tprint
local linked=require 'utils.linked'
local table=table
local pairs=pairs

PACKAGE_NAME='sched'



local sched,Cell,Obj,Sync,Timer,Task,platform
local os_time

local weak={__mode='kv'}
local weak_key={__mode='k'}

local scheduler

local fil
--[[
2D array of sets of objs, fil[emitter][event][obj]=true
wildcards for emitter, event are '*'; can only be used for listening
reserved values; do not use for custom signals:
	-emitters:
		'timer' 	-timer module;
		'platform'	-events yielded to the scheduler by os.pullEventRaw
]]


---emits a signal with emitter @emitter, event @event and parameters @vararg (...)
--can be called recursively; be careful not to signal the same entry which is being run
--to use infinite loops of signals (e.g. A->B->A) blocking the scheduler, use @Task or @Call instances.
local signal = function (emitter,event,...)
	log('sched', 'DEBUG', "SIGNAL %s.%s.[%s]", tostring(emitter), tostring(event),mtostring(...))
	local function walk_event(evl,emitter,event,...)
		local copy={}
		for obj,val in pairs(evl) do
			copy[obj]=val
		end
		for obj,val in pairs(copy) do
			-- if d then print(obj) end
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

---Class that Task,Sync implement and that describes what can be put into the waiting table @fil.
--Objs instances keep track of which signals call their @handle field in their @fil field;
--their @parent and @subs fields maintain a tree-like hierarchy used to kill @subs from an object before killing the object itself.
--Objs expect to have defined a handle field consisting of a function used to process signals received, syncronously:
--@handle is a function called with args (obj,emitter,event,...) everytime a signal (emitter,event,...) that obj is linked too is emitted.
local Obj=setmetatable({},
{__tostring=function() return 'Class Obj' end}
)
--instance methods
local O={}

local O_meta={
__index=O,
__tostring=function(t) return getmetatable(t).__type..':'..t.name end,
__type='obj'
}

---@return self a Obj instance

--@name is an optional parameter to set a debugging name
Obj.new = function (name)
	local self=setmetatable({
		fil={},
		subs={},
		parent=sched.running,
	},O_meta)
	self.name=(name or tostring(self.fil):match(':.(.*)'))
	sched.running.subs[self]=true
	return self
end

function Obj.step()
    local ptr = Obj.ready
	Obj.ready=linked.new()
    --------------------------------------------------------------------
    -- going through `Obj.ready` until it's empty.
    --------------------------------------------------------------------
    while true do
	
		local obj = ptr:remove() --pops first from left->right
		if obj==nil then break end
		
		obj:resume()
    end
end

Obj._reset=function()
	Obj.ready=linked.new()
end

---Takes a link descriptor and tranforms them into a a proper link table for Obj methods to consume
--supports emitter,ev1,ev2,...,timeout
--or {[emt1]={ev1,ev2,...},...},timeout
local function get_args(...)
	local args={...}
	local nargs=#args
	local t,timeout
	if type(args[nargs])=='number' then
		timeout=args[nargs]
		nargs=nargs-1
	end
	if nargs~=0 then
		if nargs==1 then
			t=args[1]
		else
			t={[args[1]]={unpack(args,2,nargs)}}
		end
	end
	return t,timeout
end

--helper
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

---Registers @obj in the waiting table @fil in the waiting sets described by the link table @t
function O:link(t)
	local ofil=self.fil
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
			fil_tobj[self]=true
		end
	end
	return self
end

---Unregisters @obj in the waiting table @fil from the waiting sets described by the link table @t
function O:unlink(t)
	local ofil=self.fil
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
					fil_tobj[self]=nil
					if not next(fil_tobj) then fil_tev[ev]=nil end
				end
			end
			if not next(ofil_tev) then ofil[em]=nil end
			if not next(fil_tev) then fil[em]=nil end
		end
	end
	return self
end

---Unregisters @obj from all the waiting sets it is linked to.
function O:reset()
	local fil_tev
	for em,tev in pairs(self.fil) do
		fil_tev=fil[em]
		for ev in pairs(tev) do
			-- print(ev,'|',self,'|',fil_tev[ev],'|',fil_tev[ev][self])
			fil_tev[ev][self]=nil
			if not next(fil_tev[ev]) then fil_tev[ev]=nil end
		end
		if not next(fil_tev) then fil[em]=nil end
	end
	self.fil={}
	return self
end

local ending={n=0}

--helper
---Kills @obj 's subs and removes it from the waiting sets.
function O:finalize()
	if ending[self] then
		error('Detected recursion in Obj.finalize: ending stack='..stringify(ending,nil,nil,nil,nil,1),2)
	else
		ending.n=ending.n+1
		ending[self]=ending.n
	end
	--handle subs
	while next(self.subs) do
		next(self.subs):kill()
	end
	
	self.parent.subs[self]=nil
	
	--remove self from the waiting sets
	self:reset()
	
	--remove self from the action queue
	Obj.ready:remove(self)
	
	ending[self]=nil
	ending.n=ending.n-1
	return self
end

---same as @O:finalize, but throws some useful warning events.
function O:kill()
	signal(self,'dying') --warns subs
	self:finalize()
	signal(self,'dead')
	return self
end

---Changes  an @obj parent field. When called with @parent==nil, defaults to the top object, @scheduler
function O:setParent(parent)
	if parent==self then error("A scheduler object cannot be it's own parent",2) end
	self.parent.subs[self]=nil
	parent=parent or scheduler
	self.parent=parent
	parent.subs[self]=true
	return self
end

local TIMEOUT_TOKEN={}
---helpers for linking @obj to timer signals
function O:setTimeout(timeout)
	if type(timeout)~='number' then
		error('timeout must be number',2)
	else
		timeout=Timer.norm(timeout)
	end
	self:cancelTimeout()
	self[TIMEOUT_TOKEN]={
	timeout=timeout,
	td={timer={timeout+os_time()}},
	}
	self:link(self[TIMEOUT_TOKEN].td)
	return self
end

---cancels the current timeout and sets a new one in @timeout seconds, where @timeout was set by @O:setTimeout 
function O:resetTimeout()
	local td=self[TIMEOUT_TOKEN]
	if td then
		self:unlink(td.td)
		td.td.timer[1]=os_time()+td.timeout
		self:link(self.td.td)
	end
	return self
end

---cancels the current timeout
function O:cancelTimeout()
	local td=self[TIMEOUT_TOKEN]
	if td then
		self:unlink(td.td)
		self.td=nil
	end
	return self
end

--helper
local get_o_name=function(a,b,...)
	if type(a)=='string' then
		return b,a
	else
		return a
	end
end

--helper for efficiently inheriting classes
local copy=function(t)
	local c={}
	for i,v in pairs(t) do
		c[i]=v
	end
	return c
end

---Implements callbacks that are run asyncronously.
--Useful for when coroutines ( @Task) are an overkill
-- and syncronously running functions (either using @Obj or @Sync) leads to infinite loops and dragons (e.g. A signals B that signals A that signals...)
local Call = setmetatable({},{
	__tostring=function() return 'Class Sync' end,
})



local C=copy(O)
local C_meta={
__index=C,
__tostring=O_meta.__tostring,
__type='call'
}

---Takes either (function) or (name,function)
Call.new=function(...)
	local f,name=get_o_name(...)
	check('function,?string',f,name)
	local self=Obj.new(name)
	setmetatable(self,C_meta)
	self.f=f
	return self
end
---Schedules the @call for execution with arguments (...)
--Won't pass nil arguments, e.g. (1,nil,3) is the same as (1)
function C:handle(...)
	self.args={...}
	Obj.ready:insert_r(self)
	sched.ready=true
	return self
end

function C:resume()
	local running=sched.running
	sched.running= self
	self.f(unpack(self.args))
	sched.running = running
end


 --[[syncronous calls; are called as soon as the signal is received, but can't block as tasks do
once are one-use,
on are permanent,
Constructors Sync.once and Sync.on take both either (function,...) or (name,function,...) where ... is a wait descriptor (see @get_args).
]]
local Sync = setmetatable({},{
	__tostring=function() return 'Class Sync' end,
})
local S=copy(O)
local S_meta={
__index=S,
__tostring=O_meta.__tostring,
__type='sync'
}

local sync_once_handle = function(sync,...)
	local running=sched.running
	sched.running= sync
	sync.f(...)
	sync:kill()
	self.f(unpack(self.args))
	sched.running = running
end

Sync.once = function (...)
	local f,name=get_o_name(...)
	check('function,?string',f,name)
	local sync=Obj.new(name)
	sync.handle=sync_once_handle
	sync.f=f
	setmetatable(sync,S_meta)

	local t,timeout=get_args(select(name and 3 or 2,...))
	if timeout then t=add_timer(t,timeout+os_time()) end
	if t then sync:link(t) end
	
	log('sched', 'DETAIL', 'created Sync.once %s from %s with signal descriptor %s', tostring(sync), tostring(f),mtostring(...))
	return sync
end

local sync_on_handle=function(obj,...)
	local running=sched.running
	sched.running= obj
	if obj.timeout then
		obj.f(...)
		obj:resetTimeout()
	else
		obj.f(...)
	end
	sched.running=running
end

Sync.on = function (...)
	local f,name=get_o_name(...)
	check('function,?string',f,name)
	local sync=Obj.new(name)
	sync.handle=sync_on_handle
	sync.f=f
	setmetatable(sync,S_meta)
	sync.kill=sync_perm_kill
	local t,timeout=get_args(select(name and 3 or 2,...))
	if timeout then
		sync:setTimeout(timeout)
	end
	if t then sync:link(t) end
	log('sched', 'DETAIL', 'created Sync.on %s from %s with signal descriptor %s', tostring(sync), tostring(f),mtostring(...))
	return sync
end

--asyncronous calls through coroutines
--static methods
Task=setmetatable({},{
	__tostring=function() return 'Class Task' end,
})
--instance methods
local T=copy(O)
local T_meta={
__index=T,
__tostring=O_meta.__tostring,
__type='task',
}

---Creates a task object in paused mode;
---fields set by Task.new are
--co: matching coroutine
--args: table of args to unpack and pass to co
--parent: parent task
--subs: sub tasks (see @{Task.setSub} and @{Task.setParent}
--name: name used for logging and result of tostring(task)
--Can take either (f) or (name,f) as args
--@return task
Task.new = function (...)
	local f,name=get_o_name(...)
	check('function,?string',f,name)
	
	local task = Obj.new(name)
	setmetatable(task,T_meta)
	
	task.co=coroutine.create( f )
	task.args={}
	log('sched', 'INFO', 'Task.new created %s from %s with initial args %s by %s', tostring(task), tostring(f),args and mtostring(unpack(args)) or '(no args)',tostring(sched.running))
	return task
end

---Schedules a task for execution with args (...)
--If T:handle is called several times before resuming the task, task.args will be overwritten and the last args set will be the last ones. 
function T:handle(...)
	self.args={...} --no point in catching args after nil, since self.args is unpacked before returning to the task.
	Obj.ready:insert_r(self)
	sched.ready=true
	
	log('sched', 'DETAIL', 'Task:handle rescheduling %s to receive SIGNAL %s.%s.%s',
	tostring(self),tostring(...),tostring(select(2,...)),mtostring(select(3,...)))
	return self
end


---Runs a task with initial args ...
--@param vararg optional arguments to start the task with
--@return task
function T:run(...)
	check('task',self)
	self.args={...}
	Obj.ready:insert_r(self)
    log('sched', 'INFO', "Task.run scheduling %s", tostring(self))
	return self
end

--- Finishes a task and kills it's subs.
-- @param task task to terminate (see @{Task.new})
-- @return  task
function T:kill()
	check('task',self)
	if self.status~='dead' then
		log('sched', 'INFO', "Task.kill killing %s from %s", tostring(self),tostring(sched.running))
		signal(self,'dying')
		self:finalize()
		self.status='dead'
		signal(self,'dead')
		if Task.running and Task.running.status=='dead' and Task.running.co==coroutine.running() then
			coroutine.yield()
		end
	end
	return self
end

function T:resume()
	sched.running = self
	
	local co=self.co
	Task.running=self
	
	log('sched', 'DETAIL', "Resuming %s", tostring (obj))
	local success, msg = coroutine.resume (co,unpack(self.args))
	Task.running=nil
	self.args={}
	sched.running = scheduler
	if not success then
		-- report the error msg
		log('sched', 'ERROR', "In %s:%s", tostring (self),tostring(msg))
		signal(self, "error",success, msg)
		--preserve events/subs for error catchers to analize, and then finalize
		self:finalize()
	elseif coroutine.status (co) == "dead" then --If the coroutine died, signal it for those who synchronize on its termination.
		log('sched', 'INFO', "%s is dead", tostring (task))
		signal(Obj, "dying", success, msg)
		self:finalize() --kills subs and cleans up filters, and takes out of the Obj.ready listxz
		signal(self, "dead", success, msg)
	end
end



--- Waits for a signal
--Can only be called from a task
--If called with no arguments, yields and reschedules for execution
--If called with false as argument, yields without rescheduling for execution
-- @param vararg an entries descriptor for the signal (see @{get_args})
-- @return  emitter, event, parameters
function Task.wait(...)
	local nd
	local task = sched.running
	if task.co~=coroutine.running() then error('calling Task.wait outside a task/inside a task but inside another coroutine',2) end
	if ...==nil then
		log('sched', 'DETAIL', "Task.wait rescheduling %s for resuming ASAP", tostring(task))
		Obj.ready:insert_r(task)
	elseif ... then
		log('sched', 'DETAIL', "%s waiting with args %s", tostring(task),mtostring(...))
		local t,timeout=get_args(...)
		t=timeout and add_timer(t,os_time()+timeout) or t
		task:link(t)
	else
		log('sched', 'DETAIL', "%s waiting for pre-set signals", tostring(task),mtostring(...))
	end
	
    coroutine.yield ()
	if ... then
		task:reset()
	end
	return unpack(task.args)
end




---resets the Task class vars
function Task._reset()
	Task.running=nil
end

local Wait={} --some optimizations

---Blocks execution until a signal described by (...) is received; then calls f with the signal as argument (e.g. f(emitter,event,...))
--If f returns true, breaks the loop.
Wait.loop = function (f,...)
	check('function',f)
	local t,timeout=get_args(...)
	check('task',sched.running)
	local task=sched.running
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


---Some pre-built utilities for tasks

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
-- emitter, event, parameters, just as the result of a @{wait}
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


sched={
--modules and respective shortcuts
signal=signal,
emit=function(...)
	sched.signal(sched.me(),...)
end,
Obj=Obj,
ready=false,
me=function() return sched.running end,


Task=Task,
Sync=Sync,
Call=Call,
Wait=Wait,

sigonce=Sync.once,
sighook=Sync.on,

task=Task.new,
wait=Task.wait,
sigrun=Task.sigrun,
sigrunonce=Task.sigrunonce,
call=Call.new

--others
}

sched.global={
sched=sched,
signal=signal,
emit=sched.emit,

sigonce=Sync.once,
sighook=Sync.on,

task=Task.new,
wait=Task.wait,
sigrun=Task.sigrun,
sigrunonce=Task.sigrunonce,
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
		log('sched', 'INFO', "killing %s from %s", tostring(obj),tostring(sched.running))
		if sched.running~=scheduler then
			error('killing scheduler from'..tostring(sched.running)..', use sched.stop() instead',2)
		end
		signal(obj,'dying',sched.running) --warns subs
		while next(obj.subs) do
			next(obj.subs):kill()
		end
		obj.subs={}
		obj.status='dead'
		signal(obj,'dead',sched.running)
		if Task.running and Task.running.status=='dead' and Task.running.co==coroutine.running() then
			coroutine.yield()
		end
		sched.ready=true
		return obj
	end
	},{
	__tostring=function(t) return t.name end,
	})
	
	sched.scheduler=scheduler
	sched.running=scheduler
	
	Obj._reset()
	Task._reset()
	Timer._reset()
	
	
	platform._reset() --after Timer
	loop_state = 'stopped'
	log('sched','INFO','scheduler cleaned.')
end

---Loops over the scheduler cycle,
--returning to the caller function after sched.stop has been called
--calling platform.step for performing sleeps.
function sched.loop ()
	log('sched','INFO','Scheduler started')
    loop_state = 'running'
	local Task=Task
    local Timer_nextevent, Timer_step, Obj_step, platform_step =
        Timer.nextevent, Timer.step, Obj.step, platform.step
	local timeout
    while true do --this block is the scheduler step
        Timer_step() -- Emit timer signals
        Obj_step() -- Run all the ready tasks
		-- tprint(sched.fil,3)
		-- read()
		-- Find out when the next timer event is due
        timeout = nil
		local date = Timer_nextevent()
		if date then
			local now=os_time()
			timeout = date<now and 0 or date-now
		end
		
		-- tprint(sched.fil,2)
		if loop_state~='running' then sched.reset() break end
		-- if loop_state~='running' then break end
		platform_step (timeout,date) -- Wait for platform events until the next timer is due
    end
end


sched.reset()
return sched
local sched=require'packages.sched'
local input=sched.Obj.new()
local timeout=0.15
local extra=0.6
local os_time=os.clock


input.set=function(_timeout,_extra)
	timeout,extra=_timeout,_extra
end
do
	local timer,down
	function input.key_handle(obj,em,ev,n)
		-- local down,time=ts[ev].down,t[evs].time
		if em=='timer' then
			input.key=nil
			sched.signal('key',del..'up')
		else
			if not down then
				timer=os_time()
				obj:link{timer={os_time()+timeout}}
				input.key=n
				down=true
				sched.signal('key',n..'down')
			else
				if timer then obj:unlink{timer={timer+timeout}} end
				timer=os_time()
				obj:link{timer={timer+timeout}}
			end
		end
	end
end
do
	local timer,down
	function input.char_handle(obj,em,ev,n)
		-- local down,time=ts[ev].down,t[evs].time
		if em=='timer' then
			input.char=nil
			sched.signal('char',del..'up')
		else
			if not down then
				timer=os_time()
				obj:link{timer={os_time()+timeout}}
				input.char=n
				down=true
				sched.signal('char',n..'down')
			else
				if timer then obj:unlink{timer={timer+timeout}} end
				timer=os_time()
				obj:link{timer={timer+timeout}}
			end
		end
	end
end
input._reset=function()
	input.key=nil
	input.char=nil
	sched.Obj.new('keylistener'):link('platform','key'):setParent(input).handle=input.key_handle
	sched.Obj.new('charlistener'):link('platform','char'):setParent(input).handle=input.char_handle
	new:link('platform','key')
end

input._reset()
return input
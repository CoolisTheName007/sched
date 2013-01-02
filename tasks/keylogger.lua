local sched=require'packages.sched'
local keylogger=sched.Obj.new()
local timeout=0.15
local extra=0.6
local os_time=os.clock
local down,time


keylogger.set=function(_timeout,_extra)
	timeout,extra=_timeout,_extra
end

function keylogger.handle(obj,em,ev,n)
	-- local down,time=ts[ev].down,t[evs].time
	if em=='timer' then
		local del,now=nil,os_time()
		for key,_ in pairs(down) do
			if del then
				down[del]=nil
				sched.signal('key',del..'up')
				del=nil
			end
			if now-time[key]>=timeout then
				del=key
			end
		end
		if del then
			down[del]=nil
			sched.signal('key',del..'up')
		end
	else
		if not down[n] then
			time[n]=os_time()
			obj:link{timer={time[n]+timeout}}
			down[n]=true
			sched.signal('key',n..'down')
		else
			if time[n] then obj:unlink{timer={time[n]+timeout}} end
			time[n]=os_time()
			obj:link{timer={time[n]+timeout}}
		end
	end
end
keylogger._reset=function()
	time={}
	down={}
	keylogger.time=time
	keylogger.down=down
	new=sched.Obj.new(keylogger.handle,'keylogger')
	new:link('platform','key')
end

keylogger._reset()
return keylogger
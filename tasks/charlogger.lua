local sched=require'packages.sched'
local charlogger=sched.Obj.new()
local timeout=0.15
local extra=0.6
local os_time=os.clock
local down,time


charlogger.set=function(_timeout,_extra)
	timeout,extra=_timeout,_extra
end

function charlogger.handle(obj,em,ev,n)
	-- local down,time=ts[ev].down,t[evs].time
	if em=='timer' then
		local del,now=nil,os_time()
		for char,_ in pairs(down) do
			if del then
				down[del]=nil
				sched.signal('char',del..'up')
				del=nil
			end
			if now-time[char]>=timeout then
				del=char
			end
		end
		if del then
			down[del]=nil
			sched.signal('char',del..'up')
		end
	else
		if not down[n] then
			time[n]=os_time()
			obj:link{timer={time[n]+timeout}}
			down[n]=true
			sched.signal('char',n..'down')
		else
			if time[n] then obj:unlink{timer={time[n]+timeout}} end
			time[n]=os_time()
			obj:link{timer={time[n]+timeout}}
		end
	end
end
charlogger._reset=function()
	time={}
	down={}
	charlogger.time=time
	charlogger.down=down
	new=sched.Obj.new(charlogger.handle,'charlogger')
	new:link('platform','char')
end

charlogger._reset()
return charlogger
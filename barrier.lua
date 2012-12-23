local check=require 'packages.checker'.check

PACKAGE_NAME='sched'

local sched=require 'init'

--------------------------------------------------------------------------------
-- Object metatable/class
--------------------------------------------------------------------------------
local B={__type='barrier'};B.__index=B

--------------------------------------------------------------------------------
-- A registry of all currently active barriers. This is intended as a debug aid,
-- and can be safely commented out if not needed
--------------------------------------------------------------------------------
sched.barriers = setmetatable({}, {__mode='kv'})

function barrier(n)
	check ('integer',n)
	local instance={n=n}
	if sched.barriers then
		sched.barriers[tostring(instance):match(':.(.*)')]=instance
	end
	setmetatable(instance,B)
	return instance
end

B.reach=function(self)
	if self.n<=1 then
		self.n=0
		sched.signal(self,'zero')
	else
		self.n=self.n-1
		sched.wait(self,'zero')
	end
end

return barrier